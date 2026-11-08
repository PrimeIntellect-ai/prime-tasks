#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import stat
import struct
import subprocess
import tempfile
from decimal import Decimal

PCAP_PATH = "/home/user/billing_dump.pcap"
INPUT_PATH = "/home/user/input.json"
SCRIPT_PATH = "/home/user/billing.py"
TOTAL_PATH = "/home/user/total.txt"
BAD_TX_PATH = "/home/user/bad_tx.txt"


def load_json_exact(raw):
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8")
    return json.loads(raw, parse_float=Decimal, parse_int=Decimal)


def extract_http_json_from_pcap(path):
    with open(path, "rb") as f:
        raw = f.read()

    assert len(raw) >= 24, "Packet capture is too short to contain a PCAP header."
    magic = raw[:4]
    if magic == b"\xd4\xc3\xb2\xa1":
        endian = "<"
    elif magic == b"\xa1\xb2\xc3\xd4":
        endian = ">"
    else:
        raise AssertionError("billing_dump.pcap has an invalid PCAP magic value.")

    offset = 24
    bodies = []
    while offset < len(raw):
        assert offset + 16 <= len(raw), "Truncated PCAP packet header."
        _, _, included_len, _ = struct.unpack(endian + "IIII", raw[offset:offset + 16])
        offset += 16
        assert offset + included_len <= len(raw), "Truncated PCAP packet data."
        packet = raw[offset:offset + included_len]
        offset += included_len

        marker = b"\r\n\r\n"
        if b"HTTP/" in packet and marker in packet:
            bodies.append(packet.split(marker, 1)[1])

    assert bodies, "No HTTP response payload was found in billing_dump.pcap."
    for body in bodies:
        try:
            return body, load_json_exact(body)
        except (UnicodeDecodeError, json.JSONDecodeError):
            pass
    raise AssertionError("No valid JSON HTTP response payload was found in billing_dump.pcap.")


def run_billing(input_path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, input_path],
        capture_output=True,
        text=True,
        timeout=15,
    )


def test_input_json_extracted():
    path = INPUT_PATH
    assert os.path.isfile(path), f"File {path} does not exist. Payload was not extracted."

    with open(path, "rb") as f:
        raw_input = f.read()
    try:
        data = load_json_exact(raw_input)
    except (UnicodeDecodeError, json.JSONDecodeError):
        assert False, f"{path} does not contain valid JSON."

    assert "expected_total" in data, "Extracted JSON is missing 'expected_total'."
    assert "transactions" in data, "Extracted JSON is missing 'transactions'."
    assert str(data["expected_total"]) == "10000000000000000.05", "Extracted JSON has incorrect 'expected_total'."

    _, packet_data = extract_http_json_from_pcap(PCAP_PATH)
    expected_packet_data = {
        "expected_total": "10000000000000000.05",
        "transactions": [
            {"id": "tx_normal_1", "amount": Decimal("100.0")},
            {"id": "tx_giant_bug", "amount": Decimal("10000000000000000.0")},
            {"id": "tx_micro_1", "amount": Decimal("0.02")},
            {"id": "tx_micro_2", "amount": Decimal("0.03")},
            {"id": "tx_normal_2", "amount": Decimal("-100.0")},
        ],
    }
    assert packet_data == expected_packet_data, "The packet capture payload was altered or is not the supplied billing payload."
    assert data == packet_data, "input.json does not match the JSON HTTP payload in billing_dump.pcap."


def test_bad_tx_identified():
    path = BAD_TX_PATH
    assert os.path.isfile(path), f"File {path} does not exist. Bad transaction not identified."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "tx_giant_bug", f"Incorrect transaction ID in {path}: expected 'tx_giant_bug', got '{content}'."

    _, packet_data = extract_http_json_from_pcap(PCAP_PATH)
    derived_bad_id = max(
        packet_data["transactions"],
        key=lambda tx: abs(Decimal(str(tx["amount"])))
    )["id"]
    assert content == derived_bad_id, "bad_tx.txt does not identify the abnormally large transaction in the captured payload."


def test_total_txt_correct():
    path = TOTAL_PATH
    assert os.path.isfile(path), f"File {path} does not exist. Fixed script did not write the total."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "10000000000000000.05", f"Incorrect total in {path}: expected '10000000000000000.05', got '{content}'."


def test_billing_py_uses_decimal():
    path = SCRIPT_PATH
    assert os.path.isfile(path), f"File {path} does not exist."
    assert not os.path.islink(path), f"File {path} must be a regular script, not a symbolic link."
    assert stat.S_ISREG(os.stat(path).st_mode), f"File {path} is not a regular file."

    with open(path, "r") as f:
        content = f.read()

    assert "decimal" in content.lower(), "The script billing.py does not appear to use the 'decimal' module as required."
    try:
        tree = ast.parse(content)
    except SyntaxError as exc:
        assert False, f"billing.py is not valid Python: {exc}"
    imports_decimal = any(
        (isinstance(node, ast.Import) and any(alias.name == "decimal" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "decimal")
        for node in ast.walk(tree)
    )
    assert imports_decimal, "billing.py must import and use Python's built-in decimal module."


def test_billing_py_execution():
    if not os.path.isfile(INPUT_PATH):
        assert False, f"Cannot test execution because {INPUT_PATH} is missing."

    result = run_billing(INPUT_PATH)
    assert result.returncode == 0, f"billing.py failed to execute successfully.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    assert os.path.isfile(TOTAL_PATH), "billing.py did not create total.txt when executed."
    with open(TOTAL_PATH) as f:
        assert f.read().strip() == "10000000000000000.05", "billing.py did not write the validated exact total."


def test_billing_computes_exact_sum_and_validates_checksum():
    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()

    giant = 10**24 + secrets.randbelow(10**8)
    cents_a = secrets.randbelow(89) + 10
    cents_b = secrets.randbelow(89) + 10
    amount_tokens = [
        str(giant),
        f"0.{cents_a:02d}",
        "37.40",
        f"0.{cents_b:02d}",
        "-37.40",
    ]
    expected = sum((Decimal(token) for token in amount_tokens), Decimal(0))
    expected_text = format(expected, ".2f")
    tx_ids = ["probe_" + secrets.token_hex(8) for _ in amount_tokens]

    def make_payload(expected_value):
        transactions = ",".join(
            '{"id":' + json.dumps(tx_id) + ',"amount":' + token + '}'
            for tx_id, token in zip(tx_ids, amount_tokens)
        )
        return '{"expected_total":' + json.dumps(expected_value) + ',"transactions":[' + transactions + ']}'

    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            valid_path = os.path.join(tmpdir, "valid.json")
            invalid_path = os.path.join(tmpdir, "invalid.json")
            with open(valid_path, "w") as f:
                f.write(make_payload(expected_text))
            with open(invalid_path, "w") as f:
                f.write(make_payload(format(expected + Decimal("0.01"), ".2f")))

            valid = run_billing(valid_path)
            assert valid.returncode == 0, (
                "billing.py failed on a generated precision-sensitive payload.\n"
                f"STDOUT: {valid.stdout}\nSTDERR: {valid.stderr}"
            )
            assert os.path.isfile(TOTAL_PATH), "billing.py did not write total.txt for the generated valid payload."
            with open(TOTAL_PATH) as f:
                actual_total = f.read().strip()
            assert actual_total == expected_text, (
                f"billing.py did not write the exact computed total: expected {expected_text}, got {actual_total}."
            )

            invalid = run_billing(invalid_path)
            assert invalid.returncode != 0, "billing.py accepted a payload whose expected_total does not equal the transaction sum."
    finally:
        restored = run_billing(INPUT_PATH)
        assert restored.returncode == 0, "billing.py no longer succeeds on the extracted billing payload."

    with open(INPUT_PATH, "rb") as f:
        assert f.read() == original_input, "billing.py modified input.json, which is forbidden."
    with open(TOTAL_PATH) as f:
        assert f.read().strip() == "10000000000000000.05", "billing.py did not restore the correct total for input.json."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
