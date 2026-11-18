#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import hashlib
import json
import os
import pwd
import random
import shutil
import signal
import socket
import subprocess
import tempfile
import time

HOME = "/home/user"
USER = pwd.getpwnam("user")
LEGACY = f"{HOME}/legacy_proxy.conf"
JSON_PATH = f"{HOME}/new_proxy.json"
LOG_PATH = f"{HOME}/proxy.log"
STATUS_PATH = f"{HOME}/migration_status.txt"
BACKUP_SCRIPT = f"{HOME}/backup_and_convert.sh"
DEPLOY_SCRIPT = f"{HOME}/deploy.sh"
PROJECT = f"{HOME}/proxy_service"
ORIGINAL = {
    "route_api": 18080,
    "route_web": 18081,
    "route_metrics": 18082,
}


def user_preexec():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def user_env():
    env = os.environ.copy()
    env["HOME"] = HOME
    env["USER"] = "user"
    env["LOGNAME"] = "user"
    return env


def run_user(argv, **kwargs):
    return subprocess.run(
        argv,
        preexec_fn=user_preexec,
        env=user_env(),
        cwd=kwargs.pop("cwd", HOME),
        **kwargs,
    )


def popen_user(argv, **kwargs):
    return subprocess.Popen(
        argv,
        preexec_fn=user_preexec,
        env=user_env(),
        cwd=kwargs.pop("cwd", HOME),
        **kwargs,
    )


def kill_user_processes():
    me = os.getpid()
    for _ in range(3):
        for entry in os.listdir("/proc"):
            if not entry.isdigit() or int(entry) == me:
                continue
            try:
                if os.stat(f"/proc/{entry}").st_uid == USER.pw_uid:
                    os.kill(int(entry), signal.SIGKILL)
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                pass
        time.sleep(0.15)


def free_ports(count):
    sockets = []
    ports = []
    try:
        for _ in range(count):
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.bind(("127.0.0.1", 0))
            sockets.append(s)
            ports.append(s.getsockname()[1])
        return ports
    finally:
        for s in sockets:
            s.close()


def write_legacy(routes):
    with open(LEGACY, "w") as f:
        for name, port in routes.items():
            f.write(f"{name}={port}\n")
    os.chown(LEGACY, USER.pw_uid, USER.pw_gid)


def assert_conversion(routes):
    expected_text = "".join(f"{name}={port}\n" for name, port in routes.items())
    backup = f"{HOME}/backups/legacy_proxy.conf.bak"
    assert os.path.exists(backup), f"Backup file {backup} does not exist."
    with open(backup) as f:
        assert f.read() == expected_text, "Backup is not an exact copy of the current legacy configuration."
    assert os.path.exists(JSON_PATH), f"JSON file {JSON_PATH} does not exist."
    with open(JSON_PATH) as f:
        data = json.load(f)
    expected = [{"name": name, "port": port} for name, port in routes.items()]
    assert data == {"routes": expected}, f"Converted JSON is incorrect: {data!r}"
    for route in data["routes"]:
        assert isinstance(route["port"], int), "Converted ports must be integers."


def wait_for(predicate, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.1)
    return False


def pid_listening_ports(pid):
    inodes = set()
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target.startswith("socket:["):
                inodes.add(target[8:-1])
    except FileNotFoundError:
        return set()

    ports = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A" and fields[9] in inodes:
                        ports.add(int(fields[1].split(":")[1], 16))
        except FileNotFoundError:
            pass
    return ports


def owners_for_ports(ports):
    result = {port: set() for port in ports}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            owned = pid_listening_ports(int(entry))
        except (FileNotFoundError, PermissionError):
            continue
        for port in ports:
            if port in owned:
                result[port].add(int(entry))
    return result


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


kill_user_processes()

# Preserve the original existence and executability assertions.
assert os.path.exists(BACKUP_SCRIPT), f"Script {BACKUP_SCRIPT} does not exist."
assert os.access(BACKUP_SCRIPT, os.X_OK), f"Script {BACKUP_SCRIPT} is not executable."
assert os.path.exists(f"{PROJECT}/Cargo.toml"), "Rust project not found at Cargo.toml."
assert os.path.exists(DEPLOY_SCRIPT), f"Script {DEPLOY_SCRIPT} does not exist."
assert os.access(DEPLOY_SCRIPT, os.X_OK), f"Script {DEPLOY_SCRIPT} is not executable."

# Execute the converter twice on verifier-selected ports, proving it parses input
# and remains idempotent rather than relying on fixed final-state files.
random_ports = free_ports(3)
dynamic_routes = dict(zip(ORIGINAL.keys(), random_ports))
write_legacy(dynamic_routes)
run_user([BACKUP_SCRIPT], check=True, timeout=20)
assert_conversion(dynamic_routes)
run_user([BACKUP_SCRIPT], check=True, timeout=20)
assert_conversion(dynamic_routes)

# Build the submitted Cargo project from scratch in a verifier-controlled target
# directory and locate the binary reported by Cargo itself.
target_dir = tempfile.mkdtemp(prefix="proxy-build-")
os.chown(target_dir, USER.pw_uid, USER.pw_gid)
build = run_user(
    ["cargo", "build", "--release", "--manifest-path", f"{PROJECT}/Cargo.toml",
     "--target-dir", target_dir, "--message-format=json"],
    check=True, timeout=180, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
)
executables = []
for line in build.stdout.splitlines():
    try:
        message = json.loads(line)
    except json.JSONDecodeError:
        continue
    if message.get("reason") == "compiler-artifact" and "bin" in message.get("target", {}).get("kind", []):
        executable = message.get("executable")
        if executable:
            executables.append(executable)
assert executables, "Cargo did not produce a Rust binary artifact."
binary = executables[-1]
assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Cargo binary is missing or not executable."
with open(binary, "rb") as f:
    assert f.read(4) == b"\x7fELF", "Cargo output is not a native compiled binary."

# Run that exact Cargo-produced binary against verifier-selected JSON and ensure
# the process itself owns every requested listening socket.
with open(JSON_PATH, "w") as f:
    json.dump({"routes": [{"name": n, "port": p} for n, p in dynamic_routes.items()]}, f)
os.chown(JSON_PATH, USER.pw_uid, USER.pw_gid)
try:
    os.remove(LOG_PATH)
except FileNotFoundError:
    pass
service = popen_user([binary], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    assert wait_for(lambda: service.poll() is None and set(random_ports).issubset(pid_listening_ports(service.pid)), 20), \
        "The compiled Rust process did not bind all ports from new_proxy.json."
    assert os.path.exists(LOG_PATH), "Compiled service did not create proxy.log."
    with open(LOG_PATH) as f:
        lines = [line.rstrip("\n") for line in f]
    expected_lines = [f"Started {name} on {port}" for name, port in dynamic_routes.items()]
    assert lines == expected_lines, f"Compiled service logged unexpected content: {lines!r}"
finally:
    if service.poll() is None:
        service.terminate()
        try:
            service.wait(timeout=5)
        except subprocess.TimeoutExpired:
            service.kill()
            service.wait()

# Restore the instructed configuration and regenerate its final artifacts.
write_legacy(ORIGINAL)
run_user([BACKUP_SCRIPT], check=True, timeout=20)
assert_conversion(ORIGINAL)

# Execute deployment from a clean runtime state. It must build, launch, poll, and
# finish while leaving its compiled service alive.
kill_user_processes()
for path in (LOG_PATH, STATUS_PATH):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass
run_user([DEPLOY_SCRIPT], check=True, timeout=180, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

ports = list(ORIGINAL.values())
assert wait_for(lambda: all(owners_for_ports(ports)[p] for p in ports), 15), "Deployed ports are not all listening."
owners = owners_for_ports(ports)
owner_sets = [owners[p] for p in ports]
common = set.intersection(*owner_sets)
assert common, f"The three listeners do not come from one deployed service process: {owners!r}"
deployed_pid = next(iter(common))

# The deployed listener must be the release binary built by the project, not an
# unrelated helper process that merely occupies the fixed ports.
default_binary = f"{PROJECT}/target/release/proxy_service"
assert os.path.isfile(default_binary) and os.access(default_binary, os.X_OK), "Deployment did not build the release proxy_service binary."
with open(default_binary, "rb") as f:
    assert f.read(4) == b"\x7fELF", "Deployed project artifact is not a compiled binary."
assert sha256(f"/proc/{deployed_pid}/exe") == sha256(default_binary), \
    "Listening process is not the project's compiled release binary."

# Preserve all original final-state assertions.
backup_path = f"{HOME}/backups/legacy_proxy.conf.bak"
assert os.path.exists(backup_path), f"Backup file {backup_path} does not exist."
with open(backup_path) as f:
    backup_content = f.read()
assert "route_api=18080" in backup_content, "Backup file missing route_api."
assert "route_web=18081" in backup_content, "Backup file missing route_web."
assert "route_metrics=18082" in backup_content, "Backup file missing route_metrics."

with open(JSON_PATH) as f:
    final_json = json.load(f)
assert "routes" in final_json and isinstance(final_json["routes"], list), "JSON missing a routes list."
actual = {r.get("name"): r.get("port") for r in final_json["routes"] if isinstance(r, dict)}
for name, port in ORIGINAL.items():
    assert name in actual, f"Route {name} missing in JSON."
    assert actual[name] == port, f"Route {name} has incorrect port."
    assert isinstance(actual[name], int), f"Port for {name} should be an integer."

assert os.path.exists(STATUS_PATH), "Migration status file does not exist."
with open(STATUS_PATH) as f:
    assert f.read().strip() == "status=MIGRATED", "Migration status content is incorrect."

assert os.path.exists(LOG_PATH), "proxy.log does not exist."
with open(LOG_PATH) as f:
    log_content = f.read()
for name, port in ORIGINAL.items():
    assert f"Started {name} on {port}" in log_content, f"Missing startup log for {name}."

for port in ports:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        assert s.connect_ex(("127.0.0.1", port)) == 0, f"Port {port} is not bound."
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
