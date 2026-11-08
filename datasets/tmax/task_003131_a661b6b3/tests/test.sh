#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import time


def test_operator_sh_exists_and_executable():
    path = '/home/user/operator.sh'
    assert os.path.exists(path), f"{path} does not exist"
    assert os.access(path, os.X_OK), f"{path} is not executable"


def test_operator_running():
    try:
        output = subprocess.check_output(['pgrep', '-f', 'operator.sh']).decode().strip()
        assert output, "operator.sh is not running in the background"
    except subprocess.CalledProcessError:
        assert False, "operator.sh is not running in the background"


def read_status(status_file):
    with open(status_file, 'r') as f:
        lines = f.read().splitlines()
    assert len(lines) == 2, f"{status_file} should have exactly two lines"
    assert lines[0].isdigit(), f"First line of {status_file} is not a valid PID"
    assert lines[1].isdigit(), f"Second line of {status_file} is not a valid Unix timestamp"
    return lines, int(lines[0]), int(lines[1])


def assert_live_link(live_path, source_path):
    assert os.path.islink(live_path), f"{live_path} should be a symlink for active state"
    target = os.readlink(live_path)
    abs_target = target if os.path.isabs(target) else os.path.abspath(os.path.join(os.path.dirname(live_path), target))
    assert abs_target == source_path, f"{live_path} should point to {source_path}"


def test_operator_behavior():
    src_dir = '/home/user/k8s/src'
    live_dir = '/home/user/k8s/live'
    archive_dir = '/home/user/k8s/archive'

    assert os.path.isdir(src_dir), f"{src_dir} does not exist. The script might not have created it."
    assert os.path.isdir(live_dir), f"{live_dir} does not exist. The script might not have created it."
    assert os.path.isdir(archive_dir), f"{archive_dir} does not exist. The script might not have created it."

    app1_src = os.path.join(src_dir, 'app1.yaml')
    app2_src = os.path.join(src_dir, 'app2.yaml')

    with open(app1_src, 'w') as f:
        f.write("# DEPLOY_STATE: active\nkind: Deployment\n")

    with open(app2_src, 'w') as f:
        f.write("# DEPLOY_STATE: pending\nkind: Service\n")

    token = secrets.token_hex(10)
    active_names = [f'audit_{token}_active_{i}.yaml' for i in range(4)]
    pending_names = [f'audit_{token}_pending_{i}.yaml' for i in range(2)]
    archived_names = [f'audit_{token}_archived_{i}.yaml' for i in range(2)]
    ignored_names = [f'audit_{token}_ignored.yaml', f'audit_{token}_empty.yaml']

    for name in active_names:
        with open(os.path.join(src_dir, name), 'w') as f:
            f.write('# DEPLOY_STATE: active\nkind: ConfigMap\n')
    for name in pending_names:
        with open(os.path.join(src_dir, name), 'w') as f:
            f.write('# DEPLOY_STATE: pending\nkind: Service\n')
    for name in archived_names:
        with open(os.path.join(src_dir, name), 'w') as f:
            f.write('# DEPLOY_STATE: archived\nkind: Secret\n')
    with open(os.path.join(src_dir, ignored_names[0]), 'w') as f:
        f.write(' # DEPLOY_STATE: active\nkind: Pod\n')
    open(os.path.join(src_dir, ignored_names[1]), 'w').close()

    time.sleep(3)

    app1_live = os.path.join(live_dir, 'app1.yaml')
    app2_live = os.path.join(live_dir, 'app2.yaml')

    assert os.path.islink(app1_live), f"{app1_live} should be a symlink for active state"
    target = os.readlink(app1_live)
    abs_target = target if os.path.isabs(target) else os.path.abspath(os.path.join(live_dir, target))
    assert abs_target == app1_src, f"{app1_live} should point to {app1_src}"
    assert not os.path.exists(app2_live), f"{app2_live} should not exist for pending state"

    for name in active_names:
        assert_live_link(os.path.join(live_dir, name), os.path.join(src_dir, name))
    for name in pending_names + ignored_names:
        assert os.path.exists(os.path.join(src_dir, name)), f"{name} should remain in src"
        assert not os.path.lexists(os.path.join(live_dir, name)), f"{name} should be ignored, not linked"
    for name in archived_names:
        assert not os.path.exists(os.path.join(src_dir, name)), f"{name} should have been moved from src"
        archived_path = os.path.join(archive_dir, name)
        assert os.path.isfile(archived_path) and not os.path.islink(archived_path), f"{name} should be a regular archived file"
        assert not os.path.lexists(os.path.join(live_dir, name)), f"{name} should not remain in live"

    status_file = '/home/user/operator.status'
    assert os.path.exists(status_file), f"{status_file} does not exist"
    lines, status_pid, initial_timestamp = read_status(status_file)

    assert os.path.exists(f'/proc/{status_pid}'), f"Status PID {status_pid} is not running"
    with open(f'/proc/{status_pid}/stat', 'r') as f:
        assert f.read().split()[2] != 'Z', f"Status PID {status_pid} is a zombie"
    with open(f'/proc/{status_pid}/cmdline', 'rb') as f:
        cmdline = f.read().replace(b'\0', b' ').decode(errors='replace')
    assert '/home/user/operator.sh' in cmdline or 'operator.sh' in cmdline, \
        f"Status PID {status_pid} is not the running operator script: {cmdline!r}"
    operator_pids = subprocess.check_output(['pgrep', '-f', 'operator.sh']).decode().split()
    assert str(status_pid) in operator_pids, "First status line is not a running operator.sh PID"
    assert abs(int(time.time()) - initial_timestamp) <= 5, \
        f"Status timestamp {initial_timestamp} is not the current Unix epoch time"

    with open(app1_src, 'w') as f:
        f.write("# DEPLOY_STATE: archived\nkind: Deployment\n")

    for name in active_names:
        with open(os.path.join(src_dir, name), 'w') as f:
            f.write('# DEPLOY_STATE: archived\nkind: ConfigMap\n')
    for name in pending_names + ignored_names:
        with open(os.path.join(src_dir, name), 'w') as f:
            f.write('# DEPLOY_STATE: active\nkind: Service\n')

    time.sleep(3)

    assert not os.path.exists(app1_live), f"{app1_live} symlink should have been removed after state changed to archived"
    assert not os.path.lexists(app1_live), f"{app1_live} should have been removed, not left dangling"

    app1_archive = os.path.join(archive_dir, 'app1.yaml')
    assert os.path.exists(app1_archive), f"{app1_archive} should exist after archiving"
    assert os.path.isfile(app1_archive) and not os.path.islink(app1_archive), f"{app1_archive} should be a regular file, not a symlink"
    assert not os.path.exists(app1_src), f"{app1_src} should have been moved from src directory"

    for name in active_names:
        assert not os.path.lexists(os.path.join(live_dir, name)), f"{name} live link should be removed after archiving"
        assert not os.path.exists(os.path.join(src_dir, name)), f"{name} should be moved from src"
        archived_path = os.path.join(archive_dir, name)
        assert os.path.isfile(archived_path) and not os.path.islink(archived_path), f"{name} should be archived as a regular file"
    for name in pending_names + ignored_names:
        assert_live_link(os.path.join(live_dir, name), os.path.join(src_dir, name))

    lines2, status_pid2, new_timestamp = read_status(status_file)
    assert new_timestamp > initial_timestamp, f"Timestamp in {status_file} did not increase, the loop might not be running"
    assert abs(int(time.time()) - new_timestamp) <= 5, \
        f"Updated status timestamp {new_timestamp} is not the current Unix epoch time"
    assert status_pid2 == status_pid, "Status PID changed instead of identifying the continuously running script"
    assert os.path.exists(f'/proc/{status_pid2}'), f"Updated status PID {status_pid2} is not running"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
