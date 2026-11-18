#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

EXECUTABLE = "/home/user/query_filter"
SOURCE = "/home/user/query_filter.cpp"


def test_failure_count():
    count_file = "/home/user/failure_count.txt"
    assert os.path.isfile(count_file), f"File {count_file} does not exist."
    with open(count_file, "r") as f:
        content = f.read().strip()
    assert content == "14", f"Expected failure count to be '14', but got '{content}'."


def test_query_filter_executable():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {EXECUTABLE} is not a compiled ELF executable."


def test_query_filter_clean_corpus():
    clean_dir = "/app/corpora/clean"
    assert os.path.isdir(clean_dir), f"Directory {clean_dir} does not exist."

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, f"No files found in {clean_dir}."

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, "rb") as f:
            query = f.read()

        result = subprocess.run([EXECUTABLE], input=query, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = result.stdout.decode("utf-8").strip()
        if output != "ACCEPT":
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean queries rejected. Offending files: {', '.join(failed_files)}")


def test_query_filter_evil_corpus():
    evil_dir = "/app/corpora/evil"
    assert os.path.isdir(evil_dir), f"Directory {evil_dir} does not exist."

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, f"No files found in {evil_dir}."

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, "rb") as f:
            query = f.read()

        result = subprocess.run([EXECUTABLE], input=query, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = result.stdout.decode("utf-8").strip()
        if output != "REJECT":
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil queries bypassed (accepted). Offending files: {', '.join(failed_files)}")


def random_case(text):
    return "".join(ch.upper() if ch.isalpha() and secrets.randbits(1) else ch.lower() if ch.isalpha() else ch for ch in text)


def ws():
    return secrets.choice([" ", "  ", "\t", "\n", " \n ", "\t "])


def hidden_cases():
    cases = []
    for _ in range(10):
        tag = secrets.token_hex(10)
        number = secrets.randbelow(9000) + 1
        k = random_case
        s = ws

        cases.append((f"{k('MATCH')}{s()}(n:Backup_{tag}){s()}{k('RETURN')}{s()}n{s()}{k('LIMIT')}{s()}{number}", "ACCEPT"))
        cases.append((f"{k('SELECT')}{s()}*{s()}{k('WHERE')}{s()}{{ ?s ?p ?o }}{s()}{k('LIMIT')}{s()}{number}", "ACCEPT"))

        for forbidden in ("DELETE", "DROP", "INSERT", "CREATE", "SET", "REMOVE"):
            word = k(forbidden)
            if forbidden == "DELETE":
                query = f"{k('MATCH')}{s()}(n:Backup_{tag}){s()}{word}{s()}n{s()}{k('LIMIT')}{s()}3"
            elif forbidden == "DROP":
                query = f"{word}{s()}{k('GRAPH')}{s()}<urn:{tag}>{s()}{k('LIMIT')}{s()}3"
            elif forbidden == "INSERT":
                query = f"{word}{s()}{k('DATA')}{s()}{{ <urn:{tag}> <urn:p> <urn:o> }}{s()}{k('LIMIT')}{s()}3"
            elif forbidden == "CREATE":
                query = f"{word}{s()}(n:Backup_{tag}){s()}{k('RETURN')}{s()}n{s()}{k('LIMIT')}{s()}3"
            elif forbidden == "SET":
                query = f"{k('MATCH')}{s()}(n:Backup_{tag}){s()}{word}{s()}n.flag=true{s()}{k('RETURN')}{s()}n{s()}{k('LIMIT')}{s()}3"
            else:
                query = f"{k('MATCH')}{s()}(n:Backup_{tag}){s()}{word}{s()}n.flag{s()}{k('RETURN')}{s()}n{s()}{k('LIMIT')}{s()}3"
            cases.append((query, "REJECT"))

        for restricted in ("Credential", "Secret", "Password"):
            cases.append((f"{k('MATCH')}{s()}(n:{k(restricted)}){s()}{k('RETURN')}{s()}n{s()}{k('LIMIT')}{s()}2", "REJECT"))

        cases.append((f"{k('MATCH')}{s()}(n:Backup_{tag}){s()}{k('RETURN')}{s()}n", "REJECT"))
        cases.append((f"{k('SELECT')}{s()}*{s()}{k('WHERE')}{s()}{{ ?s ?p ?o }}", "REJECT"))
        cases.append((f"{k('MATCH')}{s()}(n:Backup_{tag}){s()}{k('RETURN')}{s()}n.unlimited", "REJECT"))
        cases.append((f"{k('MATCH')}{s()}(n:Backup_{tag}){s()}{k('RETURN')}{s()}\"LIMIT 5\"", "REJECT"))
    secrets.SystemRandom().shuffle(cases)
    return cases


def run_suite(path, cases):
    for index, (query, expected) in enumerate(cases):
        try:
            result = subprocess.run(
                [path], input=query.encode("utf-8"), stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=2
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Query filter timed out on hidden case {index}.")
        assert result.returncode == 0, f"Query filter exited with {result.returncode} on hidden case {index}."
        assert result.stdout == (expected + "\n").encode("ascii"), (
            f"Hidden case {index} expected exactly {expected!r}, got {result.stdout!r}."
        )


def test_source_and_randomized_hidden_suite():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    cases = hidden_cases()

    fd, rebuilt = tempfile.mkstemp(prefix="query_filter_rebuilt_", dir="/tmp")
    os.close(fd)
    os.unlink(rebuilt)
    try:
        try:
            compile_result = subprocess.run(
                ["g++", "-std=c++17", "-O2", SOURCE, "-o", rebuilt],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Compiling query_filter.cpp timed out.")
        assert compile_result.returncode == 0, (
            "query_filter.cpp did not compile:\n" + compile_result.stderr.decode("utf-8", errors="replace")
        )
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

        run_suite(EXECUTABLE, cases)
        run_suite(rebuilt, cases)
    finally:
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
