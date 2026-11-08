#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from decimal import Decimal
from pathlib import Path

import pytest

BASE = Path("/home/user/ticket_8841")
PAYLOADS = BASE / "extracted_payloads.txt"
AVERAGES = BASE / "final_averages.txt"
SCRIPT = BASE / "process_data.sh"
PCAP = BASE / "traffic.pcap"

EXPECTED_PAYLOADS = [
    "S1,10.50",
    "S2,20.25",
    "S1,15.75",
    "MALFORMED_DATA",
    "S2,30.75",
    "S3,100.00",
    "S3,100.05",
]


def test_extracted_payloads_exists():
    """Verify that the extracted_payloads.txt file exists."""
    assert os.path.isfile(PAYLOADS), f"File {PAYLOADS} is missing. Did you extract the payloads?"


def test_extracted_payloads_content():
    """Verify every UDP/8080 payload was extracted, in packet order, one per line."""
    result = subprocess.run(
        [
            "tshark", "-r", str(PCAP),
            "-Y", "udp.dstport == 8080",
            "-T", "fields", "-e", "udp.payload",
        ],
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr
    decoded = []
    for raw_hex in result.stdout.splitlines():
        try:
            decoded.append(bytes.fromhex(raw_hex.replace(":", "")).decode("ascii"))
        except (ValueError, UnicodeDecodeError) as exc:
            pytest.fail(f"Could not decode a UDP/8080 payload from the capture: {exc}")

    assert decoded == EXPECTED_PAYLOADS, "The supplied capture no longer contains the ticket payloads"
    assert PAYLOADS.read_text().splitlines() == EXPECTED_PAYLOADS, (
        "extracted_payloads.txt must contain exactly the ASCII UDP/8080 payloads, "
        "one per line and in packet order"
    )


def test_process_script_exists_and_is_executable():
    assert SCRIPT.is_file(), f"Processing script {SCRIPT} is missing"
    assert os.access(SCRIPT, os.X_OK), f"Processing script {SCRIPT} is not executable"


def test_final_averages_exists():
    """Verify that the final_averages.txt file exists."""
    assert os.path.isfile(AVERAGES), f"File {AVERAGES} is missing. Did you run the fixed script?"


def test_final_averages_content():
    """Verify the content and formatting of final_averages.txt."""
    if not os.path.isfile(AVERAGES):
        pytest.fail(f"Cannot check content because {AVERAGES} is missing.")

    with open(AVERAGES, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_s1 = ["S1:13.12", "S1:13.13"]
    expected_s2 = ["S2:25.50"]
    expected_s3 = ["S3:100.02", "S3:100.03"]

    assert len(lines) == 3, f"Expected exactly 3 lines in {AVERAGES}, but found {len(lines)}. Make sure malformed data is skipped."
    assert lines[0] in expected_s1, f"Line 1 expected to be one of {expected_s1}, got '{lines[0]}'"
    assert lines[1] in expected_s2, f"Line 2 expected to be one of {expected_s2}, got '{lines[1]}'"
    assert lines[2] in expected_s3, f"Line 3 expected to be one of {expected_s3}, got '{lines[2]}'"


def _fmt_cents(cents):
    return f"{cents // 100}.{cents % 100:02d}"


def _expected(records):
    sums = {}
    counts = {}
    for sensor, value in records:
        sums[sensor] = sums.get(sensor, Decimal("0")) + Decimal(value)
        counts[sensor] = counts.get(sensor, 0) + 1
    return [
        f"{sensor}:{sums[sensor] / counts[sensor]:.2f}"
        for sensor in sorted(sums)
    ]


def _make_pair():
    first = 100 + secrets.randbelow(7000)
    second = first + 2 * (1 + secrets.randbelow(300))
    return _fmt_cents(first), _fmt_cents(second)


def _run_script(input_path):
    result = subprocess.run(
        [str(SCRIPT), str(input_path)],
        cwd=str(BASE),
        text=True,
        capture_output=True,
        timeout=20,
        env={**os.environ, "LC_ALL": "C"},
    )
    assert result.returncode == 0, (
        f"process_data.sh crashed on valid data mixed with malformed/empty payloads.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert AVERAGES.is_file(), "process_data.sh did not produce final_averages.txt"
    return AVERAGES.read_text().splitlines()


def test_fixed_script_on_generated_inputs_and_repeated_runs():
    """Execute the submitted script on runtime-generated values and malformed records."""
    tracked = [AVERAGES, BASE / "intermediate_state.log"]
    backups = {p: p.read_bytes() if p.exists() else None for p in tracked}

    try:
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)

            a1, a2 = _make_pair()
            m1, m2 = _make_pair()
            z1, z2 = _make_pair()
            records1 = [("A7", a1), ("M3", m1), ("A7", a2), ("Z9", z1), ("M3", m2), ("Z9", z2)]
            input1 = tmp / "generated_one.txt"
            input1.write_text(
                f"A7,{a1}\n\nMALFORMED_DATA\nM3,{m1}\nEMPTY,\n"
                f"A7,{a2}\nZ9,{z1}\nBAD,not-a-number\nM3,{m2}\nZ9,{z2}\n"
            )
            assert _run_script(input1) == _expected(records1)

            b1, b2 = _make_pair()
            x1, x2 = _make_pair()
            records2 = [("B2", b1), ("X4", x1), ("B2", b2), ("X4", x2)]
            input2 = tmp / "generated_two.txt"
            input2.write_text(
                f"B2,{b1}\nBROKEN\nX4,{x1}\nB2,{b2}\n,12.34\nX4,{x2}\n"
            )
            assert _run_script(input2) == _expected(records2), (
                "A subsequent run must replace prior output/state rather than retaining old sensors"
            )
    finally:
        for path, content in backups.items():
            if content is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
