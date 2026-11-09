#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import uuid
import pytest

SCRIPT_PATH = '/home/user/provision.py'
CONFIG_PATH = '/home/user/deployment.json'
GROUP_PATH = '/home/user/mock_group'
LOG_PATH = '/home/user/deploy_success.log'
RUNNER_PATH = '/home/user/deploy_runner.py'
TARGET_GROUP = 'deploy_admins:x:1001:app_runner'
EXPECTED_MSG = 'Deployment Successful: All services started in the correct order.'
TOKEN = uuid.uuid4().hex
MARKER_PATH = f'/tmp/.deploy_runner_called_{uuid.uuid4().hex}'


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def install_clean_initial_state():
    for path in (CONFIG_PATH, GROUP_PATH, LOG_PATH, RUNNER_PATH, MARKER_PATH):
        if os.path.lexists(path):
            remove_path(path)

    initial_config = {
        'services': {
            'cache': {
                'command': "echo 'Starting cache' && touch /home/user/cache.sock",
                'restart_policy': 'on-failure'
            },
            'backend': {
                'command': "cat /home/user/cache.sock && echo 'Backend up'",
                'restart_policy': 'on-failure'
            },
            'frontend': {
                'command': "echo 'Frontend up'",
                'restart_policy': 'none'
            }
        }
    }
    with open(CONFIG_PATH, 'w') as f:
        json.dump(initial_config, f, indent=2)
        f.write('\n')

    runner = f'''import json
import os
import sys

config_path = {CONFIG_PATH!r}
group_path = {GROUP_PATH!r}

if not os.path.exists(group_path):
    print("Error: mock_group file missing.")
    sys.exit(1)

with open(group_path, 'r') as f:
    if {TARGET_GROUP!r} not in f.read():
        print("Error: deploy_admins group missing or malformed.")
        sys.exit(1)

with open(config_path, 'r') as f:
    config = json.load(f)

backend = config['services'].get('backend', {{}})
if 'cache' not in backend.get('depends_on', []):
    print("Error: backend started before cache and crashed.")
    sys.exit(1)

frontend = config['services'].get('frontend', {{}})
if frontend.get('restart_policy') != 'always':
    print("Error: frontend restart policy is incorrect.")
    sys.exit(1)

with open({MARKER_PATH!r}, 'w') as marker:
    marker.write({TOKEN!r})
print({EXPECTED_MSG!r})
print({TOKEN!r})
sys.exit(0)
'''
    with open(RUNNER_PATH, 'w') as f:
        f.write(runner)
    os.chmod(RUNNER_PATH, 0o777)


def setup_module(module):
    install_clean_initial_state()


def test_provision_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist. You must create the provision script."


def test_provisions_from_supplied_initial_state_and_executes_runner():
    result = subprocess.run(['python3', SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {SCRIPT_PATH} from the initial state failed: {result.stderr}"
    assert os.path.isfile(MARKER_PATH), "The deployment runner was not successfully executed."
    with open(MARKER_PATH, 'r') as f:
        assert f.read() == TOKEN, "The deployment runner invocation marker is invalid."
    assert os.path.isfile(LOG_PATH), "The runner's standard output was not redirected to deploy_success.log."
    with open(LOG_PATH, 'r') as f:
        content = f.read()
    assert TOKEN in content, "deploy_success.log does not contain output produced by this runner invocation."


def test_deployment_json_updated():
    path = CONFIG_PATH
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    services = data.get("services", {})

    backend = services.get("backend", {})
    assert "depends_on" in backend, "Backend service is missing the 'depends_on' key."
    assert "cache" in backend["depends_on"], "Backend 'depends_on' list does not contain 'cache'."
    assert backend["depends_on"].count("cache") == 1, "Backend 'depends_on' contains duplicate 'cache' entries."

    frontend = services.get("frontend", {})
    assert frontend.get("restart_policy") == "always", "Frontend 'restart_policy' was not updated to 'always'."


def test_mock_group_content():
    path = GROUP_PATH
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        lines = f.readlines()

    stripped_lines = [line.strip() for line in lines]
    assert TARGET_GROUP in stripped_lines, f"The required group '{TARGET_GROUP}' is missing from {path}."
    assert stripped_lines.count(TARGET_GROUP) == 1, f"The group '{TARGET_GROUP}' appears multiple times in {path}. The script must be idempotent."


def test_deploy_success_log():
    path = LOG_PATH
    assert os.path.isfile(path), f"File {path} does not exist. Did you redirect the runner's output?"

    with open(path, 'r') as f:
        content = f.read()

    assert EXPECTED_MSG in content, f"The success log does not contain the expected message. Found: {content}"


def test_idempotency():
    if os.path.lexists(MARKER_PATH):
        remove_path(MARKER_PATH)
    if os.path.lexists(LOG_PATH):
        remove_path(LOG_PATH)

    result = subprocess.run(['python3', SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {SCRIPT_PATH} a second time failed with error: {result.stderr}"

    assert os.path.isfile(MARKER_PATH), "The deployment runner was not executed on the second run."
    with open(MARKER_PATH, 'r') as f:
        assert f.read() == TOKEN, "The second runner invocation marker is invalid."
    assert os.path.isfile(LOG_PATH), "The second run did not recreate deploy_success.log."
    with open(LOG_PATH, 'r') as f:
        log_content = f.read()
    assert EXPECTED_MSG in log_content and TOKEN in log_content, "The second run did not redirect the runner's output."

    with open(GROUP_PATH, 'r') as f:
        stripped_lines = [line.strip() for line in f.readlines()]
    assert stripped_lines.count(TARGET_GROUP) == 1, "Running the script a second time created duplicate entries in mock_group."

    with open(CONFIG_PATH, 'r') as f:
        data = json.load(f)
    backend_depends = data.get("services", {}).get("backend", {}).get("depends_on", [])
    assert backend_depends.count("cache") == 1, "Running the script a second time created duplicate 'cache' entries in deployment.json."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
