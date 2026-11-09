#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import secrets
import pytest

SCRIPT_PATH = "/home/user/generate_vm_configs.py"
CONFIGS_DIR = "/home/user/configs"


def test_script_exists():
    """Ensure the Python script exists at the correct path."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_script_execution_and_output():
    """Retain the original fixed-value output checks."""
    vm_name = "pytest_vm"
    timezone = "Asia/Tokyo"
    admin_email = "test@example.com"

    result = subprocess.run(
        ["python3", SCRIPT_PATH, vm_name, timezone, admin_email],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"

    assert os.path.exists(CONFIGS_DIR), f"Directory {CONFIGS_DIR} was not created."
    assert os.path.isdir(CONFIGS_DIR), f"{CONFIGS_DIR} is not a directory."

    fstab_path = os.path.join(CONFIGS_DIR, f"{vm_name}_fstab")
    assert os.path.exists(fstab_path), f"fstab file {fstab_path} was not created."
    with open(fstab_path, "r") as f:
        fstab_content = f.read().strip()
    expected_fstab = f"/var/lib/qemu/images/{vm_name}.img /mnt/{vm_name} ext4 loop,noexec,nosuid,nodev 0 0"
    assert fstab_content == expected_fstab, f"fstab content mismatch. Expected: '{expected_fstab}', Got: '{fstab_content}'"

    aliases_path = os.path.join(CONFIGS_DIR, f"{vm_name}_aliases")
    assert os.path.exists(aliases_path), f"aliases file {aliases_path} was not created."
    with open(aliases_path, "r") as f:
        aliases_content = f.read().strip()
    expected_aliases = f"vm-{vm_name}-alerts: {admin_email}"
    assert aliases_content == expected_aliases, f"aliases content mismatch. Expected: '{expected_aliases}', Got: '{aliases_content}'"

    apply_sh_path = os.path.join(CONFIGS_DIR, f"{vm_name}_apply.sh")
    assert os.path.exists(apply_sh_path), f"apply.sh file {apply_sh_path} was not created."

    st = os.stat(apply_sh_path)
    file_permissions = oct(st.st_mode)[-3:]
    assert file_permissions == "755", f"apply.sh permissions are not 0755. Got: {file_permissions}"

    with open(apply_sh_path, "r") as f:
        apply_sh_content = f.read()

    assert apply_sh_content.startswith("#!/bin/bash"), "apply.sh does not start with #!/bin/bash"
    assert f'TZ="{timezone}"' in apply_sh_content or f"TZ={timezone}" in apply_sh_content, "Missing or incorrect TZ assignment in apply.sh"
    assert "export TZ" in apply_sh_content, "TZ is not exported in apply.sh"
    assert f'read -p "Proceed with hardening {vm_name}? (y/n): " confirm' in apply_sh_content, "Missing correct read prompt in apply.sh"
    assert f'echo "Hardening applied for {vm_name}"' in apply_sh_content or f"echo 'Hardening applied for {vm_name}'" in apply_sh_content, "Missing correct echo statement in apply.sh"


def verify_generated_case(vm_name, timezone, admin_email):
    shutil.rmtree(CONFIGS_DIR, ignore_errors=True)

    result = subprocess.run(
        ["python3", SCRIPT_PATH, vm_name, timezone, admin_email],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, result.stderr
    assert os.path.isdir(CONFIGS_DIR)

    fstab_path = os.path.join(CONFIGS_DIR, f"{vm_name}_fstab")
    aliases_path = os.path.join(CONFIGS_DIR, f"{vm_name}_aliases")
    apply_path = os.path.join(CONFIGS_DIR, f"{vm_name}_apply.sh")

    assert os.path.isfile(fstab_path)
    assert os.path.isfile(aliases_path)
    assert os.path.isfile(apply_path)

    with open(fstab_path, "r") as f:
        assert f.read().strip() == f"/var/lib/qemu/images/{vm_name}.img /mnt/{vm_name} ext4 loop,noexec,nosuid,nodev 0 0"
    with open(aliases_path, "r") as f:
        assert f.read().strip() == f"vm-{vm_name}-alerts: {admin_email}"

    assert stat.S_IMODE(os.stat(apply_path).st_mode) == 0o755
    with open(apply_path, "r") as f:
        content = f.read()
    assert content.startswith("#!/bin/bash")
    assert f'TZ="{timezone}"' in content or f"TZ={timezone}" in content
    assert "export TZ" in content
    assert f'read -p "Proceed with hardening {vm_name}? (y/n): " confirm' in content
    assert f'echo "Hardening applied for {vm_name}"' in content or f"echo 'Hardening applied for {vm_name}'" in content

    expected = f"Hardening applied for {vm_name}\n"
    yes_run = subprocess.run([apply_path], input="y\n", capture_output=True, text=True)
    assert yes_run.returncode == 0, yes_run.stderr
    assert yes_run.stdout == expected

    for answer in ("n\n", "Y\n", "yes\n", "\n"):
        no_run = subprocess.run([apply_path], input=answer, capture_output=True, text=True)
        assert no_run.returncode == 0, no_run.stderr
        assert no_run.stdout == "", f"Hardening message was emitted for input {answer!r}"

    env_run = subprocess.run(
        ["/bin/bash", "-c", 'source "$1"; /usr/bin/printenv TZ', "bash", apply_path],
        input="n\n",
        capture_output=True,
        text=True
    )
    assert env_run.returncode == 0, env_run.stderr
    assert env_run.stdout == timezone + "\n", "Generated script did not set and export the requested TZ"


def test_randomized_inputs_and_apply_behavior():
    """Exercise argument-dependent generation and the generated script's branches."""
    zones = ["UTC", "Europe/Paris", "America/Denver", "Pacific/Auckland"]
    for index in range(2):
        token = secrets.token_hex(8)
        vm_name = f"vm_{index}_{token}"
        timezone = zones[(int(token[:2], 16) + index) % len(zones)]
        admin_email = f"alerts-{token}@example.net"
        verify_generated_case(vm_name, timezone, admin_email)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
