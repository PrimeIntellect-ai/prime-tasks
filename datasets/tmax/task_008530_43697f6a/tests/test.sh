#!/bin/bash
set -e
mkdir -p /logs/verifier

BINARY=$(mktemp /tmp/policy_enforcer_test.XXXXXX)
trap 'rm -f "$BINARY"' EXIT

if ! (cd /home/user && g++ -std=c++17 /home/user/policy_enforcer.cpp -o "$BINARY" -lssl -lcrypto); then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

rm -f /home/user/audit_report.csv
if ! (cd /home/user && timeout 20 "$BINARY"); then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
export POLICY_ENFORCER_BINARY="$BINARY"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import csv
import subprocess
import uuid


def test_cpp_source_exists():
    path = "/home/user/policy_enforcer.cpp"
    assert os.path.isfile(path), f"Expected C++ source file {path} is missing."


def test_audit_report_exists():
    path = "/home/user/audit_report.csv"
    assert os.path.isfile(path), f"Expected report file {path} is missing."


def test_audit_report_content():
    deployments_path = "/home/user/deployments.json"
    dictionary_path = "/home/user/dictionary.txt"
    report_path = "/home/user/audit_report.csv"

    assert os.path.isfile(deployments_path), f"Missing {deployments_path}"
    assert os.path.isfile(dictionary_path), f"Missing {dictionary_path}"
    assert os.path.isfile(report_path), f"Missing {report_path}"

    with open(dictionary_path, "r") as f:
        words = [line.strip() for line in f if line.strip()]

    hash_to_word = {}
    for word in words:
        md5_hash = hashlib.md5(word.encode('utf-8')).hexdigest()
        hash_to_word[md5_hash] = word

    with open(deployments_path, "r") as f:
        deployments = json.load(f)

    expected_rows = [["app_name", "password_cracked", "csp_secure"]]
    for dep in deployments:
        app_name = dep.get("app_name", "")
        admin_hash = dep.get("admin_hash", "")
        csp_header = dep.get("csp_header", "")
        password_cracked = hash_to_word.get(admin_hash, "SAFE")
        if "unsafe-inline" in csp_header or "unsafe-eval" in csp_header:
            csp_secure = "FAIL"
        else:
            csp_secure = "PASS"
        expected_rows.append([app_name, password_cracked, csp_secure])

    actual_rows = []
    with open(report_path, "r", newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, but found {len(actual_rows)}."
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch: expected {expected}, got {actual}."


def test_audit_report_formatting():
    report_path = "/home/user/audit_report.csv"
    assert os.path.isfile(report_path), f"Missing {report_path}"

    with open(report_path, "rb") as f:
        content = f.read()

    assert b"\r\n" not in content, "CSV file contains Windows-style (CRLF) newlines instead of Unix-style (LF)."
    lines = content.decode('utf-8').split('\n')
    for line in lines:
        if line:
            assert ", " not in line and " ," not in line, f"Extra spaces found around commas in line: '{line}'"


def test_compiled_program_processes_unseen_inputs():
    deployments_path = "/home/user/deployments.json"
    dictionary_path = "/home/user/dictionary.txt"
    report_path = "/home/user/audit_report.csv"
    binary = os.environ["POLICY_ENFORCER_BINARY"]

    with open(deployments_path, "rb") as f:
        original_deployments = f.read()
    with open(dictionary_path, "rb") as f:
        original_dictionary = f.read()
    with open(report_path, "rb") as f:
        original_report = f.read()

    token = uuid.uuid4().hex
    first_password = "weak_" + token
    second_password = "guess_" + token
    unknown_password = "unknown_" + token
    deployments = [
        {
            "app_name": "DynamicAlpha_" + token,
            "admin_hash": hashlib.md5(second_password.encode()).hexdigest(),
            "csp_header": "default-src 'self'; object-src 'none'"
        },
        {
            "app_name": "DynamicBeta_" + token,
            "admin_hash": hashlib.md5(unknown_password.encode()).hexdigest(),
            "csp_header": "default-src 'self'; script-src 'unsafe-inline'"
        },
        {
            "app_name": "DynamicGamma_" + token,
            "admin_hash": hashlib.md5(first_password.encode()).hexdigest(),
            "csp_header": "script-src 'self' 'unsafe-eval'"
        },
        {
            "app_name": "DynamicDelta_" + token,
            "admin_hash": hashlib.md5((unknown_password + "x").encode()).hexdigest(),
            "csp_header": "default-src https://example.invalid"
        }
    ]
    expected = [
        ["app_name", "password_cracked", "csp_secure"],
        ["DynamicAlpha_" + token, second_password, "PASS"],
        ["DynamicBeta_" + token, "SAFE", "FAIL"],
        ["DynamicGamma_" + token, first_password, "FAIL"],
        ["DynamicDelta_" + token, "SAFE", "PASS"]
    ]

    try:
        with open(dictionary_path, "w", newline="\n") as f:
            f.write(first_password + "\n" + second_password + "\n")
        with open(deployments_path, "w", newline="\n") as f:
            json.dump(deployments, f)
            f.write("\n")
        os.remove(report_path)

        subprocess.run([binary], cwd="/home/user", check=True, timeout=20)
        assert os.path.isfile(report_path), "Compiled program did not generate audit_report.csv."
        with open(report_path, "r", newline="") as f:
            actual = list(csv.reader(f))
        assert actual == expected, f"Compiled program produced incorrect output for unseen inputs: {actual}"
    finally:
        with open(deployments_path, "wb") as f:
            f.write(original_deployments)
        with open(dictionary_path, "wb") as f:
            f.write(original_dictionary)
        with open(report_path, "wb") as f:
            f.write(original_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
