#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY' > /tmp/verify_uptime_monitor.py
import os
import re
import secrets
import struct
import subprocess
import tempfile

SOURCE = "/home/user/uptime_monitor.c"
BINARY = "/home/user/uptime_monitor"
FINAL_EMA = "/home/user/final_ema.txt"
ORIGINAL_PCAP = "/home/user/crash.pcap"


def run_monitor(binary, pcap):
    result = subprocess.run(
        [binary, pcap],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{binary} failed on {pcap} with exit code {result.returncode}: "
        f"{result.stderr}"
    )
    output = result.stdout.strip()
    assert re.fullmatch(r"Final EMA: -?(?:\d+(?:\.\d*)?|\.\d+)", output), (
        f"Unexpected program output: {result.stdout!r}"
    )
    return output


def expected_output(payloads):
    ema = 0.0
    alpha = 0.25
    for payload in payloads:
        used = payload[:50]
        avg_latency = sum(used) / len(used)
        ema = (alpha * avg_latency) + ((1.0 - alpha) * ema)
    return f"Final EMA: {ema:.4f}"


def make_frame(payload):
    ethernet = bytes.fromhex("00112233445566778899aabb0800")
    total_length = 20 + 8 + len(payload)
    ip = struct.pack(
        "!BBHHHBBH4s4s",
        0x45, 0, total_length, 1, 0, 64, 17, 0,
        bytes((192, 0, 2, 1)), bytes((192, 0, 2, 2)),
    )
    udp = struct.pack("!HHHH", 12345, 8080, 8 + len(payload), 0)
    return ethernet + ip + udp + payload


def write_pcap(path, payloads):
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for index, payload in enumerate(payloads, 1):
            frame = make_frame(payload)
            f.write(struct.pack("<IIII", index, 0, len(frame), len(frame)))
            f.write(frame)


# Preserve the original source assertions.
assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."
with open(SOURCE, "r") as f:
    content = f.read()
assert "i <= payload_len" not in content, (
    "Bug 1 (off-by-one) is still present: 'i <= payload_len' found."
)
assert re.search(r"i\s*<\s*payload_len", content), (
    "Bug 1 fix not found: expected 'i < payload_len' in the loop condition."
)
assert "1.0 + alpha" not in content, (
    "Bug 2 (EMA formula) is still present: '1.0 + alpha' found."
)
assert re.search(r"1\.0\s*-\s*alpha", content), (
    "Bug 2 fix not found: expected '1.0 - alpha' in the EMA formula."
)

# The requested compiled artifact must exist and be a native executable.
assert os.path.isfile(BINARY), f"Compiled program {BINARY} is missing."
assert os.access(BINARY, os.X_OK), f"Compiled program {BINARY} is not executable."
with open(BINARY, "rb") as f:
    assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable."

# Independently compile the submitted source so stale or unrelated binaries cannot pass.
rebuilt = "/tmp/uptime_monitor_rebuilt"
compile_result = subprocess.run(
    ["gcc", "-o", rebuilt, SOURCE, "-lpcap"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=20,
)
assert compile_result.returncode == 0, f"Compilation failed:\n{compile_result.stderr}"

# Exercise both the submitted executable and the rebuilt source on unpredictable
# captures. Every payload exceeds the 50-byte cap and byte 51 is deliberately
# distinct, making an inclusive loop observably incorrect without relying on a crash.
with tempfile.TemporaryDirectory(prefix="monitor-tests-") as td:
    for case in range(4):
        payloads = []
        for packet_index in range(case + 2):
            size = 51 + secrets.randbelow(40)
            payload = bytearray(secrets.token_bytes(size))
            payload[50] = (sum(payload[:50]) + 97 + packet_index) % 256
            payloads.append(bytes(payload))
        pcap = os.path.join(td, f"capture-{secrets.token_hex(8)}.pcap")
        write_pcap(pcap, payloads)
        expected = expected_output(payloads)
        assert run_monitor(rebuilt, pcap) == expected, (
            "The submitted source produced an incorrect EMA or processed beyond "
            "the capped payload boundary."
        )
        assert run_monitor(BINARY, pcap) == expected, (
            "The compiled /home/user/uptime_monitor does not implement the fixes."
        )

# Preserve the original final_ema.txt assertion and verify it matches an actual run.
assert os.path.isfile(FINAL_EMA), f"File {FINAL_EMA} is missing. Did you save the output?"
with open(FINAL_EMA, "r") as f:
    saved = f.read().strip()
ema = 0.0
alpha = 0.25
for _ in range(5):
    ema = (alpha * 10.0) + ((1.0 - alpha) * ema)
expected_saved = f"{ema:.4f}"
assert saved == expected_saved, (
    f"Incorrect EMA value in {FINAL_EMA}. Expected '{expected_saved}', got '{saved}'."
)
assert run_monitor(BINARY, ORIGINAL_PCAP) == f"Final EMA: {expected_saved}", (
    "The compiled program does not produce the saved result on crash.pcap."
)
PY

if python3 /tmp/verify_uptime_monitor.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
