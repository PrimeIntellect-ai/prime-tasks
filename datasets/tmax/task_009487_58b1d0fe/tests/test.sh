#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import subprocess
import time
import uuid


def test_directories_exist():
    """Ensure the required directories were created."""
    directories = [
        "/home/user/k8s-manifests",
        "/home/user/active-manifests",
        "/home/user/network"
    ]
    for d in directories:
        assert os.path.isdir(d), f"Directory {d} is missing or not a directory."


def test_scripts_exist_and_executable():
    """Ensure operator.py exists and operator.sh exists and is executable."""
    assert os.path.isfile("/home/user/operator.py"), "/home/user/operator.py does not exist or is not a file."

    sh_path = "/home/user/operator.sh"
    assert os.path.isfile(sh_path), f"{sh_path} does not exist or is not a file."
    assert os.access(sh_path, os.X_OK), f"{sh_path} is not executable."


def test_lifecycle_state():
    """Ensure the daemon is stopped and the PID file is removed."""
    pid_file = "/home/user/operator.pid"
    assert not os.path.exists(pid_file), f"PID file {pid_file} still exists. The daemon might not have been stopped properly."

    try:
        output = subprocess.check_output(["pgrep", "-f", "operator.py"], text=True)
        assert not output.strip(), "An operator.py process is still running."
    except subprocess.CalledProcessError:
        pass


def test_routes_conf_contents():
    """Ensure routes.conf contains the correct routing rules with no duplicates."""
    conf_path = "/home/user/network/routes.conf"
    assert os.path.isfile(conf_path), f"{conf_path} does not exist."

    with open(conf_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_routes = {
        "ip route add 192.168.10.0/24 dev mock0 metric 100",
        "ip route add 10.5.0.0/16 dev mock0 metric 100"
    }

    for route in expected_routes:
        assert route in lines, f"Missing expected route: '{route}' in {conf_path}"

    assert len(lines) == len(set(lines)), f"Duplicate lines found in {conf_path}."

    for line in lines:
        assert line in expected_routes, f"Unexpected route found: '{line}' in {conf_path}"


def test_symlinks():
    """Ensure the correct symlinks are created and point to the right files."""
    symlinks = {
        "/home/user/active-manifests/alpha-route.yaml": "/home/user/k8s-manifests/route-alpha.yaml",
        "/home/user/active-manifests/beta-route.yaml": "/home/user/k8s-manifests/route-beta.yaml"
    }

    for link, target in symlinks.items():
        assert os.path.islink(link), f"{link} does not exist or is not a symlink."

        link_target = os.readlink(link)
        absolute_target = os.path.normpath(os.path.join(os.path.dirname(link), link_target))

        assert absolute_target == target, f"Symlink {link} points to {absolute_target} instead of {target}."


def _pid_running(pid):
    try:
        os.kill(pid, 0)
        with open(f"/proc/{pid}/stat", "r") as f:
            return f.read().split()[2] != "Z"
    except (ProcessLookupError, FileNotFoundError):
        return False


def _operator_pids():
    matches = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [a.decode(errors="replace") for a in f.read().split(b"\0") if a]
            if any(os.path.basename(arg) == "operator.py" for arg in args):
                matches.append(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return matches


def test_operator_and_init_script_runtime_behavior():
    """Exercise start/status/stop and verify a fresh manifest is processed by the daemon."""
    script = "/home/user/operator.sh"
    pid_file = "/home/user/operator.pid"
    conf_path = "/home/user/network/routes.conf"

    token = uuid.uuid4().hex
    name = f"verifier-{token}"
    manifest = f"/home/user/k8s-manifests/runtime-{token}.yaml"
    link = f"/home/user/active-manifests/{name}.yaml"
    octet2 = 16 + (int(token[:2], 16) % 16)
    octet3 = int(token[2:4], 16)
    route_ip = f"172.{octet2}.{octet3}.0/24"
    expected_rule = f"ip route add {route_ip} dev mock0 metric 100"
    started_pid = None

    try:
        start = subprocess.run([script, "start"], text=True, capture_output=True, timeout=5)
        assert start.returncode == 0, f"start failed: stdout={start.stdout!r}, stderr={start.stderr!r}"

        deadline = time.time() + 3
        while time.time() < deadline and not os.path.isfile(pid_file):
            time.sleep(0.05)
        assert os.path.isfile(pid_file), "start did not create /home/user/operator.pid"

        with open(pid_file, "r") as f:
            pid_text = f.read().strip()
        assert pid_text.isdigit(), f"PID file does not contain a numeric PID: {pid_text!r}"
        started_pid = int(pid_text)
        assert _pid_running(started_pid), "PID written by start is not running"

        with open(f"/proc/{started_pid}/cmdline", "rb") as f:
            cmdline = [a.decode(errors="replace") for a in f.read().split(b"\0") if a]
        assert any(os.path.basename(arg) == "operator.py" for arg in cmdline), \
            f"PID file does not identify operator.py: {cmdline!r}"

        running_status = subprocess.run([script, "status"], capture_output=True, timeout=5)
        assert running_status.returncode == 0, "status did not exit 0 while the operator was running"

        with open(manifest, "w") as f:
            f.write(
                "kind: Route\n"
                "metadata:\n"
                f"  name: {name}\n"
                "spec:\n"
                f"  routeIP: {route_ip}\n"
            )

        deadline = time.time() + 6
        while time.time() < deadline:
            lines = []
            if os.path.isfile(conf_path):
                with open(conf_path, "r") as f:
                    lines = [line.strip() for line in f if line.strip()]
            if expected_rule in lines and os.path.islink(link):
                break
            time.sleep(0.1)

        assert os.path.islink(link), "The running operator did not create the symlink for a fresh manifest"
        target = os.path.normpath(os.path.join(os.path.dirname(link), os.readlink(link)))
        assert target == manifest, f"Runtime symlink points to {target} instead of {manifest}"

        with open(conf_path, "r") as f:
            lines = [line.strip() for line in f if line.strip()]
        assert lines.count(expected_rule) == 1, "The running operator did not add exactly one derived route"

        time.sleep(2.2)
        assert _pid_running(started_pid), "operator.py did not remain running as a continuous daemon"
        with open(conf_path, "r") as f:
            lines = [line.strip() for line in f if line.strip()]
        assert lines.count(expected_rule) == 1, "The operator duplicated a route across iterations"

        running_status = subprocess.run([script, "status"], capture_output=True, timeout=5)
        assert running_status.returncode == 0, "status stopped reporting the live daemon as running"

        stop = subprocess.run([script, "stop"], text=True, capture_output=True, timeout=5)
        assert stop.returncode == 0, f"stop failed: stdout={stop.stdout!r}, stderr={stop.stderr!r}"

        deadline = time.time() + 3
        while time.time() < deadline and _pid_running(started_pid):
            time.sleep(0.05)
        assert not _pid_running(started_pid), "stop did not terminate the PID from operator.pid"
        assert not os.path.exists(pid_file), "stop did not remove /home/user/operator.pid"

        stopped_status = subprocess.run([script, "status"], capture_output=True, timeout=5)
        assert stopped_status.returncode == 1, "status did not exit 1 after the operator was stopped"
        assert not _operator_pids(), "An operator.py process remains after stop"
    finally:
        try:
            subprocess.run([script, "stop"], capture_output=True, timeout=3)
        except Exception:
            pass
        if started_pid is not None and _pid_running(started_pid):
            try:
                os.kill(started_pid, signal.SIGTERM)
                time.sleep(0.2)
            except ProcessLookupError:
                pass
            if _pid_running(started_pid):
                try:
                    os.kill(started_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        if os.path.lexists(link):
            os.unlink(link)
        if os.path.exists(manifest):
            os.unlink(manifest)
        if os.path.isfile(conf_path):
            with open(conf_path, "r") as f:
                retained = [line for line in f if line.strip() != expected_rule]
            with open(conf_path, "w") as f:
                f.writelines(retained)
        if os.path.exists(pid_file):
            os.unlink(pid_file)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
