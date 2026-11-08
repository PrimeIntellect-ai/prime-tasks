#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tarfile
import tempfile
import time
from pathlib import Path


def run_script(path, *, env=None, timeout=15):
    return subprocess.run([path], capture_output=True, text=True, env=env, timeout=timeout)


def test_scripts_are_executable():
    """Check that all required scripts are executable."""
    scripts = [
        "/home/user/diagnose.py",
        "/home/user/backup.sh",
        "/home/user/provision_disk.sh",
        "/home/user/launch_qemu.sh",
    ]
    for script in scripts:
        assert os.path.isfile(script), f"Script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."


def test_diagnose_py_output():
    """Exercise diagnose.py on corrected and unpredictable log fixtures."""
    script_path = "/home/user/diagnose.py"
    log_path = Path("/home/user/connection.log")
    original = log_path.read_bytes() if log_path.exists() else None

    try:
        fixtures = [("10.0.0.5", "192.168.1.10")]
        for _ in range(3):
            target_octet = secrets.randbelow(200) + 20
            decoy_octet = (target_octet + secrets.randbelow(150) + 1) % 254 + 1
            fixtures.append(
                (f"198.51.100.{target_octet}", f"203.0.113.{decoy_octet}")
            )

        for expected, decoy in fixtures:
            log_path.write_text(
                f"debug1: Connecting to {decoy} [{decoy}] port 22.\n"
                "debug1: receive packet: type 52\n"
                "debug1: unrelated diagnostic message\n"
                f"debug1: Connecting to {expected} [{expected}] port 22.\n"
                "debug1: receive packet: type 51\n"
                f"debug1: Connecting to {decoy} [{decoy}] port 22.\n"
                "debug1: receive packet: type 52\n"
            )
            result = run_script(script_path)
            assert result.returncode == 0, (
                f"{script_path} failed to execute: {result.stderr}"
            )
            assert result.stdout.strip() == expected, (
                f"Expected output {expected!r}, got {result.stdout.strip()!r}"
            )
            assert result.stdout == expected + "\n" or result.stdout == expected, (
                "diagnose.py must print only the IP address"
            )
            assert result.stderr == "", "diagnose.py must not emit diagnostic output"
    finally:
        if original is None:
            log_path.unlink(missing_ok=True)
        else:
            log_path.write_bytes(original)


def test_backup_sh_creates_tarball():
    """Test that backup.sh archives the actual manifests directory and contents."""
    script_path = "/home/user/backup.sh"
    tarball_path = Path("/home/user/manifests_backup.tar.gz")
    manifests = Path("/home/user/manifests")

    token = secrets.token_hex(8)
    nested = manifests / f"verify_{token}" / "nested"
    nested.mkdir(parents=True, exist_ok=True)
    expected_files = {
        Path(f"verify_{token}/root.txt"): f"root-{secrets.token_hex(16)}\n".encode(),
        Path(f"verify_{token}/nested/data.yaml"): f"value: {secrets.token_hex(16)}\n".encode(),
    }
    for relative, data in expected_files.items():
        path = manifests / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    tarball_path.unlink(missing_ok=True)
    result = run_script(script_path)
    assert result.returncode == 0, f"{script_path} failed to execute: {result.stderr}"
    assert tarball_path.is_file(), f"Tarball {tarball_path} was not created."

    with tarfile.open(tarball_path, "r:gz") as tar:
        names = tar.getnames()
        assert any("manifests" in name for name in names), (
            "Tarball does not contain 'manifests'."
        )

        archived = {}
        for member in tar.getmembers():
            if not member.isfile():
                continue
            parts = Path(member.name).parts
            assert "manifests" in parts, (
                f"Unexpected regular file outside manifests: {member.name}"
            )
            index = len(parts) - 1 - list(reversed(parts)).index("manifests")
            relative = Path(*parts[index + 1:])
            extracted = tar.extractfile(member)
            assert extracted is not None
            archived[relative] = extracted.read()

        for relative, expected_data in expected_files.items():
            assert relative in archived, f"Backup omitted {relative}"
            assert archived[relative] == expected_data, (
                f"Backup content for {relative} is incorrect"
            )


def test_new_fstab_content():
    """Test that new_fstab contains the correct entry."""
    fstab_path = "/home/user/new_fstab"
    assert os.path.isfile(fstab_path), f"File {fstab_path} does not exist."

    with open(fstab_path, "r") as f:
        content = f.read().strip()

    normalized_content = re.sub(r"\s+", " ", content)
    expected = "LABEL=vmdatalocal /var/lib/vmdata ext4 rw,noatime 0 2"
    assert normalized_content == expected, (
        f"Expected fstab entry {expected!r}, got {normalized_content!r}"
    )


def test_provision_disk_sh():
    """Test that provision_disk.sh creates an ext4 formatted disk image."""
    script_path = "/home/user/provision_disk.sh"
    disk_path = "/home/user/vm_disk.img"

    if os.path.exists(disk_path):
        os.remove(disk_path)

    result = run_script(script_path, timeout=30)
    assert result.returncode == 0, f"{script_path} failed to execute: {result.stderr}"
    assert os.path.isfile(disk_path), f"Disk image {disk_path} was not created."

    size = os.path.getsize(disk_path)
    assert size >= 45 * 1024 * 1024, (
        f"Disk image size {size} is less than expected ~50MB."
    )

    file_cmd = subprocess.run(["file", disk_path], capture_output=True, text=True)
    assert "ext4 filesystem" in file_cmd.stdout.lower(), (
        f"Disk image is not formatted as ext4. Output: {file_cmd.stdout}"
    )


def _option_value(args, option):
    for index, arg in enumerate(args):
        if arg == option and index + 1 < len(args):
            yield args[index + 1]
        elif arg.startswith(option + "="):
            yield arg.split("=", 1)[1]


def test_launch_qemu_sh_content_and_behavior():
    """Retain textual checks and execute the launcher against a QEMU shim."""
    script_path = "/home/user/launch_qemu.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    content = Path(script_path).read_text()
    assert "qemu-system-x86_64" in content, "Missing 'qemu-system-x86_64' command."
    assert "-vnc" in content and ":2" in content, "Missing VNC configuration for display :2."
    assert "vm_disk.img" in content, "Missing disk image attachment."
    assert "virtio" in content, "Missing 'virtio' block device configuration."
    assert "qemu.pid" in content, "Missing PID file configuration."
    assert "-nographic" in content or "-display none" in content, (
        "Missing flag to disable default graphical UI."
    )

    pid_file = Path("/home/user/qemu.pid")
    pid_file.unlink(missing_ok=True)

    with tempfile.TemporaryDirectory(prefix="qemu-verifier-") as temp_dir:
        temp = Path(temp_dir)
        shim = temp / "qemu-system-x86_64"
        shim.write_text(
            "#!/bin/sh\n"
            "exec >/dev/null 2>&1\n"
            "printf '%s\\0' \"$@\" > \"$QEMU_TEST_DIR/args\"\n"
            "echo \"$$\" > \"$QEMU_TEST_DIR/invoked_pid\"\n"
            "exec sleep 30\n"
        )
        shim.chmod(0o755)

        env = os.environ.copy()
        env["PATH"] = str(temp) + os.pathsep + env.get("PATH", "")
        env["QEMU_TEST_DIR"] = str(temp)
        launched_pid = None
        try:
            result = run_script(script_path, env=env, timeout=8)
            assert result.returncode == 0, (
                f"{script_path} failed to execute: {result.stderr}"
            )

            deadline = time.time() + 3
            while time.time() < deadline:
                if (temp / "args").exists() and (temp / "invoked_pid").exists() and pid_file.exists():
                    break
                time.sleep(0.05)

            assert (temp / "args").is_file(), "The script did not execute qemu-system-x86_64."
            assert (temp / "invoked_pid").is_file(), "The QEMU shim was not launched."
            assert pid_file.is_file(), "The script did not create /home/user/qemu.pid."

            raw_args = (temp / "args").read_bytes().split(b"\0")
            args = [item.decode() for item in raw_args if item]
            invoked_pid = int((temp / "invoked_pid").read_text().strip())
            launched_pid = int(pid_file.read_text().strip())
            assert launched_pid == invoked_pid, (
                "qemu.pid does not contain the PID of the launched QEMU process"
            )
            os.kill(launched_pid, 0)

            assert "-nographic" in args or "none" in list(_option_value(args, "-display")), (
                "QEMU was not launched without its default graphical UI"
            )
            assert ":2" in list(_option_value(args, "-vnc")), (
                "QEMU was not launched with VNC display :2"
            )

            drive_specs = list(_option_value(args, "-drive"))
            direct_virtio = any(
                "file=/home/user/vm_disk.img" in spec and "if=virtio" in spec
                for spec in drive_specs
            )

            split_virtio = False
            for spec in drive_specs:
                if "file=/home/user/vm_disk.img" not in spec:
                    continue
                match = re.search(r"(?:^|,)id=([^,]+)", spec)
                if not match:
                    continue
                drive_id = match.group(1)
                for device in _option_value(args, "-device"):
                    if "virtio" in device and f"drive={drive_id}" in device:
                        split_virtio = True

            assert direct_virtio or split_virtio, (
                "QEMU did not attach /home/user/vm_disk.img as a virtio block device"
            )
        finally:
            if launched_pid is not None:
                try:
                    os.kill(launched_pid, 9)
                except ProcessLookupError:
                    pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
