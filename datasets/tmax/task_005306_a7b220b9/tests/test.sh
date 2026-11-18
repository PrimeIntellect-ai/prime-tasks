#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import pwd
import random
import re
import secrets
import shutil
import signal
import string
import subprocess
import tempfile
import time

USER = pwd.getpwnam("user")
HOME = "/home/user"
MAPPER = f"{HOME}/port_mapper.sh"
SUPERVISOR = f"{HOME}/supervise.sh"
DEPLOY = f"{HOME}/deploy.sh"
LOG = f"{HOME}/deploy.log"
CHARSET = string.ascii_lowercase + string.digits


def expected_port(username):
    return 8000 + ((sum(ord(c) for c in username) + 5842) % 1000)


def user_popen(argv, **kwargs):
    env = os.environ.copy()
    env["HOME"] = HOME
    kwargs.setdefault("env", env)
    kwargs.setdefault("user", USER.pw_uid)
    kwargs.setdefault("group", USER.pw_gid)
    kwargs.setdefault("start_new_session", True)
    return subprocess.Popen(argv, **kwargs)


def process_table():
    table = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            with open(f"/proc/{pid}/stat") as f:
                stat = f.read()
            fields = stat[stat.rfind(")") + 2:].split()
            ppid = int(fields[1])
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            table[pid] = (ppid, cmd)
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
            pass
    return table


def descendants(root_pid):
    table = process_table()
    found = set()
    changed = True
    while changed:
        changed = False
        for pid, (ppid, _) in table.items():
            if pid not in found and (ppid == root_pid or ppid in found):
                found.add(pid)
                changed = True
    return {pid: table[pid][1] for pid in found if pid in table}


def python_server_descendants(root_pid, port):
    result = {}
    for pid, cmd in descendants(root_pid).items():
        if not cmd or not any("python" in os.path.basename(x) for x in cmd[:1]):
            continue
        for i in range(len(cmd) - 2):
            if cmd[i] == "-m" and cmd[i + 1] == "http.server" and cmd[i + 2] == str(port):
                result[pid] = cmd
    return result


def http_responds(port):
    try:
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=0.5)
        conn.request("GET", "/")
        response = conn.getresponse()
        response.read(256)
        conn.close()
        return 200 <= response.status < 500
    except OSError:
        return False


def terminate_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass


def kill_matching_server(port):
    for pid, (_, cmd) in process_table().items():
        if pid == os.getpid():
            continue
        joined = " ".join(cmd)
        if "http.server" in joined and str(port) in cmd:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def wait_until(predicate, timeout, interval=0.1):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    return None


def test_port_mapper_fuzz_equivalence():
    assert os.path.isfile(MAPPER), f"Agent script missing at {MAPPER}"
    assert os.access(MAPPER, os.X_OK), f"Agent script {MAPPER} is not executable"

    random.seed(42)
    usernames = []
    for _ in range(100):
        length = random.randint(4, 12)
        usernames.append("".join(random.choice(CHARSET) for _ in range(length)))
    rng = secrets.SystemRandom()
    for _ in range(25):
        usernames.append("".join(rng.choice(CHARSET) for _ in range(rng.randint(4, 12))))

    for username in usernames:
        proc = subprocess.run(["/bin/bash", MAPPER, username], capture_output=True, text=True, timeout=3)
        assert proc.returncode == 0, f"Agent script failed on input {username!r}"
        assert proc.stderr == "", f"Mapper wrote diagnostic output for {username!r}: {proc.stderr!r}"
        assert re.fullmatch(r"[0-9]+\n?", proc.stdout), f"Mapper did not print only a port: {proc.stdout!r}"
        assert proc.stdout.strip() == str(expected_port(username)), f"Wrong port for {username!r}"

    assert subprocess.run([MAPPER], capture_output=True, timeout=3).returncode != 0
    assert subprocess.run([MAPPER, "abcd", "extra"], capture_output=True, timeout=3).returncode != 0


def test_supervise_restarts_real_http_server():
    assert os.path.isfile(SUPERVISOR), f"Supervise script missing at {SUPERVISOR}"
    assert os.access(SUPERVISOR, os.X_OK), f"Supervise script {SUPERVISOR} is not executable"

    import socket
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()

    proc = user_popen([SUPERVISOR, str(port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        first = wait_until(lambda: python_server_descendants(proc.pid, port), 6)
        assert first, "Supervisor did not launch python3 -m http.server"
        assert wait_until(lambda: http_responds(port), 4), "Launched HTTP server did not respond"

        first_pid = next(iter(first))
        os.kill(first_pid, signal.SIGKILL)
        assert wait_until(lambda: first_pid not in process_table(), 3), "Killed server did not exit"

        def replacement():
            servers = python_server_descendants(proc.pid, port)
            return servers if servers and first_pid not in servers else None

        second = wait_until(replacement, 6)
        assert second, "Supervisor did not restart the killed HTTP server"
        assert proc.poll() is None, "Supervisor exited instead of continuing indefinitely"
        assert wait_until(lambda: http_responds(port), 4), "Restarted HTTP server did not respond"
    finally:
        terminate_group(proc)
        kill_matching_server(port)


def run_deployment_case(username):
    port = expected_port(username)
    mapper_backup = tempfile.mktemp(prefix="mapper-original-", dir="/tmp")
    supervisor_backup = tempfile.mktemp(prefix="supervisor-original-", dir="/tmp")
    mapper_marker = tempfile.mktemp(prefix="mapper-called-", dir="/tmp")
    supervisor_marker = tempfile.mktemp(prefix="supervisor-called-", dir="/tmp")
    proc = None

    shutil.copy2(MAPPER, mapper_backup)
    shutil.copy2(SUPERVISOR, supervisor_backup)
    os.chmod(mapper_backup, 0o755)
    os.chmod(supervisor_backup, 0o755)

    try:
        with open(MAPPER, "w") as f:
            f.write(f'''#!/bin/bash\nprintf '%s\\n' "$1" >> {mapper_marker}\nexec {mapper_backup} "$@"\n''')
        with open(SUPERVISOR, "w") as f:
            f.write(f'''#!/bin/bash\nprintf '%s\\n' "$1" >> {supervisor_marker}\nsleep 2.4\nexec {supervisor_backup} "$@"\n''')
        os.chmod(MAPPER, 0o755)
        os.chmod(SUPERVISOR, 0o755)
        for marker in (mapper_marker, supervisor_marker):
            open(marker, "w").close()
            os.chown(marker, USER.pw_uid, USER.pw_gid)

        if os.path.exists(LOG):
            os.remove(LOG)

        proc = user_popen([DEPLOY, username], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        expected = f"Deployment successful for user: {username} on port: {port}"

        time.sleep(1.2)
        early_content = open(LOG).read() if os.path.exists(LOG) else ""
        assert expected not in early_content, "Deployment logged success before the delayed server could respond"

        rc = proc.wait(timeout=10)
        assert rc == 0, f"Deployment exited with status {rc}"
        assert wait_until(lambda: http_responds(port), 3), "Deployment exited without a responding HTTP server"

        with open(mapper_marker) as f:
            mapper_calls = f.read().splitlines()
        with open(supervisor_marker) as f:
            supervisor_calls = f.read().splitlines()
        assert username in mapper_calls, "Deployment did not use /home/user/port_mapper.sh"
        assert str(port) in supervisor_calls, "Deployment did not launch /home/user/supervise.sh with the mapped port"

        assert os.path.isfile(LOG), "Deployment log was not created"
        with open(LOG) as f:
            lines = f.read().splitlines()
        assert expected in lines, f"Exact expected log entry was not appended: {expected!r}"
        assert http_responds(port), "Background supervisor/server did not remain alive after deploy.sh exited"
    finally:
        if proc is not None:
            terminate_group(proc)
        kill_matching_server(port)
        shutil.copy2(mapper_backup, MAPPER)
        shutil.copy2(supervisor_backup, SUPERVISOR)
        os.chmod(MAPPER, 0o755)
        os.chmod(SUPERVISOR, 0o755)
        for path in (mapper_backup, supervisor_backup, mapper_marker, supervisor_marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_deploy_script_execution_and_polling():
    assert os.path.isfile(DEPLOY), f"Deploy script missing at {DEPLOY}"
    assert os.access(DEPLOY, os.X_OK), f"Deploy script {DEPLOY} is not executable"

    run_deployment_case("testuser123")
    rng = secrets.SystemRandom()
    username = "".join(rng.choice(CHARSET) for _ in range(rng.randint(4, 12)))
    run_deployment_case(username)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
