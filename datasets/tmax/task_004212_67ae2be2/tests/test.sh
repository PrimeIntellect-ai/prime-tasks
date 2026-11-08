#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import random
import struct
import subprocess
import sys
from collections import Counter
from pathlib import Path

import pytest

PROJECT = Path('/home/user/netprofiler')
SCRIPT = Path('/home/user/run_analysis.py')
CAPTURE = Path('/home/user/capture.pcap')
REPORT = Path('/home/user/report.json')


@pytest.fixture(scope='session', autouse=True)
def install_package():
    result = subprocess.run(
        [sys.executable, '-m', 'pip', 'install', '--force-reinstall', '--no-cache-dir', '.'],
        cwd=str(PROJECT), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert result.returncode == 0, f"pip install . failed:\n{result.stdout}"

    probe = subprocess.run(
        [sys.executable, '-c', 'import netprofiler; from netprofiler import parse_pcap, calculate_mean_jitter'],
        cwd='/tmp', text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert probe.returncode == 0, f"Installed netprofiler package could not be imported:\n{probe.stdout}"


def read_expected_pcap(path):
    data = Path(path).read_bytes()
    assert len(data) >= 24, 'Capture is too short to contain a PCAP header.'
    magic = data[:4]
    if magic == b'\xd4\xc3\xb2\xa1':
        endian, divisor = '<', 1_000_000.0
    elif magic == b'\xa1\xb2\xc3\xd4':
        endian, divisor = '>', 1_000_000.0
    elif magic == b'\x4d\x3c\xb2\xa1':
        endian, divisor = '<', 1_000_000_000.0
    elif magic == b'\xa1\xb2\x3c\x4d':
        endian, divisor = '>', 1_000_000_000.0
    else:
        raise AssertionError('Unsupported PCAP magic number.')

    offset = 24
    timestamps = []
    sources = Counter()
    while offset < len(data):
        assert offset + 16 <= len(data), 'Truncated PCAP packet header.'
        sec, frac, included, _ = struct.unpack_from(endian + 'IIII', data, offset)
        offset += 16
        assert offset + included <= len(data), 'Truncated PCAP packet payload.'
        frame = data[offset:offset + included]
        offset += included
        timestamps.append(sec + frac / divisor)
        if len(frame) >= 34 and frame[12:14] == b'\x08\x00' and frame[14] >> 4 == 4:
            src = '.'.join(str(value) for value in frame[26:30])
            sources[src] += 1

    inter_arrivals = [timestamps[i] - timestamps[i - 1] for i in range(1, len(timestamps))]
    differences = [abs(inter_arrivals[i] - inter_arrivals[i - 1]) for i in range(1, len(inter_arrivals))]
    jitter = sum(differences) / len(differences) if differences else 0.0
    top_ip = max(sources, key=sources.get) if sources else None
    return len(timestamps), top_ip, jitter


def write_challenge_pcap(path):
    rng = random.SystemRandom()
    winner = bytes((10, rng.randrange(20, 220), rng.randrange(1, 255), rng.randrange(1, 255)))
    other = bytes((172, 16, rng.randrange(1, 255), rng.randrange(1, 255)))
    third = bytes((192, 168, rng.randrange(1, 255), rng.randrange(1, 255)))
    sources = [winner] * 4 + [other] * 2 + [third]
    rng.shuffle(sources)

    timestamp_us = rng.randrange(2_000_000, 5_000_000)
    timestamps = [timestamp_us]
    for _ in range(len(sources) - 1):
        timestamp_us += rng.randrange(80_000, 900_000)
        timestamps.append(timestamp_us)

    with open(path, 'wb') as f:
        f.write(struct.pack('<IHHiIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))
        for timestamp_us, src in zip(timestamps, sources):
            sec, usec = divmod(timestamp_us, 1_000_000)
            dst = b'\xcb\x00\x71\x09'
            eth = b'\x00\x11\x22\x33\x44\x55' + b'\x66\x77\x88\x99\xaa\xbb' + b'\x08\x00'
            ip = b'\x45\x00\x00\x14\x00\x00\x00\x00\x40\x01\x00\x00' + src + dst
            frame = eth + ip
            f.write(struct.pack('<IIII', sec, usec, len(frame), len(frame)))
            f.write(frame)


def load_report(path):
    with open(path, 'r') as f:
        return json.load(f)


def assert_report_matches(report, expected):
    assert set(report) == {'total_packets', 'top_src_ip', 'mean_jitter'}, 'report.json must have exactly the required keys.'
    total, top_ip, jitter = expected
    assert report['total_packets'] == total
    assert report['top_src_ip'] == top_ip
    assert math.isclose(float(report['mean_jitter']), jitter, rel_tol=1e-7, abs_tol=1e-6)


def test_setup_py_fixed():
    path = "/home/user/netprofiler/setup.py"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, 'r') as f:
        content = f.read()

    assert "dpktt" not in content, f"The intentional typo 'dpktt' is still present in {path}."
    assert "dpkt" in content, f"The dependency 'dpkt' is missing from {path}."


def test_metrics_py_fixed():
    path = "/home/user/netprofiler/netprofiler/metrics.py"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, 'r') as f:
        content = f.read()

    assert "abs(" in content, f"The file {path} does not seem to use 'abs()' to calculate absolute differences for jitter."

    from netprofiler.metrics import calculate_mean_jitter
    rng = random.SystemRandom()
    timestamps = [0.0]
    for _ in range(6):
        timestamps.append(timestamps[-1] + rng.uniform(0.05, 1.5))
    arrivals = [timestamps[i] - timestamps[i - 1] for i in range(1, len(timestamps))]
    expected = sum(abs(arrivals[i] - arrivals[i - 1]) for i in range(1, len(arrivals))) / (len(arrivals) - 1)
    assert math.isclose(calculate_mean_jitter(timestamps), expected, rel_tol=1e-10, abs_tol=1e-10)
    assert calculate_mean_jitter([]) == 0.0
    assert calculate_mean_jitter([1.0, 2.0]) == 0.0


def test_run_analysis_exists():
    path = "/home/user/run_analysis.py"
    assert os.path.isfile(path), f"File {path} does not exist. The analysis script was not created."
    tree = ast.parse(Path(path).read_text(), filename=path)
    imports_package = any(
        (isinstance(node, ast.Import) and any(alias.name == 'netprofiler' or alias.name.startswith('netprofiler.') for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module is not None and (node.module == 'netprofiler' or node.module.startswith('netprofiler.')))
        for node in ast.walk(tree)
    )
    assert imports_package, 'run_analysis.py must import the fixed netprofiler package.'


def test_run_analysis_recomputes_report_from_capture():
    original_capture = CAPTURE.read_bytes()
    challenge_error = None
    try:
        write_challenge_pcap(CAPTURE)
        expected = read_expected_pcap(CAPTURE)
        if REPORT.exists():
            REPORT.unlink()
        result = subprocess.run(
            [sys.executable, str(SCRIPT)], cwd='/tmp', text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        assert result.returncode == 0, f"run_analysis.py failed on a valid capture:\n{result.stdout}"
        assert REPORT.is_file(), 'run_analysis.py did not generate /home/user/report.json.'
        assert_report_matches(load_report(REPORT), expected)
    except BaseException as exc:
        challenge_error = exc
    finally:
        CAPTURE.write_bytes(original_capture)
        if REPORT.exists():
            REPORT.unlink()
        final_result = subprocess.run(
            [sys.executable, str(SCRIPT)], cwd='/tmp', text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )

    if challenge_error is not None:
        raise challenge_error
    assert final_result.returncode == 0, f"run_analysis.py failed on the provided capture:\n{final_result.stdout}"


def test_report_json_correct():
    path = "/home/user/report.json"
    assert os.path.isfile(path), f"File {path} does not exist. The report was not generated."

    with open(path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    assert "total_packets" in report, "Key 'total_packets' missing from report.json"
    assert "top_src_ip" in report, "Key 'top_src_ip' missing from report.json"
    assert "mean_jitter" in report, "Key 'mean_jitter' missing from report.json"
    assert set(report) == {'total_packets', 'top_src_ip', 'mean_jitter'}, 'report.json must have exactly the required structure.'

    assert report["total_packets"] == 4, f"Expected total_packets to be 4, got {report['total_packets']}"
    assert report["top_src_ip"] == "10.0.0.1", f"Expected top_src_ip to be '10.0.0.1', got {report['top_src_ip']}"

    expected_jitter = 0.15
    actual_jitter = float(report["mean_jitter"])
    assert math.isclose(actual_jitter, expected_jitter, abs_tol=0.001), \
        f"Expected mean_jitter to be close to {expected_jitter}, got {actual_jitter}"

    assert_report_matches(report, read_expected_pcap(CAPTURE))
TEST_EOF

if (cd /tmp && python3 -m pytest /tmp/test_final_state.py -x --tb=short) 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
