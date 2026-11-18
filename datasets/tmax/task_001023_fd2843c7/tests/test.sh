#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import http.client
import os
import shutil
import smtplib
import socket
import subprocess
import tarfile
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest

USER = "user"
UID = subprocess.check_output(["id", "-u", USER], text=True).strip()
USER_ENV = os.environ.copy()
USER_ENV.update({
    "HOME": "/home/user",
    "USER": USER,
    "LOGNAME": USER,
    "XDG_RUNTIME_DIR": f"/run/user/{UID}",
    "DBUS_SESSION_BUS_ADDRESS": f"unix:path=/run/user/{UID}/bus",
})


def user_systemctl(*args, check=True):
    return subprocess.run(
        ["runuser", "-u", USER, "--", "env",
         f"HOME={USER_ENV['HOME']}",
         f"XDG_RUNTIME_DIR={USER_ENV['XDG_RUNTIME_DIR']}",
         f"DBUS_SESSION_BUS_ADDRESS={USER_ENV['DBUS_SESSION_BUS_ADDRESS']}",
         "systemctl", "--user", *args],
        text=True, capture_output=True, check=check,
    )


def wait_for_port(port, open_expected=True, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.25)
            is_open = sock.connect_ex(("127.0.0.1", port)) == 0
        if is_open == open_expected:
            return
        time.sleep(0.1)
    pytest.fail(f"port {port} did not become {'open' if open_expected else 'closed'}")


def main_pid(service):
    result = user_systemctl("show", service, "-p", "MainPID", "--value")
    pid = int(result.stdout.strip() or "0")
    assert pid > 0, f"{service} has no running MainPID"
    return pid


def listening_socket_inode(port):
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table) as handle:
            next(handle)
            for line in handle:
                fields = line.split()
                local_address = fields[1]
                state = fields[3]
                if local_address.rsplit(":", 1)[1].upper() == wanted and state == "0A":
                    return fields[9]
    return None


def assert_main_pid_owns_port(service, port):
    pid = main_pid(service)
    inode = listening_socket_inode(port)
    assert inode, f"nothing is listening on TCP port {port}"
    owned = set()
    for fd in glob.glob(f"/proc/{pid}/fd/*"):
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        if target.startswith("socket:["):
            owned.add(target[8:-1])
    assert inode in owned, f"port {port} is not owned by the systemd MainPID for {service}"


def clear_artifacts():
    for pattern in ("/home/user/backups/*.tar.gz", "/home/user/emails/*.eml"):
        for path in glob.glob(pattern):
            os.unlink(path)


def wait_for_files(pattern, minimum=1, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        paths = glob.glob(pattern)
        if len(paths) >= minimum:
            return paths
        time.sleep(0.1)
    return glob.glob(pattern)


def assert_backup_contains_commit(archive, commit, expected_text):
    assert tarfile.is_tarfile(archive), f"{archive} is not a valid tar archive"
    with tempfile.TemporaryDirectory() as td:
        with tarfile.open(archive, "r:gz") as tf:
            members = tf.getmembers()
            assert members, f"{archive} is empty"
            for member in members:
                normalized = os.path.normpath(member.name)
                assert not os.path.isabs(member.name)
                assert normalized != ".." and not normalized.startswith("../"), "unsafe archive path"
            tf.extractall(td)
        repositories = []
        for root, dirs, files in os.walk(td):
            if "HEAD" in files and "objects" in dirs:
                repositories.append(root)
        assert repositories, f"{archive} does not contain a bare Git repository"
        for repo in repositories:
            exists = subprocess.run(
                ["git", "--git-dir", repo, "cat-file", "-e", f"{commit}^{{commit}}"],
                capture_output=True,
            )
            if exists.returncode == 0:
                shown = subprocess.run(
                    ["git", "--git-dir", repo, "show", f"{commit}:test.txt"],
                    capture_output=True, text=True, check=True,
                ).stdout
                assert shown == expected_text
                return
    pytest.fail(f"backup {archive} does not contain pushed commit {commit}")


def test_systemd_service_dependencies():
    """Check both installed services and the webhook dependency directives."""
    possible_paths = [
        "/home/user/.config/systemd/user/webhook-notifier.service",
        "/app/webhook-notifier-1.0.0/webhook-notifier.service",
    ]
    content = ""
    for path in possible_paths:
        if os.path.isfile(path):
            content = Path(path).read_text()
            break
    assert content, "Could not find webhook-notifier.service in expected locations"
    assert "After=smtp-sink.service" in content
    assert "Requires=smtp-sink.service" in content or "Wants=smtp-sink.service" in content

    assert Path("/home/user/smtp_sink.py").is_file()
    for service in ("smtp-sink.service", "webhook-notifier.service"):
        enabled = user_systemctl("is-enabled", service, check=False)
        assert enabled.returncode == 0 and enabled.stdout.strip() == "enabled", f"{service} is not enabled"
        active = user_systemctl("is-active", service, check=False)
        assert active.returncode == 0 and active.stdout.strip() == "active", f"{service} is not active"

    loaded_unit = user_systemctl("cat", "webhook-notifier.service").stdout
    assert "After=smtp-sink.service" in loaded_unit
    assert "Requires=smtp-sink.service" in loaded_unit or "Wants=smtp-sink.service" in loaded_unit

    props = user_systemctl(
        "show", "webhook-notifier.service", "-p", "After", "-p", "Requires", "-p", "Wants", "-p", "Environment"
    ).stdout
    assert "smtp-sink.service" in props
    assert "BACKUP_DIR=/home/user/backups/" in props
    assert "SOURCE_DIR=/home/user/project.git" in props
    assert "SMTP_PORT=8025" in props


def test_services_listening():
    """Both ports must be owned by their active systemd user service MainPIDs."""
    for port, name in ((8025, "SMTP Sink"), (8080, "Webhook Notifier")):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(2)
            assert sock.connect_ex(("127.0.0.1", port)) == 0, f"{name} is not listening on 127.0.0.1:{port}"
    assert_main_pid_owns_port("smtp-sink.service", 8025)
    assert_main_pid_owns_port("webhook-notifier.service", 8080)


def test_git_push_triggers_pipeline(tmp_path):
    project_repo = "/home/user/project.git"
    assert os.path.isdir(project_repo)
    bare = subprocess.run(
        ["git", "--git-dir", project_repo, "rev-parse", "--is-bare-repository"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    assert bare == "true"
    hook = Path(project_repo) / "hooks/post-receive"
    assert hook.is_file() and os.access(hook, os.X_OK), "post-receive hook is missing or not executable"

    # Exercise the SMTP sink independently with an unpredictable message.
    clear_artifacts()
    smtp_token = f"SMTP audit {uuid.uuid4().hex}"
    with smtplib.SMTP("127.0.0.1", 8025, timeout=4) as client:
        client.sendmail("audit@localhost", "admin@localhost", f"Subject: {smtp_token}\n\n{smtp_token}")
    smtp_files = wait_for_files("/home/user/emails/*.eml")
    assert smtp_files, "SMTP sink did not create an email"
    assert any(smtp_token in Path(p).read_text(errors="replace") for p in smtp_files)

    # Exercise the actual systemd-managed webhook directly. It must create both
    # kinds of artifact and successfully use the SMTP sink.
    clear_artifacts()
    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=8)
    conn.request("POST", "/deploy", body=b"audit=direct", headers={"Content-Type": "application/x-www-form-urlencoded"})
    response = conn.getresponse()
    body = response.read()
    conn.close()
    assert response.status == 200, f"webhook returned {response.status}: {body!r}"
    direct_backups = wait_for_files("/home/user/backups/*.tar.gz")
    direct_emails = wait_for_files("/home/user/emails/*.eml")
    assert direct_backups, "webhook did not create a backup"
    assert all(tarfile.is_tarfile(path) for path in direct_backups)
    assert any("Subject: Deploy triggered" in Path(p).read_text(errors="replace") for p in direct_emails)

    clone_dir = tmp_path / "test-clone"
    clone_proc = subprocess.run(["git", "clone", project_repo, str(clone_dir)], capture_output=True, text=True)
    assert clone_proc.returncode == 0, f"Failed to clone repository: {clone_proc.stderr}"
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=clone_dir, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=clone_dir, check=True)

    branch = f"audit-{uuid.uuid4().hex}"
    subprocess.run(["git", "checkout", "-b", branch], cwd=clone_dir, check=True)
    first_text = f"witness-{uuid.uuid4().hex}"
    (clone_dir / "test.txt").write_text(first_text)
    subprocess.run(["git", "add", "test.txt"], cwd=clone_dir, check=True)
    subprocess.run(["git", "commit", "-m", "Webhook witness push"], cwd=clone_dir, check=True)

    # Stop only the webhook service and occupy its exact address with a witness.
    # This proves the post-receive hook itself issues an HTTP POST to /deploy.
    seen = []
    class WitnessHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            seen.append((self.command, self.path))
            length = int(self.headers.get("Content-Length", "0"))
            self.rfile.read(length)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
        def log_message(self, *args):
            pass

    user_systemctl("stop", "webhook-notifier.service")
    wait_for_port(8080, False)
    witness = HTTPServer(("127.0.0.1", 8080), WitnessHandler)
    thread = threading.Thread(target=witness.handle_request, daemon=True)
    thread.start()
    try:
        push_proc = subprocess.run(
            ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
            cwd=clone_dir, capture_output=True, text=True, timeout=15,
        )
        assert push_proc.returncode == 0, f"Git push failed: {push_proc.stderr}"
        thread.join(5)
        assert seen == [("POST", "/deploy")], f"hook did not POST to /deploy: {seen}"
    finally:
        witness.server_close()
        user_systemctl("start", "webhook-notifier.service", check=False)
        wait_for_port(8080, True)

    assert user_systemctl("is-active", "webhook-notifier.service", check=False).stdout.strip() == "active"
    assert_main_pid_owns_port("webhook-notifier.service", 8080)

    # Now make a fresh push through the restored service and require fresh,
    # causally produced artifacts containing this unpredictable commit.
    second_text = f"pipeline-{uuid.uuid4().hex}"
    (clone_dir / "test.txt").write_text(second_text)
    subprocess.run(["git", "add", "test.txt"], cwd=clone_dir, check=True)
    subprocess.run(["git", "commit", "-m", "End-to-end pipeline push"], cwd=clone_dir, check=True)
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=clone_dir, text=True).strip()

    clear_artifacts()
    push_proc = subprocess.run(
        ["git", "push", "origin", branch], cwd=clone_dir,
        capture_output=True, text=True, timeout=20,
    )
    assert push_proc.returncode == 0, f"Git push failed: {push_proc.stderr}"

    backups = wait_for_files("/home/user/backups/*.tar.gz")
    emails = wait_for_files("/home/user/emails/*.eml")
    assert backups, "No backup tarball was created by the fresh push"
    assert emails, "No email was created by the fresh push"

    valid_backup = None
    errors = []
    for archive in backups:
        try:
            assert_backup_contains_commit(archive, commit, second_text)
            valid_backup = archive
            break
        except Exception as exc:
            errors.append(str(exc))
    assert valid_backup, "; ".join(errors)

    email_contents = [Path(path).read_text(errors="replace") for path in emails]
    assert any("Subject: Deploy triggered" in content for content in email_contents)
    assert any(os.path.basename(valid_backup) in content or valid_backup in content for content in email_contents), \
        "notification email does not identify the backup created by this push"

    assert_main_pid_owns_port("smtp-sink.service", 8025)
    assert_main_pid_owns_port("webhook-notifier.service", 8080)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
