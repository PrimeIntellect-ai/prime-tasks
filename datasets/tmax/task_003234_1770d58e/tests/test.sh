#!/bin/bash
set -e
mkdir -p /logs/verifier

# Run the submitted artifact against the original capture before inspecting its output.
run_ok=1
if ! timeout 10s python3 /home/user/process.py; then
    run_ok=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import re
import secrets
import subprocess
import sys

import dpkt

PROCESS_PATH = "/home/user/process.py"
PCAP_PATH = "/home/user/traffic.pcap"
RESULT_PATH = "/home/user/result.txt"


def test_result_file():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"Expected result file not found at {result_path}"

    with open(result_path, "r") as f:
        content = f.read().strip()

    assert content == "7.00", f"Expected result to be '7.00', but got '{content}'"


def test_process_code_fixes():
    process_path = "/home/user/process.py"
    assert os.path.isfile(process_path), f"Expected script not found at {process_path}"

    with open(process_path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert re.search(r'\b100\b', content), "Could not find iteration limit of 100 in process.py"
    assert "utf-16le" in content.lower() or "utf_16_le" in content.lower(), "Could not find 'utf-16le' decoding logic in process.py"


def test_compute_metric_behavior():
    # Exercise the submitted function in a separate process so an unbounded loop
    # fails by timeout rather than hanging the verifier.
    child = r'''
import importlib.util
import json
spec = importlib.util.spec_from_file_location("submitted_process", "/home/user/process.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(json.dumps([
    module.compute_metric(0),
    module.compute_metric(2),
    module.compute_metric(25),
    module.compute_metric(-4),
    module.compute_metric(-1),
]))
'''
    completed = subprocess.run(
        [sys.executable, "-c", child],
        text=True,
        capture_output=True,
        timeout=5,
        check=True,
    )
    values = json.loads(completed.stdout.strip().splitlines()[-1])
    assert values[0] == 0.0
    assert abs(values[1] - (2 ** 0.5)) < 1e-5
    assert abs(values[2] - 5.0) < 1e-5
    assert values[3] == 0.0
    assert values[4] == 0.0


def _make_packet(payload_bytes):
    tcp = dpkt.tcp.TCP(
        sport=1234,
        dport=80,
        seq=1,
        ack=1,
        flags=dpkt.tcp.TH_PUSH | dpkt.tcp.TH_ACK,
    )
    tcp.data = payload_bytes
    ip = dpkt.ip.IP(
        src=b"\x0a\x00\x00\x01",
        dst=b"\x0a\x00\x00\x02",
        p=dpkt.ip.IP_PROTO_TCP,
    )
    ip.data = tcp
    ip.len += len(tcp)
    eth = dpkt.ethernet.Ethernet(
        src=b"\x00\x11\x22\x33\x44\x55",
        dst=b"\x66\x77\x88\x99\xaa\xbb",
        type=dpkt.ethernet.ETH_TYPE_IP,
    )
    eth.data = ip
    return bytes(eth)


def test_script_on_derived_mixed_encoding_capture():
    # Use fresh, unpredictable values so a prewritten or hard-coded result cannot pass.
    roots = [8 + secrets.randbelow(5), 3 + secrets.randbelow(4), 2 + secrets.randbelow(3)]
    expected = float(sum(roots))
    payloads = [
        json.dumps({"value": roots[0] ** 2}).encode("utf-8"),
        json.dumps({"value": roots[1] ** 2}).encode("utf-16le"),
        json.dumps({"value": roots[2] ** 2}).encode("utf-16le"),
        json.dumps({"value": -9}).encode("utf-8"),
    ]

    old_pcap = open(PCAP_PATH, "rb").read()
    old_result = open(RESULT_PATH, "rb").read() if os.path.exists(RESULT_PATH) else None
    try:
        with open(PCAP_PATH, "wb") as f:
            writer = dpkt.pcap.Writer(f)
            for i, payload in enumerate(payloads):
                writer.writepkt(_make_packet(payload), 1000.0 + i)
            writer.close()

        subprocess.run(
            [sys.executable, PROCESS_PATH],
            text=True,
            capture_output=True,
            timeout=10,
            check=True,
        )
        assert os.path.isfile(RESULT_PATH), "Script did not create result.txt"
        with open(RESULT_PATH, "r") as f:
            content = f.read().strip()
        assert re.fullmatch(r"-?\d+\.\d{2}", content), f"Result is not formatted to two decimals: {content!r}"
        assert content == f"{expected:.2f}", f"Expected derived total {expected:.2f}, got {content!r}"
    finally:
        with open(PCAP_PATH, "wb") as f:
            f.write(old_pcap)
        if old_result is None:
            try:
                os.remove(RESULT_PATH)
            except FileNotFoundError:
                pass
        else:
            with open(RESULT_PATH, "wb") as f:
                f.write(old_result)
TEST_EOF

if [ "$run_ok" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
