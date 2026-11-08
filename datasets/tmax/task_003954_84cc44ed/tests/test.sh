#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import random
import string
import tempfile
import shutil
import threading
import queue
import uuid
import signal
import pytest


def oracle_converter(input_str):
    output = []
    for line in input_str.splitlines():
        if line.startswith("COMMIT:"):
            output.append(f"TRANSACTION START {line[7:]}")
        elif line.startswith("AUTHOR:"):
            output.append(f"SET_USER {line[7:]}")
        else:
            m = re.match(r"^([AMD])\s+(.+)$", line)
            if m:
                op, filename = m.groups()
                if op == "A":
                    output.append(f"FILE_ADD {filename}")
                elif op == "M":
                    output.append(f"FILE_MOD {filename}")
                elif op == "D":
                    output.append(f"FILE_DEL {filename}")
    return "\n".join(output) + ("\n" if output else "")


def generate_fuzz_input(seed):
    random.seed(seed)
    lines = []
    for _ in range(random.randint(5, 20)):
        choice = random.choice(["COMMIT", "AUTHOR", "AMD", "GARBAGE", "BLANK"])
        if choice == "COMMIT":
            h = "".join(random.choices("0123456789abcdef", k=random.randint(6, 40)))
            lines.append(f"COMMIT:{h}")
        elif choice == "AUTHOR":
            name = "".join(random.choices(string.ascii_letters + " ", k=random.randint(3, 15)))
            lines.append(f"AUTHOR:{name}")
        elif choice == "AMD":
            op = random.choice(["A", "M", "D"])
            fname = "".join(random.choices(string.ascii_letters + "._", k=random.randint(5, 15)))
            lines.append(f"{op}\t{fname}")
            lines.append(f"{op}       {fname}")
        elif choice == "GARBAGE":
            garbage = "".join(random.choices(string.printable, k=random.randint(5, 20))).replace("\n", "")
            lines.append(garbage)
        else:
            lines.append("")
    return "\n".join(lines) + "\n"


def test_fuzz_protocol_converter():
    agent_script = "/home/user/protocol_converter.py"
    assert os.path.isfile(agent_script), f"{agent_script} is missing."
    for i in range(100):
        input_data = generate_fuzz_input(i)
        expected_output = oracle_converter(input_data)
        proc = subprocess.run(
            ["python3", agent_script], input=input_data.encode(), capture_output=True
        )
        assert proc.returncode == 0, (
            f"Script failed on input:\n{input_data}\nError:\n{proc.stderr.decode()}"
        )
        actual_output = proc.stdout.decode()
        assert actual_output == expected_output, (
            f"Mismatch on input:\n{input_data}\nExpected:\n{expected_output}"
            f"\nActual:\n{actual_output}"
        )


def running_socat_proxy():
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            raw = open(f"/proc/{pid}/cmdline", "rb").read()
            args = [x.decode(errors="replace") for x in raw.split(b"\0") if x]
        except (OSError, PermissionError):
            continue
        if not args or os.path.basename(args[0]) != "socat":
            continue
        command = " ".join(args)
        if "9999" in command and "8888" in command and "LISTEN" in command.upper():
            return True
    return False


def test_proxy_running():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    result = sock.connect_ex(("127.0.0.1", 9999))
    sock.close()
    assert result == 0, "Proxy is not listening on localhost:9999."
    assert running_socat_proxy(), "The listener on port 9999 is not the required socat proxy to port 8888."


def test_logrotate_conf():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_path), f"{conf_path} is missing."
    with open(conf_path) as f:
        content = f.read()
    assert re.search(r"\bdaily\b", content), "logrotate.conf missing 'daily'"
    assert re.search(r"\brotate\s+5\b", content), "logrotate.conf missing 'rotate 5'"
    assert re.search(r"\bcompress\b", content), "logrotate.conf missing 'compress'"
    assert re.search(r"\bnotifempty\b", content), "logrotate.conf missing 'notifempty'"


def kill_port_8888_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[-1].upper() == "22B8" and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass
    victims = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(pid))
        except OSError:
            continue
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        import time
        time.sleep(0.3)


def strict_backend(expected_commands, result_queue, ready):
    transcript = []
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind(("127.0.0.1", 8888))
        server.listen(1)
        server.settimeout(15)
        ready.set()
        client, _ = server.accept()
        with client:
            client.settimeout(10)
            stream = client.makefile("rb")

            def receive():
                data = stream.readline()
                if not data:
                    raise AssertionError("Legacy client disconnected before completing the protocol")
                value = data.decode("utf-8", errors="strict").rstrip("\r\n")
                transcript.append(value)
                return value

            client.sendall(b"LOGIN:\n")
            assert receive() == "admin", f"Incorrect legacy username: {transcript[-1]!r}"
            client.sendall(b"PASSWORD:\n")
            assert receive() == "legacy_secret", "Incorrect legacy password"
            client.sendall(b"READY>\n")
            for expected in expected_commands:
                actual = receive()
                assert actual == expected, f"Expected command {expected!r}, got {actual!r}"
                client.sendall(b"OK\n")
            assert receive() == "LOGOUT", "Legacy session did not end with LOGOUT"
        result_queue.put((True, transcript))
    except BaseException as exc:
        ready.set()
        result_queue.put((False, repr(exc)))
    finally:
        server.close()


def test_end_to_end_git_push():
    central_repo = "/home/user/central.git"
    hook = os.path.join(central_repo, "hooks", "post-receive")
    converter = "/home/user/protocol_converter.py"
    sender = "/home/user/send_to_legacy.exp"
    log_file = "/home/user/logs/legacy_sync.log"

    assert os.path.isdir(central_repo), f"{central_repo} is missing."
    bare = subprocess.run(
        ["git", "--git-dir", central_repo, "rev-parse", "--is-bare-repository"],
        capture_output=True, text=True
    )
    assert bare.returncode == 0 and bare.stdout.strip() == "true", "central.git is not a bare Git repository"
    assert os.path.isfile(hook), "post-receive hook is missing"
    assert os.access(hook, os.X_OK), "post-receive hook is not executable"
    assert os.path.isfile(sender), f"{sender} is missing."
    assert os.access(sender, os.X_OK), f"{sender} is not executable."

    kill_port_8888_listeners()

    converter_backup = "/tmp/verifier_protocol_converter.py"
    sender_backup = "/tmp/verifier_send_to_legacy.exp"
    converter_marker = "/tmp/verifier_converter_called"
    sender_marker = "/tmp/verifier_sender_called"
    for path in (converter_marker, sender_marker):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    shutil.copy2(converter, converter_backup)
    shutil.copy2(sender, sender_backup)

    with open(converter, "w") as f:
        f.write("#!/usr/bin/python3\n")
        f.write("import os\n")
        f.write(f"open({converter_marker!r}, 'a').write('called\\n')\n")
        f.write(f"os.execv('/usr/bin/python3', ['python3', {converter_backup!r}])\n")
    os.chmod(converter, 0o755)

    with open(sender, "w") as f:
        f.write("#!/usr/bin/expect -f\n")
        f.write(f"set marker [open \"{sender_marker}\" a]\n")
        f.write("puts $marker called\nclose $marker\n")
        f.write(f"set cmd [list /usr/bin/expect \"{sender_backup}\"]\n")
        f.write("foreach arg $argv { lappend cmd $arg }\n")
        f.write("set failed [catch {exec {*}$cmd <@stdin >@stdout 2>@stderr} message]\n")
        f.write("if {$failed} { puts stderr $message; exit 1 }\n")
    os.chmod(sender, 0o755)

    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    open(log_file, "w").close()

    result_queue = queue.Queue()
    ready = threading.Event()
    branch = "verify-" + uuid.uuid4().hex

    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            subprocess.run(["git", "clone", central_repo, tmpdir], check=True, capture_output=True)
            subprocess.run(["git", "checkout", "--orphan", branch], cwd=tmpdir, check=True, capture_output=True)
            subprocess.run(["git", "rm", "-rf", "."], cwd=tmpdir, capture_output=True)
            with open(os.path.join(tmpdir, "test_file.txt"), "w") as f:
                f.write("test content " + uuid.uuid4().hex + "\n")
            subprocess.run(["git", "config", "user.name", "Test User"], cwd=tmpdir, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=tmpdir, check=True)
            subprocess.run(["git", "add", "test_file.txt"], cwd=tmpdir, check=True)
            subprocess.run(["git", "commit", "-m", "add test file"], cwd=tmpdir, check=True, capture_output=True)
            commit_hash = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=tmpdir, text=True).strip()

            expected = [
                f"TRANSACTION START {commit_hash}",
                "SET_USER Test User",
                "FILE_ADD test_file.txt",
            ]
            thread = threading.Thread(target=strict_backend, args=(expected, result_queue, ready), daemon=True)
            thread.start()
            assert ready.wait(3), "Test legacy backend did not start"

            proc_push = subprocess.run(
                ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
                cwd=tmpdir, capture_output=True, timeout=20
            )
            assert proc_push.returncode == 0, f"Git push failed: {proc_push.stderr.decode()}"
            thread.join(12)
            assert not thread.is_alive(), "Legacy interaction did not complete"
            ok, detail = result_queue.get_nowait()
            assert ok, f"Incorrect legacy protocol interaction: {detail}"
    finally:
        shutil.copy2(converter_backup, converter)
        shutil.copy2(sender_backup, sender)

    assert os.path.isfile(converter_marker), "The post-receive hook did not invoke protocol_converter.py"
    assert os.path.isfile(sender_marker), "The post-receive hook did not invoke send_to_legacy.exp"
    assert os.path.isfile(log_file), f"{log_file} is missing after push."
    with open(log_file) as f:
        log_content = f.read()
    assert "LOGIN:" in log_content, "Log missing LOGIN prompt"
    assert "PASSWORD:" in log_content, "Log missing PASSWORD prompt"
    assert "READY>" in log_content, "Log missing READY prompt"
    assert "TRANSACTION START" in log_content, "Log missing TRANSACTION START"
    assert "SET_USER Test User" in log_content, "Log missing SET_USER"
    assert "FILE_ADD test_file.txt" in log_content, "Log missing FILE_ADD"
    assert "LOGOUT" in log_content, "Log missing LOGOUT"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
