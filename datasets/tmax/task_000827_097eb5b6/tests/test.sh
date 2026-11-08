#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import hashlib
import importlib.metadata
import inspect
import math
import os
import random
import re
import socket
import struct
import subprocess
import sys
import tempfile

import pytest

DETECTOR = "/home/user/detector.py"
VENDORED_IP = "/app/vendored/dpkt-1.9.8/dpkt/ip.py"


def test_dpkt_installed_and_fixed():
    try:
        import dpkt
    except ImportError:
        pytest.fail("dpkt is not installed in the current Python environment.")

    # Create a simple valid IPv4 packet header
    # 45 00 00 14 00 01 00 00 40 00 7c e7 7f 00 00 01 7f 00 00 01
    raw_ip = bytes.fromhex("450000140001000040007ce77f0000017f000001")

    try:
        ip_obj = dpkt.ip.IP(raw_ip)
    except Exception as e:
        pytest.fail(f"Failed to parse a valid IP packet with the installed dpkt: {e}")

    assert type(ip_obj.sum) is int, f"Expected ip_obj.sum to be int, got {type(ip_obj.sum)}"
    assert not math.isnan(ip_obj.sum), "ip_obj.sum is NaN, perturbation was not fixed."


def test_vendored_source_repaired_and_installed():
    import dpkt
    import dpkt.ip

    assert importlib.metadata.version("dpkt") == "1.9.8"
    assert os.path.isfile(VENDORED_IP), f"Vendored source missing: {VENDORED_IP}"

    with open(VENDORED_IP, "rb") as f:
        vendored = f.read()
    assert b'self.sum = float("nan")' not in vendored, "The deliberate NaN perturbation remains in vendored dpkt."
    assert b"self.sum = float('nan')" not in vendored, "The deliberate NaN perturbation remains in vendored dpkt."

    installed_path = inspect.getsourcefile(dpkt.ip)
    assert installed_path and os.path.isfile(installed_path), "Installed dpkt.ip has no real Python source file."
    with open(installed_path, "rb") as f:
        installed = f.read()
    assert hashlib.sha256(installed).digest() == hashlib.sha256(vendored).digest(), \
        "The repaired vendored dpkt.ip source was not installed."

    # Exercise varied headers so a one-header stub or narrow special case cannot pass.
    rng = random.Random(0xD09A)
    for _ in range(24):
        total_len = rng.randrange(20, 1500)
        ident = rng.randrange(0, 65536)
        ttl = rng.randrange(1, 256)
        proto = rng.choice([1, 6, 17, 47])
        checksum = rng.randrange(0, 65536)
        src = socket.inet_aton(f"10.{rng.randrange(256)}.{rng.randrange(256)}.{rng.randrange(1, 255)}")
        dst = socket.inet_aton(f"172.{rng.randrange(16, 32)}.{rng.randrange(256)}.{rng.randrange(1, 255)}")
        raw = struct.pack("!BBHHHBBH4s4s", 0x45, 0, total_len, ident, 0, ttl, proto, checksum, src, dst)
        obj = dpkt.ip.IP(raw)
        assert type(obj.sum) is int and obj.sum == checksum
        assert obj.len == total_len
        assert obj.id == ident
        assert obj.ttl == ttl
        assert obj.p == proto
        assert obj.src == src and obj.dst == dst


def test_detector_script_exists():
    path = "/home/user/detector.py"
    assert os.path.isfile(path), f"Detector script not found at {path}"


def test_detector_clean_corpus():
    clean_dir = "/app/corpora/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    pcap_files = [f for f in os.listdir(clean_dir) if f.endswith(".pcap")]
    assert len(pcap_files) > 0, "No pcap files found in clean corpus."

    failed_files = []
    for pcap in pcap_files:
        pcap_path = os.path.join(clean_dir, pcap)
        result = subprocess.run(
            [sys.executable, DETECTOR, pcap_path],
            capture_output=True,
            text=True
        )
        if result.returncode != 0 or "CLEAN" not in result.stdout:
            failed_files.append(pcap)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(pcap_files)} clean modified/flagged. Offending files: {', '.join(failed_files)}")


def test_detector_evil_corpus():
    evil_dir = "/app/corpora/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    pcap_files = [f for f in os.listdir(evil_dir) if f.endswith(".pcap")]
    assert len(pcap_files) > 0, "No pcap files found in evil corpus."

    failed_files = []
    for pcap in pcap_files:
        pcap_path = os.path.join(evil_dir, pcap)
        result = subprocess.run(
            [sys.executable, DETECTOR, pcap_path],
            capture_output=True,
            text=True
        )
        if result.returncode != 1 or "EVIL" not in result.stdout:
            failed_files.append(pcap)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(pcap_files)} evil bypassed. Offending files: {', '.join(failed_files)}")


def _checksum(data):
    if len(data) & 1:
        data += b"\x00"
    total = sum(struct.unpack(f"!{len(data) // 2}H", data))
    total = (total & 0xffff) + (total >> 16)
    total = (total & 0xffff) + (total >> 16)
    return (~total) & 0xffff


def _ethernet_ipv4_tcp(payload, seed):
    rng = random.Random(seed)
    src_ip = bytes([10, rng.randrange(256), rng.randrange(256), rng.randrange(1, 255)])
    dst_ip = bytes([192, 0, 2, rng.randrange(1, 255)])
    tcp = struct.pack(
        "!HHIIBBHHH", rng.randrange(1024, 65536), 80, rng.randrange(2**32), 0,
        0x50, 0x18, 8192, 0, 0
    ) + payload
    ip_header = struct.pack(
        "!BBHHHBBH4s4s", 0x45, 0, 20 + len(tcp), rng.randrange(65536),
        0, rng.randrange(32, 129), 6, 0, src_ip, dst_ip
    )
    ip_header = ip_header[:10] + struct.pack("!H", _checksum(ip_header)) + ip_header[12:]
    eth = bytes(rng.randrange(256) for _ in range(12)) + b"\x08\x00"
    return eth + ip_header + tcp


def _write_pcap(path, frames):
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for i, frame in enumerate(frames):
            f.write(struct.pack("<IIII", 1700000000 + i, i * 1000, len(frame), len(frame)))
            f.write(frame)


def test_detector_on_generated_unpredictable_paths_and_pcaps():
    with open("/app/dumps/crash.bin", "rb") as f:
        dump = f.read()
    match = re.search(rb"Payload segment:\s*([A-Z0-9-]+)", dump)
    assert match, "Could not derive the poisoned payload signature from crash.bin"
    signature = match.group(1)

    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="pcap-validation-") as tmp:
        cases = []
        for i in range(8):
            clean_payload = (
                b"ordinary telemetry evil clean " + os.urandom(7) +
                b" X-MALFORMED-FLOW-TRIGGER-9940 harmless"
            )
            evil_payload = os.urandom(rng.randrange(0, 24)) + signature + os.urandom(rng.randrange(0, 24))

            # Deliberately misleading names in one neutral directory prevent pathname classification.
            clean_path = os.path.join(tmp, f"evil_suspect_{rng.randrange(10**9)}.pcap")
            evil_path = os.path.join(tmp, f"clean_capture_{rng.randrange(10**9)}.pcap")
            _write_pcap(clean_path, [_ethernet_ipv4_tcp(clean_payload, 1000 + i)])
            _write_pcap(evil_path, [_ethernet_ipv4_tcp(b"benign first packet", 2000 + i),
                                    _ethernet_ipv4_tcp(evil_payload, 3000 + i)])
            cases.extend([(clean_path, 0, "CLEAN"), (evil_path, 1, "EVIL")])

        rng.shuffle(cases)
        for path, expected_code, expected_word in cases:
            result = subprocess.run([sys.executable, DETECTOR, path], capture_output=True, text=True, timeout=10)
            assert result.returncode == expected_code, \
                f"Wrong exit code for generated capture {os.path.basename(path)}: {result.returncode}; stderr={result.stderr!r}"
            assert expected_word in result.stdout, \
                f"Missing {expected_word} for generated capture {os.path.basename(path)}; stdout={result.stdout!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
