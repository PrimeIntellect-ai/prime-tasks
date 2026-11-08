#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import socket
import stat
import subprocess
import tempfile
import time

import pytest

ACCOUNTS = [
    ("dev_alpha", 12),
    ("dev_beta", 25),
    ("ops_gamma", 40),
]

WORKSPACES_DIR = "/home/user/workspaces"
PROVISIONER_DIR = "/home/user/account_provisioner"
ACCOUNTS_CSV = "/home/user/accounts.csv"


def socat_pids_for_port(port):
    matches = []
    needle = f"TCP-LISTEN:{port}"
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if args and os.path.basename(args[0]) == "socat" and any(arg.startswith(needle) for arg in args[1:]):
            matches.append(int(entry))
    return matches


def wait_for_count(port, expected, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = socat_pids_for_port(port)
        if len(pids) == expected:
            return pids
        time.sleep(0.1)
    return socat_pids_for_port(port)


def run_script(path, env=None):
    result = subprocess.run(
        [path],
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=15,
    )
    assert result.returncode == 0, f"Tunnel script exited with status {result.returncode}"


def test_rust_project_exists():
    assert os.path.exists(PROVISIONER_DIR), f"Rust project directory {PROVISIONER_DIR} does not exist"
    cargo_toml = os.path.join(PROVISIONER_DIR, "Cargo.toml")
    assert os.path.exists(cargo_toml), f"Cargo.toml not found in {PROVISIONER_DIR}"

    result = subprocess.run(
        ["cargo", "build"],
        cwd=PROVISIONER_DIR,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Rust project failed to build:\n{result.stderr}"


def test_workspace_directories_and_files():
    for username, _ in ACCOUNTS:
        user_dir = os.path.join(WORKSPACES_DIR, username)
        logs_dir = os.path.join(user_dir, "logs")
        data_dir = os.path.join(user_dir, "data")
        latest_log = os.path.join(logs_dir, "latest.log")
        active_log = os.path.join(user_dir, "active_log")

        assert os.path.isdir(logs_dir), f"Logs directory missing for {username}: {logs_dir}"
        assert os.path.isdir(data_dir), f"Data directory missing for {username}: {data_dir}"
        assert os.path.isfile(latest_log), f"latest.log missing for {username}: {latest_log}"
        assert os.path.getsize(latest_log) == 0, f"latest.log is not empty for {username}"

        assert os.path.islink(active_log), f"active_log is not a symlink for {username}: {active_log}"
        target = os.readlink(active_log)
        assert target == "logs/latest.log", f"active_log symlink target incorrect for {username}. Expected 'logs/latest.log', got '{target}'"


def test_setup_tunnels_script():
    script_path = os.path.join(WORKSPACES_DIR, "setup_tunnels.sh")
    assert os.path.isfile(script_path), f"Script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"
    assert stat.S_IMODE(os.stat(script_path).st_mode) == 0o755, f"Script mode is not 0755: {script_path}"


def test_socat_processes_running():
    try:
        output = subprocess.check_output(["pgrep", "-f", "socat TCP-LISTEN"], text=True)
    except subprocess.CalledProcessError:
        output = ""

    running_pids = output.strip().split()

    for _, port_offset in ACCOUNTS:
        port = 8000 + port_offset
        try:
            cmd_output = subprocess.check_output(["pgrep", "-f", f"socat TCP-LISTEN:{port}"], text=True)
            pids = cmd_output.strip().split()
            assert len(pids) == 1, f"Expected exactly 1 socat process for port {port}, found {len(pids)}"
        except subprocess.CalledProcessError:
            pytest.fail(f"No socat process running for port {port}")


def test_provisioner_reads_csv_and_generated_script_is_idempotent():
    token = secrets.token_hex(5)
    usernames = [f"audit_{token}_{i}" for i in range(3)]

    held = []
    for port in range(18000 + secrets.randbelow(3000), 30000):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(("127.0.0.1", port))
            held.append((port, s))
            if len(held) == 3:
                break
        except OSError:
            s.close()
    assert len(held) == 3, "Could not reserve test ports"

    ports = [item[0] for item in held]
    blocker = held[0][1]
    blocker.listen(1)
    held[1][1].close()
    held[2][1].close()
    started_pids = set()

    try:
        with open(ACCOUNTS_CSV, "w", encoding="utf-8") as f:
            for username, port in zip(usernames, ports):
                f.write(f"{username},{port - 8000}\n")

        shutil.rmtree(WORKSPACES_DIR, ignore_errors=True)

        result = subprocess.run(
            ["cargo", "run", "--quiet"],
            cwd=PROVISIONER_DIR,
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f"Provisioner failed on verifier-supplied CSV:\n{result.stderr}"

        for username in usernames:
            user_dir = os.path.join(WORKSPACES_DIR, username)
            logs_dir = os.path.join(user_dir, "logs")
            data_dir = os.path.join(user_dir, "data")
            latest_log = os.path.join(logs_dir, "latest.log")
            active_log = os.path.join(user_dir, "active_log")
            assert os.path.isdir(logs_dir)
            assert os.path.isdir(data_dir)
            assert os.path.isfile(latest_log)
            assert os.path.getsize(latest_log) == 0
            assert os.path.islink(active_log)
            assert os.readlink(active_log) == "logs/latest.log"

        script_path = os.path.join(WORKSPACES_DIR, "setup_tunnels.sh")
        assert os.path.isfile(script_path)
        assert os.access(script_path, os.X_OK)
        assert stat.S_IMODE(os.stat(script_path).st_mode) == 0o755

        # A subsequent provisioning run must remain valid and must restore the
        # required empty-log state rather than merely accepting a precreated file.
        dirty_log = os.path.join(WORKSPACES_DIR, usernames[0], "logs", "latest.log")
        with open(dirty_log, "wb") as f:
            f.write(b"not empty")
        result = subprocess.run(
            ["cargo", "run", "--quiet"],
            cwd=PROVISIONER_DIR,
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f"Provisioner failed on repeated run:\n{result.stderr}"
        assert os.path.getsize(dirty_log) == 0, "Provisioner did not ensure latest.log is empty"
        assert os.readlink(os.path.join(WORKSPACES_DIR, usernames[0], "active_log")) == "logs/latest.log"
        assert stat.S_IMODE(os.stat(script_path).st_mode) == 0o755

        # Instrument socat to prove the generated script checks an occupied port
        # before invoking socat and emits the required command for free ports.
        with tempfile.TemporaryDirectory() as fake_bin:
            calls = os.path.join(fake_bin, "calls")
            fake_socat = os.path.join(fake_bin, "socat")
            with open(fake_socat, "w", encoding="utf-8") as f:
                f.write("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$SOCAT_CALLS\"\n")
            os.chmod(fake_socat, 0o755)
            env = os.environ.copy()
            env["PATH"] = fake_bin + os.pathsep + env.get("PATH", "")
            env["SOCAT_CALLS"] = calls
            run_script(script_path, env)
            time.sleep(0.5)
            lines = []
            if os.path.exists(calls):
                with open(calls, encoding="utf-8") as f:
                    lines = [line.strip() for line in f if line.strip()]

            assert not any(f"TCP-LISTEN:{ports[0]}," in line for line in lines), \
                "Script invoked socat even though the target local port was already in use"
            for port in ports[1:]:
                expected = f"TCP-LISTEN:{port},fork,bind=127.0.0.1 TCP:127.0.0.1:9999"
                assert lines.count(expected) == 1, f"Missing or incorrect socat command: {expected}"

        # Execute the real generated artifact twice. The second run must not
        # create duplicate listeners.
        run_script(script_path)
        for port in ports[1:]:
            pids = wait_for_count(port, 1)
            assert len(pids) == 1, f"Expected one socat listener on {port}, found {len(pids)}"
            started_pids.update(pids)
        assert len(wait_for_count(ports[0], 0)) == 0

        run_script(script_path)
        for port in ports[1:]:
            pids = wait_for_count(port, 1)
            assert len(pids) == 1, f"Repeated script run created duplicate listeners on {port}"
            started_pids.update(pids)

        blocker.close()
        blocker = None
        run_script(script_path)
        pids = wait_for_count(ports[0], 1)
        assert len(pids) == 1, f"Script did not create the newly available listener on {ports[0]}"
        started_pids.update(pids)

        run_script(script_path)
        for port in ports:
            pids = wait_for_count(port, 1)
            assert len(pids) == 1, f"Expected exactly one idempotent listener on {port}, found {len(pids)}"
            started_pids.update(pids)
    finally:
        if blocker is not None:
            blocker.close()
        for pid in started_pids:
            try:
                os.kill(pid, 15)
            except (ProcessLookupError, PermissionError):
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
