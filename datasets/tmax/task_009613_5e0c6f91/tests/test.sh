#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import subprocess
import secrets
import struct
from collections import defaultdict
import pytest

PIPELINE_DIR = "/home/user/legacy_pipeline"
PLAN_PATH = "/home/user/migration_plan.json"
SOURCE_PATH = "/home/user/migrator/main.go"
LINUX_BIN = "/home/user/migrator/build/migrator-linux"
WINDOWS_BIN = "/home/user/migrator/build/migrator-windows.exe"
REBUILT_LINUX = "/tmp/migrator-rebuilt-linux"
REBUILT_WINDOWS = "/tmp/migrator-rebuilt-windows.exe"

def compute_expected_plan():
    files = [f for f in os.listdir(PIPELINE_DIR) if f.endswith('.py')]

    scripts_info = {}
    graph = defaultdict(list)
    in_degree = {f: 0 for f in files}

    for f in files:
        path = os.path.join(PIPELINE_DIR, f)
        with open(path, 'r', encoding='utf-8') as file:
            content = file.read()

        deps = []
        schema = ""
        weight = 0

        for line in content.splitlines():
            if line.startswith('# DEPENDS_ON:'):
                deps_str = line.split(':', 1)[1].strip()
                if deps_str:
                    deps = [d.strip() for d in deps_str.split(',')]
            elif line.startswith('# SCHEMA_VERSION:'):
                schema = line.split(':', 1)[1].strip()
            elif line.startswith('# WEIGHT_FACTOR:'):
                weight = int(line.split(':', 1)[1].strip())

        stripped_lines = [line for line in content.split('\n') if not line.startswith('#')]
        stripped_content = '\n'.join(stripped_lines)
        checksum = hashlib.sha256(stripped_content.encode('utf-8')).hexdigest()

        if schema.startswith('v'):
            major = int(schema[1:].split('.')[0])
            target_schema = f"v{major + 1}.0"
        else:
            target_schema = ""

        scripts_info[f] = {
            "weight": weight,
            "deps": deps,
            "checksum": checksum,
            "target_schema": target_schema,
            "total_weight": weight
        }

    for f, info in scripts_info.items():
        for dep in info["deps"]:
            graph[dep].append(f)
            in_degree[f] += 1

    queue = [f for f in files if in_degree[f] == 0]
    queue.sort()
    sorted_scripts = []

    while queue:
        queue.sort()
        curr = queue.pop(0)
        sorted_scripts.append(curr)

        for neighbor in graph[curr]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                queue.append(neighbor)

    def get_total_weight(script):
        w = scripts_info[script]["weight"]
        for dep in scripts_info[script]["deps"]:
            w += get_total_weight(dep)
        return w

    expected_plan = []
    for script in sorted_scripts:
        total_weight = get_total_weight(script)
        expected_plan.append({
            "script": script,
            "total_weight": total_weight,
            "checksum": scripts_info[script]["checksum"],
            "target_schema": scripts_info[script]["target_schema"]
        })

    return expected_plan

def load_and_assert_plan(expected_plan):
    assert os.path.exists(PLAN_PATH), f"Expected JSON report at {PLAN_PATH} is missing."
    with open(PLAN_PATH, 'r', encoding='utf-8') as f:
        try:
            actual_plan = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {PLAN_PATH} is not valid JSON.")

    assert isinstance(actual_plan, list), "JSON report must be a list of objects."
    assert len(actual_plan) == len(expected_plan), f"Expected {len(expected_plan)} scripts in the report, found {len(actual_plan)}."
    for i, (actual, expected) in enumerate(zip(actual_plan, expected_plan)):
        assert actual.get("script") == expected["script"], f"Order mismatch at index {i}: expected {expected['script']}, got {actual.get('script')}"
        assert actual.get("total_weight") == expected["total_weight"], f"Weight mismatch for {expected['script']}: expected {expected['total_weight']}, got {actual.get('total_weight')}"
        assert actual.get("checksum") == expected["checksum"], f"Checksum mismatch for {expected['script']}: expected {expected['checksum']}, got {actual.get('checksum')}"
        assert actual.get("target_schema") == expected["target_schema"], f"Schema mismatch for {expected['script']}: expected {expected['target_schema']}, got {actual.get('target_schema')}"

def run_tool(path):
    if os.path.exists(PLAN_PATH):
        os.remove(PLAN_PATH)
    result = subprocess.run([path], cwd="/home/user/migrator", stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=20)
    assert result.returncode == 0, f"{path} failed: {result.stderr}"
    assert os.path.exists(PLAN_PATH), f"{path} did not generate {PLAN_PATH}"

def test_go_source_builds_and_executables_process_derived_input():
    assert os.path.isfile(SOURCE_PATH), f"Go source missing at {SOURCE_PATH}"

    env = os.environ.copy()
    env.update({"GOOS": "linux", "GOARCH": "amd64", "CGO_ENABLED": "0", "GO111MODULE": "off"})
    result = subprocess.run(["go", "build", "-o", REBUILT_LINUX, SOURCE_PATH],
                            cwd="/home/user/migrator", env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
    assert result.returncode == 0, f"main.go does not build for linux/amd64: {result.stderr}"

    env["GOOS"] = "windows"
    result = subprocess.run(["go", "build", "-o", REBUILT_WINDOWS, SOURCE_PATH],
                            cwd="/home/user/migrator", env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
    assert result.returncode == 0, f"main.go does not build for windows/amd64: {result.stderr}"

    token = secrets.token_hex(8)
    probe_name = f"verifier_probe_{token}.py"
    probe_path = os.path.join(PIPELINE_DIR, probe_name)
    weight = 1000 + secrets.randbelow(8000)
    major = 10 + secrets.randbelow(80)
    body_value = secrets.token_hex(20)
    with open(probe_path, 'w', encoding='utf-8', newline='') as f:
        f.write(f"# DEPENDS_ON: report_gen.py\n# SCHEMA_VERSION: v{major}.7\n# WEIGHT_FACTOR: {weight}\nprobe_value = '{body_value}'\n")

    try:
        expected = compute_expected_plan()
        for executable in (LINUX_BIN, REBUILT_LINUX):
            run_tool(executable)
            load_and_assert_plan(expected)
    finally:
        if os.path.exists(probe_path):
            os.remove(probe_path)
        if os.path.isfile(LINUX_BIN) and os.access(LINUX_BIN, os.X_OK):
            subprocess.run([LINUX_BIN], cwd="/home/user/migrator", stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=20)

def test_migration_plan_exists_and_correct():
    assert os.path.exists(PLAN_PATH), f"Expected JSON report at {PLAN_PATH} is missing."

    with open(PLAN_PATH, 'r', encoding='utf-8') as f:
        try:
            actual_plan = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {PLAN_PATH} is not valid JSON.")

    expected_plan = compute_expected_plan()

    assert isinstance(actual_plan, list), "JSON report must be a list of objects."
    assert len(actual_plan) == len(expected_plan), f"Expected {len(expected_plan)} scripts in the report, found {len(actual_plan)}."

    for i, (actual, expected) in enumerate(zip(actual_plan, expected_plan)):
        assert actual.get("script") == expected["script"], f"Order mismatch at index {i}: expected {expected['script']}, got {actual.get('script')}"
        assert actual.get("total_weight") == expected["total_weight"], f"Weight mismatch for {expected['script']}: expected {expected['total_weight']}, got {actual.get('total_weight')}"
        assert actual.get("checksum") == expected["checksum"], f"Checksum mismatch for {expected['script']}: expected {expected['checksum']}, got {actual.get('checksum')}"
        assert actual.get("target_schema") == expected["target_schema"], f"Schema mismatch for {expected['script']}: expected {expected['target_schema']}, got {actual.get('target_schema')}"

def test_linux_binary_exists_and_valid():
    assert os.path.exists(LINUX_BIN), f"Linux binary missing at {LINUX_BIN}"
    assert os.access(LINUX_BIN, os.X_OK), f"Linux binary at {LINUX_BIN} is not executable."

    with open(LINUX_BIN, 'rb') as f:
        header = f.read(20)
        assert header[:4] == b'\x7fELF', f"File {LINUX_BIN} is not a valid ELF binary."
        assert header[4] == 2, "Linux binary is not a 64-bit ELF file."
        assert struct.unpack('<H', header[18:20])[0] == 0x3e, "Linux binary is not amd64."

    result = subprocess.run(["go", "version", "-m", LINUX_BIN], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=10)
    assert result.returncode == 0 and "go1." in result.stdout, "Linux artifact is not a Go executable."

def test_windows_binary_exists_and_valid():
    assert os.path.exists(WINDOWS_BIN), f"Windows binary missing at {WINDOWS_BIN}"

    with open(WINDOWS_BIN, 'rb') as f:
        header = f.read(2)
        assert header == b'MZ', f"File {WINDOWS_BIN} is not a valid Windows PE binary (missing MZ header)."
        f.seek(0x3c)
        pe_offset_data = f.read(4)
        assert len(pe_offset_data) == 4, "Windows binary has a truncated DOS header."
        pe_offset = struct.unpack('<I', pe_offset_data)[0]
        f.seek(pe_offset)
        assert f.read(4) == b'PE\0\0', "Windows binary is missing a PE signature."
        assert struct.unpack('<H', f.read(2))[0] == 0x8664, "Windows binary is not amd64."
        f.seek(pe_offset + 24)
        assert struct.unpack('<H', f.read(2))[0] == 0x20b, "Windows binary is not a 64-bit PE executable."

    result = subprocess.run(["go", "version", "-m", WINDOWS_BIN], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=10)
    assert result.returncode == 0 and "go1." in result.stdout, "Windows artifact is not a Go executable."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
