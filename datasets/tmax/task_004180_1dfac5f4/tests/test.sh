#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import signal
import stat
import subprocess
import uuid

EXP_PATH = "/home/user/auto_mount.exp"
CONF_PATH = "/home/user/my_fstab.conf"
SETUP_PATH = "/home/user/setup_mounts.sh"
EXPECTED_CONTENT = "/dev/vdc1 /home/user/data_backup xfs rw,noexec,nodev 0 0"
EXPECTED_SETUP = '''#!/bin/bash
echo "--- User-Space Mount Configurator ---"
read -p "Enter device path: " dev_path
read -p "Enter mount point: " mount_point
read -p "Enter filesystem type: " fs_type
read -p "Enter mount options: " mount_opts

echo "$dev_path $mount_point $fs_type $mount_opts 0 0" > /home/user/my_fstab.conf
echo "Configuration saved to /home/user/my_fstab.conf"
'''


def test_auto_mount_exp_exists_and_executable():
    """Test that the expect script exists and is executable."""
    assert os.path.isfile(EXP_PATH), f"The expect script {EXP_PATH} does not exist."

    st = os.stat(EXP_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"The expect script {EXP_PATH} is not executable."

    with open(EXP_PATH, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    expect_shebang = re.compile(
        r"^#!\s*(?:/usr/bin/expect(?:\s|$)|/usr/bin/env\s+(?:-S\s+)?expect(?:\s|$))"
    )
    assert expect_shebang.match(first_line), (
        f"{EXP_PATH} must be an executable Expect script with an Expect shebang."
    )


def test_my_fstab_conf_exists_and_content():
    """Test that the generated configuration file exists and has the correct content."""
    assert os.path.isfile(CONF_PATH), f"The configuration file {CONF_PATH} does not exist. Did you run the expect script?"

    with open(CONF_PATH, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED_CONTENT, f"The contents of {CONF_PATH} are incorrect.\nExpected: '{EXPECTED_CONTENT}'\nGot: '{content}'"


def test_setup_mounts_script_unmodified():
    """Test that the original setup script was not modified."""
    assert os.path.isfile(SETUP_PATH), f"Expected script {SETUP_PATH} is missing."
    with open(SETUP_PATH, "r") as f:
        content = f.read()

    assert "read -p \"Enter device path: \" dev_path" in content, f"{SETUP_PATH} was modified and is missing the device path prompt."
    assert "read -p \"Enter mount point: \" mount_point" in content, f"{SETUP_PATH} was modified and is missing the mount point prompt."
    assert 'echo "$dev_path $mount_point $fs_type $mount_opts 0 0" > /home/user/my_fstab.conf' in content, f"{SETUP_PATH} was modified and is missing the output logic."
    assert content == EXPECTED_SETUP, f"{SETUP_PATH} was modified."


def test_expect_script_executes_and_automates_setup_mounts():
    """Run the submitted artifact and verify that it invokes the interactive setup script."""
    nonce = uuid.uuid4().hex
    marker_path = f"/tmp/setup_mounts_called_{nonce}"
    backup_path = f"/home/user/.setup_mounts_verifier_{nonce}"
    original_mode = stat.S_IMODE(os.stat(SETUP_PATH).st_mode)

    os.rename(SETUP_PATH, backup_path)
    wrapper = (
        "#!/bin/bash\n"
        f"printf '%s' {shlex.quote(nonce)} > {shlex.quote(marker_path)}\n"
        f"exec {shlex.quote(backup_path)} \"$@\"\n"
    )
    with open(SETUP_PATH, "w") as f:
        f.write(wrapper)
    os.chmod(SETUP_PATH, original_mode)

    if os.path.exists(CONF_PATH):
        os.unlink(CONF_PATH)

    proc = None
    try:
        proc = subprocess.Popen(
            [EXP_PATH],
            cwd="/home/user",
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )
        try:
            output, _ = proc.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            output, _ = proc.communicate()
            raise AssertionError(f"The Expect script timed out. Output:\n{output}")

        assert proc.returncode == 0, f"The Expect script failed with exit code {proc.returncode}. Output:\n{output}"
        assert os.path.isfile(marker_path), (
            f"The Expect script did not execute {SETUP_PATH}. Output:\n{output}"
        )
        with open(marker_path, "r") as f:
            assert f.read() == nonce

        assert os.path.isfile(CONF_PATH), (
            f"Running {EXP_PATH} did not generate {CONF_PATH}. Output:\n{output}"
        )
        with open(CONF_PATH, "r") as f:
            content = f.read().strip()
        assert content == EXPECTED_CONTENT, (
            f"Running the Expect script generated incorrect content.\n"
            f"Expected: '{EXPECTED_CONTENT}'\nGot: '{content}'\nOutput:\n{output}"
        )
    finally:
        if proc is not None and proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        if os.path.exists(SETUP_PATH):
            os.unlink(SETUP_PATH)
        if os.path.exists(backup_path):
            os.rename(backup_path, SETUP_PATH)
            os.chmod(SETUP_PATH, original_mode)
        if os.path.exists(marker_path):
            os.unlink(marker_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
