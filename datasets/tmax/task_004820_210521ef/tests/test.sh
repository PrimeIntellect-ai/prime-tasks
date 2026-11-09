#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

EXE_PATH = "/home/user/query_sanitizer"
SOURCE_PATH = "/home/user/query_sanitizer.c"
LIB_PATH = "/app/sql-parser-c/libsqlparser.a"
REBUILT_PATH = "/tmp/query_sanitizer_rebuilt"
LINK_MAP_PATH = "/tmp/query_sanitizer_rebuilt.map"


def test_verification_log_exists():
    log_path = "/home/user/verification.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist. Did you complete the task?"
    with open(log_path, "r") as f:
        content = f.read()
    assert "SANITIZER BUILD COMPLETE" in content, f"Log file {log_path} does not contain the required text."


def test_libsqlparser_compiled():
    assert os.path.isfile(LIB_PATH), f"Static library {LIB_PATH} does not exist. Did you fix and compile the vendored package?"

    try:
        result = subprocess.run(["make", "test"], cwd="/app/sql-parser-c", capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"'make test' failed in /app/sql-parser-c. Output:\n{result.stdout}\n{result.stderr}"
    except Exception as e:
        pytest.fail(f"Failed to run 'make test' in /app/sql-parser-c: {e}")


def test_sanitizer_executable_exists():
    assert os.path.isfile(EXE_PATH), f"Sanitizer executable {EXE_PATH} does not exist."
    assert os.access(EXE_PATH, os.X_OK), f"{EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXE_PATH} is not a compiled executable."


def test_sanitizer_source_builds_linked_to_library():
    assert os.path.isfile(SOURCE_PATH), f"C source {SOURCE_PATH} does not exist."
    result = subprocess.run(
        [
            "gcc",
            SOURCE_PATH,
            "-I/app/sql-parser-c/src",
            LIB_PATH,
            f"-Wl,-Map,{LINK_MAP_PATH}",
            "-o",
            REBUILT_PATH,
        ],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Failed to compile and link {SOURCE_PATH} against {LIB_PATH}:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(REBUILT_PATH) and os.access(REBUILT_PATH, os.X_OK)
    with open(REBUILT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF"
    with open(LINK_MAP_PATH, "r", errors="replace") as f:
        link_map = f.read()
    assert LIB_PATH in link_map, f"Link map does not show {LIB_PATH} as a linker input."


def test_adversarial_corpus_evil():
    evil_dir = "/app/corpora/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} missing."

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "No files found in evil corpus."

    bypassed = []
    for f in evil_files:
        file_path = os.path.join(evil_dir, f)
        result = subprocess.run([EXE_PATH, file_path], capture_output=True, text=True)
        if result.returncode != 1 or result.stdout.strip() != "REJECT":
            bypassed.append(f)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil files bypassed rejection. Offending files: {', '.join(bypassed[:10])}{'...' if len(bypassed)>10 else ''}")


def test_adversarial_corpus_clean():
    clean_dir = "/app/corpora/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} missing."

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "No files found in clean corpus."

    modified = []
    for f in clean_files:
        file_path = os.path.join(clean_dir, f)
        result = subprocess.run([EXE_PATH, file_path], capture_output=True, text=True)
        if result.returncode != 0 or result.stdout.strip() != "ACCEPT":
            modified.append(f)

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean files were incorrectly rejected. Offending files: {', '.join(modified[:10])}{'...' if len(modified)>10 else ''}")


def _identifier(prefix):
    return prefix + "_" + secrets.token_hex(6)


def _generated_cases():
    cases = []
    for _ in range(6):
        a = _identifier("accounts")
        b = _identifier("events")
        c = _identifier("items")
        r = _identifier("walk")

        cases.extend([
            (f"SELECT id FROM {a} WHERE active = 1;", 0, "ACCEPT"),
            (f"SELECT a.id, b.id FROM {a} a JOIN {b} b ON a.id = b.account_id;", 0, "ACCEPT"),
            (f"SELECT a.id, b.id FROM {a} a, {b} b WHERE a.id = b.account_id;", 0, "ACCEPT"),
            (f"SELECT * FROM {a} CROSS JOIN {b} LIMIT 17;", 0, "ACCEPT"),
            (f"WITH RECURSIVE {r}(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM {r}) SELECT n FROM {r} LIMIT 23;", 0, "ACCEPT"),
            (f"SELECT * FROM {c} ORDER BY id DESC LIMIT 9;", 0, "ACCEPT"),
            (f"SELECT a.id, b.id FROM {a} a, {b} b;", 1, "REJECT"),
            (f"SELECT * FROM {a} a CROSS JOIN {b} b;", 1, "REJECT"),
            (f"SELECT * FROM {a}, {b}, {c};", 1, "REJECT"),
            (f"WITH RECURSIVE {r}(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM {r}) SELECT n FROM {r};", 1, "REJECT"),
            (f"WITH RECURSIVE {r}(n) AS (SELECT 1 LIMIT 1 UNION ALL SELECT n + 1 FROM {r}) SELECT n FROM {r};", 1, "REJECT"),
        ])
    random.SystemRandom().shuffle(cases)
    return cases


def _run_case(executable, path, expected_code, expected_output):
    try:
        result = subprocess.run([executable, path], capture_output=True, text=True, timeout=5)
    except subprocess.TimeoutExpired:
        pytest.fail(f"{executable} timed out on generated query {os.path.basename(path)}")
    assert result.returncode == expected_code, (
        f"{executable} returned {result.returncode}, expected {expected_code}, "
        f"for generated query {os.path.basename(path)}. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_output, (
        f"{executable} printed {result.stdout!r}, expected {expected_output!r}, "
        f"for generated query {os.path.basename(path)}"
    )


def test_generated_unseen_queries_on_neutral_paths():
    assert os.path.isfile(REBUILT_PATH), "Verifier-built sanitizer is missing."
    cases = _generated_cases()
    with tempfile.TemporaryDirectory(prefix="query-sanitizer-cases-") as case_dir:
        paths = []
        for query, expected_code, expected_output in cases:
            filename = f"case_{secrets.token_hex(10)}.sql"
            path = os.path.join(case_dir, filename)
            with open(path, "w") as f:
                f.write(query)
            paths.append((path, expected_code, expected_output))

        for executable in (EXE_PATH, REBUILT_PATH):
            for path, expected_code, expected_output in paths:
                _run_case(executable, path, expected_code, expected_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
