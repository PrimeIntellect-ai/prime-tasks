#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import http.client
import os
import pathlib
import pwd
import re
import socket
import stat
import subprocess
import sys
import tempfile
import urllib.request
import uuid

USER = "user"
UID = pwd.getpwnam(USER).pw_uid


def fetch(path="/ping"):
    try:
        res = urllib.request.urlopen("http://127.0.0.1:8080" + path, timeout=2)
        return res.getcode(), res.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except Exception:
        return 0, b""


def user_systemctl(*args, check=True):
    runtime = f"/run/user/{UID}"
    env = os.environ.copy()
    env["XDG_RUNTIME_DIR"] = runtime
    env["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={runtime}/bus"
    return subprocess.run(
        ["runuser", "-u", USER, "--", "systemctl", "--user", *args],
        capture_output=True, text=True, check=check, env=env, timeout=15
    )


def proc_uid(pid):
    return os.stat(f"/proc/{pid}").st_uid


def proc_cmdline(pid):
    try:
        return pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
    except (FileNotFoundError, PermissionError):
        return ""


def proc_environ(pid):
    try:
        data = pathlib.Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
        return {x.split(b"=", 1)[0].decode(errors="replace"): x.split(b"=", 1)[1].decode(errors="replace")
                for x in data if b"=" in x}
    except (FileNotFoundError, PermissionError):
        return {}


def descendants(root):
    found = {root}
    changed = True
    while changed:
        changed = False
        for entry in pathlib.Path("/proc").iterdir():
            if not entry.name.isdigit() or int(entry.name) in found:
                continue
            try:
                fields = (entry / "stat").read_text().split()
                ppid = int(fields[3])
            except (FileNotFoundError, PermissionError, ValueError, IndexError):
                continue
            if ppid in found:
                found.add(int(entry.name))
                changed = True
    return found


def unix_request(sock_path, path):
    class UnixConnection(http.client.HTTPConnection):
        def connect(self):
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.settimeout(2)
            self.sock.connect(sock_path)
    conn = UnixConnection("localhost", timeout=2)
    conn.request("GET", path, headers={"Host": "localhost"})
    response = conn.getresponse()
    body = response.read()
    status = response.status
    conn.close()
    return status, body


def listener_inodes():
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except FileNotFoundError:
            continue
        for line in lines:
            cols = line.split()
            local, state = cols[1], cols[3]
            addr, port = local.rsplit(":", 1)
            if int(port, 16) != 8080 or state != "0A":
                continue
            if table.endswith("tcp") and addr != "0100007F":
                continue
            result.add(cols[9])
    return result


def pids_holding_inodes(inodes):
    holders = set()
    for entry in pathlib.Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            for fd in (entry / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except (FileNotFoundError, PermissionError, OSError):
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    holders.add(int(entry.name))
        except (FileNotFoundError, PermissionError):
            pass
    return holders


def test_load_balancer_success_rate():
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        results = list(executor.map(lambda _: 1 if fetch()[0] == 200 else 0, range(100)))
    success_rate = sum(results) / len(results)
    assert success_rate >= 0.95, f"Success rate is {success_rate}, expected >= 0.95"
    random_path = "/verifier-" + uuid.uuid4().hex
    assert fetch(random_path)[0] == 404, "The public listener is not proxying the vendored application's routing behavior"


def test_gunicorn_conf_fixed():
    path = "/app/backend-api-2.1/gunicorn_conf.py"
    assert os.path.isfile(path), f"File {path} does not exist."
    content = pathlib.Path(path).read_text()
    assert "BIND_SOCKET" in content, f"File {path} does not use the BIND_SOCKET environment variable."
    for value in (f"/tmp/check-{uuid.uuid4().hex}.sock", f"unix:/tmp/check-{uuid.uuid4().hex}.sock"):
        code = "import runpy,sys; d=runpy.run_path(sys.argv[1]); print(d.get('bind'))"
        env = os.environ.copy()
        env["BIND_SOCKET"] = value
        result = subprocess.run([sys.executable, "-c", code, path], env=env, capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == value, "gunicorn_conf.py does not dynamically use the supplied BIND_SOCKET value"


def test_sockets_exist_and_serve_application():
    for sock in ("/tmp/backend_1.sock", "/tmp/backend_2.sock"):
        assert os.path.exists(sock), f"Socket {sock} does not exist. Is the service running?"
        assert stat.S_ISSOCK(os.stat(sock).st_mode), f"Path {sock} exists but is not a socket."
        status, body = unix_request(sock, "/ping")
        assert status == 200 and body == b"pong", f"{sock} is not serving the vendored application"
        assert unix_request(sock, "/missing-" + uuid.uuid4().hex)[0] == 404


def test_user_systemd_gunicorn_services_active_and_persistent():
    listed = user_systemctl("list-units", "--type=service", "--state=active", "--no-legend", "--plain").stdout
    units = [line.split()[0] for line in listed.splitlines() if line.split()]
    assert units, "No active user-level systemd services were found"

    matched = {}
    for unit in units:
        show = user_systemctl("show", unit, "--property=MainPID", "--value", check=False)
        if show.returncode != 0:
            continue
        try:
            main_pid = int(show.stdout.strip())
        except ValueError:
            continue
        if main_pid <= 0:
            continue
        for pid in descendants(main_pid):
            env = proc_environ(pid)
            cmd = proc_cmdline(pid).lower()
            target = env.get("BIND_SOCKET")
            if target in ("/tmp/backend_1.sock", "/tmp/backend_2.sock") and "gunicorn" in cmd:
                assert proc_uid(pid) == UID, f"Gunicorn for {target} is not running as user {USER}"
                matched[target] = unit

    assert set(matched) == {"/tmp/backend_1.sock", "/tmp/backend_2.sock"}, \
        "Both sockets must be served by Gunicorn processes managed by active user systemd services"
    assert len(set(matched.values())) == 2, "The two backend instances must be separate systemd service instances"
    for unit in set(matched.values()):
        enabled = user_systemctl("is-enabled", unit, check=False)
        assert enabled.returncode == 0 and enabled.stdout.strip() == "enabled", f"{unit} is not enabled persistently"


def test_nginx_config_exists_and_is_active_load_balancer():
    path = "/home/user/nginx.conf"
    assert os.path.isfile(path), f"Nginx configuration file {path} does not exist."
    result = subprocess.run(["runuser", "-u", USER, "--", "nginx", "-t", "-c", path],
                            capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr

    text = re.sub(r"#.*", "", pathlib.Path(path).read_text())
    assert re.search(r"listen\s+127\.0\.0\.1:8080\s*;", text), "Nginx is not configured for 127.0.0.1:8080"
    upstreams = re.findall(r"upstream\s+\w+\s*\{(.*?)\}", text, flags=re.S)
    assert any("unix:/tmp/backend_1.sock" in block and "unix:/tmp/backend_2.sock" in block for block in upstreams), \
        "An Nginx upstream must contain both backend Unix sockets"
    relevant = next(block for block in upstreams if "unix:/tmp/backend_1.sock" in block and "unix:/tmp/backend_2.sock" in block)
    assert not re.search(r"\b(weight|backup|down)\b", relevant), "The two backends are not configured with equal status"
    assert re.search(r"proxy_pass\s+http://", text), "Nginx is not configured as a reverse proxy"

    inodes = listener_inodes()
    assert inodes, "Nothing is listening on 127.0.0.1:8080"
    holders = pids_holding_inodes(inodes)
    nginx_holders = [pid for pid in holders if "nginx" in proc_cmdline(pid).lower()]
    assert nginx_holders, "The port 8080 listener is not Nginx"
    assert all(proc_uid(pid) == UID for pid in nginx_holders), "Nginx is not running as the non-root user"
    assert any(path in proc_cmdline(pid) for pid in nginx_holders), "The running Nginx is not using /home/user/nginx.conf"


def run_monitor(extra_pythonpath=None):
    env = os.environ.copy()
    if extra_pythonpath:
        env["PYTHONPATH"] = extra_pythonpath
    return subprocess.run(["runuser", "-u", USER, "--", "env", *[f"{k}={v}" for k, v in env.items()],
                           sys.executable, "/home/user/monitor.py"], capture_output=True, text=True, timeout=10)


def test_monitor_script_exists_and_behaves():
    path = "/home/user/monitor.py"
    assert os.path.isfile(path), f"Monitoring script {path} does not exist."
    source = pathlib.Path(path).read_text()
    assert "http://127.0.0.1:8080/ping" in source, "monitor.py does not check the required endpoint"
    assert "/home/user/uptime.log" in source, "monitor.py does not write the required log"

    log = pathlib.Path("/home/user/uptime.log")
    log.touch(exist_ok=True)
    os.chown(log, UID, pwd.getpwnam(USER).pw_gid)
    os.chmod(log, 0o664)
    log.write_text("")
    ok = run_monitor()
    assert ok.returncode == 0, ok.stderr
    assert "UP" in [line.strip() for line in log.read_text().splitlines()], "monitor.py did not append UP for HTTP 200"

    with tempfile.TemporaryDirectory() as temp:
        pathlib.Path(temp, "sitecustomize.py").write_text(
            "import socket\n"
            "_S=socket.socket\n"
            "class FailingSocket(_S):\n"
            "    def connect(self, *a, **k): raise OSError('verification-forced connection failure')\n"
            "socket.socket=FailingSocket\n"
            "def _fail(*a, **k): raise OSError('verification-forced connection failure')\n"
            "socket.create_connection=_fail\n"
        )
        failed = run_monitor(temp)
    assert failed.returncode == 0, failed.stderr
    assert "DOWN" in [line.strip() for line in log.read_text().splitlines()], "monitor.py did not append DOWN on connection failure"


def test_cron_job_exists_for_user():
    result = subprocess.run(["crontab", "-u", USER, "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read user user's crontab. Has it been set up?"
    jobs = [line.strip() for line in result.stdout.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    assert any(line.split(None, 5)[:5] == ["*", "*", "*", "*", "*"] and
               len(line.split(None, 5)) == 6 and "/home/user/monitor.py" in line.split(None, 5)[5]
               for line in jobs), "An every-minute cron job for /home/user/monitor.py was not found in user user's crontab"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
