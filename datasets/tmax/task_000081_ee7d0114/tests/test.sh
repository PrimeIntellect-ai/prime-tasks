#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import tempfile
from decimal import Decimal, ROUND_HALF_EVEN

import pytest
from scapy.all import Ether, IP, TCP, UDP, Raw, wrpcap

PROJECT = "/home/user/ticket_8832"
RESULT = "/home/user/result.txt"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, timeout=30, **kwargs)


def expected_variance(values):
    nums = [Decimal(v) for v in values]
    mean = sum(nums) / Decimal(len(nums))
    variance = sum((v - mean) ** 2 for v in nums) / Decimal(len(nums))
    return f"{variance.quantize(Decimal('0.01'), rounding=ROUND_HALF_EVEN):.2f}"


def make_dynamic_values():
    rng = secrets.SystemRandom()
    while True:
        base = rng.randrange(1_000_000_000, 3_000_000_000)
        values = [base + rng.randrange(0, 1001) for _ in range(53)]
        expected = expected_variance(values)

        # Ensure this case detects the original catastrophic-cancellation formula
        # and is not close to a two-decimal rounding boundary.
        total = 0.0
        squares = 0.0
        for value in values:
            number = float(value)
            total += number
            squares += number * number
        naive = squares / len(values) - (total / len(values)) ** 2

        nums = [Decimal(v) for v in values]
        mean = sum(nums) / Decimal(len(nums))
        variance = sum((v - mean) ** 2 for v in nums) / Decimal(len(nums))
        fraction_of_cent = (variance * 100) % 1
        safely_rounded = abs(fraction_of_cent - Decimal("0.5")) > Decimal("0.10")
        if safely_rounded and f"{naive:.2f}" != expected:
            return values, expected


def write_test_pcap(path, values):
    packets = []
    for index, sequence in enumerate(values):
        packets.append(
            Ether(dst="00:11:22:33:44:55", src="55:44:33:22:11:00")
            / IP(src="10.23.0.1", dst="10.23.0.2")
            / TCP(sport=23456, dport=8080, seq=sequence, flags="A")
        )
        if index % 9 == 0:
            packets.append(
                Ether()
                / IP(src="10.23.0.3", dst="10.23.0.4")
                / UDP(sport=9999, dport=9998)
                / Raw(b"not tcp")
            )
    wrpcap(path, packets)


def test_result_file_exists():
    assert os.path.isfile(RESULT), f"File {RESULT} is missing. Did you save the result?"


def test_result_content():
    if not os.path.isfile(RESULT):
        pytest.fail(f"File {RESULT} is missing.")
    with open(RESULT, "r") as handle:
        content = handle.read().strip()
    expected = "833.25"
    assert content == expected, f"Expected variance to be '{expected}', but got '{content}'."


def test_repaired_artifacts_and_pipeline():
    makefile = os.path.join(PROJECT, "Makefile")
    process_script = os.path.join(PROJECT, "process_pcap.sh")
    variance_script = os.path.join(PROJECT, "calc_variance.awk")
    traffic = os.path.join(PROJECT, "traffic.pcap")
    output = os.path.join(PROJECT, "output.txt")

    assert os.path.isfile(makefile), "Makefile is missing"
    assert os.path.isfile(process_script), "process_pcap.sh is missing"
    assert os.path.isfile(variance_script), "calc_variance.awk is missing"
    mode = os.stat(process_script).st_mode
    assert stat.S_ISREG(mode) and os.access(process_script, os.X_OK), \
        "process_pcap.sh must be an executable regular file"

    values, expected = make_dynamic_values()
    with tempfile.TemporaryDirectory(prefix="ticket8832_verify_") as tempdir:
        pcap = os.path.join(tempdir, "unseen_capture.pcap")
        write_test_pcap(pcap, values)

        # Exercise the extraction script on an unseen capture containing both
        # TCP and non-TCP packets. Every absolute sequence number must be exact.
        extracted = run(
            [process_script, pcap],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout.splitlines()
        assert extracted == [str(v) for v in values], \
            "process_pcap.sh did not emit only the absolute TCP sequence numbers"

        # Exercise the awk program independently with large, varying numbers.
        awk_input = "".join(f"{v}\n" for v in values)
        calculated = run(
            ["gawk", "-f", variance_script],
            cwd=PROJECT,
            input=awk_input,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout.strip()
        assert calculated == expected, \
            f"Stable variance calculation expected {expected}, got {calculated}"

        # Replace the project capture temporarily and force the actual Makefile
        # pipeline to process data whose answer was generated at verification time.
        with open(traffic, "rb") as handle:
            original_pcap = handle.read()
        try:
            with open(pcap, "rb") as source, open(traffic, "wb") as destination:
                destination.write(source.read())
            run(["make", "clean"], cwd=PROJECT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            assert not os.path.exists(output), "make clean did not remove output.txt"
            run(["make"], cwd=PROJECT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            assert os.path.isfile(output), "make did not create output.txt"
            with open(output, "r") as handle:
                pipeline_result = handle.read().strip()
            assert pipeline_result == expected, \
                f"Makefile pipeline expected {expected}, got {pipeline_result}"
        finally:
            with open(traffic, "wb") as handle:
                handle.write(original_pcap)

    # Confirm the restored ticket capture also runs through the repaired build.
    run(["make", "clean"], cwd=PROJECT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    run(["make"], cwd=PROJECT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert os.path.isfile(output), "The restored project build did not create output.txt"
    with open(output, "r") as handle:
        assert handle.read().strip() == "833.25", \
            "The repaired pipeline produced the wrong variance for traffic.pcap"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
