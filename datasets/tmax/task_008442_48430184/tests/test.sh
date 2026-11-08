#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import textwrap
import uuid

import pytest

HOME = "/home/user"
SCRIPT = f"{HOME}/deploy_automation.py"


def test_deploy_script_exists():
    assert os.path.isfile(SCRIPT), f"Required automation script {SCRIPT} is missing."
    assert not os.path.islink(SCRIPT), f"{SCRIPT} must be a regular Python script, not a symlink."
    result = subprocess.run(["python3", "-m", "py_compile", SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"{SCRIPT} is not valid Python:\n{result.stderr}"


def test_deploy_auth_log():
    log_path = "/home/user/deploy_auth.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_users = ["xena", "yusuf", "zane"]
    assert lines == expected_users, f"Expected users {expected_users} in {log_path}, but got {lines}."


def test_deployment_log():
    log_path = "/home/user/deployment.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Node 1 deployed successfully",
        "Node 2 deployed successfully",
        "Node 3 deployed successfully"
    ]
    assert lines == expected_lines, f"Expected lines {expected_lines} in {log_path}, but got {lines}."


def test_node_deployments():
    payload_path = "/home/user/update_payload.py"
    assert os.path.isfile(payload_path), f"Original payload {payload_path} is missing."

    with open(payload_path, "r") as f:
        expected_payload = f.read()

    for i in range(1, 4):
        node_dir = f"/home/user/nodes/node{i}"
        assert os.path.isdir(node_dir), f"Directory {node_dir} is missing."

        app_path = os.path.join(node_dir, "app.py")
        assert os.path.isfile(app_path), f"File {app_path} is missing."
        with open(app_path, "r") as f:
            app_content = f.read()
        assert app_content == expected_payload, f"Content of {app_path} does not match {payload_path}."

        backup_path = os.path.join(node_dir, "disk_backup.qcow2")
        assert os.path.isfile(backup_path), f"File {backup_path} is missing."

        result = subprocess.run(["qemu-img", "info", backup_path], capture_output=True, text=True)
        assert result.returncode == 0, f"qemu-img info failed on {backup_path}. Is qemu-utils installed?"

        output = result.stdout
        assert "file format: qcow2" in output, f"{backup_path} is not a valid qcow2 file."
        assert "backing file: disk.qcow2" in output or "backing file: /home/user/nodes/node" in output, \
            f"{backup_path} is not backed by disk.qcow2. qemu-img info output:\n{output}"


@pytest.fixture(scope="module")
def behavioral_environment():
    token = uuid.uuid4().hex
    saved_home = f"/home/user.verifier-original-{token}"
    qemu_path = os.path.realpath(shutil.which("qemu-img"))
    saved_qemu = f"{qemu_path}.verifier-real-{token}"

    os.rename(HOME, saved_home)
    shutil.copytree(saved_home, HOME, symlinks=True)
    os.rename(qemu_path, saved_qemu)

    wrapper = textwrap.dedent(f"""\
        #!/bin/sh
        node=""
        case "$PWD" in
          */node1) node=1 ;;
          */node2) node=2 ;;
          */node3) node=3 ;;
        esac
        if [ -z "$node" ]; then
          for arg in "$@"; do
            case "$arg" in
              */node1/*) node=1 ;;
              */node2/*) node=2 ;;
              */node3/*) node=3 ;;
            esac
          done
        fi
        if [ -n "$node" ]; then
          actual=$(cat /home/user/deploy_auth.log 2>/dev/null || true)
          if [ "$actual" != "$EXPECTED_AUTH" ]; then
            exit 91
          fi
          echo "BACKUP_$node" >> /home/user/workflow_events.log
        fi
        exec "{saved_qemu}" "$@"
    """)
    with open(qemu_path, "w") as f:
        f.write(wrapper)
    os.chmod(qemu_path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                        stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

    try:
        yield saved_qemu
    finally:
        if os.path.lexists(qemu_path):
            os.remove(qemu_path)
        if os.path.exists(saved_qemu):
            os.rename(saved_qemu, qemu_path)
        if os.path.exists(HOME):
            shutil.rmtree(HOME)
        if os.path.exists(saved_home):
            os.rename(saved_home, HOME)


def clean_outputs():
    for path in [f"{HOME}/deploy_auth.log", f"{HOME}/deployment.log", f"{HOME}/workflow_events.log"]:
        if os.path.lexists(path):
            os.remove(path)
    for i in range(1, 4):
        for name in ["app.py", "disk_backup.qcow2"]:
            path = f"{HOME}/nodes/node{i}/{name}"
            if os.path.lexists(path):
                os.remove(path)


def write_payload(fail_node=None):
    payload = textwrap.dedent(f"""\
        import os
        import sys

        node = int(os.path.basename(os.getcwd()).replace("node", ""))
        home = "/home/user"
        if not os.path.isfile("disk_backup.qcow2"):
            sys.exit(40)
        for previous in range(1, node):
            if not os.path.isfile(f"{{home}}/nodes/node{{previous}}/app.py"):
                sys.exit(41)
        for future in range(node + 1, 4):
            if os.path.exists(f"{{home}}/nodes/node{{future}}/disk_backup.qcow2"):
                sys.exit(42)
            if os.path.exists(f"{{home}}/nodes/node{{future}}/app.py"):
                sys.exit(43)
        with open(f"{{home}}/workflow_events.log", "a") as events:
            events.write(f"VERIFY_{{node}}\\n")
        if node == {repr(fail_node)}:
            sys.exit(17)
        sys.exit(0)
    """)
    with open(f"{HOME}/update_payload.py", "w") as f:
        f.write(payload)
    return payload


def run_script(expected_auth):
    env = os.environ.copy()
    env["EXPECTED_AUTH"] = expected_auth
    return subprocess.run(["python3", SCRIPT], cwd=HOME, env=env, capture_output=True, text=True)


def read_nonempty_lines(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


def assert_dynamic_backups(saved_qemu):
    for i in range(1, 4):
        backup = f"{HOME}/nodes/node{i}/disk_backup.qcow2"
        result = subprocess.run([saved_qemu, "info", backup], capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        assert "file format: qcow2" in result.stdout
        assert "backing file: disk.qcow2" in result.stdout or f"/nodes/node{i}/disk.qcow2" in result.stdout


def test_script_executes_dynamic_workflow_in_strict_order(behavioral_environment):
    clean_outputs()
    with open(f"{HOME}/admin_groups.txt", "w") as f:
        f.write("operators:someone\ndeployers:zoe,amy,mike\nadmins:root\n")
    payload = write_payload()

    result = run_script("amy\nmike\nzoe")
    assert result.returncode == 0, f"Automation failed on a valid deployment:\n{result.stdout}\n{result.stderr}"
    assert read_nonempty_lines(f"{HOME}/deploy_auth.log") == ["amy", "mike", "zoe"]
    assert read_nonempty_lines(f"{HOME}/workflow_events.log") == [
        "BACKUP_1", "VERIFY_1", "BACKUP_2", "VERIFY_2", "BACKUP_3", "VERIFY_3"
    ]
    assert read_nonempty_lines(f"{HOME}/deployment.log") == [
        "Node 1 deployed successfully", "Node 2 deployed successfully", "Node 3 deployed successfully"
    ]
    for i in range(1, 4):
        with open(f"{HOME}/nodes/node{i}/app.py") as f:
            assert f.read() == payload
    assert_dynamic_backups(behavioral_environment)


def test_script_aborts_remaining_nodes_after_verification_failure(behavioral_environment):
    clean_outputs()
    with open(f"{HOME}/admin_groups.txt", "w") as f:
        f.write("deployers:delta,bravo\n")
    write_payload(fail_node=2)

    result = run_script("bravo\ndelta")
    assert result.returncode != 0, "Automation must return an error when a deployed application fails."
    assert read_nonempty_lines(f"{HOME}/workflow_events.log") == [
        "BACKUP_1", "VERIFY_1", "BACKUP_2", "VERIFY_2"
    ]
    assert read_nonempty_lines(f"{HOME}/deployment.log") == ["Node 1 deployed successfully"]
    assert not os.path.exists(f"{HOME}/nodes/node3/disk_backup.qcow2")
    assert not os.path.exists(f"{HOME}/nodes/node3/app.py")


@pytest.mark.parametrize("groups", [
    "wheel:alice,bob\nadmins:root\n",
    "wheel:alice,bob\ndeployers:\nadmins:root\n",
])
def test_script_exits_before_deployment_without_authorized_users(behavioral_environment, groups):
    clean_outputs()
    with open(f"{HOME}/admin_groups.txt", "w") as f:
        f.write(groups)
    write_payload()

    result = run_script("")
    assert result.returncode != 0, "Automation must fail when the deployers group is missing or empty."
    assert read_nonempty_lines(f"{HOME}/workflow_events.log") == []
    assert read_nonempty_lines(f"{HOME}/deployment.log") == []
    for i in range(1, 4):
        assert not os.path.exists(f"{HOME}/nodes/node{i}/disk_backup.qcow2")
        assert not os.path.exists(f"{HOME}/nodes/node{i}/app.py")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
