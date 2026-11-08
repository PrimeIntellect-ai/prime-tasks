#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import os
import random
import secrets
import shutil
import struct
import subprocess
import tempfile
import uuid

FILTER_SCRIPT = '/home/user/filter.py'
PROJECT_DIR = '/home/user/audioproc'
EVIL_CORPUS_DIR = '/app/eval_corpus/evil'
CLEAN_CORPUS_DIR = '/app/eval_corpus/clean'


def run_filter(path):
    return subprocess.run(
        ['python3', FILTER_SCRIPT, path],
        capture_output=True,
        timeout=10,
    ).returncode


def test_filter_script_exists():
    assert os.path.isfile(FILTER_SCRIPT), f"The filter script {FILTER_SCRIPT} is missing."


def test_extension_is_repaired_and_built():
    assert os.path.isfile(os.path.join(PROJECT_DIR, 'setup.py')), 'setup.py is missing.'

    shutil.rmtree(os.path.join(PROJECT_DIR, 'build'), ignore_errors=True)
    for suffix in importlib.machinery.EXTENSION_SUFFIXES:
        for artifact in glob.glob(os.path.join(PROJECT_DIR, 'fast_wav*' + suffix)):
            os.remove(artifact)

    result = subprocess.run(
        ['python3', 'setup.py', 'build_ext', '--inplace'],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        'The C extension did not build successfully.\nSTDOUT:\n'
        + result.stdout + '\nSTDERR:\n' + result.stderr
    )

    artifacts = []
    for suffix in importlib.machinery.EXTENSION_SUFFIXES:
        artifacts.extend(glob.glob(os.path.join(PROJECT_DIR, 'fast_wav*' + suffix)))
    assert artifacts, 'Building did not produce a fast_wav extension module.'
    assert any(open(path, 'rb').read(4) == b'\x7fELF' for path in artifacts), (
        'The produced fast_wav artifact is not a compiled ELF extension.'
    )

    result = subprocess.run(
        ['python3', '-c',
         "import fast_wav; assert callable(fast_wav.parse_wav); fast_wav.parse_wav('/app/trigger.wav')"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        'The built extension could not be imported and exercised.\nSTDOUT:\n'
        + result.stdout + '\nSTDERR:\n' + result.stderr
    )

    result = subprocess.run(
        ['python3', 'run_service.py', '/app/trigger.wav'],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        'run_service.py does not work with the rebuilt extension.\nSTDOUT:\n'
        + result.stdout + '\nSTDERR:\n' + result.stderr
    )


def test_adversarial_corpus_filtering():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory {EVIL_CORPUS_DIR} missing."
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory {CLEAN_CORPUS_DIR} missing."

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    assert len(evil_files) > 0, "No evil files found in the corpus."
    assert len(clean_files) > 0, "No clean files found in the corpus."

    bypassed_evil = []
    for evil_file in evil_files:
        result = subprocess.run(['python3', FILTER_SCRIPT, evil_file], capture_output=True)
        if result.returncode != 1:
            bypassed_evil.append((os.path.basename(evil_file), result.returncode))

    modified_clean = []
    for clean_file in clean_files:
        result = subprocess.run(['python3', FILTER_SCRIPT, clean_file], capture_output=True)
        if result.returncode != 0:
            modified_clean.append((os.path.basename(clean_file), result.returncode))

    error_messages = []
    if bypassed_evil:
        error_messages.append(f"{len(bypassed_evil)} of {len(evil_files)} evil files bypassed the filter. Offending files: " + ", ".join([f"{f} (exit code {c})" for f, c in bypassed_evil]))

    if modified_clean:
        error_messages.append(f"{len(modified_clean)} of {len(clean_files)} clean files were incorrectly flagged. Offending files: " + ", ".join([f"{f} (exit code {c})" for f, c in modified_clean]))

    assert not error_messages, "\n".join(error_messages)


def make_chunk(chunk_id, payload):
    assert len(chunk_id) == 4
    padding = b'\x00' if len(payload) & 1 else b''
    return chunk_id + struct.pack('<I', len(payload)) + payload + padding


def make_wav(chunks):
    body = b'WAVE' + b''.join(make_chunk(chunk_id, payload) for chunk_id, payload in chunks)
    return b'RIFF' + struct.pack('<I', len(body)) + body


def oracle_has_leaking_chunk(data):
    if len(data) < 12 or data[:4] != b'RIFF' or data[8:12] != b'WAVE':
        return False
    offset = 12
    while offset + 8 <= len(data):
        chunk_id = data[offset:offset + 4]
        chunk_size = struct.unpack_from('<I', data, offset + 4)[0]
        payload_end = offset + 8 + chunk_size
        if payload_end > len(data):
            return False
        if chunk_id == b'JUNK':
            return True
        offset = payload_end + (chunk_size & 1)
    return False


def test_filter_on_runtime_generated_unlabelled_corpus():
    fmt_payload = struct.pack('<HHIIHH', 1, 1, 44100, 88200, 2, 16)
    specs = []

    for _ in range(12):
        junk_payload = secrets.token_bytes(2 * random.randint(1, 20))
        extra_id = random.choice([b'LIST', b'fact', b'abcd', b'INFO'])
        chunks = [
            (b'fmt ', fmt_payload),
            (extra_id, secrets.token_bytes(2 * random.randint(1, 12))),
            (b'JUNK', junk_payload),
            (b'data', secrets.token_bytes(2 * random.randint(1, 20))),
        ]
        random.shuffle(chunks)
        specs.append(make_wav(chunks))

    for _ in range(12):
        # Include the text JUNK inside ordinary payloads so a raw substring search
        # is not sufficient; only a JUNK chunk identifier reaches the leaking branch.
        payload = secrets.token_bytes(4) + b'JUNK' + secrets.token_bytes(4)
        chunks = [
            (b'fmt ', fmt_payload),
            (random.choice([b'LIST', b'fact', b'abcd', b'junk']), payload),
            (b'data', secrets.token_bytes(2 * random.randint(1, 20))),
        ]
        random.shuffle(chunks)
        specs.append(make_wav(chunks))

    secrets.SystemRandom().shuffle(specs)
    with tempfile.TemporaryDirectory(prefix='wavcheck_' + uuid.uuid4().hex + '_') as directory:
        cases = []
        for data in specs:
            path = os.path.join(directory, uuid.uuid4().hex + '.bin')
            with open(path, 'wb') as handle:
                handle.write(data)
            cases.append((path, 1 if oracle_has_leaking_chunk(data) else 0))

        secrets.SystemRandom().shuffle(cases)
        assert {expected for _, expected in cases} == {0, 1}
        failures = []
        for path, expected in cases:
            actual = run_filter(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))
        assert not failures, 'Runtime-generated corpus failures: ' + repr(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
