#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import json
import math
import os
import random
import secrets
import struct
import subprocess
import tempfile

from scapy.all import Ether, IP, UDP, Raw, wrpcap

EVIL_DIR = "/app/corpora/evil"
CLEAN_DIR = "/app/corpora/clean"
SCRIPT_PATH = "/home/user/classifier.py"
C_FILE_PATH = "/app/vendored_parser/src/parser.c"


def test_classifier_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Classifier script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"


def test_c_extension_fixed():
    assert os.path.exists(C_FILE_PATH), f"C file not found at {C_FILE_PATH}"
    with open(C_FILE_PATH, "r") as f:
        content = f.read()
        assert "(float)" not in content, "The C extension still contains the intentional `(float)` cast bug causing precision loss."


def test_rebuilt_extension_is_installed_and_preserves_precision():
    probe = r'''
import importlib.machinery
import json
import struct
import c2_telemetry_parser
lat = 1000.1234567890123
lon = -887.9876543210987
parsed = c2_telemetry_parser.parse_packet(struct.pack("dd", lat, lon))
print(json.dumps({
    "origin": c2_telemetry_parser.__file__,
    "lat": parsed["lat"].hex(),
    "lon": parsed["lon"].hex(),
    "expected_lat": lat.hex(),
    "expected_lon": lon.hex(),
}))
'''
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    result = subprocess.run(
        ["python3", "-c", probe], cwd="/tmp", env=env,
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Installed parser extension could not be imported/executed:\n{result.stderr}"
    data = json.loads(result.stdout.strip())
    assert any(data["origin"].endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f"Installed parser is not a compiled extension: {data['origin']}"
    assert data["lat"] == data["expected_lat"], "Installed extension loses latitude precision"
    assert data["lon"] == data["expected_lon"], "Installed extension loses longitude precision"


def run_classifier(directory):
    return subprocess.run(
        ["python3", SCRIPT_PATH, directory],
        capture_output=True,
        text=True
    )


def test_adversarial_corpus():
    evil_files = sorted(glob.glob(os.path.join(EVIL_DIR, "*.pcap")))
    clean_files = sorted(glob.glob(os.path.join(CLEAN_DIR, "*.pcap")))

    assert len(evil_files) > 0, f"No pcap files found in {EVIL_DIR}"
    assert len(clean_files) > 0, f"No pcap files found in {CLEAN_DIR}"

    result_evil = run_classifier(EVIL_DIR)
    assert result_evil.returncode == 0, f"Classifier script failed on evil corpus:\n{result_evil.stderr}"

    result_clean = run_classifier(CLEAN_DIR)
    assert result_clean.returncode == 0, f"Classifier script failed on clean corpus:\n{result_clean.stderr}"

    evil_output = result_evil.stdout.strip().splitlines()
    clean_output = result_clean.stdout.strip().splitlines()

    evil_bypassed = []
    for pcap in evil_files:
        basename = os.path.basename(pcap)
        expected = f"{basename}: EVIL"
        if expected not in evil_output:
            evil_bypassed.append(basename)

    clean_modified = []
    for pcap in clean_files:
        basename = os.path.basename(pcap)
        expected = f"{basename}: CLEAN"
        if expected not in clean_output:
            clean_modified.append(basename)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not error_msgs, " | ".join(error_msgs)


def evil_coordinate_candidates():
    candidates = []
    for lat in range(101, 1337):
        lon = math.sqrt(1337.0 ** 2 - float(lat) ** 2)
        distance = math.sqrt(float(lat) ** 2 + lon ** 2)
        float_lat = struct.unpack("f", struct.pack("f", float(lat)))[0]
        float_lon = struct.unpack("f", struct.pack("f", lon))[0]
        truncated_distance = math.sqrt(float_lat ** 2 + float_lon ** 2)
        if distance == 1337.0 and truncated_distance != 1337.0:
            candidates.append((float(lat), lon))
    assert candidates, "Could not construct precision-sensitive telemetry"
    return candidates


def packet(lat, lon):
    payload = struct.pack("dd", lat, lon)
    return Ether()/IP(dst="127.0.0.1")/UDP(dport=1234)/Raw(payload)


def test_classifier_on_fresh_unlabelled_corpus():
    rng = random.Random(secrets.randbits(128))
    evil_coords = evil_coordinate_candidates()
    rng.shuffle(evil_coords)

    # Labels are intentionally unrelated to filenames, and some names are misleading.
    cases = [
        ("clean_" + secrets.token_hex(6) + ".pcap", True),
        ("evil_" + secrets.token_hex(6) + ".pcap", False),
        ("capture_" + secrets.token_hex(6) + ".pcap", True),
        ("capture_" + secrets.token_hex(6) + ".pcap", False),
        ("sample_" + secrets.token_hex(6) + ".pcap", True),
        ("sample_" + secrets.token_hex(6) + ".pcap", False),
    ]
    rng.shuffle(cases)

    expected = []
    with tempfile.TemporaryDirectory(prefix="telemetry_" + secrets.token_hex(5) + "_") as corpus:
        for index, (name, is_evil) in enumerate(cases):
            packets = []
            clean_count = rng.randint(1, 3)
            for j in range(clean_count):
                lat = 200.123456789 + index * 17.0 + j
                lon = -300.987654321 - index * 11.0 - j
                assert math.sqrt(lat * lat + lon * lon) != 1337.0
                packets.append(packet(lat, lon))

            if is_evil:
                lat, lon = evil_coords[index % len(evil_coords)]
                if rng.choice([True, False]):
                    lat = -lat
                if rng.choice([True, False]):
                    lon = -lon
                if rng.choice([True, False]):
                    lat, lon = lon, lat
                assert math.sqrt(lat * lat + lon * lon) == 1337.0
                packets.insert(rng.randrange(len(packets) + 1), packet(lat, lon))

            wrpcap(os.path.join(corpus, name), packets)
            expected.append(f"{name}: {'EVIL' if is_evil else 'CLEAN'}")

        result = run_classifier(corpus)
        assert result.returncode == 0, f"Classifier failed on fresh corpus:\n{result.stderr}"
        actual = result.stdout.strip().splitlines()
        assert len(actual) == len(expected), f"Expected exactly one output line per pcap, got: {actual!r}"
        assert sorted(actual) == sorted(expected), \
            f"Incorrect classifications for fresh corpus. Expected {sorted(expected)!r}, got {sorted(actual)!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
