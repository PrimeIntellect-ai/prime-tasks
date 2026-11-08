#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import stat
import subprocess
import time
import traceback
import uuid
import pytest

LOG_FILE = "/home/user/deployment_final.log"
SCRIPT_PATH = "/home/user/deploy_vms.sh"
CONF_PATH = "/home/user/nginx/nginx.conf"
QEMU_PATH = "/home/user/bin/qemu_mock.sh"
EXPECTED_PATHS = [
    "/home/user/run/microvm_alpha.sock",
    "/home/user/run/microvm_beta.sock",
    "/home/user/run/microvm_gamma.sock"
]


def qemu_pids():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
            if QEMU_PATH in cmdline:
                found.append(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return found


def kill_qemus():
    pids = qemu_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.15)
    for pid in qemu_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def parse_backend_paths(path):
    paths = []
    in_backend = False
    depth = 0
    with open(path) as f:
        for line in f:
            if not in_backend:
                if re.search(r"\bupstream\s+backend\s*\{", line):
                    in_backend = True
                    depth = line.count("{") - line.count("}")
                continue

            match = re.search(r"^\s*server\s+unix:([^;]+)\s*;", line)
            if match:
                paths.append(match.group(1).strip())
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                break
    return paths


def test_00_script_performs_dynamic_staged_deployment():
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"File {SCRIPT_PATH} is not executable."

    with open(CONF_PATH, "rb") as f:
        original_conf = f.read()
    with open(QEMU_PATH, "rb") as f:
        original_qemu = f.read()
    original_qemu_mode = stat.S_IMODE(os.stat(QEMU_PATH).st_mode)

    token = uuid.uuid4().hex[:10]
    dynamic_paths = [
        f"/home/user/run/verify_{token}_first.sock",
        f"/home/user/run/verify_{token}_second.sock",
        f"/home/user/run/verify_{token}_third.sock",
    ]
    decoy_before = f"/home/user/run/verify_{token}_decoy_before.sock"
    decoy_after = f"/home/user/run/verify_{token}_decoy_after.sock"
    all_test_paths = [decoy_before, *dynamic_paths, decoy_after]
    event_file = f"/tmp/qemu_events_{token}"
    sleep_file = f"/tmp/sleep_events_{token}"
    sleep_dir = f"/tmp/sleep_path_{token}"
    errors = []

    dynamic_conf = f"""worker_processes 1;
events {{ worker_connections 1024; }}
http {{
    upstream not_backend {{
        server unix:{decoy_before};
    }}
    upstream backend {{
        server unix:{dynamic_paths[0]};
        server unix:{dynamic_paths[1]};
        server unix:{dynamic_paths[2]};
    }}
    upstream backend_shadow {{
        server unix:{decoy_after};
    }}
    server {{ listen 8080; }}
}}
"""

    try:
        kill_qemus()
        for path in all_test_paths + EXPECTED_PATHS:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        try:
            os.unlink(LOG_FILE)
        except FileNotFoundError:
            pass

        with open(CONF_PATH, "w") as f:
            f.write(dynamic_conf)
        expected = parse_backend_paths(CONF_PATH)
        assert expected == dynamic_paths, "Verifier failed to derive the generated backend paths."

        qemu_wrapper = """#!/bin/bash
printf '%s\\t%s\\t%s\\n' "$$" "$1" "$(date +%s%N)" >> "$VERIFIER_EVENT_FILE"
touch -- "$1"
trap 'exit 0' TERM INT
while true; do /bin/sleep 60; done
"""
        with open(QEMU_PATH, "w") as f:
            f.write(qemu_wrapper)
        os.chmod(QEMU_PATH, 0o755)

        os.makedirs(sleep_dir, exist_ok=True)
        sleep_wrapper = """#!/bin/bash
count=0
if [ -f /home/user/deployment_final.log ]; then
    count=$(grep -cve '^[[:space:]]*$' /home/user/deployment_final.log || true)
fi
printf '%s\\t%s\\t%s\\n' "$(date +%s%N)" "$*" "$count" >> "$VERIFIER_SLEEP_FILE"
/bin/sleep "$@"
"""
        sleep_path = os.path.join(sleep_dir, "sleep")
        with open(sleep_path, "w") as f:
            f.write(sleep_wrapper)
        os.chmod(sleep_path, 0o755)

        env = os.environ.copy()
        env["PATH"] = sleep_dir + ":" + env.get("PATH", "")
        env["VERIFIER_EVENT_FILE"] = event_file
        env["VERIFIER_SLEEP_FILE"] = sleep_file

        started = time.monotonic()
        result = subprocess.run(
            [SCRIPT_PATH],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            timeout=12,
        )
        elapsed = time.monotonic() - started
        assert result.returncode == 0, f"Deployment script exited {result.returncode}: {result.stderr}"
        assert elapsed >= 2.75, f"Deployment returned after {elapsed:.2f}s instead of waiting after all three launches."
        assert elapsed < 8, f"Deployment took unexpectedly long ({elapsed:.2f}s)."

        assert os.path.isfile(event_file), "The deployment did not invoke qemu_mock.sh."
        with open(event_file) as f:
            events = [line.rstrip("\n").split("\t") for line in f if line.strip()]
        assert len(events) == 3, f"Expected exactly 3 qemu_mock.sh invocations, found {len(events)}."
        assert all(len(event) == 3 for event in events), "Malformed emulator invocation record."
        invoked_paths = [event[1] for event in events]
        assert invoked_paths == expected, f"Emulators were not launched in backend configuration order: {invoked_paths}"
        invocation_pids = [int(event[0]) for event in events]
        invocation_times = [int(event[2]) for event in events]

        assert os.path.isfile(LOG_FILE), f"The log file {LOG_FILE} was not created by the script."
        with open(LOG_FILE) as f:
            log_lines = [line.strip() for line in f if line.strip()]
        assert len(log_lines) == 3, f"Expected exactly 3 generated log entries, found {len(log_lines)}."
        for i, (line, path, pid) in enumerate(zip(log_lines, expected, invocation_pids)):
            match = re.fullmatch(r"DEPLOYED PID ([0-9]+) TO (.*)", line)
            assert match, f"Log line {i + 1} has the wrong format: {line}"
            assert int(match.group(1)) == pid, f"Log line {i + 1} does not contain the actual background PID."
            assert match.group(2) == path, f"Log line {i + 1} has the wrong socket path."

        assert os.path.isfile(sleep_file), "No staged sleep calls were observed."
        with open(sleep_file) as f:
            sleeps = [line.rstrip("\n").split("\t") for line in f if line.strip()]
        assert len(sleeps) == 3, f"Expected exactly one sleep after each launch, found {len(sleeps)} sleeps."
        assert all(len(item) == 3 for item in sleeps), "Malformed sleep invocation record."
        assert [item[1] for item in sleeps] == ["1", "1", "1"], "Each staged delay must invoke sleep with exactly the argument 1."
        assert [int(item[2]) for item in sleeps] == [1, 2, 3], "Each deployment record must be written before its corresponding sleep."

        sleep_times = [int(item[0]) for item in sleeps]
        for i in range(3):
            assert sleep_times[i] >= invocation_times[i], "A sleep occurred before its emulator was started."
        for i in range(2):
            gap = (invocation_times[i + 1] - invocation_times[i]) / 1_000_000_000
            assert gap >= 0.85, f"Launches {i + 1} and {i + 2} were only {gap:.2f}s apart."

        for pid, path in zip(invocation_pids, expected):
            assert os.path.exists(f"/proc/{pid}"), f"Logged emulator PID {pid} is not running."
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
            assert QEMU_PATH in cmdline and path in cmdline, f"PID {pid} is not the expected emulator for {path}."
            assert os.path.exists(path), f"Emulator did not create {path}."
        assert not os.path.exists(decoy_before), "The script parsed a server line outside upstream backend."
        assert not os.path.exists(decoy_after), "The script parsed a similarly named non-backend upstream."
    except Exception:
        errors.append(traceback.format_exc())
    finally:
        kill_qemus()
        with open(CONF_PATH, "wb") as f:
            f.write(original_conf)
        with open(QEMU_PATH, "wb") as f:
            f.write(original_qemu)
        os.chmod(QEMU_PATH, original_qemu_mode)
        for path in all_test_paths + EXPECTED_PATHS:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        for path in (LOG_FILE, event_file, sleep_file):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        try:
            result = subprocess.run(
                [SCRIPT_PATH],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
                timeout=12,
            )
            if result.returncode != 0:
                errors.append(f"Final deployment exited {result.returncode}: {result.stderr}")
        except Exception:
            errors.append("Final deployment failed:\n" + traceback.format_exc())

    assert not errors, "\n".join(errors)


def test_log_file_exists_and_content():
    assert os.path.isfile(LOG_FILE), f"The log file {LOG_FILE} was not created."

    with open(LOG_FILE, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 log entries in {LOG_FILE}, found {len(lines)}."

    for i, expected_path in enumerate(EXPECTED_PATHS):
        line = lines[i]
        match = re.match(r"^DEPLOYED PID ([0-9]+) TO (.*)$", line)
        assert match, f"Log line {i+1} does not match expected format: {line}"

        pid_str, path = match.groups()
        assert path == expected_path, f"Expected path {expected_path} in log line {i+1}, found {path}"

        # Verify PID is a number
        assert pid_str.isdigit(), f"Extracted PID {pid_str} is not a valid number."


def test_processes_are_running():
    for expected_path in EXPECTED_PATHS:
        # We check if the process is running using pgrep
        cmd = ["pgrep", "-f", f"/home/user/bin/qemu_mock.sh {expected_path}"]
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode == 0, f"Process for {expected_path} is not running."

        # Check if the socket file was actually created by the mock script
        assert os.path.exists(expected_path), f"Socket file {expected_path} was not created."


def test_deployment_script_modified():
    script_path = "/home/user/deploy_vms.sh"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    assert "/tmp/vm_1.sock" not in content, "The deployment script still contains hardcoded /tmp/ paths."
    assert "nginx.conf" in content or "grep" in content or "awk" in content or "sed" in content, \
        "The deployment script doesn't seem to parse nginx.conf or extract paths dynamically."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
