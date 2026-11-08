#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import pathlib
import shutil
import stat
import subprocess
import tempfile
import uuid
import pytest


def test_device_configs_generated():
    expected_configs = {
        "node-alpha_active.json": {
            "device_id": "node-alpha",
            "auth_token": "tk_9912a",
            "region": "EU",
            "telemetry": True
        },
        "node-beta_active.json": {
            "device_id": "node-beta",
            "auth_token": "tk_8821b",
            "region": "US",
            "telemetry": False
        },
        "node-gamma_active.json": {
            "device_id": "node-gamma",
            "auth_token": "tk_7734c",
            "region": "AP",
            "telemetry": True
        }
    }

    base_dir = "/home/user/device_configs"
    for filename, expected_content in expected_configs.items():
        filepath = os.path.join(base_dir, filename)
        assert os.path.isfile(filepath), f"Expected configuration file {filepath} was not generated."
        with open(filepath, "r") as f:
            try:
                actual_content = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"File {filepath} does not contain valid JSON.")
        assert actual_content == expected_content, f"Content of {filepath} does not match expected configuration. Expected {expected_content}, got {actual_content}."


def test_deploy_script_exists():
    script_path = "/home/user/deploy_fleet.py"
    assert os.path.isfile(script_path), f"Deployment script {script_path} is missing."
    try:
        source = pathlib.Path(script_path).read_text()
        ast.parse(source, filename=script_path)
    except (OSError, SyntaxError) as exc:
        pytest.fail(f"Deployment script is not valid Python 3 source: {exc}")


def test_script_drives_cli_with_pexpect_on_fresh_inventory():
    home = pathlib.Path("/home/user")
    script = home / "deploy_fleet.py"
    inventory = home / "device_inventory.csv"
    cli = home / "iot_setup_cli"
    config_dir = home / "device_configs"

    suffix = uuid.uuid4().hex[:10]
    rows = [
        (f"verify-a-{suffix}", f"tok-A-{suffix}", "EU", "y"),
        (f"verify-b-{suffix}", f"tok-B-{suffix}", "US", "n"),
        (f"verify-c-{suffix}", f"tok-C-{suffix}", "AP", "y"),
    ]

    inventory_bytes = inventory.read_bytes()
    inventory_mode = stat.S_IMODE(inventory.stat().st_mode)
    cli_bytes = cli.read_bytes()
    cli_mode = stat.S_IMODE(cli.stat().st_mode)

    saved_configs = {}
    if config_dir.exists():
        for path in config_dir.rglob("*"):
            if path.is_file():
                saved_configs[path.relative_to(config_dir)] = (
                    path.read_bytes(), stat.S_IMODE(path.stat().st_mode)
                )

    with tempfile.TemporaryDirectory(prefix="fleet_verify_") as tmp:
        tmp_path = pathlib.Path(tmp)
        cli_log = tmp_path / "cli_calls.jsonl"
        pexpect_log = tmp_path / "pexpect_calls.log"

        wrapper_template = r'''#!/usr/bin/env python3
import json
import os
import sys

LOG_PATH = __LOG_PATH__

def main():
    if not os.isatty(0) or not os.isatty(1):
        print("This utility requires an interactive terminal.", file=sys.stderr)
        raise SystemExit(9)
    print("IoT Edge Configuration Utility v1.0")
    dev_id = input("Device ID: ").strip()
    token = input("Authentication Token: ").strip()
    region = input("Target Region (US/EU/AP): ").strip()
    telemetry = input("Enable telemetry stream? (y/n): ").strip().lower()
    commit = input("Commit configuration? (yes/no): ").strip().lower()
    if commit != "yes":
        print("Aborted.")
        return
    record = {
        "device_id": dev_id,
        "auth_token": token,
        "region": region,
        "telemetry": telemetry,
        "commit": commit,
    }
    with open(LOG_PATH, "a") as log:
        log.write(json.dumps(record) + "\n")
    output = {
        "device_id": dev_id,
        "auth_token": token,
        "region": region,
        "telemetry": telemetry == "y",
    }
    path = f"/home/user/device_configs/{dev_id}_active.json"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(output, f)
    print(f"Success! Configuration saved to {path}")

if __name__ == "__main__":
    main()
'''
        wrapper = wrapper_template.replace("__LOG_PATH__", repr(str(cli_log)))

        sitecustomize = r'''import os
import pexpect

_log_path = os.environ.get("PEXPECT_AUDIT_LOG")
_original_spawn = pexpect.spawn
_original_run = pexpect.run

def _mark(name):
    if _log_path:
        with open(_log_path, "a") as f:
            f.write(name + "\n")

def audited_spawn(*args, **kwargs):
    _mark("spawn")
    return _original_spawn(*args, **kwargs)

def audited_run(*args, **kwargs):
    _mark("run")
    return _original_run(*args, **kwargs)

pexpect.spawn = audited_spawn
pexpect.run = audited_run
'''

        try:
            inventory.write_text("".join(",".join(row) + "\n" for row in rows))
            os.chmod(inventory, inventory_mode)
            cli.write_text(wrapper)
            os.chmod(cli, 0o755)
            (tmp_path / "sitecustomize.py").write_text(sitecustomize)

            for dev_id, _, _, _ in rows:
                target = config_dir / f"{dev_id}_active.json"
                if target.exists():
                    target.unlink()

            env = os.environ.copy()
            env["PEXPECT_AUDIT_LOG"] = str(pexpect_log)
            old_pythonpath = env.get("PYTHONPATH")
            env["PYTHONPATH"] = str(tmp_path) + (os.pathsep + old_pythonpath if old_pythonpath else "")

            result = subprocess.run(
                ["python3", str(script)],
                cwd=str(home),
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert result.returncode == 0, (
                f"deploy_fleet.py exited with {result.returncode}.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )

            assert pexpect_log.is_file(), "The script did not invoke an instrumented pexpect API."
            calls = pexpect_log.read_text().splitlines()
            assert any(call in {"spawn", "run"} for call in calls), (
                "The script did not use pexpect.spawn or pexpect.run while executing."
            )

            assert cli_log.is_file(), "The interactive utility was not successfully driven."
            actual_calls = [json.loads(line) for line in cli_log.read_text().splitlines() if line.strip()]
            expected_calls = [
                {
                    "device_id": dev_id,
                    "auth_token": token,
                    "region": region,
                    "telemetry": telemetry,
                    "commit": "yes",
                }
                for dev_id, token, region, telemetry in rows
            ]
            assert actual_calls == expected_calls, (
                f"Expected one correctly completed CLI session per inventory row. "
                f"Expected {expected_calls}, got {actual_calls}."
            )

            for dev_id, token, region, telemetry in rows:
                path = config_dir / f"{dev_id}_active.json"
                assert path.is_file(), f"Fresh configuration {path} was not generated."
                with path.open() as f:
                    actual = json.load(f)
                expected = {
                    "device_id": dev_id,
                    "auth_token": token,
                    "region": region,
                    "telemetry": telemetry == "y",
                }
                assert actual == expected, f"Incorrect fresh configuration in {path}: {actual}"
        finally:
            inventory.write_bytes(inventory_bytes)
            os.chmod(inventory, inventory_mode)
            cli.write_bytes(cli_bytes)
            os.chmod(cli, cli_mode)
            if config_dir.exists():
                shutil.rmtree(config_dir)
            config_dir.mkdir(parents=True, exist_ok=True)
            for relative, (content, mode) in saved_configs.items():
                restored = config_dir / relative
                restored.parent.mkdir(parents=True, exist_ok=True)
                restored.write_bytes(content)
                os.chmod(restored, mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
