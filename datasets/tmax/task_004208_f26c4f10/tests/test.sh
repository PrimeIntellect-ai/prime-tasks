#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import struct
import zlib
import tempfile


def generate_random_noise(size):
    return bytearray(random.getrandbits(8) for _ in range(size))


def build_valid_header(bav=17):
    return b'WAL' + bytes([1]) + struct.pack('<H', bav)


def build_valid_record(payload):
    length = len(payload)
    crc = zlib.crc32(payload) & 0xFFFFFFFF
    return struct.pack('<I', length) + payload + struct.pack('<I', crc)


def generate_valid_file(bav=17, num_records=None):
    if num_records is None:
        num_records = random.randint(0, 50)
    data = bytearray(build_valid_header(bav))
    for _ in range(num_records):
        payload_len = random.randint(0, 1000)
        payload = generate_random_noise(payload_len)
        data.extend(build_valid_record(payload))
    return data


def generate_fuzz_inputs(n=1000, seed=42):
    random.seed(seed)
    inputs = []

    for _ in range(n):
        category = random.random()
        if category < 0.2:
            size = random.randint(1, 10000)
            data = generate_random_noise(size)
        elif category < 0.4:
            data = bytearray(build_valid_header(17))
            num_records = random.randint(1, 10)
            for i in range(num_records):
                payload_len = random.randint(0, 1000)
                payload = generate_random_noise(payload_len)
                record = bytearray(build_valid_record(payload))
                if i == num_records - 1:
                    if random.choice([True, False]) and len(record) > 0:
                        record[-1] ^= 0xFF
                    elif len(record) > 1:
                        trunc_len = random.randint(1, len(record) - 1)
                        record = record[:trunc_len]
                data.extend(record)
        elif category < 0.6:
            wrong_bav = random.randint(0, 65535)
            if wrong_bav == 17:
                wrong_bav = 18
            data = generate_valid_file(bav=wrong_bav)
        elif category < 0.8:
            data = generate_valid_file(bav=17)
        else:
            data = bytearray(generate_valid_file(bav=17))
            if len(data) > 6:
                flip_idx = random.randint(6, len(data) - 1)
                data[flip_idx] ^= 1 << random.randint(0, 7)
        inputs.append(bytes(data))
    return inputs


def expected_output(data):
    if len(data) < 6:
        return 'INVALID_HEADER'

    if data[:3] != b'WAL' or data[3] != 1:
        return 'INVALID_HEADER'

    bav = struct.unpack('<H', data[4:6])[0]
    if bav != 17:
        return 'INVALID_BAV'

    offset = 6
    while offset < len(data):
        if offset + 4 > len(data):
            return 'CORRUPT'
        length = struct.unpack('<I', data[offset:offset + 4])[0]
        offset += 4

        if offset + length > len(data):
            return 'CORRUPT'
        payload = data[offset:offset + length]
        offset += length

        if offset + 4 > len(data):
            return 'CORRUPT'
        stored_crc = struct.unpack('<I', data[offset:offset + 4])[0]
        offset += 4

        if stored_crc != (zlib.crc32(payload) & 0xFFFFFFFF):
            return 'CORRUPT'

    return 'SAFE'


def test_wal_checker_fuzz_equivalence():
    agent_path = '/home/user/wal_checker'

    assert os.path.isfile(agent_path), f'Agent tool missing at {agent_path}'
    assert os.access(agent_path, os.X_OK), f'Agent tool not executable at {agent_path}'

    inputs = generate_fuzz_inputs(n=1000, seed=1337)

    with tempfile.TemporaryDirectory() as tmpdir:
        input_file_path = os.path.join(tmpdir, 'test.wal')

        for i, data in enumerate(inputs):
            with open(input_file_path, 'wb') as f:
                f.write(data)

            expected = expected_output(data)
            agent_proc = subprocess.run(
                [agent_path, input_file_path],
                capture_output=True,
                text=True,
            )
            agent_out = agent_proc.stdout.strip()

            assert agent_proc.returncode == 0, (
                f'Agent exited with non-zero code {agent_proc.returncode} on input {i}'
            )
            assert expected == agent_out, (
                f'Mismatch on input {i} (len={len(data)}).\n'
                f'Expected output: {expected!r}\n'
                f'Agent output: {agent_out!r}\n'
                f'Input data prefix (hex): {data[:64].hex()}'
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
