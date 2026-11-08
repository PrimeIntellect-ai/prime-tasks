#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import statistics
import struct
import subprocess
import sys
import tempfile

import pytest
from scapy.all import Ether, IP, Raw, UDP
from scapy.utils import PcapWriter

ANALYZER = "/home/user/sensor_analyzer.py"
OUTPUT_RE = re.compile(r"^StdDev:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)$")


def run_analyzer(pcap_path):
    assert os.path.isfile(ANALYZER), f"Analyzer {ANALYZER} is missing."
    result = subprocess.run(
        [sys.executable, ANALYZER, pcap_path],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Analyzer failed on {pcap_path}:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    match = OUTPUT_RE.fullmatch(result.stdout.strip())
    assert match, f"Unexpected analyzer output: {result.stdout!r}"
    value = float(match.group(1))
    assert math.isfinite(value), f"Analyzer returned a non-finite value: {value}"
    return value


def write_case(path, values):
    with PcapWriter(path, append=False, sync=True) as pcap:
        # These packets must not affect the answer.
        pcap.write(Ether()/IP(dst="127.0.0.1")/UDP(dport=9998, sport=1234)/Raw(struct.pack(">i", 123456789)))
        pcap.write(Ether()/IP(dst="127.0.0.1")/UDP(dport=9999, sport=1234)/Raw(b"\x01\x02\x03"))

        for index, value in enumerate(values):
            payload = struct.pack(">i", value)
            if index % 2:
                payload += b"ignored-trailing-data"
            pcap.write(Ether()/IP(dst="127.0.0.1")/UDP(dport=9999, sport=1234)/Raw(payload))


def assert_case(values):
    with tempfile.TemporaryDirectory() as tmpdir:
        pcap_path = os.path.join(tmpdir, "case.pcap")
        write_case(pcap_path, values)
        actual = run_analyzer(pcap_path)

    expected = statistics.pstdev(values) if values else 0.0
    assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-5), (
        f"Expected population StdDev {expected:.12g} for generated readings, got {actual:.12g}"
    )


def test_result_file_exists_and_correct():
    path = "/home/user/result.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did you run the script and redirect output?"

    with open(path, 'r') as f:
        content = f.read().strip()

    assert "StdDev:" in content, f"Output in {path} does not contain 'StdDev:'"

    # Extract the number
    try:
        val_str = content.split("StdDev:")[1].strip()
        val = float(val_str)
    except Exception as e:
        pytest.fail(f"Could not parse standard deviation from {path}: {e}")

    # The expected population stddev for [-1000000000, -1000000001, -1000000002]
    # Variance is 2/3, stddev is sqrt(2/3) ~ 0.81649658
    expected = math.sqrt(2.0 / 3.0)
    assert math.isclose(val, expected, rel_tol=1e-4), f"Expected StdDev close to {expected:.6f}, got {val}"

    # Also execute the submitted analyzer on the supplied target PCAP.
    target_val = run_analyzer("/home/user/test.pcap")
    assert math.isclose(target_val, expected, rel_tol=1e-9, abs_tol=1e-5), (
        f"Analyzer itself returned {target_val}, expected {expected:.6f} on test.pcap"
    )


def test_generated_signed_and_stable_cases():
    rng = secrets.SystemRandom()

    # Mixed-sign values distinguish signed decoding from unsigned decoding.
    for _ in range(3):
        values = [
            -rng.randint(1_200_000_000, 2_000_000_000),
            -rng.randint(10_000, 900_000_000),
            rng.randint(-100, 100),
            rng.randint(10_000, 900_000_000),
            rng.randint(1_200_000_000, 2_000_000_000),
        ]
        rng.shuffle(values)
        assert_case(values)

    # Large, tightly clustered values expose catastrophic cancellation while
    # still having a nonzero standard deviation that must be computed correctly.
    for sign in (1, -1):
        base = sign * rng.randint(1_100_000_000, 1_900_000_000)
        offsets = [rng.randint(0, 7) for _ in range(257)]
        offsets[0] = 0
        offsets[1] = 7
        values = [base + sign * offset for offset in offsets]
        assert_case(values)


def test_fuzzing_passes():
    fuzz_script = "/home/user/fuzz.sh"
    assert os.path.isfile(fuzz_script), f"Fuzz script {fuzz_script} missing."

    # Run the fuzz script to ensure the numerical instability bug is fixed
    result = subprocess.run(["bash", fuzz_script], capture_output=True, text=True)
    assert result.returncode == 0, f"Fuzz test failed, indicating numerical instability is still present:\n{result.stdout}\n{result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
