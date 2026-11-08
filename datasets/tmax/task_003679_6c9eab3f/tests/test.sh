#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import struct
import subprocess
import tempfile

import pytest

PACKAGE_DIR = "/app/vendored/log-processor-2.0"
LOG_PROC = os.path.join(PACKAGE_DIR, "log-proc")
CLASSIFIER = "/home/user/classifier"
CLASSIFIER_SOURCE = "/home/user/classifier.c"


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Expected compiled binary at {path}"
    assert os.access(path, os.X_OK), f"Expected {path} to be executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected {path} to be a compiled ELF executable"


def write_log(path, offsets):
    with open(path, "wb") as f:
        f.write(b"LOG1")
        for offset in offsets:
            f.write(struct.pack("<I", offset))


def run_with_timeout(argv, timeout=3):
    return subprocess.run(argv, capture_output=True, timeout=timeout)


@pytest.fixture(scope="session")
def generated_cases():
    root = tempfile.mkdtemp(prefix="log-validation-")
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "little"))
    cases = []

    # Canonical safe chains of unpredictable lengths.
    for _ in range(8):
        count = rng.randint(2, 18)
        offsets = [4 * (i + 2) for i in range(count)]
        path = os.path.join(root, secrets.token_hex(12))
        write_log(path, offsets)
        cases.append((path, 0))

    # Cycles, out-of-range references, and unaligned references. Sizes overlap
    # the safe cases and all files share one directory with opaque names.
    for _ in range(5):
        count = rng.randint(2, 18)
        offsets = [4 * (i + 2) for i in range(count)]
        cycle_at = rng.randrange(count)
        target_record = rng.randrange(cycle_at + 1)
        offsets[cycle_at] = 4 * (target_record + 1)
        path = os.path.join(root, secrets.token_hex(12))
        write_log(path, offsets)
        cases.append((path, 1))

    for _ in range(4):
        count = rng.randint(2, 18)
        offsets = [4 * (i + 2) for i in range(count)]
        offsets[rng.randrange(count)] = 4 * (count + rng.randint(2, 30))
        path = os.path.join(root, secrets.token_hex(12))
        write_log(path, offsets)
        cases.append((path, 1))

    for _ in range(4):
        count = rng.randint(2, 18)
        offsets = [4 * (i + 2) for i in range(count)]
        index = rng.randrange(count)
        offsets[index] = 4 * rng.randint(1, count) + rng.randint(1, 3)
        path = os.path.join(root, secrets.token_hex(12))
        write_log(path, offsets)
        cases.append((path, 1))

    rng.shuffle(cases)
    return cases


def test_log_proc_built_by_make_and_handles_cycle(tmp_path):
    result = subprocess.run(
        ["make", "-B"], cwd=PACKAGE_DIR, capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"
    assert_elf_executable(LOG_PROC)

    safe = tmp_path / secrets.token_hex(10)
    cyclic = tmp_path / secrets.token_hex(10)
    write_log(safe, [8, 12, 16])
    write_log(cyclic, [8, 8])

    safe_result = run_with_timeout([LOG_PROC, str(safe)])
    assert safe_result.returncode == 0, "rebuilt log-proc failed on a valid log"
    # The corrected processor may reject the malformed log or merely stop
    # processing it, but it must not retain the original infinite loop.
    run_with_timeout([LOG_PROC, str(cyclic)])


def test_classifier_built_and_source_present(tmp_path):
    assert_elf_executable(CLASSIFIER)
    assert os.path.isfile(CLASSIFIER_SOURCE), f"Expected C source at {CLASSIFIER_SOURCE}"

    rebuilt = tmp_path / "classifier-from-source"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", CLASSIFIER_SOURCE, "-o", str(rebuilt)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"classifier.c does not compile:\n{result.stdout}\n{result.stderr}"
    assert_elf_executable(str(rebuilt))


def test_classifier_argument_count():
    assert run_with_timeout([CLASSIFIER]).returncode != 0
    assert run_with_timeout([CLASSIFIER, "/app/sample_clean.log", "/app/sample_evil.log"]).returncode != 0


def test_classifier_generated_cases(generated_cases, tmp_path):
    rebuilt = tmp_path / "rebuilt-classifier"
    build = subprocess.run(
        ["gcc", "-std=c11", "-O2", CLASSIFIER_SOURCE, "-o", str(rebuilt)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"classifier.c does not compile:\n{build.stderr}"

    for executable in (CLASSIFIER, str(rebuilt)):
        failures = []
        for path, expected in generated_cases:
            result = run_with_timeout([executable, path])
            if result.returncode != expected:
                failures.append((os.path.basename(path), expected, result.returncode))
        assert not failures, f"classifier misclassified generated structural cases: {failures}"


def test_classifier_clean_corpus():
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"Directory {clean_dir} does not exist"
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, f"No files found in {clean_dir}"

    failed_files = []
    for name in clean_files:
        result = run_with_timeout([CLASSIFIER, os.path.join(clean_dir, name)])
        if result.returncode != 0:
            failed_files.append(name)
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected (expected exit code 0). Offending files: {failed_files}")


def test_classifier_evil_corpus():
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"Directory {evil_dir} does not exist"
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, f"No files found in {evil_dir}"

    failed_files = []
    for name in evil_files:
        result = run_with_timeout([CLASSIFIER, os.path.join(evil_dir, name)])
        if result.returncode != 1:
            failed_files.append(name)
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (expected exit code 1). Offending files: {failed_files}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
