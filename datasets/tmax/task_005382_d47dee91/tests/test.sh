#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import shlex
import socket
import string
import subprocess
import time
import pytest

AGENT = "/home/user/new_filter"
UNIT = "/home/user/.config/systemd/user/log-filter.service"


def generate_fuzz_input():
    length = random.randint(50, 200)
    prefixes = [
        "Jan 01 12:34:56 host process[123]: ",
        "2023-10-12T15:20:30Z host process: ",
        "Invalid timestamp host: ",
        "Dec 32 25:61:99 host app: ",
        ""
    ]
    prefix = random.choice(prefixes)
    charset = string.ascii_letters + string.digits + string.punctuation + " "
    body_length = max(0, length - len(prefix))
    body = "".join(random.choices(charset, k=body_length))
    return prefix + body


def test_fuzz_equivalence():
    oracle = "/app/legacy_filter.sh"
    agent = AGENT

    assert os.path.exists(agent), f"Agent program {agent} does not exist."
    assert os.access(agent, os.X_OK), f"Agent program {agent} is not executable."
    with open(agent, "rb") as f:
        assert f.read(4) == b"\x7fELF", "new_filter is not a compiled native executable."
    assert os.path.isfile("/home/user/new_filter.rs"), "Rust source /home/user/new_filter.rs is missing."

    random.seed(42)
    for i in range(1000):
        inp = generate_fuzz_input()
        oracle_proc = subprocess.run([oracle], input=inp, text=True, capture_output=True, timeout=5)
        agent_proc = subprocess.run([agent], input=inp, text=True, capture_output=True, timeout=5)
        if oracle_proc.stdout != agent_proc.stdout:
            pytest.fail(
                f"Mismatch on input {i}:\n"
                f"Input: {repr(inp)}\n"
                f"Oracle output: {repr(oracle_proc.stdout)}\n"
                f"Agent output: {repr(agent_proc.stdout)}"
            )


def execstart_commands(path):
    commands = []
    section = None
    pending = ""
    with open(path, encoding="utf-8") as f:
        physical = f.readlines()
    logical = []
    for line in physical:
        line = line.rstrip("\n")
        pending += line
        if pending.endswith("\\"):
            pending = pending[:-1]
            continue
        logical.append(pending)
        pending = ""
    if pending:
        logical.append(pending)
    for raw in logical:
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            continue
        if section == "Service" and "=" in line:
            key, value = line.split("=", 1)
            if key.strip() == "ExecStart" and value.strip():
                commands.append(value.strip())
    return commands


def user_systemctl(*args):
    u = pwd.getpwnam("user")
    runtime = f"/run/user/{u.pw_uid}"
    bus = os.path.join(runtime, "bus")
    assert os.path.exists(bus), "The user systemd manager is not running; the service was not reloaded/restarted."
    env = os.environ.copy()
    env.update({
        "HOME": u.pw_dir,
        "USER": u.pw_name,
        "LOGNAME": u.pw_name,
        "XDG_RUNTIME_DIR": runtime,
        "DBUS_SESSION_BUS_ADDRESS": f"unix:path={bus}",
    })

    def demote():
        os.setgroups([])
        os.setgid(u.pw_gid)
        os.setuid(u.pw_uid)

    return subprocess.run(
        ["systemctl", "--user", *args], text=True, capture_output=True,
        timeout=15, env=env, preexec_fn=demote
    )


def test_systemd_service_updated():
    path = UNIT
    assert os.path.exists(path), f"Service file {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "/home/user/new_filter" in content, "The systemd service ExecStart was not updated to use /home/user/new_filter."

    commands = execstart_commands(path)
    assert len(commands) == 1, "The service must have exactly one non-empty ExecStart directive."
    argv = shlex.split(commands[0])
    assert argv, "ExecStart is empty."
    executable = argv[0].lstrip("-@:+!")
    assert executable == AGENT, f"ExecStart actually launches {executable!r}, not {AGENT}."
    assert "/app/legacy_filter.sh" not in argv, "ExecStart still invokes the legacy filter."


def test_systemd_service_can_be_reloaded_and_restarted():
    reload_proc = user_systemctl("daemon-reload")
    assert reload_proc.returncode == 0, f"systemd user daemon-reload failed: {reload_proc.stderr}"

    fragment = user_systemctl("show", "log-filter.service", "-p", "FragmentPath", "--value")
    assert fragment.returncode == 0, fragment.stderr
    assert os.path.realpath(fragment.stdout.strip()) == os.path.realpath(UNIT), "systemd did not load the required user unit."

    loaded_exec = user_systemctl("show", "log-filter.service", "-p", "ExecStart", "--value")
    assert loaded_exec.returncode == 0, loaded_exec.stderr
    assert re.search(r"(?:path=|argv\[\]=)/home/user/new_filter(?:[ ;]|$)", loaded_exec.stdout), \
        f"systemd's loaded ExecStart does not launch new_filter: {loaded_exec.stdout!r}"

    restart = user_systemctl("restart", "log-filter.service")
    assert restart.returncode == 0, f"systemd user service restart failed: {restart.stderr}"
    result = user_systemctl("show", "log-filter.service", "-p", "Result", "--value")
    status = user_systemctl("show", "log-filter.service", "-p", "ExecMainStatus", "--value")
    assert result.returncode == 0 and result.stdout.strip() == "success", f"Service result was not successful: {result.stdout} {result.stderr}"
    assert status.returncode == 0 and status.stdout.strip() == "0", f"new_filter exited unsuccessfully: {status.stdout} {status.stderr}"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            for fd in os.listdir(f"/proc/{name}/fd"):
                target = os.readlink(f"/proc/{name}/fd/{fd}")
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.append(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def redis_reply(stream):
    first = stream.read(1)
    assert first, "Redis tunnel closed unexpectedly."
    line = stream.readline().rstrip(b"\r\n")
    if first == b"+":
        return line
    if first == b"$":
        length = int(line)
        if length == -1:
            return None
        data = stream.read(length)
        assert stream.read(2) == b"\r\n"
        return data
    if first == b"-":
        pytest.fail(f"Redis returned an error through the tunnel: {line!r}")
    pytest.fail(f"Unexpected Redis response through tunnel: {first + line!r}")


def resp_command(*parts):
    encoded = [p if isinstance(p, bytes) else str(p).encode() for p in parts]
    return b"*%d\r\n" % len(encoded) + b"".join(
        b"$%d\r\n%s\r\n" % (len(p), p) for p in encoded
    )


def test_ssh_tunnel_active():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2)
        result = s.connect_ex(("127.0.0.1", 9999))
        assert result == 0, "Port 9999 is not open. The SSH tunnel to Redis is likely not active."

    pids = listener_pids(9999)
    assert pids, "No process owns the listening socket on port 9999."
    valid_ssh = False
    user_uid = pwd.getpwnam("user").pw_uid
    for pid in pids:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            uid = os.stat(f"/proc/{pid}").st_uid
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if not argv or os.path.basename(argv[0]) != "ssh":
            continue
        specs = []
        identities = []
        for i, arg in enumerate(argv[1:]):
            if arg == "-L" and i + 2 <= len(argv) - 1:
                specs.append(argv[i + 2])
            elif arg.startswith("-L") and len(arg) > 2:
                specs.append(arg[2:])
            if arg == "-i" and i + 2 <= len(argv) - 1:
                identities.append(argv[i + 2])
            elif arg.startswith("-i") and len(arg) > 2:
                identities.append(arg[2:])
        correct_forward = any(re.search(r"(?:^|:)9999:localhost:6379$", spec) for spec in specs)
        correct_key = (uid == user_uid and not identities) or any(
            os.path.realpath(key).startswith("/home/user/.ssh/") and os.path.isfile(key)
            for key in identities
        )
        if correct_forward and correct_key:
            valid_ssh = True
            break
    assert valid_ssh, "Port 9999 is not owned by an SSH process forwarding 9999 to localhost:6379 with the user's SSH key."

    marker = f"verifier:{os.getpid()}:{time.time_ns()}"
    value = os.urandom(24).hex()
    with socket.create_connection(("127.0.0.1", 9999), timeout=3) as sock:
        sock.settimeout(3)
        stream = sock.makefile("rwb", buffering=0)
        stream.write(resp_command("PING"))
        assert redis_reply(stream) == b"PONG", "Port 9999 does not forward to a Redis server."
        stream.write(resp_command("SET", marker, value, "EX", "30"))
        assert redis_reply(stream) == b"OK", "Could not write to Redis through the SSH tunnel."
        stream.write(resp_command("GET", marker))
        assert redis_reply(stream) == value.encode(), "Redis data did not round-trip through the SSH tunnel."
        stream.write(resp_command("DEL", marker))
        redis_reply(stream)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
