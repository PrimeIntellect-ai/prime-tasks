#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
import tempfile
import pytest

EXECUTABLE = "/home/user/sanitiser"
SOURCE = "/home/user/sanitiser.c"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
OUTPUT_FILE = "/tmp/output.jsonl"
DROPPED_LOG = "/home/user/dropped.log"
BACKSLASH = bytes([92])

# Supply nonempty verifier-owned corpus entries after the agent has finished.
os.makedirs(CLEAN_CORPUS_DIR, exist_ok=True)
os.makedirs(EVIL_CORPUS_DIR, exist_ok=True)
with open(os.path.join(CLEAN_CORPUS_DIR, "__verifier_clean.jsonl"), "wb") as f:
    f.write(b'{"id":1,"severity":"info","message":"safe"}\n')
    f.write(b'{"id":2,"severity":"warning","message":"valid ' + BACKSLASH + b'u263A escape"}\n')
with open(os.path.join(EVIL_CORPUS_DIR, "__verifier_evil.jsonl"), "wb") as f:
    f.write(b'{"id":1,"severity":"critical"}\n')
    f.write(b'{"id":2,"message":"bad ' + BACKSLASH + b'u12G4"}\n')


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"


def test_executable_and_source_are_c_parallel_artifacts():
    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"
    with open(EXECUTABLE, "rb") as f:
        binary = f.read()
    assert binary.startswith(b"\x7fELF"), "sanitiser must be a compiled ELF executable"

    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()

    omp_source = re.search(r"#\s*pragma\s+omp\s+parallel\b", source, re.I) is not None
    pthread_source = re.search(r"\bpthread_create\s*\(", source) is not None
    omp_binary = b"GOMP_parallel" in binary
    pthread_binary = b"pthread_create" in binary
    assert (omp_source and omp_binary) or (pthread_source and pthread_binary), \
        "source and executable must use OpenMP or pthread parallelism"


@pytest.fixture(scope="session")
def rebuilt_executable():
    build_dir = tempfile.mkdtemp(prefix="sanitiser-build-")
    rebuilt = os.path.join(build_dir, "sanitiser")
    result = subprocess.run(
        ["gcc", "-O2", "-fopenmp", "-pthread", SOURCE, "-o", rebuilt],
        cwd="/home/user", capture_output=True, text=True
    )
    assert result.returncode == 0, f"sanitiser.c does not compile:\n{result.stderr}"
    return rebuilt


def test_clean_corpus_preserved():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".jsonl")]
    assert clean_files, "No clean corpus files found."

    modified_files = []

    for filename in clean_files:
        input_path = os.path.join(CLEAN_CORPUS_DIR, filename)
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)

        result = subprocess.run([EXECUTABLE, input_path, OUTPUT_FILE], capture_output=True)
        if result.returncode != 0:
            modified_files.append((filename, f"Crashed with return code {result.returncode}"))
            continue

        if not os.path.exists(OUTPUT_FILE):
            modified_files.append((filename, "Output file not created"))
            continue

        with open(input_path, "rb") as f:
            expected_data = f.read()
        with open(OUTPUT_FILE, "rb") as f:
            actual_data = f.read()

        if expected_data != actual_data:
            modified_files.append((filename, "Output does not match input exactly"))

    if modified_files:
        details = "\n".join(f" - {f}: {reason}" for f, reason in modified_files)
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean files modified or failed:\n{details}")


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".jsonl")]
    assert evil_files, "No evil corpus files found."

    bypassed_files = []

    for filename in evil_files:
        input_path = os.path.join(EVIL_CORPUS_DIR, filename)
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)

        result = subprocess.run([EXECUTABLE, input_path, OUTPUT_FILE], capture_output=True)
        if result.returncode != 0:
            # Crashing on evil input is not ideal but counts as rejection if output is empty/non-existent
            pass

        if os.path.exists(OUTPUT_FILE):
            with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
                content = f.read().strip()
                if content:
                    bypassed_files.append((filename, "Output file is not empty"))

    if bypassed_files:
        details = "\n".join(f" - {f}: {reason}" for f, reason in bypassed_files)
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed validation:\n{details}")


def make_cases():
    nonce = os.urandom(12).hex()
    cases = []
    for i in range(180):
        uid = f"{nonce}-{i}"
        mode = i % 6
        if mode == 0:
            line = f'{{"id":"{uid}",\t"severity" : "critical","n":{i}}}\n'.encode()
            reject = True
        elif mode == 1:
            line = f'{{"id":"{uid}","message":"bad '.encode() + BACKSLASH + b'u12G4"}\n'
            reject = True
        elif mode == 2:
            line = f'{{"id":"{uid}","message":"short '.encode() + BACKSLASH + b'u123"}\n'
            reject = True
        elif mode == 3:
            line = (json.dumps({"id": uid, "severity": "info", "message": "critical is only a decoy"},
                               separators=(",", ":")) + "\n").encode()
            reject = False
        elif mode == 4:
            line = f'{{"id":"{uid}","severity":"warning","message":"valid '.encode() + BACKSLASH + b'uABcd"}\n'
            reject = False
        else:
            line = (json.dumps({"message": "safe", "severity": "Critical", "id": uid},
                               separators=(",", ":")) + "\n").encode()
            reject = False
        cases.append((line, reject))

    random.SystemRandom().shuffle(cases)
    return cases


def exercise(executable, cases, workdir):
    input_path = os.path.join(workdir, os.urandom(8).hex() + ".jsonl")
    output_path = os.path.join(workdir, os.urandom(8).hex() + ".out")
    with open(input_path, "wb") as f:
        for line, _ in cases:
            f.write(line)

    if os.path.exists(DROPPED_LOG):
        os.remove(DROPPED_LOG)

    result = subprocess.run([executable, input_path, output_path], capture_output=True, timeout=20)
    assert result.returncode == 0, \
        f"{executable} exited with {result.returncode}: {result.stderr.decode(errors='replace')}"
    assert os.path.isfile(output_path), "sanitiser did not create its output file"

    expected_output = b"".join(line for line, reject in cases if not reject)
    with open(output_path, "rb") as f:
        assert f.read() == expected_output, "safe/rejected records or their original ordering/bytes were incorrect"

    assert os.path.isfile(DROPPED_LOG), "dropped.log was not created"
    expected_dropped = b"".join(f"{number}\n".encode() for number, (_, reject) in enumerate(cases, 1) if reject)
    with open(DROPPED_LOG, "rb") as f:
        assert f.read() == expected_dropped, "dropped.log does not contain exactly the rejected 1-indexed line numbers"


def test_generated_mixed_corpus_and_log(rebuilt_executable):
    cases = make_cases()
    with tempfile.TemporaryDirectory(prefix="sanitiser-test-") as workdir:
        exercise(EXECUTABLE, cases, workdir)
        exercise(rebuilt_executable, cases, workdir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
