#!/bin/bash
set -u
mkdir -p /logs/verifier

fail_verifier() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

PROJECT_DIR=/home/user/project
cd "$PROJECT_DIR" || fail_verifier

# Force the submitted project to rebuild the requested executable.
rm -f migrate data_v2.bin
make -B migrate >/tmp/make_migrate.log 2>&1 || fail_verifier
[ -f migrate ] && [ -x migrate ] || fail_verifier

# The requested artifact must be a compiled executable, not a script or copied output.
python3 - <<'PY' || fail_verifier
from pathlib import Path
p = Path('/home/user/project/migrate')
assert p.read_bytes()[:4] == b'\x7fELF', 'migrate is not an ELF executable'
PY

# Compile migrate.c independently so behavioral tests necessarily exercise the
# source file the instruction required the agent to fix.
gcc -Wall -Wextra -O2 -o /tmp/migrate_from_source migrate.c >/tmp/gcc_migrate.log 2>&1 || fail_verifier
[ -x /tmp/migrate_from_source ] || fail_verifier

# Run the make-built tool on the supplied sample, as required by the task.
./migrate data_v1.bin data_v2.bin || fail_verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import struct
import subprocess
import pytest

PROJECT_DIR = "/home/user/project"
DATA_V1_PATH = os.path.join(PROJECT_DIR, "data_v1.bin")
DATA_V2_PATH = os.path.join(PROJECT_DIR, "data_v2.bin")
BUILT_MIGRATE = os.path.join(PROJECT_DIR, "migrate")
SOURCE_MIGRATE = "/tmp/migrate_from_source"

def test_data_v2_exists():
    assert os.path.isfile(DATA_V2_PATH), f"The output file {DATA_V2_PATH} does not exist. Did you run the migration tool?"

def test_data_v2_correctness():
    assert os.path.isfile(DATA_V1_PATH), f"The input file {DATA_V1_PATH} is missing."
    assert os.path.isfile(DATA_V2_PATH), f"The output file {DATA_V2_PATH} is missing."

    with open(DATA_V1_PATH, "rb") as f:
        v1_data = f.read()

    assert len(v1_data) % 16 == 0, "Input data_v1.bin is corrupted or has an invalid size."
    num_records = len(v1_data) // 16

    with open(DATA_V2_PATH, "rb") as f:
        v2_data = f.read()

    expected_v2_size = num_records * 17
    assert len(v2_data) == expected_v2_size, (
        f"Expected data_v2.bin to be exactly {expected_v2_size} bytes for {num_records} records "
        f"(17 bytes per record), but got {len(v2_data)} bytes. Check your struct packing and padding."
    )

    for i in range(num_records):
        v1_offset = i * 16
        v2_offset = i * 17

        v1_chunk = v1_data[v1_offset:v1_offset+16]
        v2_chunk = v2_data[v2_offset:v2_offset+17]

        v1_unpacked = struct.unpack('<IfQ', v1_chunk)
        try:
            v2_unpacked = struct.unpack('<IBfQ', v2_chunk)
        except struct.error:
            pytest.fail(f"Record {i+1}: Failed to unpack 17 bytes as <IBfQ. Data might be malformed.")

        assert v2_unpacked[0] == v1_unpacked[0], f"Record {i+1}: ID mismatch. Expected {v1_unpacked[0]}, got {v2_unpacked[0]}."
        assert v2_unpacked[1] == 1, f"Record {i+1}: Flags mismatch. Expected 1 (0x01), got {v2_unpacked[1]}."

        # Float comparison
        assert abs(v2_unpacked[2] - v1_unpacked[1]) < 0.0001, (
            f"Record {i+1}: Value mismatch. Expected approx {v1_unpacked[1]}, got {v2_unpacked[2]}."
        )

        assert v2_unpacked[3] == v1_unpacked[2], f"Record {i+1}: Timestamp mismatch. Expected {v1_unpacked[2]}, got {v2_unpacked[3]}."


def make_random_v1(count):
    records = []
    expected = []
    for _ in range(count):
        id_bytes = secrets.token_bytes(4)
        timestamp_bytes = secrets.token_bytes(8)

        # Generate a finite IEEE-754 binary32 representation so ordinary C
        # float deserialization and serialization must preserve it exactly.
        while True:
            float_bits = secrets.randbits(32)
            if ((float_bits >> 23) & 0xff) != 0xff:
                break
        value_bytes = struct.pack('<I', float_bits)

        records.append(id_bytes + value_bytes + timestamp_bytes)
        expected.append(id_bytes + b'\x01' + value_bytes + timestamp_bytes)
    return b''.join(records), b''.join(expected)


@pytest.mark.parametrize('executable', [BUILT_MIGRATE, SOURCE_MIGRATE])
@pytest.mark.parametrize('record_count', [0, 1, 2, 7, 31])
def test_migrate_executable_on_fresh_inputs(executable, record_count, tmp_path):
    v1_data, expected_v2 = make_random_v1(record_count)
    input_path = tmp_path / 'fresh_v1.bin'
    output_path = tmp_path / 'fresh_v2.bin'
    input_path.write_bytes(v1_data)

    result = subprocess.run(
        [executable, str(input_path), str(output_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} failed with exit code {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    assert output_path.is_file(), f"{executable} did not create its output file"
    actual_v2 = output_path.read_bytes()
    assert actual_v2 == expected_v2, (
        f"{executable} produced incorrect packed v2 bytes for "
        f"{record_count} freshly generated records"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
