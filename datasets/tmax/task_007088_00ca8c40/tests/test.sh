#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest


def get_dir_size_bytes(path):
    total_size = 0
    for dirpath, _, filenames in os.walk(path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)
    return total_size


def test_scripts_exist():
    py_script = "/home/user/scripts/update_routing.py"
    sh_script = "/home/user/scripts/run_checks.sh"

    assert os.path.isfile(py_script), f"Python script missing: {py_script}"
    assert os.path.isfile(sh_script), f"Bash script missing: {sh_script}"
    assert os.access(sh_script, os.X_OK), f"Bash script is not executable: {sh_script}"


def test_config_updated_in_place():
    config_path = "/home/user/config/router.json"
    assert os.path.isfile(config_path), f"Config file missing: {config_path}"

    with open(config_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {config_path} is not valid JSON")

    assert "global_settings" in data, "Missing 'global_settings' in config"
    assert data["global_settings"].get("timeout") == 30, "Incorrect global_settings.timeout"
    assert data["global_settings"].get("retries") == 3, "Incorrect global_settings.retries"

    assert "nodes" in data, "Missing 'nodes' in config"

    for node_name, node_info in data["nodes"].items():
        node_path = node_info.get("path")
        assert node_path, f"Missing path for node {node_name}"
        assert os.path.isdir(node_path), f"Node path does not exist: {node_path}"

        size_bytes = get_dir_size_bytes(node_path)
        expected_status = "offline" if size_bytes > 40 * 1024 * 1024 else "online"
        actual_status = node_info.get("status")

        assert actual_status == expected_status, \
            f"Node {node_name} status is '{actual_status}', expected '{expected_status}' based on size {size_bytes} bytes"


def test_final_log_exists_and_correct():
    log_path = "/home/user/logs/final_router.json"
    assert os.path.isfile(log_path), f"Final log file missing: {log_path}. Did the bash script run and copy the file?"

    with open(log_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {log_path} is not valid JSON")

    nodes = data.get("nodes", {})
    assert nodes.get("node1", {}).get("status") == "offline", "node1 should be offline"
    assert nodes.get("node2", {}).get("status") == "online", "node2 should be online"
    assert nodes.get("node3", {}).get("status") == "offline", "node3 should be offline"

    global_settings = data.get("global_settings", {})
    assert global_settings.get("timeout") == 30, "global_settings.timeout should be preserved as 30"
    assert global_settings.get("retries") == 3, "global_settings.retries should be preserved as 3"


def _write_allocated_file(path, size):
    chunk = b"x" * (1024 * 1024)
    remaining = size
    with open(path, "wb") as f:
        while remaining:
            part = chunk if remaining >= len(chunk) else chunk[:remaining]
            f.write(part)
            remaining -= len(part)
        f.flush()
        os.fsync(f.fileno())


def _run(command):
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )


def _assert_run_ok(result, description):
    assert result.returncode == 0, (
        f"{description} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def _assert_dynamic_result(data, expected, names):
    assert set(data.keys()) == set(expected.keys()), "Top-level config keys were added or removed"
    assert data["global_settings"] == expected["global_settings"], "global_settings was not preserved"
    assert data["unrelated_top_level"] == expected["unrelated_top_level"], "Unrelated top-level data was not preserved"
    assert set(data["nodes"].keys()) == set(names), "Dynamic nodes were added or removed"

    for name in names:
        original = expected["nodes"][name]
        actual = data["nodes"][name]
        assert actual.get("path") == original["path"], f"Path was changed for dynamic node {name}"
        assert actual.get("metadata") == original["metadata"], f"Metadata was not preserved for dynamic node {name}"
        wanted = "offline" if get_dir_size_bytes(original["path"]) > 40 * 1024 * 1024 else "online"
        assert actual.get("status") == wanted, f"Dynamic node {name} has status {actual.get('status')!r}, expected {wanted!r}"
        assert set(actual.keys()) == set(original.keys()), f"Fields were added or removed for dynamic node {name}"


def test_dynamic_execution_wrapper_and_idempotence():
    config_path = Path("/home/user/config/router.json")
    log_path = Path("/home/user/logs/final_router.json")
    py_script = Path("/home/user/scripts/update_routing.py")
    sh_script = Path("/home/user/scripts/run_checks.sh")

    token = uuid.uuid4().hex
    root = Path(tempfile.mkdtemp(prefix=f"quota_{token}_", dir="/home/user/app_data"))
    sizes = [1024 * 1024, 40 * 1024 * 1024, 41 * 1024 * 1024]
    names = [f"dynamic_{token}_{i}" for i in range(3)]
    nodes = {}

    for i, (name, size) in enumerate(zip(names, sizes)):
        node_dir = root / f"storage_{i}"
        node_dir.mkdir()
        _write_allocated_file(node_dir / "payload.bin", size)
        nodes[name] = {
            "path": str(node_dir),
            "status": "offline" if size <= 40 * 1024 * 1024 else "online",
            "metadata": {"token": token, "index": i},
        }

    fixture = {
        "global_settings": {"timeout": 73, "retries": 8, "token": token},
        "unrelated_top_level": {"preserve": [token, 17]},
        "nodes": nodes,
    }

    # Execute the Python artifact itself against randomized node names and paths.
    config_path.write_text(json.dumps(fixture, indent=2) + "\n")
    result = _run(["python3", str(py_script)])
    _assert_run_ok(result, "Python updater")
    try:
        direct_data = json.loads(config_path.read_text())
    except json.JSONDecodeError as exc:
        pytest.fail(f"Python updater produced invalid JSON: {exc}")
    _assert_dynamic_result(direct_data, fixture, names)

    # Reset wrong statuses, then exercise the required wrapper and its copy step.
    config_path.write_text(json.dumps(fixture, indent=2) + "\n")
    if log_path.exists():
        log_path.unlink()
    result = _run([str(sh_script)])
    _assert_run_ok(result, "Bash wrapper")
    assert log_path.is_file(), "Wrapper did not create final_router.json"

    try:
        wrapped_data = json.loads(config_path.read_text())
        logged_data = json.loads(log_path.read_text())
    except json.JSONDecodeError as exc:
        pytest.fail(f"Wrapper produced invalid JSON: {exc}")
    _assert_dynamic_result(wrapped_data, fixture, names)
    assert logged_data == wrapped_data, "final_router.json is not a copy of the updated configuration"

    # A second run must leave both the config and copied log byte-for-byte stable.
    first_config = config_path.read_bytes()
    result = _run([str(sh_script)])
    _assert_run_ok(result, "Second Bash wrapper run")
    assert config_path.read_bytes() == first_config, "Updater is not idempotent across repeated runs"
    assert log_path.read_bytes() == config_path.read_bytes(), "Wrapper did not copy the final configuration on the second run"

    # Confirm that the wrapper really invokes the requested Python script path.
    original_python = py_script.read_bytes()
    original_mode = stat.S_IMODE(py_script.stat().st_mode)
    marker = Path(tempfile.gettempdir()) / f"wrapper_marker_{uuid.uuid4().hex}"
    sentinel = (
        "#!/usr/bin/env python3\n"
        "from pathlib import Path\n"
        f"Path({str(marker)!r}).write_text('executed')\n"
    )
    try:
        py_script.write_text(sentinel)
        py_script.chmod(original_mode | stat.S_IXUSR)
        result = _run([str(sh_script)])
        _assert_run_ok(result, "Wrapper invocation probe")
        assert marker.is_file(), "Bash wrapper does not execute /home/user/scripts/update_routing.py"
        assert log_path.read_bytes() == config_path.read_bytes(), "Wrapper did not copy router.json after invoking Python"
    finally:
        py_script.write_bytes(original_python)
        py_script.chmod(original_mode)
        if marker.exists():
            marker.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
