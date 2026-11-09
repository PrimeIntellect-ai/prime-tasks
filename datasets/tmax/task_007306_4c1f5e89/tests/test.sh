#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import signal
import shutil
import subprocess
import time

import pytest

HOME = "/home/user"
SETUP = f"{HOME}/setup_hybrid.sh"
SHIM = f"{HOME}/container_shim.sh"
QEMU_IMAGE = f"{HOME}/legacy.img"
SERIAL_LOG = f"{HOME}/legacy_vm.log"
NEXTGEN_LOG = f"{HOME}/nextgen.log"
STATUS = f"{HOME}/logrotate.status"
CONFIG = f"{HOME}/vm_logrotate.conf"


def proc_cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return [x.decode("utf-8", "replace") for x in f.read().split(b"\0") if x]


def proc_exe(pid):
    return os.path.realpath(f"/proc/{pid}/exe")


def process_exists(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def wait_gone(pid, timeout=6):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not process_exists(pid):
            return True
        try:
            with open(f"/proc/{pid}/stat") as f:
                if f.read().split()[2] == "Z":
                    return True
        except OSError:
            return True
        time.sleep(0.1)
    return not process_exists(pid)


def stop_old_processes():
    # Stop only genuine QEMU processes, not processes merely spoofing argv text.
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            if os.path.basename(proc_exe(pid)) == "qemu-system-x86_64":
                os.kill(pid, signal.SIGTERM)
        except (OSError, PermissionError):
            pass

    pid_file = f"{HOME}/container_shim.pid"
    try:
        with open(pid_file) as f:
            pid = int(f.read().strip())
        if SHIM in proc_cmdline(pid):
            os.kill(pid, signal.SIGTERM)
    except (OSError, ValueError):
        pass
    time.sleep(1)


def remove_generated_state():
    for path in [SHIM, SERIAL_LOG, NEXTGEN_LOG, STATUS, CONFIG,
                 f"{HOME}/container_shim.pid"]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    for path in glob.glob(SERIAL_LOG + ".*"):
        try:
            os.remove(path)
        except OSError:
            pass

    profile = f"{HOME}/.profile"
    with open(profile, "r") as f:
        lines = f.readlines()
    with open(profile, "w") as f:
        for line in lines:
            if "MIGRATION_PHASE" not in line and "QEMU_VNC_DISPLAY" not in line:
                f.write(line)


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SETUP), f"{SETUP} does not exist or is not a regular file."
    assert os.access(SETUP, os.X_OK), f"{SETUP} is not executable."
    stop_old_processes()
    remove_generated_state()

    started = time.time()
    try:
        result = subprocess.run(
            [SETUP], cwd=HOME, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=20
        )
    except subprocess.TimeoutExpired:
        pytest.fail("setup_hybrid.sh did not detach its background services and return.")
    except OSError as exc:
        pytest.fail(f"Could not execute setup_hybrid.sh directly: {exc}")
    assert result.returncode == 0, f"setup_hybrid.sh exited with {result.returncode}."

    # Allow the daemon and shim a brief period to initialize.
    time.sleep(1.5)
    yield started


def test_environment_variables():
    profile_path = f"{HOME}/.profile"
    assert os.path.exists(profile_path), f"{profile_path} does not exist."
    with open(profile_path, "r") as f:
        content = f.read()
    assert "MIGRATION_PHASE=hybrid" in content, "MIGRATION_PHASE=hybrid not found in .profile"
    assert "QEMU_VNC_DISPLAY=:5" in content, "QEMU_VNC_DISPLAY=:5 not found in .profile"


def test_qemu_running():
    try:
        output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
    except subprocess.CalledProcessError:
        pytest.fail("Failed to execute ps command.")

    qemu_processes = [line for line in output.splitlines()
                      if "qemu-system-x86_64" in line and "grep" not in line]
    assert qemu_processes, "qemu-system-x86_64 is not running."
    assert any(("-vnc :5" in p or ("-vnc" in p and ":5" in p)) for p in qemu_processes), \
        "QEMU is not running with VNC display :5."
    assert any("-serial file:/home/user/legacy_vm.log" in p for p in qemu_processes), \
        "QEMU is not running with serial redirect to /home/user/legacy_vm.log."

    expected_exe = os.path.realpath(shutil.which("qemu-system-x86_64"))
    genuine = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            if proc_exe(pid) != expected_exe:
                continue
            args = proc_cmdline(pid)
            vnc_ok = any(args[i] == "-vnc" and i + 1 < len(args) and args[i + 1] == ":5"
                         for i in range(len(args)))
            serial_ok = any(args[i] == "-serial" and i + 1 < len(args)
                            and args[i + 1] == f"file:{SERIAL_LOG}"
                            for i in range(len(args)))
            image_arg = any(QEMU_IMAGE in arg for arg in args)
            open_image = False
            for fd in glob.glob(f"/proc/{pid}/fd/*"):
                try:
                    if os.path.realpath(fd) == os.path.realpath(QEMU_IMAGE):
                        open_image = True
                        break
                except OSError:
                    pass
            if vnc_ok and serial_ok and image_arg and open_image:
                genuine.append(pid)
        except (OSError, PermissionError):
            continue
    assert genuine, "No genuine QEMU process is running with the required VNC, serial, and open disk image."


def active_target_block(content):
    active_lines = []
    for raw in content.splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            active_lines.append(line)
    active = "\n".join(active_lines)
    match = re.search(r'(?m)^["\']?/home/user/legacy_vm\.log["\']?\s*\{(.*?)\}',
                      active, re.S)
    assert match, "No active logrotate stanza for /home/user/legacy_vm.log."
    return match.group(1)


def test_logrotate_config_and_execution(execute_submission):
    assert os.path.exists(CONFIG), f"{CONFIG} does not exist."
    with open(CONFIG, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert re.search(r'\bhourly\b', content), "Rule 'hourly' not found in logrotate config."
    assert re.search(r'\brotate\s+5\b', content), "Rule 'rotate 5' not found in logrotate config."
    assert re.search(r'\bcompress\b', content), "Rule 'compress' not found in logrotate config."
    assert re.search(r'\bmissingok\b', content), "Rule 'missingok' not found in logrotate config."

    block = active_target_block(content)
    directives = [line.split() for line in block.splitlines() if line.strip()]
    assert ["hourly"] in directives, "Active target stanza does not specify hourly."
    assert ["rotate", "5"] in directives, "Active target stanza does not specify rotate 5."
    assert ["compress"] in directives, "Active target stanza does not specify compress."
    assert ["missingok"] in directives, "Active target stanza does not specify missingok."

    # The freshly executed setup must have caused logrotate to create a real state file.
    assert os.path.exists(STATUS), f"{STATUS} does not exist. Did logrotate run?"
    assert os.path.getmtime(STATUS) >= execute_submission - 1, "logrotate status was not freshly generated."
    with open(STATUS, "r", errors="replace") as f:
        state = f.read()
    assert state.startswith("logrotate state -- version"), "Status file is not a logrotate state file."

    # Exercise the submitted configuration and prove it really rotates and compresses the target log.
    sentinel = f"verifier-logrotate-{time.time_ns()}"
    with open(SERIAL_LOG, "a") as f:
        f.write(sentinel + "\n")
    for path in glob.glob(SERIAL_LOG + ".*"):
        try:
            os.remove(path)
        except OSError:
            pass

    old_mode = os.stat(HOME).st_mode & 0o7777
    try:
        os.chmod(HOME, 0o755)
        result = subprocess.run(
            ["logrotate", "-f", "-s", STATUS, CONFIG],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
    finally:
        os.chmod(HOME, old_mode)
    assert result.returncode == 0, f"logrotate rejected the config: {result.stderr}"

    compressed = glob.glob(SERIAL_LOG + ".*.gz")
    assert compressed, "Forcing logrotate did not create a compressed rotation."
    found = False
    for path in compressed:
        result = subprocess.run(["gzip", "-cd", path], capture_output=True, text=True)
        if result.returncode == 0 and sentinel in result.stdout:
            found = True
            break
    assert found, "The compressed rotation did not contain data from legacy_vm.log."


def test_container_shim_lifecycle():
    assert os.path.isfile(SHIM), f"{SHIM} does not exist or is not a regular file."
    assert os.access(SHIM, os.X_OK), f"{SHIM} is not executable."

    pid_file = f"{HOME}/container_shim.pid"
    assert os.path.exists(pid_file), f"{pid_file} does not exist."
    with open(pid_file, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid PID."
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} is not running.")

    args = proc_cmdline(pid)
    assert SHIM in args, "Saved PID does not belong to container_shim.sh."
    assert os.path.basename(proc_exe(pid)) in ("bash", "sh"), "Shim PID is not a shell executing the shim."

    assert os.path.exists(NEXTGEN_LOG), f"{NEXTGEN_LOG} does not exist."
    with open(NEXTGEN_LOG, "r") as f:
        before = f.read()
    assert "[INFO] Starting next-gen service" in before, "Startup log message not found."
    assert "[INFO] Shutting down gracefully" not in before, "Shutdown was logged before a signal was sent."

    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pytest.fail(f"Failed to send SIGTERM to process {pid}.")
    assert wait_gone(pid), f"Process {pid} did not exit after receiving SIGTERM."
    with open(NEXTGEN_LOG, "r") as f:
        after = f.read()
    assert "[INFO] Shutting down gracefully" in after, "Shutdown log message not found."


@pytest.mark.parametrize("sig", [signal.SIGTERM, signal.SIGINT])
def test_shim_artifact_handles_each_signal_cleanly(sig):
    # Execute the artifact directly so prewritten messages or an unrelated PID cannot satisfy the test.
    with open(NEXTGEN_LOG, "w"):
        pass
    proc = subprocess.Popen([SHIM], cwd=HOME, stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.time() + 3
        while time.time() < deadline:
            if proc.poll() is not None:
                pytest.fail("container_shim.sh exited instead of remaining in its loop.")
            with open(NEXTGEN_LOG, "r") as f:
                initial = f.read()
            if "[INFO] Starting next-gen service" in initial:
                break
            time.sleep(0.1)
        else:
            pytest.fail("Directly executed shim did not log startup.")

        lines = initial.splitlines()
        assert "[INFO] Starting next-gen service" in lines
        assert "[INFO] Shutting down gracefully" not in lines
        time.sleep(1.1)
        assert proc.poll() is None, "Shim did not remain running before receiving a signal."

        proc.send_signal(sig)
        assert proc.wait(timeout=5) == 0, f"Shim did not exit cleanly for signal {sig}."
        with open(NEXTGEN_LOG, "r") as f:
            final_lines = f.read().splitlines()
        assert "[INFO] Shutting down gracefully" in final_lines
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
