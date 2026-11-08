#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile
import uuid


def run_service(path, value_marker):
    env = os.environ.copy()
    if value_marker is None:
        env.pop("VNC_DISPLAY", None)
        expected_display = ":1"
    else:
        env["VNC_DISPLAY"] = value_marker
        expected_display = value_marker if value_marker else ":1"

    result = subprocess.run([path], env=env, capture_output=True, text=True)
    assert result.returncode == 0, (
        f"{path} returned {result.returncode}. stderr: {result.stderr}"
    )
    expected = f"Starting QEMU on VNC display {expected_display}\n"
    assert result.stdout == expected, f"Expected {expected!r}, got {result.stdout!r}."


def test_source_exists_compiles_and_has_required_behavior():
    source_path = "/home/user/src/vm_service.c"
    assert os.path.isfile(source_path), f"{source_path} does not exist."
    assert not os.path.islink(source_path), f"{source_path} must be a source file, not a symlink."

    with tempfile.TemporaryDirectory() as tmpdir:
        compiled = os.path.join(tmpdir, "vm_service_from_source")
        result = subprocess.run(
            ["gcc", source_path, "-o", compiled], capture_output=True, text=True
        )
        assert result.returncode == 0, f"The C source does not compile: {result.stderr}"
        run_service(compiled, None)
        run_service(compiled, "")
        run_service(compiled, ":audit_" + uuid.uuid4().hex)


def test_deploy_script_exists_and_executable():
    deploy_script = "/home/user/deploy.sh"
    assert os.path.isfile(deploy_script), f"{deploy_script} does not exist."
    assert os.access(deploy_script, os.X_OK), f"{deploy_script} is not executable."


def test_vm_service_binary_exists_and_executable():
    binary_path = "/home/user/bin/vm_service"
    assert os.path.isfile(binary_path), f"{binary_path} does not exist."
    assert not os.path.islink(binary_path), f"{binary_path} must be a compiled executable, not a symlink."
    assert os.access(binary_path, os.X_OK), f"{binary_path} is not executable."
    assert os.stat(binary_path).st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary_path} is not an ELF compiled executable."


def test_vm_service_default_and_variable_behavior():
    binary_path = "/home/user/bin/vm_service"
    run_service(binary_path, None)
    run_service(binary_path, "")
    for _ in range(3):
        run_service(binary_path, ":audit_" + uuid.uuid4().hex)


def test_run_deploy_script_and_check_state():
    deploy_script = "/home/user/deploy.sh"
    binary_path = "/home/user/bin/vm_service"
    logs_dir = "/home/user/logs"
    log_path = os.path.join(logs_dir, "service.log")
    bak_log_path = os.path.join(logs_dir, "service.log.bak")
    bashrc_path = "/home/user/.bashrc"

    # First retain the original end-to-end assertions using the submitted binary.
    os.makedirs(logs_dir, exist_ok=True)
    for path in (log_path, bak_log_path):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(["bash", deploy_script], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"deploy.sh failed with return code {result.returncode}. stderr: {result.stderr}"
    )

    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist."
    with open(bashrc_path, "r") as f:
        bashrc_content = f.read()
    assert "export VNC_DISPLAY=:5" in bashrc_content, (
        f"The required export statement was not found in {bashrc_path}."
    )

    assert os.path.isfile(bak_log_path), f"{bak_log_path} does not exist."
    with open(bak_log_path, "r") as f:
        bak_content = f.read().strip()
    expected_log = "Starting QEMU on VNC display :5"
    assert bak_content == expected_log, (
        f"Expected '{expected_log}' in {bak_log_path}, got '{bak_content}'."
    )

    assert os.path.isfile(log_path), f"{log_path} does not exist."
    assert os.path.getsize(log_path) == 0, f"{log_path} is not empty (size > 0 bytes)."

    # Replace the service temporarily with a randomized probe. This verifies that
    # deploy.sh really appends to .bashrc, exports :5 before invoking the exact
    # service path, appends its stdout, copies the log, and truncates the original.
    token = uuid.uuid4().hex
    marker = f"/tmp/vm_service_called_{token}"
    probe_output = f"DEPLOY_PROBE_{token}"
    prior_log = f"PREEXISTING_{token}\n"
    with open(bashrc_path, "r") as f:
        prior_export_count = sum(
            1 for line in f if line.rstrip("\n") == "export VNC_DISPLAY=:5"
        )
    with open(log_path, "w") as f:
        f.write(prior_log)

    backup_binary = f"/tmp/vm_service_saved_{token}"
    os.replace(binary_path, backup_binary)
    probe = f'''#!/bin/bash
count=$(grep -Fxc 'export VNC_DISPLAY=:5' /home/user/.bashrc 2>/dev/null || true)
[ "$count" -gt {prior_export_count} ] || exit 71
[ "${{VNC_DISPLAY+x}}" = x ] && [ "$VNC_DISPLAY" = ':5' ] || exit 72
printf '%s' '{token}' > '{marker}'
printf '%s\\n' '{probe_output}'
'''
    try:
        with open(binary_path, "w") as f:
            f.write(probe)
        os.chmod(binary_path, 0o755)
        result = subprocess.run(["bash", deploy_script], capture_output=True, text=True)

        marker_value = None
        if os.path.isfile(marker):
            with open(marker, "r") as f:
                marker_value = f.read()
        bak_value = None
        if os.path.isfile(bak_log_path):
            with open(bak_log_path, "r") as f:
                bak_value = f.read()
        log_exists = os.path.isfile(log_path)
        log_size = os.path.getsize(log_path) if log_exists else None
    finally:
        if os.path.lexists(binary_path):
            os.remove(binary_path)
        os.replace(backup_binary, binary_path)
        if os.path.lexists(marker):
            os.remove(marker)

    assert result.returncode == 0, (
        f"deploy.sh failed its instrumented run with return code {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert marker_value == token, "deploy.sh did not execute /home/user/bin/vm_service."
    assert bak_value == prior_log + probe_output + "\n", (
        "deploy.sh did not append service stdout and then copy the complete log to service.log.bak."
    )
    assert log_exists, f"{log_path} does not exist."
    assert log_size == 0, f"{log_path} was not truncated after rotation."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
