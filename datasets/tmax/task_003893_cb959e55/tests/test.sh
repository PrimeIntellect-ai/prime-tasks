#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import hashlib
import json
import os
import random
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile

ORACLE_PATH = "/app/legacy_oracle"
AGENT_PATH = "/home/user/parser.sh"
DB_PATH = "/app/meta.db"
N_FUZZ = 500


def run_program(executable, args, timeout=2):
    try:
        result = subprocess.run(
            [executable] + list(args),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Timeout"
    except Exception as exc:
        return -2, "", str(exc)


def generate_fuzz_file(path, category):
    if category == 0:
        length = random.randint(16, 4096)
        content = bytearray(random.getrandbits(8) for _ in range(length))
        content[0:4] = b"AUDI"
    elif category == 1:
        length = random.randint(16, 4096)
        content = bytearray(random.getrandbits(8) for _ in range(length))
        content[0:4] = b"CORR"
    elif category == 2:
        length = random.randint(16, 4096)
        content = bytearray(random.getrandbits(8) for _ in range(length))
        if content[0:4] == b"AUDI":
            content[0] = 0
    else:
        length = random.randint(0, 15)
        content = bytearray(random.getrandbits(8) for _ in range(length))

    with open(path, "wb") as handle:
        handle.write(content)


@contextlib.contextmanager
def oracle_unavailable():
    assert os.path.isfile(ORACLE_PATH), f"Missing legacy oracle: {ORACLE_PATH}"
    with open(ORACLE_PATH, "rb") as handle:
        oracle_bytes = handle.read()
    oracle_mode = stat.S_IMODE(os.stat(ORACLE_PATH).st_mode)
    os.unlink(ORACLE_PATH)
    try:
        yield
        assert not os.path.exists(ORACLE_PATH), "Submission recreated the legacy oracle"
    finally:
        if os.path.lexists(ORACLE_PATH):
            os.unlink(ORACLE_PATH)
        with open(ORACLE_PATH, "wb") as handle:
            handle.write(oracle_bytes)
        os.chmod(ORACLE_PATH, oracle_mode)


def find_restored_repo():
    candidates = []
    for root, dirs, _files in os.walk("/home/user"):
        if ".git" in dirs:
            candidates.append(root)
            dirs.remove(".git")

    for repo in candidates:
        log = subprocess.run(
            ["git", "-C", repo, "log", "--format=%H%x00%s"],
            capture_output=True,
            text=True,
        )
        if log.returncode != 0:
            continue
        for line in log.stdout.splitlines():
            parts = line.split("\x00", 1)
            if len(parts) != 2 or parts[1] != "revert bash experiment":
                continue
            recovered = subprocess.run(
                ["git", "-C", repo, "show", f"{parts[0]}^:parser.sh"],
                capture_output=True,
                text=True,
            )
            if recovered.returncode == 0 and "API_TOKEN=TOKEN_99A" in recovered.stdout:
                return repo
    return None


def test_parser_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Missing agent script: {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script is not executable: {AGENT_PATH}"
    assert stat.S_ISREG(os.lstat(AGENT_PATH).st_mode), "parser.sh must be a regular file, not a symlink"

    with open(AGENT_PATH, "rb") as handle:
        parser_bytes = handle.read()
    with open(ORACLE_PATH, "rb") as handle:
        oracle_bytes = handle.read()

    assert parser_bytes.startswith((b"#!/bin/bash", b"#!/usr/bin/env bash")), \
        "parser.sh must be a Bash script"
    assert hashlib.sha256(parser_bytes).digest() != hashlib.sha256(oracle_bytes).digest(), \
        "Submission is byte-identical to the legacy oracle"
    assert b"legacy_oracle" not in parser_bytes, \
        "parser.sh must implement the work rather than invoke the legacy oracle"


def test_repository_recovery_and_chunker_build():
    repo = find_restored_repo()
    assert repo is not None, \
        "No extracted Git repository under /home/user contains the deleted parser and recovered token"
    assert os.path.isfile(os.path.join(repo, "src", "chunker.c")), "Missing recovered src/chunker.c"
    assert os.path.isfile(os.path.join(repo, "Makefile")), "Missing repaired Makefile"

    possible_outputs = [os.path.join(repo, "chunker"), os.path.join(repo, "src", "chunker")]
    for output in possible_outputs:
        if os.path.lexists(output):
            os.unlink(output)

    built = subprocess.run(
        ["make", "-C", repo],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert built.returncode == 0, f"make failed:\n{built.stdout}\n{built.stderr}"

    chunkers = [path for path in possible_outputs if os.path.isfile(path) and os.access(path, os.X_OK)]
    assert chunkers, "make did not build an executable chunker"
    result = subprocess.run(chunkers[0:1], capture_output=True, text=True, timeout=2)
    assert result.returncode == 0, f"chunker failed: {result.stderr}"
    assert result.stdout == "chunker\n", f"Unexpected chunker output: {result.stdout!r}"


def test_database_query_and_corrupt_input_handling():
    nonce = "verifier_" + secrets.token_hex(16)
    with tempfile.TemporaryDirectory() as tmpdir:
        backup = os.path.join(tmpdir, "meta.db.backup")
        shutil.copyfile(DB_PATH, backup)
        try:
            connection = sqlite3.connect(DB_PATH)
            connection.execute("DELETE FROM metadata")
            connection.execute(
                "INSERT INTO metadata(token, value) VALUES (?, ?)",
                ("WRONG_TOKEN", "duplicate_noise"),
            )
            connection.execute(
                "INSERT INTO metadata(token, value) VALUES (?, ?)",
                ("ANOTHER_TOKEN", "duplicate_noise"),
            )
            connection.execute(
                "INSERT INTO metadata(token, value) VALUES (?, ?)",
                ("TOKEN_99A", nonce),
            )
            connection.commit()
            connection.close()

            valid = os.path.join(tmpdir, "valid.bin")
            corrupt = os.path.join(tmpdir, "corrupt.bin")
            short = os.path.join(tmpdir, "short.bin")
            with open(valid, "wb") as handle:
                handle.write(b"AUDI" + os.urandom(28))
            with open(corrupt, "wb") as handle:
                handle.write(b"CORR" + os.urandom(28))
            with open(short, "wb") as handle:
                handle.write(b"AUDI")

            with oracle_unavailable():
                code, out, _err = run_program(AGENT_PATH, [valid])
                expected = json.dumps(
                    {"status": "success", "token": "TOKEN_99A", "data": nonce},
                    separators=(", ", ": "),
                ) + "\n"
                assert code == 0, f"Valid input exited with {code}"
                assert out == expected, f"Database result mismatch: expected {expected!r}, got {out!r}"

                code, out, _err = run_program(AGENT_PATH, [corrupt])
                assert code == 1
                assert out == '{"status": "error", "reason": "corrupt_header"}\n'

                code, out, _err = run_program(AGENT_PATH, [short])
                assert code == 1
                assert out == '{"status": "error", "reason": "file_too_short"}\n'
        finally:
            shutil.copyfile(backup, DB_PATH)


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Missing legacy oracle: {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Legacy oracle is not executable: {ORACLE_PATH}"

    random.seed(42)
    with tempfile.TemporaryDirectory() as tmpdir:
        cases = []
        for i in range(N_FUZZ):
            rand_val = random.random()
            if rand_val < 0.2:
                category = 0
            elif rand_val < 0.6:
                category = 1
            elif rand_val < 0.9:
                category = 2
            else:
                category = 3

            test_file = os.path.join(tmpdir, f"fuzz_{i}.bin")
            generate_fuzz_file(test_file, category)
            oracle_code, oracle_out, oracle_err = run_program(ORACLE_PATH, [test_file])
            cases.append((i, category, test_file, oracle_code, oracle_out, oracle_err))

        no_arg_expected = run_program(ORACLE_PATH, [])
        two_arg_expected = run_program(ORACLE_PATH, [cases[0][2], cases[1][2]])

        with oracle_unavailable():
            for i, category, test_file, oracle_code, oracle_out, oracle_err in cases:
                agent_code, agent_out, agent_err = run_program(AGENT_PATH, [test_file])
                error_msg = (
                    f"Mismatch on fuzz input {i} (category {category}, size {os.path.getsize(test_file)}).\n"
                    f"Oracle exited with {oracle_code}, Agent exited with {agent_code}.\n"
                    f"Oracle stdout:\n{oracle_out}\nAgent stdout:\n{agent_out}\n"
                    f"Oracle stderr:\n{oracle_err}\nAgent stderr:\n{agent_err}\n"
                )
                assert oracle_code == agent_code, error_msg
                assert oracle_out == agent_out, error_msg

            agent_no_arg = run_program(AGENT_PATH, [])
            assert agent_no_arg[:2] == no_arg_expected[:2], "No-argument behavior differs from oracle"
            agent_two_arg = run_program(AGENT_PATH, [cases[0][2], cases[1][2]])
            assert agent_two_arg[:2] == two_arg_expected[:2], "Two-argument behavior differs from oracle"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
