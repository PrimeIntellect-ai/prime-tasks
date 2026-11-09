#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import struct
import subprocess
import tempfile
import pytest

EXECUTABLE = "/home/user/secure_extractor"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def parse_archive(archive_path):
    """Parses the custom archive format and yields (filename, data)."""
    with open(archive_path, 'rb') as f:
        while True:
            l_bytes = f.read(2)
            if not l_bytes:
                break
            if len(l_bytes) < 2:
                break
            name_len = struct.unpack('<H', l_bytes)[0]
            filename = f.read(name_len).decode('ascii')
            s_bytes = f.read(4)
            if len(s_bytes) < 4:
                break
            data_len = struct.unpack('<I', s_bytes)[0]
            data = f.read(data_len)
            yield filename, data


def build_archive(entries):
    archive = bytearray()
    for filename, data in entries:
        encoded_name = filename.encode('ascii')
        archive += struct.pack('<H', len(encoded_name))
        archive += encoded_name
        archive += struct.pack('<I', len(data))
        archive += data
    return bytes(archive)


def run_archive(archive, target_dir):
    return subprocess.run(
        [EXECUTABLE, target_dir],
        input=archive,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15
    )


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found. Did you compile the code?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_clean_corpus():
    if not os.path.isdir(CLEAN_CORPUS_DIR):
        pytest.skip(f"Clean corpus dir {CLEAN_CORPUS_DIR} missing")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_clean = []

    for filename in clean_files:
        archive_path = os.path.join(CLEAN_CORPUS_DIR, filename)
        target_dir = f"/tmp/clean_extraction_{filename}"

        if os.path.exists(target_dir):
            shutil.rmtree(target_dir)
        os.makedirs(target_dir)

        with open(archive_path, 'rb') as stdin_f:
            result = subprocess.run(
                [EXECUTABLE, target_dir],
                stdin=stdin_f,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )

        stdout_out = result.stdout.strip()

        if result.returncode != 0 or stdout_out != "CLEAN":
            failed_clean.append(f"{filename} (exit {result.returncode}, stdout: {stdout_out})")
            continue

        expected_entries = list(parse_archive(archive_path))
        for exp_name, exp_data in expected_entries:
            exp_path = os.path.join(target_dir, exp_name)
            if not os.path.isfile(exp_path):
                failed_clean.append(f"{filename} missing extracted file {exp_name}")
                break
            with open(exp_path, 'rb') as f:
                actual_data = f.read()
            if actual_data != exp_data:
                failed_clean.append(f"{filename} extracted data mismatch for {exp_name}")
                break

    if failed_clean:
        pytest.fail(f"{len(failed_clean)} of {len(clean_files)} clean archives failed to extract properly:\n" + "\n".join(failed_clean))


def test_evil_corpus():
    if not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.skip(f"Evil corpus dir {EVIL_CORPUS_DIR} missing")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_evil = []

    for filename in evil_files:
        archive_path = os.path.join(EVIL_CORPUS_DIR, filename)
        target_dir = f"/tmp/evil_extraction_{filename}"

        if os.path.exists(target_dir):
            shutil.rmtree(target_dir)
        os.makedirs(target_dir)

        with open(archive_path, 'rb') as stdin_f:
            result = subprocess.run(
                [EXECUTABLE, target_dir],
                stdin=stdin_f,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )

        stdout_out = result.stdout.strip()

        if result.returncode != 1 or stdout_out != "MALICIOUS":
            failed_evil.append(f"{filename} bypassed (exit {result.returncode}, stdout: {stdout_out})")
            continue

        extracted_files = os.listdir(target_dir)
        if len(extracted_files) > 0:
            failed_evil.append(f"{filename} left files in target dir: {extracted_files}")
            continue

    if failed_evil:
        pytest.fail(f"{len(failed_evil)} of {len(evil_files)} evil archives bypassed checks:\n" + "\n".join(failed_evil))


def test_generated_clean_archives_with_binary_data():
    work_dir = tempfile.mkdtemp(prefix="secure_extractor_generated_clean_")
    try:
        for index in range(4):
            token = secrets.token_hex(8)
            target_dir = os.path.join(work_dir, f"target_{index}_{token}")
            os.makedirs(target_dir)
            entries = [
                (f"clip_{token}.mp4", b"\x00\xff" + os.urandom(257 + index)),
                (f"data_{token}/chunk.bin", os.urandom(1024 + index * 31)),
                (f"data_{token}/deep/empty.bin", b""),
                (f"clips..bak_{token}", os.urandom(19)),
                (f".../frame_{token}.bin", os.urandom(73)),
            ]
            result = run_archive(build_archive(entries), target_dir)
            assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
            assert result.stdout.strip() == b"CLEAN", result.stdout
            for filename, expected_data in entries:
                output_path = os.path.join(target_dir, filename)
                assert os.path.isfile(output_path), f"Missing generated clean entry {filename}"
                with open(output_path, 'rb') as f:
                    assert f.read() == expected_data, f"Data mismatch for generated clean entry {filename}"
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


def test_generated_traversal_variants_and_rollback():
    work_dir = tempfile.mkdtemp(prefix="secure_extractor_generated_evil_")
    token = secrets.token_hex(12)
    leaf = f"escaped_{token}.bin"
    safe = f"safe_{secrets.token_hex(5)}"
    absolute_escape = f"/tmp/secure_extractor_escape_{token}"
    malicious_names = [
        f"../{leaf}",
        f"..//{leaf}",
        f"./../{leaf}",
        f"{safe}/../../{leaf}",
        f"{safe}//..//../{leaf}",
        f"..\\{leaf}",
        f"{safe}\\..\\..\\{leaf}",
        absolute_escape,
        f"\\{leaf}",
    ]

    failures = []
    try:
        for index, malicious_name in enumerate(malicious_names):
            case_dir = os.path.join(work_dir, f"case_{index}_{secrets.token_hex(4)}")
            target_dir = os.path.join(case_dir, "target")
            os.makedirs(target_dir)

            outside_candidate = None
            if malicious_name.startswith('/'):
                outside_candidate = os.path.normpath(malicious_name)
            elif '\\' not in malicious_name:
                candidate = os.path.normpath(os.path.join(target_dir, malicious_name))
                if os.path.commonpath([target_dir, candidate]) != target_dir:
                    outside_candidate = candidate

            if outside_candidate and os.path.lexists(outside_candidate):
                if os.path.isdir(outside_candidate) and not os.path.islink(outside_candidate):
                    shutil.rmtree(outside_candidate)
                else:
                    os.unlink(outside_candidate)

            prefix_name = f"already/extracted_{secrets.token_hex(8)}.bin"
            archive = build_archive([
                (prefix_name, os.urandom(91)),
                (malicious_name, b"escape-" + token.encode('ascii')),
            ])
            result = run_archive(archive, target_dir)

            escaped = bool(outside_candidate and os.path.lexists(outside_candidate))
            remaining = os.listdir(target_dir) if os.path.isdir(target_dir) else ["target directory removed"]
            if result.returncode != 1 or result.stdout.strip() != b"MALICIOUS" or remaining or escaped:
                failures.append(
                    f"{malicious_name!r}: exit={result.returncode}, stdout={result.stdout!r}, "
                    f"remaining={remaining!r}, escaped={escaped}"
                )

            if outside_candidate and os.path.lexists(outside_candidate):
                if os.path.isdir(outside_candidate) and not os.path.islink(outside_candidate):
                    shutil.rmtree(outside_candidate)
                else:
                    os.unlink(outside_candidate)

        if failures:
            pytest.fail("Generated traversal cases failed:\n" + "\n".join(failures))
    finally:
        if os.path.lexists(absolute_escape):
            if os.path.isdir(absolute_escape) and not os.path.islink(absolute_escape):
                shutil.rmtree(absolute_escape)
            else:
                os.unlink(absolute_escape)
        shutil.rmtree(work_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
