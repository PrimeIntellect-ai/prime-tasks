#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
import tempfile
import statistics

import pytest
from scapy.all import Ether, IP, ICMP, rdpcap, wrpcap

REPO = "/home/user/sla-monitor"
SCRIPT = os.path.join(REPO, "check_sla.py")


def get_bad_commit():
    result = subprocess.run(
        ["git", "-C", REPO, "log", "--format=%H", "--grep=Optimize jitter calculation"],
        capture_output=True, text=True, check=True
    )
    commit = result.stdout.strip()
    if not commit:
        pytest.fail("Could not find the bad commit in git history.")
    return commit


def expected_jitter_for(path):
    try:
        packets = rdpcap(path)
    except Exception as e:
        pytest.fail(f"Could not read {path}: {e}")
    times = [float(p.time) for p in packets]
    intervals = [times[i] - times[i-1] for i in range(1, len(times))]
    return statistics.variance(intervals)


def get_expected_jitter():
    return expected_jitter_for(os.path.join(REPO, "prod.pcap"))


def run_script(path):
    result = subprocess.run(
        ["python3", SCRIPT, path],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"check_sla.py failed for {path} with exit code {result.returncode}: "
        f"{result.stderr}"
    )
    lines = result.stdout.splitlines()
    assert len(lines) == 1 and lines[0].strip() == lines[0] and lines[0], (
        "check_sla.py must output exactly one numeric line"
    )
    try:
        value = float(lines[0])
    except ValueError:
        pytest.fail(f"check_sla.py output is not numeric: {result.stdout!r}")
    assert math.isfinite(value), "check_sla.py output must be finite"
    return value


def make_runtime_pcap(path, intervals):
    packets = []
    timestamp = 1700000000.0 + secrets.randbelow(100000) / 1000.0
    for interval in intervals:
        timestamp += interval
        packet = Ether()/IP(dst="10.0.0.1")/ICMP()
        packet.time = timestamp
        packets.append(packet)
    wrpcap(path, packets)


def test_resolution_file_exists():
    assert os.path.exists("/home/user/resolution.txt"), "/home/user/resolution.txt does not exist."


def test_resolution_content():
    with open("/home/user/resolution.txt", "r") as f:
        raw = f.read()
    lines = raw.splitlines()

    assert len(lines) == 2, "/home/user/resolution.txt must contain exactly two lines."
    assert all(line and line == line.strip() for line in lines), (
        "/home/user/resolution.txt lines must be non-empty and contain no surrounding whitespace."
    )

    expected_commit = get_bad_commit()
    expected_jitter = get_expected_jitter()

    assert lines[0] == expected_commit, f"Line 1 should be the bad commit hash. Expected {expected_commit}, got {lines[0]}."

    try:
        actual_jitter = float(lines[1])
        assert abs(actual_jitter - expected_jitter) < 1e-8, f"Line 2 should be the expected jitter. Expected ~{expected_jitter}, got {actual_jitter}."
    except ValueError:
        pytest.fail("Line 2 in /home/user/resolution.txt is not a valid float.")


def test_final_jitter_file():
    assert os.path.exists("/home/user/final_jitter.txt"), "/home/user/final_jitter.txt does not exist."
    with open("/home/user/final_jitter.txt", "r") as f:
        content = f.read().strip()

    expected_jitter = get_expected_jitter()
    try:
        actual_jitter = float(content)
        assert abs(actual_jitter - expected_jitter) < 1e-8, f"/home/user/final_jitter.txt expected ~{expected_jitter}, got {actual_jitter}."
    except ValueError:
        pytest.fail("/home/user/final_jitter.txt does not contain a valid float.")


def test_repaired_script_exists_and_is_not_reference_copy():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist or is not a regular file."
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"{SCRIPT} is not a regular file."

    oldest = subprocess.run(
        ["git", "-C", REPO, "rev-list", "--max-parents=0", "HEAD"],
        capture_output=True, text=True, check=True
    ).stdout.splitlines()[0]
    reference = subprocess.run(
        ["git", "-C", REPO, "show", f"{oldest}:check_sla.py"],
        capture_output=True, check=True
    ).stdout
    with open(SCRIPT, "rb") as f:
        submitted = f.read()
    assert submitted != reference, "check_sla.py must be repaired, not left as a byte-identical copy of the shipped reference implementation."


def test_repaired_script_computes_production_result():
    expected = get_expected_jitter()
    actual = run_script(os.path.join(REPO, "prod.pcap"))
    assert abs(actual - expected) <= 6e-11, (
        f"check_sla.py produced {actual} for prod.pcap; expected {expected}."
    )


def test_repaired_script_on_unseen_captures():
    with tempfile.TemporaryDirectory() as directory:
        for case in range(3):
            intervals = []
            for i in range(80 + case * 11):
                random_part = (secrets.randbelow(40001) - 20000) / 1000000.0
                patterned_part = ((i % 7) - 3) * 0.0007
                intervals.append(1.0 + random_part + patterned_part)

            path = os.path.join(directory, f"runtime_{case}.pcap")
            make_runtime_pcap(path, intervals)
            expected = expected_jitter_for(path)
            actual = run_script(path)
            assert abs(actual - expected) <= 6e-11, (
                f"check_sla.py produced {actual} for an unseen capture; expected {expected}."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
