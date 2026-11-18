#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
import uuid
import pytest

DETECTOR = '/home/user/detector.sh'
SRC_DIR = '/home/user/decoder_src'
DECODER_SRC = os.path.join(SRC_DIR, 'decoder.c')
MAKEFILE = os.path.join(SRC_DIR, 'Makefile')
DECODER = os.path.join(SRC_DIR, 'decoder')
KEY = 0x3F
MARKER = b'C2_CONNECT_INIT'


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, **kwargs)


def test_detector_script_exists():
    assert os.path.isfile(DETECTOR), 'The detector script /home/user/detector.sh is missing.'
    syntax = run(['bash', '-n', DETECTOR])
    assert syntax.returncode == 0, syntax.stderr.decode(errors='replace')


def test_decoder_source_build_and_boundary_fix():
    assert os.path.isfile(DECODER_SRC), 'decoder.c is missing.'
    assert os.path.isfile(MAKEFILE), 'Makefile is missing.'

    make_text = open(MAKEFILE, encoding='utf-8', errors='replace').read()
    assert re.search(r'(^|\s)-lm($|\s)', make_text), 'The Makefile still lacks the required -lm linker flag.'

    if os.path.lexists(DECODER):
        os.remove(DECODER)
    built = run(['make', '-B'], cwd=SRC_DIR)
    assert built.returncode == 0, (built.stdout + built.stderr).decode(errors='replace')
    assert os.path.isfile(DECODER), 'make did not create the decoder binary.'
    with open(DECODER, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'decoder is not a compiled ELF binary.'

    asan_decoder = os.path.join(tempfile.mkdtemp(prefix='decoder_asan_'), 'decoder')
    compiled = run([
        'gcc', '-fsanitize=address', '-fno-omit-frame-pointer', '-O0',
        '-o', asan_decoder, DECODER_SRC, '-lm'
    ])
    assert compiled.returncode == 0, compiled.stderr.decode(errors='replace')

    plain = b'BOUNDARY_TEST_' + secrets.token_bytes(31)
    encoded = bytes(b ^ KEY for b in plain)
    fd, payload = tempfile.mkstemp(prefix='boundary_', suffix='.blob')
    os.close(fd)
    with open(payload, 'wb') as f:
        f.write(encoded)

    env = os.environ.copy()
    env['EXEC_MODE'] = 'unsafe'
    checked = run([asan_decoder, payload, '0x3F'], env=env)
    assert checked.returncode == 0, checked.stderr.decode(errors='replace')
    assert checked.stdout == plain + b'\n', 'The repaired decoder produced incorrect output.'

    env.pop('EXEC_MODE', None)
    denied = run([DECODER, payload, '0x3F'], env=env)
    assert denied.returncode == 2, 'The decoder environment check is not present or does not work.'


def install_decoder_probe(log_path):
    backup = os.path.join('/tmp', 'real_decoder_' + uuid.uuid4().hex)
    shutil.move(DECODER, backup)
    wrapper = f'''#!/bin/bash
printf '%s\\t%s\\t%s\\n' "${{EXEC_MODE-}}" "${{1-}}" "${{2-}}" >> {log_path!r}
exec {backup!r} "$@"
'''
    with open(DECODER, 'w') as f:
        f.write(wrapper)
    os.chmod(DECODER, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                       stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
    return backup


def read_probe(log_path, offset):
    if not os.path.exists(log_path):
        return []
    with open(log_path, encoding='utf-8', errors='replace') as f:
        lines = f.readlines()
    records = []
    for line in lines[offset:]:
        parts = line.rstrip('\n').split('\t')
        if len(parts) == 3:
            records.append(parts)
    return records


def assert_detector_case(path, malicious, log_path):
    before = 0
    if os.path.exists(log_path):
        with open(log_path, encoding='utf-8', errors='replace') as f:
            before = len(f.readlines())

    result = run(['bash', DETECTOR, path])
    expected = 1 if malicious else 0
    assert result.returncode == expected, (
        f'{os.path.basename(path)} returned {result.returncode}; expected {expected}. '
        f'stdout={result.stdout!r} stderr={result.stderr!r}'
    )

    records = read_probe(log_path, before)
    matching = []
    for mode, supplied_path, supplied_key in records:
        try:
            key_ok = int(supplied_key, 16) == KEY
        except ValueError:
            key_ok = False
        if mode == 'unsafe' and supplied_path == path and key_ok:
            matching.append((mode, supplied_path, supplied_key))
    assert matching, 'detector.sh did not invoke the compiled ./decoder with the payload, extracted key, and EXEC_MODE=unsafe.'


def test_adversarial_corpus_classification():
    evil_dir = '/app/corpora/evil'
    clean_dir = '/app/corpora/clean'

    assert os.path.isdir(evil_dir), f'Evil corpus directory {evil_dir} missing.'
    assert os.path.isdir(clean_dir), f'Clean corpus directory {clean_dir} missing.'

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    assert evil_files, 'No files found in evil corpus.'
    assert clean_files, 'No files found in clean corpus.'

    log_path = os.path.join('/tmp', 'decoder_probe_' + uuid.uuid4().hex + '.log')
    backup = install_decoder_probe(log_path)
    try:
        evil_bypassed = []
        for path in evil_files:
            try:
                assert_detector_case(path, True, log_path)
            except AssertionError as exc:
                evil_bypassed.append(f'{os.path.basename(path)} ({exc})')

        clean_modified = []
        for path in clean_files:
            try:
                assert_detector_case(path, False, log_path)
            except AssertionError as exc:
                clean_modified.append(f'{os.path.basename(path)} ({exc})')

        errors = []
        if evil_bypassed:
            errors.append(f'{len(evil_bypassed)} of {len(evil_files)} evil bypassed: ' + ', '.join(evil_bypassed))
        if clean_modified:
            errors.append(f'{len(clean_modified)} of {len(clean_files)} clean modified/rejected: ' + ', '.join(clean_modified))
        assert not errors, ' | '.join(errors)

        case_dir = tempfile.mkdtemp(prefix='payload_checks_')
        cases = []
        for malicious in (False, True, False, True, True, False):
            name = secrets.token_hex(12) + '.dat'
            path = os.path.join(case_dir, name)
            prefix = secrets.token_bytes(17)
            suffix = secrets.token_bytes(23)
            if malicious:
                plain = prefix + MARKER + suffix
            else:
                plain = prefix + b'C2_CONNECT_INI_' + suffix
                plain = plain.replace(MARKER, b'NOT_A_COMMAND__')
            with open(path, 'wb') as f:
                f.write(bytes(b ^ KEY for b in plain))
            cases.append((path, malicious))

        for path, malicious in cases:
            assert_detector_case(path, malicious, log_path)

        assert run(['bash', DETECTOR]).returncode != 0, 'detector.sh accepted zero arguments.'
        assert run(['bash', DETECTOR, cases[0][0], cases[1][0]]).returncode != 0, 'detector.sh accepted more than one argument.'
    finally:
        if os.path.lexists(DECODER):
            os.remove(DECODER)
        if os.path.exists(backup):
            shutil.move(backup, DECODER)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
