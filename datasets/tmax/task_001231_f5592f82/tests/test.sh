#!/bin/bash
set -e
mkdir -p /logs/verifier
mkdir -p /run/sshd

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import socket
import secrets
import shutil
import subprocess
import tempfile
import time
import pytest


def find_mountpoint():
    fstab_file = "/home/user/network_fstab"
    with open(fstab_file, "r") as f:
        for line in f:
            if line.strip() and not line.startswith("#"):
                parts = line.split()
                if len(parts) >= 2 and parts[0] == "//storage-node/router-backups":
                    return parts[1]
    return None


def test_ssh_key_permissions_fixed():
    private_key = "/home/user/.ssh/id_rsa"
    assert os.path.exists(private_key), f"Private key {private_key} is missing."

    st = os.stat(private_key)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"Permissions for {private_key} are not 600. Current permissions: {oct(perms)}. SSH will reject an open private key."


def test_mount_directory_created():
    fstab_file = "/home/user/network_fstab"
    assert os.path.exists(fstab_file), f"{fstab_file} is missing."

    expected_mount = find_mountpoint()
    assert expected_mount is not None, "Could not find //storage-node/router-backups in fstab."
    assert os.path.isdir(expected_mount), f"The mount directory {expected_mount} does not exist or is not a directory."


def test_python_script_behavior():
    script_path = "/home/user/net_manager.py"
    assert os.path.isfile(script_path), f"Python script {script_path} is missing."

    expected_mount = find_mountpoint()
    assert expected_mount is not None, "Could not find //storage-node/router-backups in fstab."
    backup_file = os.path.join(expected_mount, "router-01-latest.bak")
    if os.path.exists(backup_file):
        os.remove(backup_file)

    source_file = "/home/user/router_config.txt"
    client_config = "/home/user/.ssh/config"
    source_stat = os.stat(source_file)
    mount_stat = os.stat(expected_mount)
    with open(source_file, "rb") as f:
        original_source = f.read()
    with open(client_config, "rb") as f:
        original_config = f.read()
    config_stat = os.stat(client_config)

    tempdir = tempfile.mkdtemp(prefix="net-manager-verify-")
    remote_user = f"rtv{os.getpid()}"
    sshd = None
    user_created = False

    try:
        subprocess.run(["useradd", "-M", "-s", "/bin/sh", remote_user], check=True)
        user_created = True
        subprocess.run(
            ["chpasswd"],
            input=f"{remote_user}:{secrets.token_hex(16)}\n",
            text=True,
            check=True,
        )
        remote_entry = subprocess.run(
            ["getent", "passwd", remote_user], text=True, capture_output=True, check=True
        ).stdout.strip().split(":")
        remote_uid, remote_gid = int(remote_entry[2]), int(remote_entry[3])

        # Use content generated only at verification time. The local process runs as
        # 'user' and cannot read this file, while the isolated SSH account can.
        expected_content = (
            "hostname ROUTER-01\n"
            f"verification nonce {secrets.token_hex(32)}\n"
            "interface eth0\n"
            " ip address 10.0.0.1 255.255.255.0\n"
        )
        with open(source_file, "w") as f:
            f.write(expected_content)
        os.chown(source_file, remote_uid, remote_gid)
        os.chmod(source_file, 0o600)

        # Ensure the engineer account can create the backup without granting it
        # access to the protected remote source file.
        user_entry = subprocess.run(
            ["getent", "passwd", "user"], text=True, capture_output=True, check=True
        ).stdout.strip().split(":")
        user_uid, user_gid = int(user_entry[2]), int(user_entry[3])
        os.chown(expected_mount, user_uid, user_gid)
        os.chmod(expected_mount, 0o755)

        host_key = os.path.join(tempdir, "ssh_host_ed25519_key")
        auth_keys = os.path.join(tempdir, "authorized_keys")
        sshd_config = os.path.join(tempdir, "sshd_config")
        sshd_log = os.path.join(tempdir, "sshd.log")
        sshd_pid = os.path.join(tempdir, "sshd.pid")

        subprocess.run(
            ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", host_key],
            check=True,
        )
        shutil.copyfile("/home/user/.ssh/id_rsa.pub", auth_keys)
        os.chmod(auth_keys, 0o644)

        probe = socket.socket()
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
        probe.close()

        with open(sshd_config, "w") as f:
            f.write(f"""Port {port}
ListenAddress 127.0.0.1
HostKey {host_key}
PidFile {sshd_pid}
AuthorizedKeysFile {auth_keys}
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM no
StrictModes no
PermitRootLogin no
AllowUsers {remote_user}
LogLevel VERBOSE
""")

        with open(client_config, "w") as f:
            f.write(f"""Host router-01
    HostName 127.0.0.1
    Port {port}
    User {remote_user}
    IdentityFile /home/user/.ssh/id_rsa
    IdentitiesOnly yes
    BatchMode yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
""")
        os.chown(client_config, user_uid, user_gid)
        os.chmod(client_config, 0o600)

        sshd = subprocess.Popen(
            ["/usr/sbin/sshd", "-D", "-f", sshd_config, "-E", sshd_log],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        deadline = time.time() + 5
        while time.time() < deadline:
            if sshd.poll() is not None:
                pytest.fail(f"Test SSH server failed to start: {sshd.stderr.read()}")
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.05)
        else:
            pytest.fail("Test SSH server did not start listening in time.")

        input_data = "UNKNOWN\nBACKUP\nEXIT\n"
        try:
            result = subprocess.run(
                ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "python3", script_path],
                input=input_data,
                text=True,
                capture_output=True,
                timeout=10,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Script exited with non-zero return code {e.returncode}. Stderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail("Script timed out. Ensure it exits when receiving 'EXIT'.")

        stdout = [line.strip() for line in result.stdout.strip().split("\n") if line.strip()]
        assert len(stdout) >= 2, f"Expected at least two lines of output, got: {stdout}"
        assert "UNKNOWN_COMMAND" in stdout[0], f"Expected UNKNOWN_COMMAND for unknown input, got: {stdout[0]}"
        assert "BACKUP_SUCCESS" in stdout[1], f"Expected BACKUP_SUCCESS after backup command, got: {stdout[1]}"

        assert os.path.isfile(backup_file), f"Backup file {backup_file} was not created."
        with open(backup_file, "r") as f:
            actual_content = f.read()
        assert actual_content == expected_content, f"Content of {backup_file} does not match the content fetched from router-01."

        with open(sshd_log, "r", errors="replace") as f:
            server_log = f.read()
        assert f"Accepted publickey for {remote_user}" in server_log, "No successful key-authenticated SSH connection to router-01 was observed."
        assert "Starting session: command" in server_log, "The backup did not execute a command through the router-01 SSH session."

    finally:
        if sshd is not None and sshd.poll() is None:
            sshd.terminate()
            try:
                sshd.wait(timeout=3)
            except subprocess.TimeoutExpired:
                sshd.kill()
                sshd.wait()

        with open(source_file, "wb") as f:
            f.write(original_source)
        os.chown(source_file, source_stat.st_uid, source_stat.st_gid)
        os.chmod(source_file, stat.S_IMODE(source_stat.st_mode))

        with open(client_config, "wb") as f:
            f.write(original_config)
        os.chown(client_config, config_stat.st_uid, config_stat.st_gid)
        os.chmod(client_config, stat.S_IMODE(config_stat.st_mode))

        os.chown(expected_mount, mount_stat.st_uid, mount_stat.st_gid)
        os.chmod(expected_mount, stat.S_IMODE(mount_stat.st_mode))

        if user_created:
            subprocess.run(["userdel", remote_user], check=False)
        shutil.rmtree(tempdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
