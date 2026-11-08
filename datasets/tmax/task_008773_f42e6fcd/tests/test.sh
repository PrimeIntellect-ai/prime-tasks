#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import struct
import subprocess
from pathlib import Path

import pytest

INVENTORY_PATH = "/home/user/inventory.json"
BASE_DIR = "/home/user/project_dump"


def decompress_if_needed(data: bytes) -> bytes:
    """Decompress CRLE data if the magic header is present."""
    if data.startswith(b"CRLE"):
        decompressed = bytearray()
        i = 4
        while i + 1 < len(data):
            count = data[i]
            byte = data[i + 1:i + 2]
            decompressed.extend(byte * count)
            i += 2
        return bytes(decompressed)
    return data


def process_file(path: str) -> dict:
    """Extract metadata from a file according to the specifications."""
    with open(path, "rb") as f:
        data = f.read()

    data = decompress_if_needed(data)

    if data.startswith(b"\x7fELF"):
        if len(data) >= 0x18 + 8:
            val = struct.unpack_from("<Q", data, 0x18)[0]
            return {"type": "ELF", "metric": hex(val)}
    elif data.startswith(b"\x37\x7f\x06\x82") or data.startswith(b"\x37\x7f\x06\x83"):
        if len(data) >= 0x08 + 4:
            val = struct.unpack_from(">I", data, 0x08)[0]
            return {"type": "WAL", "metric": val}
    elif data.startswith(b"; FLAVOR:Marlin"):
        text = data.decode("utf-8", errors="ignore")
        count = sum(1 for line in text.splitlines() if line.startswith("G1 "))
        return {"type": "GCode", "metric": count}

    return None


def get_expected_inventory(base_dir: str) -> dict:
    """Dynamically compute the expected inventory from the actual files."""
    inventory = {}
    for root, _, files in os.walk(base_dir):
        for f in files:
            path = os.path.join(root, f)
            res = process_file(path)
            if res is not None:
                inventory[path] = res
    return inventory


def compress_crle(data: bytes) -> bytes:
    out = bytearray(b"CRLE")
    i = 0
    while i < len(data):
        value = data[i]
        count = 1
        while i + count < len(data) and data[i + count] == value and count < 255:
            count += 1
        out.extend((count, value))
        i += count
    return bytes(out)


def install_runtime_fixtures():
    token = secrets.token_hex(8)
    root = Path(BASE_DIR) / ("runtime_" + token) / "nested" / "deeper"
    root.mkdir(parents=True, exist_ok=False)

    elf_raw_value = secrets.randbits(63) | 1
    elf_comp_value = secrets.randbits(63) | 1
    wal_raw_value = secrets.choice([1024, 2048, 4096, 8192, 16384, 32768])
    wal_comp_value = secrets.choice([1024, 2048, 4096, 8192, 16384, 32768])
    raw_moves = secrets.randbelow(8) + 2
    comp_moves = secrets.randbelow(8) + 3

    elf_raw = b"\x7fELF" + b"\x00" * 20 + struct.pack("<Q", elf_raw_value)
    elf_comp = b"\x7fELF" + b"\x00" * 20 + struct.pack("<Q", elf_comp_value)
    wal_raw = b"\x37\x7f\x06\x82" + b"\x00" * 4 + struct.pack(">I", wal_raw_value)
    wal_comp = b"\x37\x7f\x06\x83" + b"\x00" * 4 + struct.pack(">I", wal_comp_value)
    gcode_raw = (b"; FLAVOR:Marlin\nG10 X0\n" +
                 b"G1 X7 Y8\n" * raw_moves + b" G1 X99\nM104 S205\n")
    gcode_comp = (b"; FLAVOR:Marlin\n; G1 ignored\n" +
                  b"G1 Z0.25\n" * comp_moves + b"G1X0\nM140 S60\n")

    fixtures = {
        root / ("elf_raw_" + token): elf_raw,
        root / ("elf_crle_" + token): compress_crle(elf_comp),
        root / ("wal_raw_" + token): wal_raw,
        root / ("wal_crle_" + token): compress_crle(wal_comp),
        root / ("gcode_raw_" + token): gcode_raw,
        root / ("gcode_crle_" + token): compress_crle(gcode_comp),
    }
    for path, data in fixtures.items():
        path.write_bytes(data)
    return fixtures


RUNTIME_FIXTURES = install_runtime_fixtures()
EXPECTED_BEFORE_EXECUTION = get_expected_inventory(BASE_DIR)


def find_python_scripts():
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for name in files:
            path = os.path.join(root, name)
            if path == INVENTORY_PATH or not os.path.isfile(path):
                continue
            if name.endswith(".py"):
                candidates.append(path)
                continue
            try:
                data = Path(path).read_bytes()
                if len(data) > 1024 * 1024 or b"\x00" in data:
                    continue
                text = data.decode("utf-8")
                compile(text, path, "exec")
                if text.strip():
                    candidates.append(path)
            except (OSError, UnicodeDecodeError, SyntaxError):
                pass
    return sorted(set(candidates))


def inventory_matches(actual, expected):
    if not isinstance(actual, dict):
        return False
    if set(actual) != set(expected):
        return False
    for path, expected_data in expected.items():
        actual_data = actual.get(path)
        if not isinstance(actual_data, dict):
            return False
        if actual_data.get("type") != expected_data["type"]:
            return False
        if actual_data.get("metric") != expected_data["metric"]:
            return False
    return True


def test_python_script_exists_and_generates_inventory():
    candidates = find_python_scripts()
    assert candidates, "No Python processing script was created under /home/user."

    failures = []
    for script in candidates:
        try:
            if os.path.exists(INVENTORY_PATH):
                os.unlink(INVENTORY_PATH)
            result = subprocess.run(
                ["python3", script],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            failures.append(f"{script}: {exc}")
            continue

        if result.returncode != 0:
            failures.append(f"{script}: exited with status {result.returncode}")
            continue
        if not os.path.isfile(INVENTORY_PATH):
            failures.append(f"{script}: did not create {INVENTORY_PATH}")
            continue
        try:
            with open(INVENTORY_PATH, "r") as f:
                actual = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            failures.append(f"{script}: produced an invalid inventory: {exc}")
            continue

        if inventory_matches(actual, EXPECTED_BEFORE_EXECUTION):
            for path, original_data in RUNTIME_FIXTURES.items():
                assert path.is_file(), f"The processing script removed runtime fixture {path}"
                assert path.read_bytes() == original_data, f"The processing script modified runtime fixture {path}"
            return
        failures.append(f"{script}: generated incorrect inventory contents")

    pytest.fail("No submitted Python script generated the required inventory. " + "; ".join(failures))


def test_inventory_file_exists():
    assert os.path.isfile(INVENTORY_PATH), f"The output file {INVENTORY_PATH} was not created."


def test_inventory_file_is_valid_json():
    assert os.path.isfile(INVENTORY_PATH), "Inventory file missing."
    with open(INVENTORY_PATH, "r") as f:
        try:
            json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"The file {INVENTORY_PATH} does not contain valid JSON: {e}")


def test_inventory_contents_match():
    assert os.path.isfile(INVENTORY_PATH), "Inventory file missing."

    with open(INVENTORY_PATH, "r") as f:
        actual_inventory = json.load(f)

    expected_inventory = get_expected_inventory(BASE_DIR)

    assert isinstance(actual_inventory, dict), "The top-level JSON structure must be an object (dictionary)."

    # Check that all expected keys are present and values match
    for path, expected_data in expected_inventory.items():
        assert path in actual_inventory, f"Missing entry for file: {path}"
        actual_data = actual_inventory[path]
        assert actual_data.get("type") == expected_data["type"], f"Incorrect type for {path}. Expected {expected_data['type']}, got {actual_data.get('type')}"
        assert actual_data.get("metric") == expected_data["metric"], f"Incorrect metric for {path}. Expected {expected_data['metric']}, got {actual_data.get('metric')}"

    # Check for any extra unexpected keys
    extra_keys = set(actual_inventory.keys()) - set(expected_inventory.keys())
    assert not extra_keys, f"Found unexpected entries in the inventory: {extra_keys}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
