#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess

BASE = "/home/user/ingester_diag"
RUN_SH = os.path.join(BASE, "run.sh")
PCAP = os.path.join(BASE, "traffic.pcap")
LOGS = os.path.join(BASE, "recovered_logs.txt")
MAIN_RS = os.path.join(BASE, "ingester/src/main.rs")


def nonempty_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def udp_payloads(path, destination_port):
    result = []
    with open(path, "rb") as f:
        magic = f.read(4)
        if magic == b"\xd4\xc3\xb2\xa1":
            endian = "<"
        elif magic == b"\xa1\xb2\xc3\xd4":
            endian = ">"
        else:
            raise AssertionError("traffic.pcap is not a supported classic PCAP file")

        global_rest = f.read(20)
        assert len(global_rest) == 20, "Truncated PCAP global header"

        while True:
            record = f.read(16)
            if not record:
                break
            assert len(record) == 16, "Truncated PCAP record header"
            _, _, captured_len, _ = struct.unpack(endian + "IIII", record)
            packet = f.read(captured_len)
            assert len(packet) == captured_len, "Truncated PCAP packet"

            if len(packet) < 14 or packet[12:14] != b"\x08\x00":
                continue
            ip = packet[14:]
            if len(ip) < 20 or (ip[0] >> 4) != 4 or ip[9] != 17:
                continue
            ihl = (ip[0] & 0x0f) * 4
            if len(ip) < ihl + 8:
                continue
            udp = ip[ihl:]
            _, dst_port, udp_len, _ = struct.unpack("!HHHH", udp[:8])
            if dst_port == destination_port:
                result.append(udp[8:udp_len])
    return result


def expected_output(payloads):
    return ["LOG: " + payload.decode("utf-8", errors="replace") for payload in payloads]


def write_test_pcap(path, packets):
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for index, (src_port, dst_port, payload) in enumerate(packets):
            udp_len = 8 + len(payload)
            udp = struct.pack("!HHHH", src_port, dst_port, udp_len, 0) + payload
            ip_len = 20 + len(udp)
            ip = struct.pack(
                "!BBHHHBBH4s4s",
                0x45, 0, ip_len, index, 0, 64, 17, 0,
                b"\x7f\x00\x00\x01", b"\x7f\x00\x00\x01"
            ) + udp
            ethernet = b"\x00" * 12 + b"\x08\x00"
            packet = ethernet + ip
            f.write(struct.pack("<IIII", index, 0, len(packet), len(packet)))
            f.write(packet)


def execute_run_sh():
    completed = subprocess.run(
        ["bash", "./run.sh"],
        cwd=BASE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f"run.sh failed with status {completed.returncode}. stderr:\n{completed.stderr}"
    )
    return nonempty_lines(completed.stdout)


def test_run_sh_updated():
    assert os.path.isfile(RUN_SH), f"{RUN_SH} does not exist."
    with open(RUN_SH, "r") as f:
        content = f.read()
    assert "TARGET_PORT=9000" in content, "run.sh does not have TARGET_PORT updated to 9000."
    assert "tshark" in content, "run.sh does not use tshark to extract payloads."
    assert "cargo run" in content, "run.sh does not pipe to 'cargo run'."


def test_main_rs_fixed():
    assert os.path.isfile(MAIN_RS), f"{MAIN_RS} does not exist."
    with open(MAIN_RS, "r") as f:
        content = f.read()
    assert "String::from_utf8(bytes).unwrap()" not in content, \
        "main.rs still contains the panic-inducing unwrap()."


def test_recovered_logs():
    assert os.path.isfile(LOGS), f"The file {LOGS} was not created."
    with open(LOGS, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected 3 log lines, found {len(lines)}."
    assert lines[0] == "LOG: INFO: System start", "First log line does not match expected output."
    assert "LOG: WARN: Disk" in lines[1] and "error" in lines[1], \
        "Second log line does not match expected output format."
    assert lines[2] == "LOG: INFO: System stop", "Third log line does not match expected output."
    assert "\ufffd" in lines[1] or "?" in lines[1] or lines[1] == "LOG: WARN: Disk  error", \
        "The invalid UTF-8 byte was not gracefully handled."


def test_pipeline_executes_and_saved_output_matches():
    expected = expected_output(udp_payloads(PCAP, 9000))
    assert len(expected) == 3, "Could not derive the expected packets from traffic.pcap."

    with open(LOGS, "r", encoding="utf-8") as f:
        saved = nonempty_lines(f.read())

    actual = execute_run_sh()
    assert actual == expected, f"run.sh output differs from traffic.pcap: {actual!r}"
    assert saved == actual, "recovered_logs.txt is not the output produced by the working pipeline."


def test_pipeline_on_fresh_payloads():
    original_pcap = open(PCAP, "rb").read()
    token1 = ("DYNAMIC-" + secrets.token_hex(12)).encode("ascii")
    token2 = ("BROKEN-" + secrets.token_hex(8)).encode("ascii") + b"\xff-END"
    decoy = ("DECOY-" + secrets.token_hex(10)).encode("ascii")
    packets = [
        (12001, 9000, token1),
        (12002, 8000, decoy),
        (12003, 9000, token2),
    ]

    try:
        write_test_pcap(PCAP, packets)
        actual = execute_run_sh()
    finally:
        with open(PCAP, "wb") as f:
            f.write(original_pcap)

    expected = expected_output([token1, token2])
    assert actual == expected, (
        "run.sh and the Rust ingester did not correctly process newly generated UDP payloads: "
        f"expected {expected!r}, got {actual!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
