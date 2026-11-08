#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import http.client
import os
import pwd
import random
import signal
import socket
import stat
import string
import subprocess
import time

HOME = "/home/user"
PORTS = (8080, 8081, 8082)
user = pwd.getpwnam("user")


def demote():
    os.setgroups([])
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)


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

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def kill_ports():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        victims = set()
        for port in PORTS:
            victims.update(listener_pids(port))
        for pid in victims:
            if pid != os.getpid():
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        if not victims:
            return
        time.sleep(0.5)


def can_connect(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.25):
            return True
    except OSError:
        return False


def wait_port(port, timeout=15):
    end = time.time() + timeout
    while time.time() < end:
        if can_connect(port):
            return
        time.sleep(0.1)
    raise AssertionError(f"port {port} did not become available")


def wait_all_ports():
    for port in PORTS:
        wait_port(port)


def run_deploy():
    assert os.path.isfile(f"{HOME}/deploy.sh"), "deploy.sh does not exist"
    proc = subprocess.run(
        ["/bin/bash", f"{HOME}/deploy.sh"],
        cwd=HOME,
        env={**os.environ, "HOME": HOME, "USER": "user", "LOGNAME": "user"},
        preexec_fn=demote,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=45,
    )
    assert proc.returncode == 0, f"deploy.sh exited with status {proc.returncode}"
    wait_all_ports()


def request(port, path, headers=None):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=4)
    conn.request("GET", path, headers=headers or {})
    response = conn.getresponse()
    body = response.read()
    result = (response.status, body, dict(response.getheaders()))
    conn.close()
    return result


def log_lines():
    with open(f"{HOME}/proxy.log", "r") as f:
        return f.read().splitlines()


def assert_new_log_lines(before, expected):
    end = time.time() + 3
    while time.time() < end:
        after = log_lines()
        if len(after) >= len(before) + len(expected):
            break
        time.sleep(0.05)
    else:
        raise AssertionError("proxy.log did not receive the expected entries")
    assert after[:len(before)] == before, "existing proxy.log entries were altered"
    assert after[len(before):] == expected, "proxy must append exactly one correctly formatted line per request"


def assert_go_listeners():
    owners = []
    for port in PORTS:
        pids = listener_pids(port)
        assert len(pids) == 1, f"expected exactly one listening process on port {port}, found {pids}"
        pid = next(iter(pids))
        owners.append(pid)
        exe = os.path.realpath(f"/proc/{pid}/exe")
        result = subprocess.run(["go", "version", "-m", exe], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        assert result.returncode == 0 and "go1" in result.stdout, \
            f"listener on port {port} is not a compiled Go program"
    assert len(set(owners)) == 3, "the proxy and two backends must be separate running binaries"


def write_user_file(path, data, mode=0o644):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    os.write(fd, data.encode())
    os.close(fd)
    os.chown(path, user.pw_uid, user.pw_gid)
    os.chmod(path, mode)


backend_paths = [f"{HOME}/backend_v1.go", f"{HOME}/backend_v2.go"]
backups = [(open(path, "rb").read(), stat.S_IMODE(os.stat(path).st_mode)) for path in backend_paths]

try:
    assert os.path.isfile(f"{HOME}/proxy.go"), "proxy.go does not exist"
    assert os.path.isfile(f"{HOME}/deploy.sh"), "deploy.sh does not exist"

    # Execute the submitted proxy independently and verify that it really blocks
    # until the two readiness markers occur on separate lines.
    kill_ports()
    sync_binary = f"/tmp/verifier_proxy_{os.getpid()}"
    build = subprocess.run(
        ["go", "build", "-o", sync_binary, f"{HOME}/proxy.go"],
        cwd=HOME,
        env={**os.environ, "HOME": HOME},
        preexec_fn=demote,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=45,
    )
    assert build.returncode == 0, "proxy.go does not compile:\n" + build.stdout
    write_user_file(f"{HOME}/startup.txt", "v1_ready v2_ready\n")
    write_user_file(f"{HOME}/proxy.log", "", 0o640)
    proxy_proc = subprocess.Popen([sync_binary], cwd=HOME, preexec_fn=demote,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1.5)
        assert proxy_proc.poll() is None, "proxy exited while waiting for dependencies"
        assert not can_connect(8080), "proxy bound before readiness markers appeared on separate lines"
        write_user_file(f"{HOME}/startup.txt", "v1_ready\nv2_ready\n")
        wait_port(8080, 12)
    finally:
        if proxy_proc.poll() is None:
            proxy_proc.terminate()
            try:
                proxy_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proxy_proc.kill()
        try:
            os.unlink(sync_binary)
        except FileNotFoundError:
            pass
    kill_ports()

    # Execute deploy.sh against the supplied backends and retain all original checks.
    for generated in (f"{HOME}/startup.txt", f"{HOME}/proxy.log"):
        try:
            os.unlink(generated)
        except FileNotFoundError:
            pass
    run_deploy()

    startup_file = f"{HOME}/startup.txt"
    assert os.path.isfile(startup_file), "startup.txt does not exist"
    with open(startup_file, "r") as f:
        startup_content = f.read()
    assert "v1_ready" in startup_content, "startup.txt missing 'v1_ready'"
    assert "v2_ready" in startup_content, "startup.txt missing 'v2_ready'"
    startup_lines = startup_content.splitlines()
    assert "v1_ready" in startup_lines and "v2_ready" in startup_lines, \
        "readiness markers must be written as separate lines"

    log_file = f"{HOME}/proxy.log"
    assert os.path.isfile(log_file), "proxy.log does not exist"
    perms = stat.S_IMODE(os.stat(log_file).st_mode)
    assert perms == 0o640, f"proxy.log permissions are {oct(perms)}, expected 0o640"

    body_v1 = request(8080, "/data1")[1].decode()
    assert "Legacy v1 Response: /data1" in body_v1, \
        "v1 routing failed or returned incorrect response"
    body_v2 = request(8080, "/data2", {"X-API-Version": "v2"})[1].decode()
    assert "New v2 Response: /data2" in body_v2, \
        "v2 routing failed or returned incorrect response"
    current_log = "\n".join(log_lines())
    assert "v1 /data1" in current_log, "proxy.log missing v1 entry"
    assert "v2 /data2" in current_log, "proxy.log missing v2 entry"
    assert_go_listeners()

    # Replace backend source only at verification time with unpredictable behavior.
    # A valid deployment must compile these paths, and the proxy must forward their
    # exact status, body, and headers rather than synthesize fixed responses.
    kill_ports()
    token = "".join(random.SystemRandom().choices(string.ascii_letters + string.digits, k=24))
    for index, (path, version, port, status) in enumerate([
        (backend_paths[0], "v1", 8081, 201),
        (backend_paths[1], "v2", 8082, 202),
    ]):
        source = f'''package main
import ("fmt"; "net/http")
func main() {{
 http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {{
  w.Header().Set("X-Verifier-Backend", "{token}-{version}")
  w.WriteHeader({status})
  fmt.Fprintf(w, "{token}|{version}|%s|%s|%s", r.Method, r.URL.RequestURI(), r.Header.Get("X-Challenge"))
 }})
 http.ListenAndServe("127.0.0.1:{port}", nil)
}}
'''
        with open(path, "w") as f:
            f.write(source)
        os.chmod(path, backups[index][1])

    run_deploy()
    assert stat.S_IMODE(os.stat(log_file).st_mode) == 0o640, \
        "deploy.sh did not recreate proxy.log with mode 640"
    assert_go_listeners()

    nonce = "".join(random.SystemRandom().choices(string.ascii_lowercase + string.digits, k=16))
    cases = [
        (f"/verify/{nonce}/legacy", {"X-Challenge": nonce}, 8081, "v1"),
        (f"/verify/{nonce}/default", {"X-API-Version": "V2", "X-Challenge": nonce + "x"}, 8081, "v1"),
        (f"/verify/{nonce}/new", {"X-API-Version": "v2", "X-Challenge": nonce + "y"}, 8082, "v2"),
    ]
    before = log_lines()
    expected_logs = []
    for path, headers, backend_port, version in cases:
        direct = request(backend_port, path, headers)
        proxied = request(8080, path, headers)
        assert proxied[0] == direct[0], f"proxy did not forward backend status for {path}"
        assert proxied[1] == direct[1], f"proxy did not return the exact backend body for {path}"
        header_name = "X-Verifier-Backend"
        assert proxied[2].get(header_name) == direct[2].get(header_name), \
            f"proxy did not forward backend headers for {path}"
        expected_logs.append(f"{version} {path}")
    assert_new_log_lines(before, expected_logs)

finally:
    kill_ports()
    for path, (content, mode) in zip(backend_paths, backups):
        with open(path, "wb") as f:
            f.write(content)
        os.chmod(path, mode)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
