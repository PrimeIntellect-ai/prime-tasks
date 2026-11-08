#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shlex
import shutil
import subprocess
import tempfile
from decimal import Decimal

import pytest
from scapy.all import IP, UDP, Raw, wrpcap


def test_pipeline_execution_and_output():
    script_path = "/home/user/pipeline/run.sh"
    assert os.path.isfile(script_path), f"Script not found: {script_path}"

    output_file = "/home/user/pipeline/output/results.txt"
    if os.path.exists(output_file):
        os.remove(output_file)

    # Execute the pipeline script
    result = subprocess.run(
        ["bash", script_path],
        cwd="/home/user/pipeline",
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"run.sh failed to execute. stderr: {result.stderr}"

    assert os.path.isfile(output_file), f"Output file not generated at expected path: {output_file}"

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines of output, but got {len(lines)}: {lines}"

    # Verify no floating point anomalies are present in the strings
    for i, line in enumerate(lines, start=1):
        assert "0.30000000000000004" not in line, f"Floating point anomaly found in output line {i}: {line}"

    # Extract the summed values
    try:
        val1 = lines[0].split(":")[1].strip()
        val2 = lines[1].split(":")[1].strip()
        val3 = lines[2].split(":")[1].strip()
    except IndexError:
        pytest.fail(f"Output lines are not formatted as 'Packet <N>: <Sum>'. Got: {lines}")

    # Verify string representations to ensure precision correctness
    assert val1 in ["0.3", "0.30"], f"Packet 1 value incorrect or imprecise: {val1}"
    assert val2 in ["0.3", "0.30"], f"Packet 2 value incorrect or imprecise: {val2}"
    assert val3 in ["0.8", "0.80"], f"Packet 3 value incorrect or imprecise: {val3}"

    # Verify prefix formatting
    assert lines[0].startswith("Packet 1:"), f"Line 1 prefix incorrect: {lines[0]}"
    assert lines[1].startswith("Packet 2:"), f"Line 2 prefix incorrect: {lines[1]}"
    assert lines[2].startswith("Packet 3:"), f"Line 3 prefix incorrect: {lines[2]}"


def _make_precision_sensitive_pairs(count):
    pairs = []
    while len(pairs) < count:
        scale = secrets.choice(range(2, 10))
        denominator = 10 ** scale
        a = Decimal(secrets.randbelow(denominator * 8) + 1) / Decimal(denominator)
        b = Decimal(secrets.randbelow(denominator * 8) + 1) / Decimal(denominator)
        a_text = format(a, f".{scale}f")
        b_text = format(b, f".{scale}f")
        exact = Decimal(a_text) + Decimal(b_text)
        float_result = Decimal(str(float(a_text) + float(b_text)))
        if float_result != exact:
            pairs.append((a_text, b_text, exact))
    return pairs


def test_pipeline_on_unseen_pcap_and_spaced_paths():
    pipeline_dir = "/home/user/pipeline"
    script_path = os.path.join(pipeline_dir, "run.sh")
    config_path = os.path.join(pipeline_dir, "config.env")
    assert os.path.isfile(script_path), f"Script not found: {script_path}"
    assert os.path.isfile(config_path), f"Configuration not found: {config_path}"

    with open(config_path, "rb") as f:
        original_config = f.read()

    root = tempfile.mkdtemp(prefix="pipeline verification ")
    data_dir = os.path.join(root, "unseen raw data")
    output_dir = os.path.join(root, "new output directory")
    os.makedirs(data_dir)
    os.makedirs(output_dir)

    pairs = _make_precision_sensitive_pairs(5)
    packets = []
    for a_text, b_text, _ in pairs:
        payload = ('{"v1": %s, "v2": %s}' % (a_text, b_text)).encode("ascii")
        packets.append(IP(dst="127.0.0.1") / UDP(dport=5000) / Raw(load=payload))

    # These packets must not be treated as destination-port-5000 sensor payloads.
    packets.insert(2, IP(dst="127.0.0.1") / UDP(dport=4000) /
                   Raw(load=b'{"v1": 99.1, "v2": 99.2}'))
    pcap_path = os.path.join(data_dir, "unseen sensor input.pcap")
    wrpcap(pcap_path, packets)

    try:
        with open(config_path, "w", encoding="utf-8") as f:
            f.write(f"DATA_DIR={shlex.quote(data_dir)}\n")
            f.write(f"OUTPUT_DIR={shlex.quote(output_dir)}\n")

        result = subprocess.run(
            ["bash", script_path],
            cwd=pipeline_dir,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"run.sh failed for an unseen PCAP in paths containing spaces. "
            f"stdout: {result.stdout} stderr: {result.stderr}"
        )

        output_file = os.path.join(output_dir, "results.txt")
        assert os.path.isfile(output_file), f"Output file not generated at expected path: {output_file}"
        with open(output_file, encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]

        assert len(lines) == len(pairs), (
            f"Expected {len(pairs)} processed UDP payloads, got {len(lines)}: {lines}"
        )
        for index, (line, (_, _, expected)) in enumerate(zip(lines, pairs), start=1):
            match = re.fullmatch(
                r"Packet ([0-9]+): ([+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))",
                line,
            )
            assert match, f"Incorrect output format on line {index}: {line}"
            assert int(match.group(1)) == index, f"Incorrect packet number on line {index}: {line}"
            actual_text = match.group(2)
            assert Decimal(actual_text) == expected, (
                f"Packet {index} must equal the exact decimal sum {expected}, got {actual_text}"
            )
    finally:
        with open(config_path, "wb") as f:
            f.write(original_config)
        shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
