#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import os
import secrets
import shutil
import stat
import subprocess

SCRIPT = '/home/user/deploy_vm.py'
DEPLOYMENTS = '/home/user/deployments'
BASE_IMAGE = '/home/user/images/base.img'


def test_script_exists():
    assert os.path.exists(SCRIPT), "/home/user/deploy_vm.py script is missing."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a regular file."


def test_deployment_directories_and_symlinks():
    v42_dir = '/home/user/deployments/v42'
    assert os.path.isdir(v42_dir), f"Deployment directory {v42_dir} is missing."

    disk_img = os.path.join(v42_dir, 'disk.img')
    assert os.path.islink(disk_img), f"{disk_img} is not a symlink."
    assert os.readlink(disk_img) == '/home/user/images/base.img', f"{disk_img} does not point to /home/user/images/base.img."

    current_link = '/home/user/deployments/current'
    assert os.path.islink(current_link), f"{current_link} is not a symlink."
    assert os.readlink(current_link) == '/home/user/deployments/v42', f"{current_link} does not point to /home/user/deployments/v42."


def test_run_sh_script():
    run_sh = '/home/user/deployments/v42/run.sh'
    assert os.path.isfile(run_sh), f"{run_sh} is missing."

    st = os.stat(run_sh)
    assert bool(st.st_mode & stat.S_IXUSR), f"{run_sh} is not executable by the user."

    with open(run_sh, 'r') as f:
        content = f.read().strip()

    expected_content = "#!/bin/bash\nqemu-system-x86_64 -m 1024 -drive file=disk.img,format=qcow2 -vnc :5"
    assert expected_content in content, f"{run_sh} does not contain the expected QEMU command."
    assert content == expected_content, f"{run_sh} contains content other than the required script."


def test_log_rotation():
    log_file = '/home/user/deployments/deploy.log'
    log_1 = log_file + '.1'
    log_2 = log_file + '.2'

    assert os.path.isfile(log_file), f"Log file {log_file} is missing."
    assert os.path.isfile(log_1), f"Rotated log file {log_1} is missing. Log rotation may have failed."
    assert os.path.isfile(log_2), f"Rotated log file {log_2} is missing. Log rotation may have failed."


def _constant(node, constants):
    if isinstance(node, ast.Name) and node.id in constants:
        return constants[node.id]
    try:
        return ast.literal_eval(node)
    except Exception:
        return None


def test_required_python_apis_are_used():
    with open(SCRIPT, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    imports_argparse = any(
        (isinstance(node, ast.Import) and any(alias.name == 'argparse' for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == 'argparse')
        for node in ast.walk(tree)
    )
    assert imports_argparse, "deploy_vm.py must import and use argparse."

    def call_name(call):
        func = call.func
        if isinstance(func, ast.Name):
            return func.id
        if isinstance(func, ast.Attribute):
            parts = []
            while isinstance(func, ast.Attribute):
                parts.append(func.attr)
                func = func.value
            if isinstance(func, ast.Name):
                parts.append(func.id)
            return '.'.join(reversed(parts))
        return ''

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    assert any(call_name(call).split('.')[-1] == 'ArgumentParser' for call in calls), \
        "deploy_vm.py must construct an argparse.ArgumentParser."

    constants = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            value = _constant(node.value, constants)
            if value is not None:
                constants[node.targets[0].id] = value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.value is not None:
            value = _constant(node.value, constants)
            if value is not None:
                constants[node.target.id] = value

    rotating_calls = [call for call in calls if call_name(call).split('.')[-1] == 'RotatingFileHandler']
    assert rotating_calls, "deploy_vm.py must construct a RotatingFileHandler."

    correctly_configured = False
    for call in rotating_calls:
        keywords = {kw.arg: _constant(kw.value, constants) for kw in call.keywords if kw.arg}
        max_bytes = keywords.get('maxBytes')
        backup_count = keywords.get('backupCount')
        if max_bytes is None and len(call.args) >= 3:
            max_bytes = _constant(call.args[2], constants)
        if backup_count is None and len(call.args) >= 4:
            backup_count = _constant(call.args[3], constants)
        if max_bytes == 500 and backup_count == 2:
            correctly_configured = True
            break
    assert correctly_configured, "RotatingFileHandler must use maxBytes=500 and backupCount=2."


def test_execute_script_with_unpredictable_arguments():
    version = 100000 + secrets.randbelow(800000)
    vnc_port = 10 + secrets.randbelow(80)
    version_dir = os.path.join(DEPLOYMENTS, f'v{version}')
    current_link = os.path.join(DEPLOYMENTS, 'current')

    if os.path.lexists(version_dir):
        if os.path.isdir(version_dir) and not os.path.islink(version_dir):
            shutil.rmtree(version_dir)
        else:
            os.unlink(version_dir)

    if os.path.lexists(current_link):
        if os.path.isdir(current_link) and not os.path.islink(current_link):
            shutil.rmtree(current_link)
        else:
            os.unlink(current_link)
    os.symlink('/tmp/stale-deployment-target', current_link)

    for path in glob.glob(os.path.join(DEPLOYMENTS, 'deploy.log*')):
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)

    result = subprocess.run(
        ['python3', SCRIPT, '--version', str(version), '--vnc-port', str(vnc_port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"deploy_vm.py failed: {result.stderr}"

    assert os.path.isdir(version_dir), f"Dynamic deployment directory {version_dir} was not created."
    disk_img = os.path.join(version_dir, 'disk.img')
    assert os.path.islink(disk_img), f"{disk_img} is not a symlink."
    assert os.readlink(disk_img) == BASE_IMAGE, f"{disk_img} has the wrong target."
    assert os.path.islink(current_link), f"{current_link} is not a symlink after execution."
    assert os.readlink(current_link) == version_dir, f"{current_link} was not updated to the requested version."

    run_sh = os.path.join(version_dir, 'run.sh')
    assert os.path.isfile(run_sh), f"{run_sh} was not created."
    assert os.stat(run_sh).st_mode & stat.S_IXUSR, f"{run_sh} is not executable by its owner."
    with open(run_sh, 'r', encoding='utf-8') as f:
        run_content = f.read().rstrip('\n')
    expected_run = (
        "#!/bin/bash\n"
        f"qemu-system-x86_64 -m 1024 -drive file=disk.img,format=qcow2 -vnc :{vnc_port}"
    )
    assert run_content == expected_run, f"{run_sh} does not have exactly the required content."

    log_file = os.path.join(DEPLOYMENTS, 'deploy.log')
    log_paths = [log_file + '.2', log_file + '.1', log_file]
    for path in log_paths:
        assert os.path.isfile(path), f"Expected rotated log file {path} is missing."
        assert os.path.getsize(path) <= 500, f"{path} exceeds the required 500-byte rotation threshold."
    assert not os.path.exists(log_file + '.3'), "More than two backup log files were retained."

    actual_lines = []
    for path in log_paths:
        with open(path, 'r', encoding='utf-8') as f:
            actual_lines.extend(f.read().splitlines())

    expected_lines = [f"INFO - Deployed version {version} on VNC port {vnc_port}"]
    expected_lines.extend(
        f"INFO - Padding log line {iteration} for rotation testing"
        for iteration in range(1, 21)
    )
    assert actual_lines == expected_lines, \
        "The rotated logs do not contain exactly the required formatted messages in order."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
