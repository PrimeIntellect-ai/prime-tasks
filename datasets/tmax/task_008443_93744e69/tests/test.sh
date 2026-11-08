#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import shutil
import subprocess
import tempfile
import uuid

DESIRED_STATE_FILE = "/home/user/desired_state.json"
OPERATOR_SCRIPT = "/home/user/manifest_operator.py"
LOGROTATE_CONF = "/home/user/generated_logrotate.conf"


def get_desired_state():
    assert os.path.isfile(DESIRED_STATE_FILE), f"Missing {DESIRED_STATE_FILE}"
    with open(DESIRED_STATE_FILE, "r") as f:
        return json.load(f)


def test_operator_script_exists():
    """Verify that the manifest operator script exists."""
    assert os.path.isfile(OPERATOR_SCRIPT), f"The script {OPERATOR_SCRIPT} does not exist."


def test_log_directories_exist():
    """Verify that the log directories specified in the desired state exist."""
    state = get_desired_state()
    containers = state.get("containers", [])
    assert containers, "No containers found in desired state."

    for container in containers:
        log_dir = container.get("log_dir")
        assert log_dir, f"Container {container.get('name')} is missing a log_dir."
        assert os.path.isdir(log_dir), f"The expected log directory {log_dir} does not exist."


def test_logrotate_conf_content():
    """Verify that the generated logrotate configuration matches the expected output."""
    assert os.path.isfile(LOGROTATE_CONF), f"The file {LOGROTATE_CONF} does not exist."

    state = get_desired_state()
    containers = state.get("containers", [])

    expected_blocks = []
    for container in containers:
        log_dir = container.get("log_dir")
        block = f"{log_dir}/*.log {{\n    daily\n    rotate 7\n    compress\n    missingok\n    notifempty\n}}"
        expected_blocks.append(block)

    expected_content = "\n\n".join(expected_blocks)

    with open(LOGROTATE_CONF, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, f"The content of {LOGROTATE_CONF} does not match the expected format."


def test_operator_executes_from_random_directory_and_is_idempotent():
    """Exercise the submitted operator with verifier-derived state as an unprivileged user."""
    token = uuid.uuid4().hex
    log_dirs = [
        f"/home/user/.operator-test-{token}-one/nested/logs",
        f"/home/user/.operator-test-{token}-two/nested/logs",
    ]
    test_state = {
        "containers": [
            {"name": "dynamic-one", "log_dir": log_dirs[0]},
            {"name": "dynamic-two", "log_dir": log_dirs[1]},
        ]
    }
    expected_blocks = [
        f"{path}/*.log {{\n    daily\n    rotate 7\n    compress\n    missingok\n    notifempty\n}}"
        for path in log_dirs
    ]
    expected_content = "\n\n".join(expected_blocks)

    with open(DESIRED_STATE_FILE, "rb") as f:
        original_state = f.read()
    original_conf_exists = os.path.isfile(LOGROTATE_CONF)
    original_conf = None
    if original_conf_exists:
        with open(LOGROTATE_CONF, "rb") as f:
            original_conf = f.read()

    random_cwd = tempfile.mkdtemp(prefix="operator-cwd-", dir="/var/tmp")
    os.chmod(random_cwd, 0o755)
    user = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    try:
        with open(DESIRED_STATE_FILE, "w") as f:
            json.dump(test_state, f)
        os.chmod(DESIRED_STATE_FILE, 0o666)

        if os.path.exists(LOGROTATE_CONF):
            os.remove(LOGROTATE_CONF)
        for path in log_dirs:
            shutil.rmtree(path.split("/nested/logs")[0], ignore_errors=True)

        command = ["python3", OPERATOR_SCRIPT]
        subprocess.run(
            command,
            cwd=random_cwd,
            check=True,
            timeout=20,
            preexec_fn=demote,
            env={"HOME": "/home/user", "PATH": os.environ.get("PATH", "")},
        )

        for path in log_dirs:
            assert os.path.isdir(path), f"Operator did not create dynamic log directory {path}"
        assert os.path.isfile(LOGROTATE_CONF), "Operator did not generate the configuration"
        with open(LOGROTATE_CONF, "rb") as f:
            first_output = f.read()
        assert first_output.decode().strip() == expected_content

        subprocess.run(
            command,
            cwd=random_cwd,
            check=True,
            timeout=20,
            preexec_fn=demote,
            env={"HOME": "/home/user", "PATH": os.environ.get("PATH", "")},
        )
        with open(LOGROTATE_CONF, "rb") as f:
            second_output = f.read()
        assert second_output == first_output, "Repeated execution changed the generated file"
        assert second_output.decode().strip() == expected_content
    finally:
        with open(DESIRED_STATE_FILE, "wb") as f:
            f.write(original_state)
        os.chmod(DESIRED_STATE_FILE, 0o777)

        if original_conf_exists:
            with open(LOGROTATE_CONF, "wb") as f:
                f.write(original_conf)
        elif os.path.exists(LOGROTATE_CONF):
            os.remove(LOGROTATE_CONF)

        for path in log_dirs:
            shutil.rmtree(path.split("/nested/logs")[0], ignore_errors=True)
        shutil.rmtree(random_cwd, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
