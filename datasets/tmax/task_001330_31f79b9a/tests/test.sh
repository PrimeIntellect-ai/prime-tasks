#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import struct
import subprocess
import sys
import zlib

BASE_DIR = "/home/user/system_build"
CONFIGS_DIR = os.path.join(BASE_DIR, "configs")
PACK_PATH = os.path.join(BASE_DIR, "output.pack")
SCRIPT_PATH = os.path.join(BASE_DIR, "build_pack.py")

EXPECTED_CONFIGS = {
    "service_A.json": """{
  "name": "service_A",
  "allowed_ports": [8000, 8001, 8002],
  "retries": 3
}
""",
    "service_B.json": """{
  "name": "service_B",
  "allowed_ports": [8001, 8002],
  "timeout": 30
}
""",
    "service_C.json": """{
  "name": "service_C",
  "allowed_ports": [8002],
  "secure": true
}
""",
    "service_D.json": """{
  "name": "service_D",
  "allowed_ports": [8000, 8001, 8002, 8003],
  "debug": false
}
""",
}


def assert_original_configs_unchanged():
    actual_names = sorted(
        name for name in os.listdir(CONFIGS_DIR) if name.endswith(".json")
    )
    assert actual_names == sorted(EXPECTED_CONFIGS), (
        f"JSON config set was modified: expected {sorted(EXPECTED_CONFIGS)}, "
        f"got {actual_names}"
    )

    for name, expected in EXPECTED_CONFIGS.items():
        path = os.path.join(CONFIGS_DIR, name)
        assert os.path.isfile(path), f"Required config is missing: {name}"
        with open(path, "r", encoding="utf-8", newline="") as fp:
            actual = fp.read()
        assert actual == expected, f"Config file was modified: {name}"


def test_output_pack_exists():
    assert os.path.isfile(PACK_PATH), "/home/user/system_build/output.pack was not generated"


def test_configs_are_unchanged():
    assert_original_configs_unchanged()


def test_build_script_regenerates_output():
    assert os.path.isfile(SCRIPT_PATH), "/home/user/system_build/build_pack.py is missing"

    if os.path.lexists(PACK_PATH):
        os.remove(PACK_PATH)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd=BASE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"build_pack.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(PACK_PATH), "build_pack.py did not regenerate output.pack"
    assert_original_configs_unchanged()


def test_output_pack_format_and_logic():
    pack_path = PACK_PATH
    configs_dir = CONFIGS_DIR

    assert os.path.isfile(pack_path), "output.pack does not exist"

    with open(pack_path, "rb") as f:
        data = f.read()

    assert len(data) >= 8, "output.pack is too small to be valid"

    # Verify Magic Header
    assert data[:4] == b"PACK", f"Magic header is incorrect: expected b'PACK', got {data[:4]}"

    # Verify Checksum
    crc_expected = zlib.crc32(data[:-4]) & 0xFFFFFFFF
    crc_actual = struct.unpack(">I", data[-4:])[0]
    assert crc_expected == crc_actual, f"CRC32 mismatch: expected {crc_expected}, got {crc_actual}"

    # Parse original configs
    expected_services = []
    for fname in os.listdir(configs_dir):
        if fname.endswith('.json'):
            with open(os.path.join(configs_dir, fname), 'r') as fp:
                raw_data = fp.read()
                js = json.loads(raw_data)
                expected_services.append({
                    "name": js["name"],
                    "data": raw_data,
                    "allowed": js["allowed_ports"]
                })
    expected_services.sort(key=lambda x: x["name"])

    # Verify Service Count
    count = struct.unpack(">H", data[4:6])[0]
    assert count == len(expected_services), f"Expected {len(expected_services)} services, got {count}"

    offset = 6
    parsed_services = []
    for i in range(count):
        nlen = struct.unpack(">B", data[offset:offset+1])[0]
        offset += 1

        name = data[offset:offset+nlen].decode('ascii')
        offset += nlen

        port = struct.unpack(">H", data[offset:offset+2])[0]
        offset += 2

        dlen = struct.unpack(">I", data[offset:offset+4])[0]
        offset += 4

        config_data = data[offset:offset+dlen].decode('utf-8')
        offset += dlen

        parsed_services.append({
            "name": name,
            "port": port,
            "data": config_data
        })

    assert offset == len(data) - 4, "Data length mismatch: extra or missing bytes before checksum"

    # Verify constraints and data integrity
    assigned_ports = set()
    for parsed, expected in zip(parsed_services, expected_services):
        assert parsed["name"] == expected["name"], f"Service order/name mismatch: expected {expected['name']}, got {parsed['name']}"
        assert parsed["data"] == expected["data"], f"Config data mismatch for service {parsed['name']}"

        port = parsed["port"]
        assert port in expected["allowed"], f"Port {port} is not in allowed_ports for {parsed['name']}"
        assert port not in assigned_ports, f"Port {port} was assigned to multiple services"
        assigned_ports.add(port)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
