#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shlex
import subprocess

FIREWALL_SOURCE = "/home/user/audit/firewall_bypass.go"
CHECKSUM_FILE = "/home/user/audit/checksums.txt"
SERVICES_DIR = "/home/user/services"


def findings():
    with open(FIREWALL_SOURCE, "r", encoding="utf-8") as f:
        source = f.read()

    hash_match = re.search(r'const\s+secretHash\s*=\s*"([0-9a-fA-F]{64})"', source)
    port_match = re.search(r'const\s+backdoorPort\s*=\s*"([0-9]+)"', source)
    assert hash_match, "Could not extract secretHash from firewall_bypass.go"
    assert port_match, "Could not extract backdoorPort from firewall_bypass.go"

    target_hash = hash_match.group(1).lower()
    matches = [
        f"{pin:04d}"
        for pin in range(10000)
        if hashlib.sha256(f"{pin:04d}".encode()).hexdigest() == target_hash
    ]
    assert len(matches) == 1, "The supplied hash must identify exactly one four-digit PIN"

    approved = {}
    with open(CHECKSUM_FILE, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            assert len(parts) == 2 and re.fullmatch(r"[0-9a-fA-F]{64}", parts[0]), \
                f"Malformed checksum entry: {line!r}"
            approved[parts[1]] = parts[0].lower()

    service_names = ["service_alpha", "service_beta", "service_gamma"]
    mismatches = []
    for name in service_names:
        assert name in approved, f"Missing approved checksum for {name}"
        path = os.path.join(SERVICES_DIR, name)
        with open(path, "rb") as f:
            actual = hashlib.sha256(f.read()).hexdigest()
        if actual != approved[name]:
            mismatches.append(name)

    assert len(mismatches) == 1, "Expected exactly one tampered service binary"
    return matches[0], port_match.group(1), mismatches[0]


def test_crack_go_executes_and_finds_pin():
    path = "/home/user/crack.go"
    assert os.path.isfile(path), f"{path} is missing"
    assert os.path.getsize(path) > 0, f"{path} is empty"

    with open(path, "r", encoding="utf-8") as f:
        source = f.read()
    assert re.search(r'["`]crypto/sha256["`]', source), \
        "crack.go must use Go's SHA256 implementation"
    assert re.search(r"\bfor\b", source), "crack.go must brute-force candidates in a loop"

    expected_pin, _, _ = findings()
    result = subprocess.run(
        ["go", "run", path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, \
        f"crack.go did not run successfully:\n{result.stdout}{result.stderr}"
    assert re.search(rf"(?<!\d){re.escape(expected_pin)}(?!\d)", result.stdout), \
        f"crack.go output did not contain the cracked PIN; output was: {result.stdout!r}"


def test_remediate_sh_is_single_valid_rule():
    path = "/home/user/remediate.sh"
    assert os.path.isfile(path), f"{path} is missing"

    with open(path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    if lines and lines[0].startswith("#!"):
        lines = lines[1:]
    assert len(lines) == 1, "remediate.sh must contain exactly one iptables command"

    try:
        tokens = shlex.split(lines[0], posix=True)
    except ValueError as exc:
        raise AssertionError(f"Invalid shell syntax in remediate.sh: {exc}")

    assert tokens and os.path.basename(tokens[0]) == "iptables", \
        "The sole command in remediate.sh must be iptables"

    expected_pin, expected_port, _ = findings()
    del expected_pin
    values = {}
    i = 1
    while i < len(tokens):
        token = tokens[i]
        if token in ("-A", "--append"):
            key = "append"
        elif token in ("-p", "--protocol"):
            key = "protocol"
        elif token in ("--dport", "--destination-port"):
            key = "dport"
        elif token in ("-j", "--jump"):
            key = "jump"
        elif token in ("-m", "--match"):
            key = "match"
        elif token in ("-t", "--table"):
            key = "table"
        else:
            raise AssertionError(f"Unexpected token in iptables command: {token!r}")

        assert key not in values, f"Duplicate iptables option for {key}"
        assert i + 1 < len(tokens), f"Missing argument after {token}"
        values[key] = tokens[i + 1]
        i += 2

    assert values.get("append") == "INPUT", "iptables rule must append to INPUT"
    assert values.get("protocol", "").lower() == "tcp", "iptables rule must specify TCP"
    assert values.get("dport") == expected_port, \
        f"iptables rule must target destination port {expected_port}"
    assert values.get("jump", "").upper() == "DROP", "iptables rule must jump to DROP"
    assert values.get("match", "tcp").lower() == "tcp", "Only the TCP matcher is valid here"
    assert values.get("table", "filter").lower() == "filter", "The rule must use the filter table"


def test_report_txt():
    path = "/home/user/report.txt"
    assert os.path.isfile(path), f"{path} is missing"

    pin, port, tampered = findings()
    expected = f"PIN: {pin}\nPORT: {port}\nTAMPERED_BINARY: {tampered}"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    assert content.rstrip("\n") == expected, \
        f"report.txt content is incorrect. Expected:\n{expected}\nGot:\n{content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
