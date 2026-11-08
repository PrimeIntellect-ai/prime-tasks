#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import email
from email import policy
import os
import secrets
import socket
import stat
import subprocess
import tempfile
import threading


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def assert_python_file(path):
    with open(path, "r", encoding="utf-8") as f:
        source = f.read()
    ast.parse(source, filename=path)


def test_bare_repo_exists():
    """Verify that /home/user/deploy.git is a bare git repository."""
    repo_path = "/home/user/deploy.git"
    assert os.path.isdir(repo_path), f"Directory {repo_path} does not exist."
    assert os.path.isdir(os.path.join(repo_path, "objects")), f"{repo_path} is not a valid git repository (no objects dir)."
    assert os.path.isfile(os.path.join(repo_path, "config")), f"{repo_path} is not a valid git repository (no config file)."

    result = run(["git", "-C", repo_path, "config", "--get", "core.bare"])
    assert result.stdout.strip() == "true", f"{repo_path} is not configured as a bare repository."


def test_pre_receive_hook_exists_and_executable():
    """Verify that the pre-receive hook exists, is Python, and is executable."""
    hook_path = "/home/user/deploy.git/hooks/pre-receive"
    assert os.path.isfile(hook_path), f"Hook {hook_path} does not exist."
    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Hook {hook_path} is not executable."
    assert_python_file(hook_path)


def tree_snapshot(root):
    snapshot = {}
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        rel_current = os.path.relpath(current, root)
        if rel_current == ".":
            rel_current = ""
        snapshot[rel_current] = ("dir", stat.S_IMODE(os.lstat(current).st_mode))
        for name in list(dirs) + files:
            path = os.path.join(current, name)
            rel = os.path.relpath(path, root)
            st = os.lstat(path)
            if stat.S_ISLNK(st.st_mode):
                snapshot[rel] = ("symlink", os.readlink(path))
                if name in dirs:
                    dirs.remove(name)
            elif stat.S_ISREG(st.st_mode):
                with open(path, "rb") as f:
                    snapshot[rel] = ("file", stat.S_IMODE(st.st_mode), f.read())
            elif stat.S_ISDIR(st.st_mode):
                pass
            else:
                snapshot[rel] = ("other", stat.S_IFMT(st.st_mode))
    return snapshot


def test_sync_script_functionality():
    """Verify sync.py removes an old backup and copies the complete repository tree."""
    sync_script = "/home/user/sync.py"
    assert os.path.isfile(sync_script), f"Script {sync_script} does not exist."
    assert_python_file(sync_script)

    repo_path = "/home/user/deploy.git"
    backup_path = "/home/user/backup.git"

    marker = secrets.token_hex(16)
    marker_dir = os.path.join(repo_path, "verification-" + marker, "nested", "empty")
    os.makedirs(marker_dir)
    marker_file = os.path.join(os.path.dirname(marker_dir), "payload.bin")
    marker_data = os.urandom(257)
    with open(marker_file, "wb") as f:
        f.write(marker_data)

    if os.path.lexists(backup_path):
        if os.path.isdir(backup_path) and not os.path.islink(backup_path):
            import shutil
            shutil.rmtree(backup_path)
        else:
            os.unlink(backup_path)
    os.makedirs(os.path.join(backup_path, "stale", "nested"))
    stale_file = os.path.join(backup_path, "stale", "nested", marker)
    with open(stale_file, "w", encoding="utf-8") as f:
        f.write("must be removed")

    expected = tree_snapshot(repo_path)
    result = run(["/usr/bin/python3", sync_script])
    assert result.returncode == 0, f"sync.py failed to execute: {result.stderr}"

    assert os.path.isdir(backup_path), f"Backup directory {backup_path} was not created by sync.py."
    assert os.path.isdir(os.path.join(backup_path, "objects")), f"{backup_path} does not seem to contain the copied git objects."
    assert os.path.isfile(os.path.join(backup_path, "config")), f"{backup_path} does not seem to contain the copied git config."
    assert not os.path.exists(stale_file), "sync.py did not completely remove the previous backup."
    assert tree_snapshot(backup_path) == expected, "backup.git is not a complete copy of deploy.git."


def test_crontab_schedule():
    """Verify that the cron job is correctly scheduled."""
    result = run(["crontab", "-l"])
    assert result.returncode == 0, "Failed to read crontab."

    expected_command = "/usr/bin/python3 /home/user/sync.py"
    found = False
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split(None, 5)
        if len(fields) == 6 and fields[:5] == ["*/5", "*", "*", "*", "*"] and fields[5] == expected_command:
            found = True
            break

    assert found, f"Crontab does not contain the correct schedule for {expected_command}."


class MockSMTP:
    def __init__(self):
        self.messages = []
        self.lock = threading.Lock()
        self.ready = threading.Event()
        self.stop_event = threading.Event()
        self.thread = threading.Thread(target=self._serve, daemon=True)

    def start(self):
        self.thread.start()
        assert self.ready.wait(3), "Mock SMTP server did not start."

    def stop(self):
        self.stop_event.set()
        try:
            with socket.create_connection(("127.0.0.1", 2525), timeout=0.2):
                pass
        except OSError:
            pass
        self.thread.join(timeout=3)

    def count(self):
        with self.lock:
            return len(self.messages)

    def _serve(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", 2525))
        server.listen(8)
        server.settimeout(0.5)
        self.ready.set()
        try:
            while not self.stop_event.is_set():
                try:
                    conn, _ = server.accept()
                except socket.timeout:
                    continue
                try:
                    self._handle(conn)
                finally:
                    conn.close()
        finally:
            server.close()

    def _handle(self, conn):
        conn.settimeout(2)
        stream = conn.makefile("rb")
        conn.sendall(b"220 mock.smtp ESMTP\r\n")
        sender = None
        recipients = []
        while not self.stop_event.is_set():
            try:
                line = stream.readline()
            except (OSError, socket.timeout):
                return
            if not line:
                return
            command = line.decode("utf-8", "replace").rstrip("\r\n")
            upper = command.upper()
            if upper.startswith("EHLO"):
                conn.sendall(b"250-mock.smtp\r\n250 SIZE 1048576\r\n")
            elif upper.startswith("HELO"):
                conn.sendall(b"250 mock.smtp\r\n")
            elif upper.startswith("MAIL FROM:"):
                sender = command.split(":", 1)[1].strip().split()[0].strip("<>")
                conn.sendall(b"250 OK\r\n")
            elif upper.startswith("RCPT TO:"):
                recipients.append(command.split(":", 1)[1].strip().split()[0].strip("<>") )
                conn.sendall(b"250 OK\r\n")
            elif upper == "DATA":
                conn.sendall(b"354 End data with <CR><LF>.<CR><LF>\r\n")
                chunks = []
                while True:
                    data_line = stream.readline()
                    if not data_line:
                        return
                    if data_line in (b".\r\n", b".\n"):
                        break
                    if data_line.startswith(b".."):
                        data_line = data_line[1:]
                    chunks.append(data_line)
                with self.lock:
                    self.messages.append({"from": sender, "to": list(recipients), "data": b"".join(chunks)})
                conn.sendall(b"250 Message accepted\r\n")
            elif upper == "RSET":
                sender = None
                recipients = []
                conn.sendall(b"250 OK\r\n")
            elif upper == "QUIT":
                conn.sendall(b"221 Bye\r\n")
                return
            else:
                conn.sendall(b"250 OK\r\n")


def message_body(msg):
    if msg.is_multipart():
        part = msg.get_body(preferencelist=("plain",))
        value = part.get_content() if part is not None else ""
    else:
        value = msg.get_content()
    if isinstance(value, bytes):
        value = value.decode("utf-8", "replace")
    return value.rstrip("\r\n")


def test_git_hook_functionality():
    """Exercise randomized creations, updates, missing files, and multi-ref pushes."""
    smtp = MockSMTP()
    smtp.start()
    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            work = os.path.join(temp_dir, "work")
            assert run(["git", "init", work]).returncode == 0
            assert run(["git", "-C", work, "config", "user.email", "test@test.com"]).returncode == 0
            assert run(["git", "-C", work, "config", "user.name", "Test User"]).returncode == 0
            assert run(["git", "-C", work, "remote", "add", "origin", "/home/user/deploy.git"]).returncode == 0

            mounts = os.path.join(work, "mounts.fstab")
            token = secrets.token_hex(10)
            primary_ref = "refs/heads/verify-" + token

            def commit_contents(contents, message):
                if contents is None:
                    if os.path.exists(mounts):
                        os.unlink(mounts)
                    run(["git", "-C", work, "rm", "--cached", "--ignore-unmatch", "mounts.fstab"])
                else:
                    with open(mounts, "w", encoding="utf-8") as f:
                        f.write(contents)
                    assert run(["git", "-C", work, "add", "mounts.fstab"]).returncode == 0
                result = run(["git", "-C", work, "commit", "--allow-empty", "-m", message])
                assert result.returncode == 0, result.stderr
                return run(["git", "-C", work, "rev-parse", "HEAD"]).stdout.strip()

            def push(refspecs, should_succeed):
                result = run(["git", "-C", work, "push", "origin"] + refspecs)
                if should_succeed:
                    assert result.returncode == 0, f"Expected push to succeed: {result.stderr}"
                else:
                    assert result.returncode != 0, "Expected violating push to be rejected."
                return result

            valid_mount = f"device-{token} /srv/{token} ext4 defaults 0 2\n"
            first = commit_contents(valid_mount, "valid creation")
            push([f"{first}:{primary_ref}"], True)

            valid_update = commit_contents(
                f"# none /etc tmpfs defaults 0 0\n\nserver:/data\t/etc-{token}\tnfs\tro\t0\t0\n",
                "valid update",
            )
            push([f"{valid_update}:{primary_ref}"], True)

            missing = commit_contents(None, "mount file absent")
            push([f"{missing}:{primary_ref}"], True)
            assert smtp.count() == 0, "A non-violating push unexpectedly sent email."

            invalid_update = commit_contents(
                f"# randomized {token}\nnone\t/etc\ttmpfs\tdefaults\t0\t0\n",
                "invalid update",
            )
            before = smtp.count()
            push([f"{invalid_update}:{primary_ref}"], False)
            assert smtp.count() > before, "Rejecting an /etc update did not send email."

            creation_ref = "refs/heads/invalid-create-" + secrets.token_hex(8)
            before = smtp.count()
            push([f"{invalid_update}:{creation_ref}"], False)
            assert smtp.count() > before, "An /etc violation on ref creation was not rejected with email."

            assert run(["git", "-C", work, "reset", "--hard", missing]).returncode == 0
            valid_multi = commit_contents(f"dev /opt/{token} ext4 rw 0 0\n", "multi valid")
            invalid_multi = commit_contents("dev /etc ext4 ro 0 0\n", "multi invalid")
            good_ref = "refs/heads/a-good-" + secrets.token_hex(8)
            bad_ref = "refs/heads/z-bad-" + secrets.token_hex(8)
            before = smtp.count()
            push([f"{valid_multi}:{good_ref}", f"{invalid_multi}:{bad_ref}"], False)
            assert smtp.count() > before, "A violation in a multi-ref push did not send email."

        with smtp.lock:
            captured = list(smtp.messages)
        assert captured, "No SMTP message was captured."
        for item in captured:
            assert item["from"] == "git@local.system", "SMTP envelope sender is incorrect."
            assert item["to"] == ["admin@local.system"], "SMTP envelope recipient is incorrect."
            msg = email.message_from_bytes(item["data"], policy=policy.default)
            assert msg.get("Subject") == "Violation", "Email Subject must be exactly 'Violation'."
            assert message_body(msg) == "Invalid mount", "Email body must be exactly 'Invalid mount'."
    finally:
        smtp.stop()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
