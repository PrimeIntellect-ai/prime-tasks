#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/filter_backups.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"


def invoke(path, *extra):
    try:
        return subprocess.run(
            [SCRIPT_PATH, path, *extra],
            capture_output=True,
            timeout=3,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script did not terminate while inspecting {path!r}")


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} to exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Expected script {SCRIPT_PATH} to be executable."
    with open(SCRIPT_PATH, "rb") as script:
        first_line = script.readline(256).decode("utf-8", "replace").strip()
    assert first_line.startswith("#!") and "bash" in first_line, \
        f"Expected {SCRIPT_PATH} to be a Bash script."


def test_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory {CLEAN_CORPUS_DIR} missing."

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR)]
    assert clean_files, "Clean corpus is empty, cannot perform test."

    failed_files = []
    for file_path in clean_files:
        result = subprocess.run([SCRIPT_PATH, file_path], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(file_path))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected (expected exit code 0). Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory {EVIL_CORPUS_DIR} missing."

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR)]
    assert evil_files, "Evil corpus is empty, cannot perform test."

    failed_files = []
    for file_path in evil_files:
        result = subprocess.run([SCRIPT_PATH, file_path], capture_output=True)
        if result.returncode == 0:
            failed_files.append(os.path.basename(file_path))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (expected exit code 1). Offending files: {', '.join(failed_files)}")


def test_generated_files_and_symlinks():
    # Use unpredictable, semantically neutral names in the same directory so the
    # expected result cannot be inferred from clean/evil path components.
    with tempfile.TemporaryDirectory(prefix="backup-check-", dir="/home/user") as base:
        outside = tempfile.mkdtemp(prefix="backup-check-outside-", dir="/home/user")
        try:
            clean = []
            evil = []
            signatures = [
                bytes.fromhex("89504E47"),
                bytes.fromhex("504B0304"),
                bytes.fromhex("1F8B08"),
            ]

            for signature in signatures:
                for _ in range(3):
                    path = os.path.join(base, secrets.token_hex(10))
                    with open(path, "wb") as f:
                        f.write(signature + secrets.token_bytes(31))
                    clean.append(path)

            bad_headers = [
                b"",
                bytes.fromhex("89"),
                bytes.fromhex("89504E"),
                bytes.fromhex("504B03"),
                bytes.fromhex("1F8B"),
                bytes.fromhex("4D5A9000"),
                bytes.fromhex("7F454C46"),
                b"xxxx" + bytes.fromhex("89504E47"),
            ]
            for header in bad_headers:
                path = os.path.join(base, secrets.token_hex(10))
                with open(path, "wb") as f:
                    f.write(header + secrets.token_bytes(17))
                evil.append(path)

            target = clean[secrets.randbelow(len(clean))]
            relative_link = os.path.join(base, secrets.token_hex(10))
            os.symlink(os.path.basename(target), relative_link)
            clean.append(relative_link)

            absolute_link = os.path.join(base, secrets.token_hex(10))
            os.symlink(target, absolute_link)
            clean.append(absolute_link)

            chained_link = os.path.join(base, secrets.token_hex(10))
            os.symlink(os.path.basename(relative_link), chained_link)
            clean.append(chained_link)

            broken = os.path.join(base, secrets.token_hex(10))
            os.symlink(secrets.token_hex(10), broken)
            evil.append(broken)

            loop_a = os.path.join(base, secrets.token_hex(10))
            loop_b = os.path.join(base, secrets.token_hex(10))
            os.symlink(os.path.basename(loop_b), loop_a)
            os.symlink(os.path.basename(loop_a), loop_b)
            evil.extend([loop_a, loop_b])

            outside_target = os.path.join(outside, secrets.token_hex(10))
            with open(outside_target, "wb") as f:
                f.write(bytes.fromhex("89504E47") + secrets.token_bytes(20))
            escaping_link = os.path.join(base, secrets.token_hex(10))
            os.symlink(outside_target, escaping_link)
            evil.append(escaping_link)

            directory = os.path.join(base, secrets.token_hex(10))
            os.mkdir(directory)
            evil.append(directory)

            missing = os.path.join(base, secrets.token_hex(10))
            evil.append(missing)

            for path in clean:
                result = invoke(path)
                assert result.returncode == 0, \
                    f"Generated clean file {path!r} was rejected with exit code {result.returncode}"

            for path in evil:
                result = invoke(path)
                assert result.returncode == 1, \
                    f"Generated evil or invalid path {path!r} returned exit code {result.returncode}, expected 1"
        finally:
            import shutil
            shutil.rmtree(outside, ignore_errors=True)


def test_argument_validation():
    try:
        no_args = subprocess.run([SCRIPT_PATH], capture_output=True, timeout=3)
        too_many = subprocess.run(
            [SCRIPT_PATH, "/definitely/not/present", "extra"],
            capture_output=True,
            timeout=3,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Script did not terminate for an invalid argument count")
    assert no_args.returncode == 1, "Invocation without an input path must exit 1"
    assert too_many.returncode == 1, "Invocation with more than one argument must exit 1"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
