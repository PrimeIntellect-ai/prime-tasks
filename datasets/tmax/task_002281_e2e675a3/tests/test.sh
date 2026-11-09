#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import secrets
import stat
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

import pytest


def test_secure_data_permissions():
    crt_file = Path("/app/secure_data/server.crt")
    key_file = Path("/app/secure_data/server.key")

    assert crt_file.exists(), f"Missing file: {crt_file}"
    assert key_file.exists(), f"Missing file: {key_file}"

    try:
        www_data_uid = pwd.getpwnam("www-data").pw_uid
    except KeyError:
        pytest.fail("User 'www-data' does not exist")

    crt_stat = crt_file.stat()
    key_stat = key_file.stat()

    assert crt_stat.st_uid == www_data_uid, f"Expected {crt_file} to be owned by www-data"
    assert key_stat.st_uid == www_data_uid, f"Expected {key_file} to be owned by www-data"
    assert stat.S_IMODE(crt_stat.st_mode) == 0o444, f"Expected {crt_file} to have 0444 permissions"
    assert stat.S_IMODE(key_stat.st_mode) == 0o400, f"Expected {key_file} to have 0400 permissions"


def test_services_running_and_proxy_pass():
    try:
        req = urllib.request.Request("http://127.0.0.1:8080/api/health")
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected 200 OK, got {response.status}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx or backend via Nginx: {e}")


def run_filter(executable, input_bytes, expected_lines, description):
    expected = b"".join((line + "\n").encode("ascii") for line in expected_lines)
    try:
        result = subprocess.run(
            [str(executable)],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out while processing {description}")

    assert result.returncode == 0, (
        f"Filter exited with status {result.returncode} while processing {description}; "
        f"stderr={result.stderr!r}"
    )
    assert result.stdout == expected, (
        f"Incorrect or incorrectly formatted output for {description}: "
        f"expected {expected!r}, got {result.stdout!r}"
    )
    return result.stdout


def corpus_line_count(data):
    return len(data.splitlines())


def test_filter_binary_adversarial_corpus(tmp_path):
    filter_source = Path("/home/user/filter.c")
    filter_bin = Path("/home/user/filter")

    assert filter_source.exists(), f"Missing C source: {filter_source}"
    assert filter_source.is_file(), f"C source is not a regular file: {filter_source}"
    assert filter_bin.exists(), f"Missing filter binary: {filter_bin}"
    assert filter_bin.is_file(), f"Filter binary is not a regular file: {filter_bin}"
    assert os.access(filter_bin, os.X_OK), f"Filter binary is not executable: {filter_bin}"
    assert filter_bin.read_bytes()[:4] == b"\x7fELF", "Compiled filter is not an ELF binary"

    rebuilt_filter = tmp_path / "filter-rebuilt"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", str(filter_source), "-o", str(rebuilt_filter)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert compile_result.returncode == 0, (
        "filter.c does not compile successfully with gcc: " + compile_result.stderr.decode(errors="replace")
    )
    assert rebuilt_filter.read_bytes()[:4] == b"\x7fELF"

    clean_corpus = Path("/app/corpus/clean")
    evil_corpus = Path("/app/corpus/evil")
    assert clean_corpus.is_dir(), f"Missing clean corpus dir: {clean_corpus}"
    assert evil_corpus.is_dir(), f"Missing evil corpus dir: {evil_corpus}"

    clean_files = [p for p in clean_corpus.glob("*") if p.is_file()]
    evil_files = [p for p in evil_corpus.glob("*") if p.is_file()]
    assert clean_files, "Clean corpus contains no files"
    assert evil_files, "Evil corpus contains no files"

    executables = [filter_bin, rebuilt_filter]
    for executable in executables:
        for corpus_file in clean_files:
            data = corpus_file.read_bytes()
            run_filter(
                executable,
                data,
                ["ACCEPT"] * corpus_line_count(data),
                f"clean corpus file {corpus_file.name}",
            )

        for corpus_file in evil_files:
            data = corpus_file.read_bytes()
            run_filter(
                executable,
                data,
                ["REJECT"] * corpus_line_count(data),
                f"evil corpus file {corpus_file.name}",
            )

    token = secrets.token_hex(12)
    octets = secrets.token_bytes(4)
    ip1 = f"10.{octets[0]}.{octets[1]}.{octets[2]}"
    ip2 = f"172.16.{octets[2]}.{octets[3]}"

    dynamic_lines = [
        f"{ip1} GET /articles/{token}",
        f"{ip2} GET /search?q={token} ' OR '1'='1",
        f"{ip1} GET /reports/{token} UNION SELECT password FROM users",
        f"{ip2} GET /page?q=<script>alert('{token}')</script>",
        f"{ip1} GET /image?tag=<img src=x onerror=alert('{token}')>",
    ]
    dynamic_expected = ["ACCEPT", "REJECT", "REJECT", "REJECT", "REJECT"]

    for _ in range(7):
        dynamic_lines.append(f"{ip1} GET /login user={token}")
    dynamic_expected.extend(["ACCEPT"] * 5 + ["REJECT"] * 2)

    dynamic_lines.extend([
        f"{ip1} GET /home/{token}",
        f"{ip1} GET /login user={token}",
        f"{ip2} GET /login user={token}",
        f"{ip1} GET /login user={token}",
    ])
    dynamic_expected.extend(["ACCEPT", "ACCEPT", "ACCEPT", "ACCEPT"])
    dynamic_input = ("\n".join(dynamic_lines) + "\n").encode("utf-8")

    for executable in executables:
        run_filter(executable, dynamic_input, dynamic_expected, "generated adversarial cases")


def test_verification_log_exists():
    ver_log = Path("/home/user/verification.log")
    evil_log = Path("/app/corpus/evil/test_log_1.txt")
    filter_bin = Path("/home/user/filter")

    assert ver_log.exists(), f"Missing verification log: {ver_log}"
    content = ver_log.read_text()
    assert "ACCEPT" in content or "REJECT" in content, "verification.log does not contain expected filter output"
    assert evil_log.is_file(), f"Missing required evil log: {evil_log}"

    result = subprocess.run(
        [str(filter_bin)],
        input=evil_log.read_bytes(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, "Filter failed when reproducing verification.log"
    assert ver_log.read_bytes() == result.stdout, (
        "verification.log is not the exact output of running the filter against test_log_1.txt"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
