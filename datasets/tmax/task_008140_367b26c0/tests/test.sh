#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import math
import os
import secrets
import shutil
import socket
import statistics
import struct
import subprocess
import sys

import dpkt
import pytest

BASE_DIR = "/home/user/legacy_telemetry"
DATA_DIR = os.path.join(BASE_DIR, "data")
PCAP_FILE = os.path.join(DATA_DIR, "sample.pcap")
RESULT_FILE = os.path.join(BASE_DIR, "result.txt")


def independently_read_measurements(path):
    values = []
    names = []
    sensor_ids = []
    with open(path, "rb") as f:
        for _, buf in dpkt.pcap.Reader(f):
            eth = dpkt.ethernet.Ethernet(buf)
            if not isinstance(eth.data, dpkt.ip.IP):
                continue
            ip = eth.data
            if not isinstance(ip.data, dpkt.udp.UDP):
                continue
            payload = bytes(ip.data.data)
            if len(payload) < 12:
                continue
            sensor_ids.append(struct.unpack(">I", payload[:4])[0])
            values.append(struct.unpack(">d", payload[4:12])[0])
            names.append(payload[12:].decode("utf-8"))
    return sensor_ids, values, names


def load_module(path, prefix):
    name = prefix + "_" + secrets.token_hex(8)
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_challenge_pcap(path, values, empty_name_index):
    with open(path, "wb") as out:
        writer = dpkt.pcap.Writer(out)
        for i, value in enumerate(values):
            name = b"" if i == empty_name_index else ("HiddenSensor_%d" % i).encode("utf-8")
            payload = struct.pack(">I", 50000 + i) + struct.pack(">d", value) + name
            udp = dpkt.udp.UDP(sport=21000 + i, dport=31000, data=payload)
            udp.ulen = len(udp)
            ip = dpkt.ip.IP(
                src=socket.inet_aton("10.20.30.1"),
                dst=socket.inet_aton("10.20.30.2"),
                p=dpkt.ip.IP_PROTO_UDP,
                data=udp,
            )
            ip.len = len(ip)
            eth = dpkt.ethernet.Ethernet(type=dpkt.ethernet.ETH_TYPE_IP, data=ip)
            writer.writepkt(eth, ts=1700000000 + i)
        writer.close()


def test_sample_pcap_restored():
    """Verify that the sample.pcap file was restored from the git history."""
    assert os.path.isfile(PCAP_FILE), (
        f"The file {PCAP_FILE} is missing. It should have been restored from git history."
    )
    assert os.path.getsize(PCAP_FILE) > 0, (
        f"The file {PCAP_FILE} is empty. Ensure it was properly restored."
    )

    roots = subprocess.check_output(
        ["git", "rev-list", "--max-parents=0", "HEAD"], cwd=BASE_DIR, text=True
    ).splitlines()
    assert roots, "The repository has no root commit containing the original capture."
    original = subprocess.check_output(
        ["git", "show", roots[0] + ":data/sample.pcap"], cwd=BASE_DIR
    )
    with open(PCAP_FILE, "rb") as f:
        restored = f.read()
    assert restored == original, "data/sample.pcap is not the capture stored in the original git history."

    sensor_ids, values, names = independently_read_measurements(PCAP_FILE)
    assert sensor_ids == list(range(10))
    assert len(values) == 10
    assert names[5] == ""


def test_pipeline_executes_on_restored_capture():
    """Run the submitted pipeline and derive its expected result from the restored capture."""
    if os.path.exists(RESULT_FILE):
        os.unlink(RESULT_FILE)
    completed = subprocess.run(
        [sys.executable, "main.py"],
        cwd=BASE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert os.path.isfile(RESULT_FILE), "Running main.py did not generate result.txt."

    _, values, _ = independently_read_measurements(PCAP_FILE)
    expected = statistics.variance(values)
    with open(RESULT_FILE) as f:
        actual = float(f.read().strip())
    assert math.isclose(actual, expected, rel_tol=1e-5), (
        f"Executed pipeline produced {actual}, expected approximately {expected}."
    )


def test_parser_analytics_and_pipeline_on_hidden_capture(tmp_path):
    """Exercise the submitted parser and analytics on values chosen at verification time."""
    project = tmp_path / "project"
    data_dir = project / "data"
    data_dir.mkdir(parents=True)
    for filename in ("reader.py", "analytics.py", "main.py"):
        source = os.path.join(BASE_DIR, filename)
        assert os.path.isfile(source), f"{source} is missing."
        shutil.copy2(source, project / filename)

    rng = secrets.SystemRandom()
    offsets = rng.sample(range(-40, 41), 13)
    base = 100000000.0 + rng.randrange(1000, 9000)
    values = [base + offset * 0.0001 for offset in offsets]
    empty_index = rng.randrange(len(values))
    challenge_pcap = data_dir / "sample.pcap"
    write_challenge_pcap(str(challenge_pcap), values, empty_index)

    reader = load_module(str(project / "reader.py"), "submitted_reader")
    parsed = list(reader.parse_pcap(str(challenge_pcap)))
    assert len(parsed) == len(values), "reader.py did not parse every valid telemetry packet."
    assert parsed == values, "reader.py did not extract the encoded big-endian float values correctly."

    analytics = load_module(str(project / "analytics.py"), "submitted_analytics")
    expected = statistics.variance(values)
    calculated = analytics.calculate_variance(parsed)
    assert math.isclose(calculated, expected, rel_tol=1e-5), (
        f"analytics.py returned {calculated} for hidden data; expected approximately {expected}."
    )

    completed = subprocess.run(
        [sys.executable, "main.py"],
        cwd=str(project),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    challenge_result = project / "result.txt"
    assert challenge_result.is_file(), "main.py did not generate result.txt for the hidden capture."
    try:
        actual = float(challenge_result.read_text().strip())
    except ValueError as exc:
        pytest.fail(f"Hidden pipeline result is not a valid float: {exc}")
    assert math.isclose(actual, expected, rel_tol=1e-5), (
        f"Pipeline returned {actual} for hidden capture; expected approximately {expected}."
    )


def test_result_file_exists():
    """Verify that the result.txt file was generated."""
    assert os.path.isfile(RESULT_FILE), (
        f"The file {RESULT_FILE} is missing. You need to run the pipeline to generate it."
    )


def test_result_file_variance_accurate():
    """Verify that the variance calculated in result.txt is accurate."""
    base_val = 100000000.0
    values = [base_val + (i * 0.0001) for i in range(10)]
    expected_variance = statistics.variance(values)

    with open(RESULT_FILE, "r") as f:
        content = f.read().strip()

    try:
        actual_variance = float(content)
    except ValueError:
        pytest.fail(f"The content of {RESULT_FILE} ('{content}') is not a valid float.")

    assert math.isclose(actual_variance, expected_variance, rel_tol=1e-5), (
        f"The variance in {RESULT_FILE} ({actual_variance}) is incorrect. "
        f"Expected approximately {expected_variance}. "
        "Check analytics.py for catastrophic cancellation issues and ensure reader.py parses all packets correctly."
    )


def test_reader_bug_fixed():
    """Check that reader.py does not contain the original hardcoded buggy slice access."""
    reader_path = os.path.join(BASE_DIR, "reader.py")
    assert os.path.isfile(reader_path), f"{reader_path} is missing."

    with open(reader_path, "r") as f:
        content = f.read()

    if "if name_bytes[0] == 0:" in content and "len(name_bytes)" not in content and "try:" not in content:
        pytest.fail("The parsing bug in reader.py appears to be unfixed. It still assumes name_bytes has at least 1 element without checking.")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
