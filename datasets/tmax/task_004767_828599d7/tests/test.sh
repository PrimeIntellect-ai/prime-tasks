#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import glob
import os
import struct
import numpy as np
import pytest


def read_compacted(filepath):
    # Format: uint64, uint16, uint16, double (20 bytes total)
    fmt = '<QHHd'
    record_size = struct.calcsize(fmt)
    records = []
    with open(filepath, 'rb') as f:
        while chunk := f.read(record_size):
            if len(chunk) == record_size:
                records.append(struct.unpack(fmt, chunk))
    return records


def read_expected_from_telemetry():
    # Source format from the schema: uint64, uint16, uint16, double, 12 bytes padding.
    source_fmt = '<QHHd12s'
    source_record_size = struct.calcsize(source_fmt)
    records = []
    source_files = sorted(glob.glob('/app/telemetry_data/*'))
    assert source_files, 'No telemetry source files found. Environment may be corrupted.'

    for filepath in source_files:
        assert os.path.isfile(filepath), f'Telemetry source {filepath} is not a regular file.'
        assert os.path.getsize(filepath) % source_record_size == 0, \
            f'Telemetry source {filepath} has an invalid size.'
        with open(filepath, 'rb') as f:
            while chunk := f.read(source_record_size):
                timestamp, sensor_id, status_code, value, _padding = struct.unpack(source_fmt, chunk)
                if status_code not in (404, 500):
                    records.append((timestamp, sensor_id, status_code, value))
    return records


def test_compacted_telemetry_file():
    agent_file = '/home/user/compacted_telemetry.bin'

    assert os.path.isfile(agent_file), f"Agent output file {agent_file} does not exist. Did you save it to the correct path?"

    agent_records = read_compacted(agent_file)
    truth_records = read_expected_from_telemetry()

    assert len(agent_records) == len(truth_records), \
        f"Count mismatch. Expected {len(truth_records)} valid records, got {len(agent_records)}."

    # Sort both by TIMESTAMP (index 0) to handle concurrent append disorder
    agent_records.sort(key=lambda x: x[0])
    truth_records.sort(key=lambda x: x[0])

    agent_values = np.array([r[3] for r in agent_records])
    truth_values = np.array([r[3] for r in truth_records])

    mse = np.mean((agent_values - truth_values)**2)

    assert mse <= 0.001, f"MSE threshold exceeded. Expected MSE <= 0.001, got {mse}. Ensure you are parsing the VALUE field correctly as a double."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
