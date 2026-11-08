#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import os
import re
import runpy


def evidence_port(path):
    with open(path, "r") as f:
        tree = ast.parse(f.read(), filename=path)

    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "bind":
            if node.args and isinstance(node.args[0], ast.Tuple) and len(node.args[0].elts) == 2:
                port_node = node.args[0].elts[1]
                if isinstance(port_node, ast.Constant) and isinstance(port_node.value, int):
                    return port_node.value
    raise AssertionError("Could not determine listening port from evidence")


def test_forensics_report():
    report_path = "/home/user/forensics_report.txt"
    evidence_path = "/home/user/evidence/service.py"

    assert os.path.exists(report_path), f"Report file missing: {report_path}"
    assert os.path.isfile(report_path), f"Path is not a file: {report_path}"
    assert os.path.isfile(evidence_path), f"Evidence file missing: {evidence_path}"

    evidence = runpy.run_path(evidence_path)
    expected_payload = evidence["get_p"]()
    expected_port = evidence_port(evidence_path)
    expected_hash = hashlib.sha256(expected_payload.encode("utf-8")).hexdigest()

    with open(report_path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in the report, found {len(lines)}"

    port_match = re.match(r"^Port:\s*(\d+)$", lines[0])
    assert port_match, f"Line 1 does not match 'Port: [port number]'. Found: {lines[0]}"
    assert port_match.group(1) == "44444", f"Expected Port 44444, found {port_match.group(1)}"
    assert int(port_match.group(1)) == expected_port, f"Reported port does not match evidence: {expected_port}"

    payload_match = re.match(r"^Payload:\s*(.+)$", lines[1])
    assert payload_match, f"Line 2 does not match 'Payload: [payload]'. Found: {lines[1]}"
    assert payload_match.group(1) == "<img src=x onerror=alert('pwned')>", f"Expected Payload '<img src=x onerror=alert('pwned')>', found {payload_match.group(1)}"
    assert payload_match.group(1) == expected_payload, "Reported payload does not match decoded evidence"

    hash_match = re.match(r"^Hash:\s*([a-fA-F0-9]{64})$", lines[2])
    assert hash_match, f"Line 3 does not match 'Hash: [SHA-256 hash]'. Found: {lines[2]}"
    assert hash_match.group(1).lower() == "f17711fde97843d1a473c22ff7ee8c15eb18daec3ce9516d2f3c30ea515cc606", f"Expected Hash f17711fde97843d1a473c22ff7ee8c15eb18daec3ce9516d2f3c30ea515cc606, found {hash_match.group(1)}"
    assert hash_match.group(1).lower() == expected_hash, "Reported hash does not match the SHA-256 of the decoded evidence payload"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
