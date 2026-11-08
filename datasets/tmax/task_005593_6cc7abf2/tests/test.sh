#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import pytest

def test_updates_csv_content():
    csv_path = "/home/user/updates.csv"
    assert os.path.exists(csv_path), f"File {csv_path} does not exist. Did you redirect stdout to it?"

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "cache_layer,0,5",
        "db_backend,1,2"
    ]

    assert lines == expected_lines, (
        f"CSV content mismatch.\nExpected:\n{expected_lines}\nGot:\n{lines}\n"
        "Ensure you are printing in the format 'app_name,old_version,new_version' "
        "and sorting alphabetically by app_name."
    )

def test_state_bin_updated_correctly():
    state_path = "/home/user/state.bin"
    assert os.path.exists(state_path), f"File {state_path} does not exist."

    size = os.path.getsize(state_path)
    assert size % 36 == 0, f"State file size ({size} bytes) is not a multiple of 36 bytes."
    assert size == 144, f"State file size mismatch. Expected 144 bytes (4 records), got {size} bytes."

    records = {}
    with open(state_path, "rb") as f:
        while True:
            data = f.read(36)
            if not data:
                break
            assert len(data) == 36, "Incomplete record found at the end of the file."

            name_bytes, version = struct.unpack("<32si", data)

            try:
                name = name_bytes.rstrip(b'\x00').decode('ascii')
            except UnicodeDecodeError:
                pytest.fail("Failed to decode application name as ASCII. Ensure proper null-padding.")

            records[name] = version

    expected_records = {
        "web_server": 3,
        "db_backend": 2,
        "queue_mgr": 4,
        "cache_layer": 5
    }

    assert records == expected_records, (
        f"State file records mismatch.\nExpected: {expected_records}\nGot: {records}\n"
        "Ensure you are updating existing records properly and appending new ones."
    )
TEST_EOF

cat << 'BEHAVIOR_EOF' > /tmp/test_tracker_behavior.py
import json
import os
import shutil
import stat
import struct
import subprocess
import tempfile
import uuid

SOURCE = "/home/user/tracker.c"
BINARY = "/home/user/tracker"
STATE = "/home/user/state.bin"
CONFIGS = "/home/user/configs"

assert os.path.isfile(SOURCE), f"Missing C source file: {SOURCE}"
assert os.path.getsize(SOURCE) > 0, f"C source file is empty: {SOURCE}"
assert os.path.isfile(BINARY), f"Missing compiled tracker: {BINARY}"
assert os.access(BINARY, os.X_OK), f"Tracker is not executable: {BINARY}"
with open(BINARY, "rb") as f:
    assert f.read(4) == b"\x7fELF", "Compiled tracker must be an ELF executable"

rebuilt = os.path.join(tempfile.mkdtemp(prefix="tracker-build-"), "tracker")
compile_result = subprocess.run(
    ["gcc", SOURCE, "-o", rebuilt, "-ljson-c"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=30,
)
assert compile_result.returncode == 0, "tracker.c did not compile:\n" + compile_result.stderr

suffix = uuid.uuid4().hex[:8]
names = {
    "up": "m_up_" + suffix,
    "equal": "z_equal_" + suffix,
    "lower": "q_lower_" + suffix,
    "absent": "p_absent_" + suffix,
    "new_a": "a_new_" + suffix,
    "new_b": "x_new_" + suffix,
}
base_records = [
    (names["up"], 7),
    (names["equal"], 12),
    (names["lower"], 20),
    (names["absent"], 31),
]
configs = [
    ("05.json", names["up"], 11),
    ("04.json", names["equal"], 12),
    ("03.json", names["lower"], 4),
    ("02.json", names["new_b"], 9),
    ("01.json", names["new_a"], 6),
]
expected_records = {
    names["up"]: 11,
    names["equal"]: 12,
    names["lower"]: 20,
    names["absent"]: 31,
    names["new_a"]: 6,
    names["new_b"]: 9,
}
expected_output = sorted([
    f'{names["up"]},7,11',
    f'{names["new_a"]},0,6',
    f'{names["new_b"]},0,9',
])

def reset_inputs():
    if os.path.exists(CONFIGS):
        shutil.rmtree(CONFIGS)
    os.makedirs(CONFIGS)
    for filename, app_name, version in configs:
        with open(os.path.join(CONFIGS, filename), "w") as f:
            json.dump({"app_name": app_name, "config_version": version, "extra": True}, f)
    with open(os.path.join(CONFIGS, "ignored.txt"), "w") as f:
        json.dump({"app_name": "must_not_be_added_" + suffix, "config_version": 999}, f)
    with open(STATE, "wb") as f:
        for name, version in base_records:
            f.write(struct.pack("<32si", name.encode("ascii"), version))

def read_state():
    data = open(STATE, "rb").read()
    assert len(data) % 36 == 0, "Updated state is not composed of 36-byte records"
    result = {}
    for offset in range(0, len(data), 36):
        name_field, version = struct.unpack("<32si", data[offset:offset + 36])
        assert b"\x00" in name_field, "Application name is not null-terminated"
        name_bytes, padding = name_field.split(b"\x00", 1)
        assert padding == b"\x00" * len(padding), "Application name has nonzero padding"
        name = name_bytes.decode("ascii")
        assert name not in result, "State contains duplicate application records"
        result[name] = version
    return result

def exercise(executable):
    reset_inputs()
    first = subprocess.run(
        [executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert first.returncode == 0, f"Tracker exited with {first.returncode}: {first.stderr}"
    lines = [line.strip() for line in first.stdout.splitlines() if line.strip()]
    assert lines == expected_output, f"Dynamic update output mismatch: expected {expected_output}, got {lines}"
    assert read_state() == expected_records, "Dynamic state update did not preserve/update records correctly"

    before = open(STATE, "rb").read()
    second = subprocess.run(
        [executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert second.returncode == 0, f"Tracker failed on a second run: {second.stderr}"
    assert [x for x in second.stdout.splitlines() if x.strip()] == [], "Second run should report no updates"
    assert open(STATE, "rb").read() == before, "Second run unexpectedly changed the state file"

exercise(BINARY)
exercise(rebuilt)
BEHAVIOR_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/test_tracker_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
