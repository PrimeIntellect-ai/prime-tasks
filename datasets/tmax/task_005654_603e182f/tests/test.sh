#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import configparser
import http.client
import os
import pwd
import secrets
import shlex
import shutil
import socket
import ssl
import subprocess
import tempfile
import time

HOME = "/home/user"


def require(condition, message):
    assert condition, message


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def proc_cmdline(pid):
    try:
        data = open(f"/proc/{pid}/cmdline", "rb").read()
        return [x.decode("utf-8", "replace") for x in data.rstrip(b"\0").split(b"\0")]
    except OSError:
        return []


def proc_state(pid):
    try:
        return open(f"/proc/{pid}/stat", "r").read().split()[2]
    except OSError:
        return None


def descendants(root_pid):
    parent = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            fields = open(f"/proc/{name}/stat", "r").read().split()
            parent[int(name)] = int(fields[3])
        except (OSError, ValueError, IndexError):
            pass
    found = set()
    changed = True
    while changed:
        changed = False
        for pid, ppid in parent.items():
            if pid not in found and (ppid == root_pid or ppid in found):
                found.add(pid)
                changed = True
    return found


def wait_for_port(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError(f"Port {port} is not accepting connections")


def fetch_log(port):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    conn = http.client.HTTPSConnection("127.0.0.1", port, context=ctx, timeout=5)
    try:
        conn.request("GET", "/alerts.log")
        response = conn.getresponse()
        body = response.read().decode("utf-8")
        require(response.status == 200, f"HTTPS request through port {port} returned {response.status}")
        return body
    finally:
        conn.close()


def test_files_build_and_configuration():
    required_dirs = ["src", "bin", "data_drop", "alerts", "certs"]
    for name in required_dirs:
        require(os.path.isdir(os.path.join(HOME, name)), f"Missing directory {name}")

    source = os.path.join(HOME, "src/monitor.cpp")
    deploy = os.path.join(HOME, "deploy.sh")
    binary = os.path.join(HOME, "bin/fs_monitor")
    server = os.path.join(HOME, "server.py")
    config = os.path.join(HOME, "supervisord.conf")
    cert = os.path.join(HOME, "certs/cert.pem")
    key = os.path.join(HOME, "certs/key.pem")

    for path in [source, deploy, binary, server, config, cert, key]:
        require(os.path.isfile(path), f"Required file is missing: {path}")
    require(os.access(deploy, os.X_OK), "deploy.sh is not executable")
    require(os.access(binary, os.X_OK), "fs_monitor is not executable")
    require(open(binary, "rb").read(4) == b"\x7fELF", "fs_monitor is not an ELF executable")

    src = read_text(source)
    require("IN_CREATE" in src, "monitor.cpp does not request IN_CREATE events")
    require("inotify_add_watch" in src, "monitor.cpp does not install an inotify watch")
    require("inotify_init" in src, "monitor.cpp does not initialize inotify")
    require(".dat" in src, "monitor.cpp does not contain the required .dat filtering")
    require("new_data" in src and "alerts.log" in src, "monitor.cpp lacks the required alert output")
    require("flush" in src or "endl" in src, "monitor.cpp does not visibly flush each alert")

    deploy_text = read_text(deploy)
    require("g++" in deploy_text, "deploy.sh does not invoke g++")
    require("/home/user/src/monitor.cpp" in deploy_text, "deploy.sh does not compile monitor.cpp")
    require("/home/user/bin/fs_monitor" in deploy_text, "deploy.sh does not output fs_monitor")
    subprocess.run(["bash", "-n", deploy], check=True, timeout=5)
    with tempfile.TemporaryDirectory() as td:
        subprocess.run(["g++", source, "-o", os.path.join(td, "fs_monitor")], check=True, timeout=30)

    subprocess.run(["openssl", "x509", "-in", cert, "-noout", "-checkend", "0"], check=True, timeout=5)
    subprocess.run(["openssl", "pkey", "-in", key, "-noout", "-check"], check=True, timeout=5,
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    cert_info = subprocess.check_output(["openssl", "x509", "-in", cert, "-noout", "-text"], text=True, timeout=5)
    require("rsaEncryption" in cert_info, "Certificate does not contain an RSA public key")

    cp = configparser.ConfigParser(interpolation=None)
    cp.read(config)
    require(cp.has_section("supervisord"), "Missing [supervisord] section")
    require(cp.get("supervisord", "logfile", fallback="") == "/home/user/supervisord.log",
            "Wrong supervisord logfile")
    require(cp.get("supervisord", "pidfile", fallback="") == "/home/user/supervisord.pid",
            "Wrong supervisord pidfile")
    for name in ["fs_monitor", "https_server", "port_forward"]:
        require(cp.has_section(f"program:{name}"), f"Missing [program:{name}] section")

    fs_command = shlex.split(cp.get("program:fs_monitor", "command", fallback=""))
    require(fs_command == ["/home/user/bin/fs_monitor"], "fs_monitor has the wrong supervised command")
    https_command = shlex.split(cp.get("program:https_server", "command", fallback=""))
    require(https_command == ["/usr/bin/env", "python3", "/home/user/server.py"],
            "https_server has the wrong supervised command")
    forward_command = cp.get("program:port_forward", "command", fallback="")
    require("socat" in forward_command and "9090" in forward_command and "8443" in forward_command,
            "port_forward is not the required socat forwarding command")
    require(forward_command.count("127.0.0.1") >= 2, "socat forwarding is not restricted to loopback")


def test_supervisord_and_children():
    pid_file = "/home/user/supervisord.pid"
    require(os.path.isfile(pid_file), f"supervisord PID file not found at {pid_file}")
    pid_text = read_text(pid_file).strip()
    require(pid_text.isdigit(), "PID file does not contain a valid numeric PID")
    pid = int(pid_text)
    require(os.path.exists(f"/proc/{pid}"), f"supervisord process with PID {pid} is not running")
    require(proc_state(pid) not in (None, "Z"), "supervisord PID is dead or a zombie")
    command = " ".join(proc_cmdline(pid))
    require("supervisord" in command and "/home/user/supervisord.conf" in command,
            "PID file does not identify the requested supervisord instance")
    expected_uid = pwd.getpwnam("user").pw_uid
    require(os.stat(f"/proc/{pid}").st_uid == expected_uid, "supervisord is not running as user")

    children = descendants(pid)
    live = [p for p in children if proc_state(p) not in (None, "Z")]
    require(live, "supervisord has no live supervised children")

    monitor_pids = []
    server_pids = []
    socat_pids = []
    for child in live:
        args = proc_cmdline(child)
        joined = " ".join(args)
        try:
            exe = os.path.realpath(f"/proc/{child}/exe")
        except OSError:
            exe = ""
        if exe == "/home/user/bin/fs_monitor":
            monitor_pids.append(child)
        if "/home/user/server.py" in args and "python" in os.path.basename(exe).lower():
            server_pids.append(child)
        if os.path.basename(exe) == "socat" and "9090" in joined and "8443" in joined:
            socat_pids.append(child)

    require(monitor_pids, "supervisord is not supervising /home/user/bin/fs_monitor")
    require(server_pids, "supervisord is not supervising the Python HTTPS server")
    require(socat_pids, "supervisord is not supervising the socat port forwarder")


def test_ports_and_dynamic_end_to_end_alerts():
    wait_for_port(8443)
    wait_for_port(9090)
    direct_before = fetch_log(8443)
    forwarded_before = fetch_log(9090)
    require(direct_before == forwarded_before, "Port 9090 is not forwarding the HTTPS alert service")

    token = secrets.token_hex(12)
    dat_names = [f"audit_{token}_a.dat", f"audit_{token}_b.dat"]
    ignored_name = f"audit_{token}.txt"
    all_names = dat_names + [ignored_name]
    for name in all_names:
        path = os.path.join(HOME, "data_drop", name)
        if os.path.exists(path):
            os.unlink(path)

    for name in [ignored_name] + dat_names:
        with open(os.path.join(HOME, "data_drop", name), "x", encoding="utf-8") as f:
            f.write(secrets.token_hex(8))

    expected = [f'{{"alert": "new_data", "file": "{name}"}}' for name in dat_names]
    forbidden = f'{{"alert": "new_data", "file": "{ignored_name}"}}'
    deadline = time.time() + 8
    content = ""
    while time.time() < deadline:
        content = fetch_log(9090)
        lines = content.splitlines()
        if all(line in lines for line in expected):
            break
        time.sleep(0.15)

    lines = content.splitlines()
    for line in expected:
        require(lines.count(line) == 1, f"Expected exactly one newly generated line {line!r}")
    time.sleep(0.5)
    final_direct = fetch_log(8443)
    final_forwarded = fetch_log(9090)
    require(final_direct == final_forwarded, "Forwarded service differs from the direct HTTPS service")
    require(forbidden not in final_forwarded.splitlines(), "Monitor incorrectly alerted on a non-.dat file")


if __name__ == "__main__":
    test_files_build_and_configuration()
    test_supervisord_and_children()
    test_ports_and_dynamic_end_to_end_alerts()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
