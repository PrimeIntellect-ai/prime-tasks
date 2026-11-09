#!/bin/bash
set +e
mkdir -p /logs/verifier

PIPELINE_DIR=/home/user/pipeline
ORIGINAL_PCAP=/tmp/verifier_original_telemetry.pcap
CHALLENGE_PCAP=/tmp/verifier_challenge.pcap
ok=1

if [ ! -f "$PIPELINE_DIR/build_and_run.sh" ] || [ ! -f "$PIPELINE_DIR/process_telemetry.py" ] || [ ! -f "$PIPELINE_DIR/telemetry.pcap" ]; then
    ok=0
fi

if [ "$ok" -eq 1 ]; then
    cp "$PIPELINE_DIR/telemetry.pcap" "$ORIGINAL_PCAP" || ok=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

PIPELINE_DIR = "/home/user/pipeline"
BAD_IPS_PATH = os.path.join(PIPELINE_DIR, "bad_ips.txt")
SUMMARY_PATH = os.path.join(PIPELINE_DIR, "summary.json")

def test_bad_ips_file():
    assert os.path.isfile(BAD_IPS_PATH), f"Expected file {BAD_IPS_PATH} does not exist."
    with open(BAD_IPS_PATH, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 1, f"Expected exactly 1 IP in {BAD_IPS_PATH}, but found {len(lines)}."
    assert lines[0] == "10.0.0.55", f"Expected IP '10.0.0.55' in {BAD_IPS_PATH}, but found '{lines[0]}'."

def test_summary_json_file():
    assert os.path.isfile(SUMMARY_PATH), f"Expected file {SUMMARY_PATH} does not exist."
    with open(SUMMARY_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {SUMMARY_PATH} does not contain valid JSON.")

    assert "valid_packets" in data, f"Key 'valid_packets' missing from {SUMMARY_PATH}."
    assert data["valid_packets"] == 4, f"Expected 4 valid packets, but found {data['valid_packets']}."
TEST_EOF

# Execute the submitted entry point on the provided capture. Remove any stale or
# pre-created outputs first so they cannot satisfy the original assertions.
if [ "$ok" -eq 1 ]; then
    rm -f "$PIPELINE_DIR/bad_ips.txt" "$PIPELINE_DIR/summary.json"
    if ! (cd "$PIPELINE_DIR" && timeout 180s runuser -u user -- bash build_and_run.sh); then
        ok=0
    fi
fi

if [ "$ok" -eq 1 ]; then
    if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short; then
        ok=0
    fi
fi

# Build an additional capture unknown to the submission. It contains valid
# telemetry, two different malformed telemetry payloads, and malformed data on
# a non-telemetry port that must be ignored.
if [ "$ok" -eq 1 ]; then
python3 - << 'PY_EOF'
import dpkt
import socket

OUT = "/tmp/verifier_challenge.pcap"

def packet(src_ip, payload, dport=5000):
    eth = dpkt.ethernet.Ethernet(
        src=b'\x02\x00\x00\x00\x00\x01',
        dst=b'\x02\x00\x00\x00\x00\x02',
        type=dpkt.ethernet.ETH_TYPE_IP,
    )
    ip = dpkt.ip.IP(
        src=socket.inet_aton(src_ip),
        dst=socket.inet_aton('198.51.100.20'),
        p=dpkt.ip.IP_PROTO_UDP,
    )
    udp = dpkt.udp.UDP(sport=23456, dport=dport)
    udp.data = payload
    udp.ulen = len(udp)
    ip.data = udp
    ip.len = len(ip)
    eth.data = ip
    return eth.pack()

cases = [
    ('172.20.4.10', b'{"sensor":"humidity","val":40}', 5000),
    ('172.20.4.91', b'{broken json', 5000),
    ('172.20.4.11', b'{"sensor":"humidity","val":41}', 5000),
    ('172.20.4.92', b'\xff\xfe\x00\x81', 5000),
    ('172.20.4.12', b'{"sensor":"humidity","val":42}', 5000),
    ('172.20.4.93', b'not-json-but-not-telemetry', 6000),
]
with open(OUT, 'wb') as f:
    writer = dpkt.pcap.Writer(f)
    for i, case in enumerate(cases):
        writer.writepkt(packet(*case), 1700000000.0 + i)
PY_EOF
    if [ $? -ne 0 ]; then ok=0; fi
fi

if [ "$ok" -eq 1 ]; then
    cp "$CHALLENGE_PCAP" "$PIPELINE_DIR/telemetry.pcap" || ok=0
    chown user:user "$PIPELINE_DIR/telemetry.pcap" 2>/dev/null
    rm -f "$PIPELINE_DIR/bad_ips.txt" "$PIPELINE_DIR/summary.json"
    if ! (cd "$PIPELINE_DIR" && timeout 180s runuser -u user -- bash build_and_run.sh); then
        ok=0
    fi
fi

# Independently derive the expected result from the verifier-owned capture and
# compare it with the files produced by the second execution.
if [ "$ok" -eq 1 ]; then
python3 - << 'PY_EOF'
import json
import os
import socket
import sys
import dpkt

pcap_path = "/tmp/verifier_challenge.pcap"
bad_path = "/home/user/pipeline/bad_ips.txt"
summary_path = "/home/user/pipeline/summary.json"

valid = 0
expected_bad = []
with open(pcap_path, "rb") as f:
    for _, buf in dpkt.pcap.Reader(f):
        eth = dpkt.ethernet.Ethernet(buf)
        if not isinstance(eth.data, dpkt.ip.IP):
            continue
        ip = eth.data
        if not isinstance(ip.data, dpkt.udp.UDP) or ip.data.dport != 5000:
            continue
        try:
            json.loads(ip.data.data.decode("utf-8"))
            valid += 1
        except (UnicodeDecodeError, json.JSONDecodeError):
            expected_bad.append(socket.inet_ntoa(ip.src))

if not os.path.isfile(bad_path) or not os.path.isfile(summary_path):
    sys.exit(1)

with open(bad_path, "r") as f:
    actual_bad = [line.strip() for line in f if line.strip()]
if len(actual_bad) != len(expected_bad) or set(actual_bad) != set(expected_bad):
    print(f"Expected malformed source IPs {expected_bad}, got {actual_bad}")
    sys.exit(1)

try:
    with open(summary_path, "r") as f:
        summary = json.load(f)
except (OSError, json.JSONDecodeError):
    sys.exit(1)

if summary != {"valid_packets": valid}:
    print(f"Expected summary {{'valid_packets': {valid}}}, got {summary}")
    sys.exit(1)
PY_EOF
    if [ $? -ne 0 ]; then ok=0; fi
fi

# Restore the supplied capture after testing.
if [ -f "$ORIGINAL_PCAP" ]; then
    cp "$ORIGINAL_PCAP" "$PIPELINE_DIR/telemetry.pcap"
    chown user:user "$PIPELINE_DIR/telemetry.pcap" 2>/dev/null
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
