#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import zlib
import struct


def test_recovered_telemetry_bin():
    path = "/home/user/recovered_telemetry.bin"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "rb") as f:
        data = f.read()
    expected = b'\x0E\x00\x00\x00\x08\x64\x12\x03\x61\x70\x70\x1A\x01\xFF\x20\xEF\xBE\xAD\xDE\x00'
    assert data == expected, (
        f"Recovered telemetry data is incorrect. Got {data.hex()}, "
        f"expected {expected.hex()}"
    )


def encode_varint(value):
    encoded = []
    while True:
        byte = value & 0x7f
        value >>= 7
        if value:
            encoded.append(byte | 0x80)
        else:
            encoded.append(byte)
            break
    return bytes(encoded)


def encode_telemetry(timestamp, module_name, data, crc_val):
    out = bytearray()
    out.extend(b'\x08')
    out.extend(encode_varint(timestamp))
    out.extend(b'\x12')
    name_bytes = module_name.encode('utf-8')
    out.extend(encode_varint(len(name_bytes)))
    out.extend(name_bytes)
    out.extend(b'\x1a')
    out.extend(encode_varint(len(data)))
    out.extend(data)
    out.extend(b'\x20')
    out.extend(encode_varint(crc_val))
    return bytes(out)


def test_telemetry_sorter_fuzz():
    agent_bin = "/home/user/telemetry_sorter"
    assert os.path.exists(agent_bin), f"Agent program {agent_bin} does not exist."
    assert os.path.isfile(agent_bin), f"Agent program {agent_bin} is not a regular file."
    assert os.access(agent_bin, os.X_OK), f"Agent program {agent_bin} is not executable."

    random.seed(42)

    for i in range(100):
        num_messages = random.randint(0, 100)
        stream = bytearray()
        valid_messages = []

        for _ in range(num_messages):
            ts = random.randint(0, 1000000)
            mod = f"mod_{random.randint(0, 10)}"
            data_len = random.randint(0, 256)
            data = bytes(random.getrandbits(8) for _ in range(data_len))

            correct_crc = zlib.crc32(data) & 0xffffffff
            crc = correct_crc
            if random.random() < 0.2:
                crc ^= 0x12345678
            else:
                valid_messages.append((ts, mod, data))

            msg = encode_telemetry(ts, mod, data, crc)
            stream.extend(struct.pack('<I', len(msg)))
            stream.extend(msg)

        valid_messages.sort(key=lambda item: (item[0], item[1]))
        expected_stdout = ''.join(
            f"[{ts}] {mod}: {data.hex()}\n"
            for ts, mod, data in valid_messages
        ).encode('utf-8')

        agent_proc = subprocess.run(
            [agent_bin], input=bytes(stream), capture_output=True, timeout=10
        )

        assert agent_proc.returncode == 0, (
            f"Nonzero return code on fuzz input {i}: {agent_proc.returncode}\n"
            f"stderr: {agent_proc.stderr.decode('utf-8', 'replace')}"
        )
        assert agent_proc.stdout == expected_stdout, (
            f"Output mismatch on fuzz input {i}.\n"
            f"Expected:\n{expected_stdout.decode('utf-8', 'replace')}\n"
            f"Got:\n{agent_proc.stdout.decode('utf-8', 'replace')}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
