#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import shutil
import subprocess

SCRIPT = '/home/user/run_mtu_check.py'
TARGET_DIR = '/home/user/app_data/network_logs'
SYMLINK_PATH = '/home/user/current_logs'
JSON_PATH = '/home/user/current_logs/mtu.json'


def run_script():
    cwd = '/tmp/mtu_verifier_cwd'
    os.makedirs(cwd, exist_ok=True)
    try:
        subprocess.run(
            ['python3', SCRIPT],
            cwd=cwd,
            check=True,
            capture_output=True,
            text=True
        )
    except subprocess.CalledProcessError as e:
        assert False, f'Script execution failed with error: {e.stderr}'


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)
    elif os.path.lexists(path):
        os.unlink(path)


def expected_mtu():
    try:
        output = subprocess.check_output(['ip', '-j', 'link', 'show']).decode('utf-8')
        data = json.loads(output)
        return {iface['ifname']: iface['mtu'] for iface in data}
    except Exception as e:
        assert False, f'Failed to retrieve ground truth MTU data: {e}'


def assert_correct_state():
    assert os.path.isdir(TARGET_DIR), f'Directory {TARGET_DIR} does not exist.'
    assert os.path.islink(SYMLINK_PATH), f'{SYMLINK_PATH} is not a symlink.'
    assert os.readlink(SYMLINK_PATH) == TARGET_DIR, (
        f'Symlink {SYMLINK_PATH} does not point to {TARGET_DIR}.'
    )
    assert os.path.isfile(JSON_PATH), f'File {JSON_PATH} does not exist.'
    with open(JSON_PATH, 'r') as f:
        try:
            agent_mtu = json.load(f)
        except json.JSONDecodeError:
            assert False, f'File {JSON_PATH} does not contain valid JSON.'
    expected = expected_mtu()
    assert agent_mtu == expected, f'MTU data mismatch. Expected {expected}, but got {agent_mtu}.'


def test_script_exists():
    assert os.path.isfile(SCRIPT), 'The script /home/user/run_mtu_check.py does not exist.'


def test_repairs_missing_and_incorrect_states_and_is_idempotent():
    # Missing directory and link: the script must create all required parents/state.
    remove_path(SYMLINK_PATH)
    remove_path('/home/user/app_data')
    run_script()
    assert_correct_state()

    # Broken symlink: lexists is true while its target does not exist.
    remove_path(SYMLINK_PATH)
    broken_target = '/tmp/mtu_verifier_missing_target'
    remove_path(broken_target)
    os.symlink(broken_target, SYMLINK_PATH)
    run_script()
    assert_correct_state()

    # Wrong symlink, including one whose target exists.
    remove_path(SYMLINK_PATH)
    wrong_target = '/tmp/mtu_verifier_wrong_target'
    remove_path(wrong_target)
    os.makedirs(wrong_target)
    wrong_json = os.path.join(wrong_target, 'mtu.json')
    with open(wrong_json, 'w') as f:
        f.write('wrong-target-marker')
    os.symlink(wrong_target, SYMLINK_PATH)
    run_script()
    assert_correct_state()
    with open(wrong_json, 'r') as f:
        assert f.read() == 'wrong-target-marker', 'Diagnostic output was written through the wrong symlink.'

    # A regular file at the required link path must be replaced.
    remove_path(SYMLINK_PATH)
    with open(SYMLINK_PATH, 'w') as f:
        f.write('blocking regular file')
    run_script()
    assert_correct_state()

    # Re-running from a non-home working directory must overwrite stale output
    # and preserve the already-correct state without errors.
    with open(JSON_PATH, 'w') as f:
        json.dump({'stale-interface': -1}, f)
    run_script()
    assert_correct_state()
    run_script()
    assert_correct_state()


def test_script_execution_and_idempotency():
    # Run the script from /tmp to test path independence
    try:
        subprocess.run(
            ['python3', '/home/user/run_mtu_check.py'],
            cwd='/tmp',
            check=True,
            capture_output=True,
            text=True
        )
    except subprocess.CalledProcessError as e:
        assert False, f'Script execution failed with error: {e.stderr}'


def test_directory_structure():
    target_dir = '/home/user/app_data/network_logs'
    assert os.path.isdir(target_dir), f'Directory {target_dir} does not exist.'


def test_symlink_state():
    symlink_path = '/home/user/current_logs'
    target_dir = '/home/user/app_data/network_logs'

    assert os.path.islink(symlink_path), f'{symlink_path} is not a symlink.'
    assert os.readlink(symlink_path) == target_dir, f'Symlink {symlink_path} does not point to {target_dir}.'


def test_mtu_json_content():
    json_path = '/home/user/current_logs/mtu.json'
    assert os.path.isfile(json_path), f'File {json_path} does not exist.'

    with open(json_path, 'r') as f:
        try:
            agent_mtu = json.load(f)
        except json.JSONDecodeError:
            assert False, f'File {json_path} does not contain valid JSON.'

    # Get ground truth
    try:
        output = subprocess.check_output(['ip', '-j', 'link', 'show']).decode('utf-8')
        data = json.loads(output)
        expected_mtu = {iface['ifname']: iface['mtu'] for iface in data}
    except Exception as e:
        assert False, f'Failed to retrieve ground truth MTU data: {e}'

    assert agent_mtu == expected_mtu, f'MTU data mismatch. Expected {expected_mtu}, but got {agent_mtu}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
