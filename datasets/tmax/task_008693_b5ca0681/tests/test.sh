#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import uuid

CONFIG_PATH = "/home/user/config.json"
PROVISION_SCRIPT = "/home/user/provision.py"
BASHRC_PATH = "/home/user/.bashrc"
SOURCE_LINE = "source /home/user/workspace/env.sh"

EXPECTED_CONFIG = {
    "volumes": [
        {
            "name": "raw_data",
            "source": "/home/user/storage/raw",
            "target": "/home/user/workspace/mnt/raw"
        },
        {
            "name": "processed_data",
            "source": "/home/user/storage/processed",
            "target": "/home/user/workspace/mnt/processed"
        }
    ],
    "env_vars": {
        "DATA_PIPELINE_ENV": "production",
        "WORKSPACE_ROOT": "/home/user/workspace"
    }
}


def run_provision():
    return subprocess.run(
        ["python3", PROVISION_SCRIPT], capture_output=True, text=True
    )


def nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_config_exists_and_has_required_content():
    assert os.path.isfile(CONFIG_PATH), f"Configuration file missing: {CONFIG_PATH}"
    with open(CONFIG_PATH, "r") as f:
        config = json.load(f)
    assert config == EXPECTED_CONFIG, "config.json does not contain the required configuration."


def test_directories_exist():
    """Verify that all source and target directories have been created."""
    expected_dirs = [
        "/home/user/storage/raw",
        "/home/user/storage/processed",
        "/home/user/workspace/mnt/raw",
        "/home/user/workspace/mnt/processed"
    ]
    for d in expected_dirs:
        assert os.path.isdir(d), f"Directory missing: {d}"


def test_fstab_conf_contents():
    """Verify the contents of the simulated fstab.conf file."""
    fstab_path = "/home/user/workspace/fstab.conf"
    assert os.path.isfile(fstab_path), f"File missing: {fstab_path}"

    lines = nonempty_lines(fstab_path)
    expected_lines = [
        "/home/user/storage/processed /home/user/workspace/mnt/processed none bind 0 0",
        "/home/user/storage/raw /home/user/workspace/mnt/raw none bind 0 0"
    ]
    assert lines == expected_lines, f"Contents of {fstab_path} do not match expected output."


def test_env_sh_contents():
    """Verify the contents of the env.sh file."""
    env_path = "/home/user/workspace/env.sh"
    assert os.path.isfile(env_path), f"File missing: {env_path}"

    lines = nonempty_lines(env_path)
    expected_lines = [
        'export DATA_PIPELINE_ENV="production"',
        'export WORKSPACE_ROOT="/home/user/workspace"'
    ]
    assert lines == expected_lines, f"Contents of {env_path} do not match expected output."


def test_bashrc_and_idempotency():
    """Verify that .bashrc contains exactly one source line, even after re-running."""
    assert os.path.isfile(BASHRC_PATH), f"File missing: {BASHRC_PATH}"

    with open(BASHRC_PATH, "r") as f:
        content = f.read()
    count = content.count(SOURCE_LINE)
    assert count == 1, f"Expected exactly 1 instance of '{SOURCE_LINE}' in {BASHRC_PATH}, found {count}."

    assert os.path.isfile(PROVISION_SCRIPT), f"Provision script missing: {PROVISION_SCRIPT}"
    result = run_provision()
    assert result.returncode == 0, f"Running {PROVISION_SCRIPT} a second time failed:\n{result.stderr}"

    with open(BASHRC_PATH, "r") as f:
        content = f.read()
    count = content.count(SOURCE_LINE)
    assert count == 1, f"Idempotency failed: Expected exactly 1 instance of '{SOURCE_LINE}' in {BASHRC_PATH} after re-running, found {count}."


def test_provision_uses_current_configuration():
    """Change the configuration and verify outputs are derived from it rather than hardcoded."""
    token = uuid.uuid4().hex
    base = f"/home/user/config_probe_{token}"
    probe_config = {
        "volumes": [
            {
                "name": "middle_volume",
                "source": f"{base}/sources/middle",
                "target": f"{base}/targets/middle"
            },
            {
                "name": "z_last_volume",
                "source": f"{base}/sources/last",
                "target": f"{base}/targets/last"
            },
            {
                "name": "a_first_volume",
                "source": f"{base}/sources/first",
                "target": f"{base}/targets/first"
            }
        ],
        "env_vars": {
            f"ZETA_{token.upper()}": f"zeta-{token}",
            f"ALPHA_{token.upper()}": f"alpha-{token}",
            f"MIDDLE_{token.upper()}": f"middle-{token}"
        }
    }

    with open(CONFIG_PATH, "rb") as f:
        original_config_bytes = f.read()

    try:
        with open(CONFIG_PATH, "w") as f:
            json.dump(probe_config, f)

        for output in ["/home/user/workspace/fstab.conf", "/home/user/workspace/env.sh"]:
            if os.path.exists(output):
                os.remove(output)

        result = run_provision()
        assert result.returncode == 0, f"Provisioning from a changed configuration failed:\n{result.stderr}"

        for volume in probe_config["volumes"]:
            assert os.path.isdir(volume["source"]), f"Configured source directory missing: {volume['source']}"
            assert os.path.isdir(volume["target"]), f"Configured target directory missing: {volume['target']}"

        expected_fstab = [
            f"{volume['source']} {volume['target']} none bind 0 0"
            for volume in sorted(probe_config["volumes"], key=lambda volume: volume["name"])
        ]
        assert nonempty_lines("/home/user/workspace/fstab.conf") == expected_fstab

        expected_env = [
            f'export {key}="{probe_config["env_vars"][key]}"'
            for key in sorted(probe_config["env_vars"])
        ]
        assert nonempty_lines("/home/user/workspace/env.sh") == expected_env

        with open(BASHRC_PATH, "r") as f:
            assert f.read().count(SOURCE_LINE) == 1
    finally:
        with open(CONFIG_PATH, "wb") as f:
            f.write(original_config_bytes)
        restore_result = run_provision()
        assert restore_result.returncode == 0, f"Failed to restore provisioned state:\n{restore_result.stderr}"

    expected_fstab = [
        "/home/user/storage/processed /home/user/workspace/mnt/processed none bind 0 0",
        "/home/user/storage/raw /home/user/workspace/mnt/raw none bind 0 0"
    ]
    expected_env = [
        'export DATA_PIPELINE_ENV="production"',
        'export WORKSPACE_ROOT="/home/user/workspace"'
    ]
    assert nonempty_lines("/home/user/workspace/fstab.conf") == expected_fstab
    assert nonempty_lines("/home/user/workspace/env.sh") == expected_env
    with open(BASHRC_PATH, "r") as f:
        assert f.read().count(SOURCE_LINE) == 1
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
