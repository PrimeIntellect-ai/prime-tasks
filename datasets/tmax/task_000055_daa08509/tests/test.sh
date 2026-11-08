#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any service left running by the agent so failure behavior can be tested.
pkill -f '[m]ock_service.py' 2>/dev/null || true
if command -v fuser >/dev/null 2>&1; then
    fuser -k 9090/tcp >/dev/null 2>&1 || true
fi

# Restore the specified interactive interface before exercising the submission.
cat << 'CLI_EOF' > /home/user/interactive_cli.py
import sys
import time

def log_action(action):
    with open('/home/user/cli_backend.log', 'a') as f:
        f.write(action + '\n')

def main():
    sys.stdout.write('Enter Edge ID: ')
    sys.stdout.flush()
    edge_id = sys.stdin.readline().strip()

    sys.stdout.write('Enter Passcode: ')
    sys.stdout.flush()
    passcode = sys.stdin.readline().strip()

    if edge_id != 'EDGE-999' or passcode != '314159':
        print("Authentication failed.")
        sys.exit(1)

    log_action("AUTH_SUCCESS")

    while True:
        sys.stdout.write('edge-shell> ')
        sys.stdout.flush()
        cmd = sys.stdin.readline().strip()

        if cmd == 'exit':
            log_action("EXITED")
            break
        elif cmd.startswith('stop '):
            container = cmd.split(' ')[1]
            log_action(f"STOPPED:{container}")
            print(f"Container {container} stopped.")
        elif cmd.startswith('start '):
            container = cmd.split(' ')[1]
            log_action(f"STARTED:{container}")
            print(f"Container {container} started.")
        else:
            print("Unknown command.")

if __name__ == '__main__':
    main()
CLI_EOF
chmod +x /home/user/interactive_cli.py

mkdir -p /tmp/verifier_hooks /tmp/verifier_bin
cat << 'HOOK_EOF' > /tmp/verifier_hooks/sitecustomize.py
import os
import shutil

if os.environ.get("VERIFIER_LOW_STORAGE") == "1":
    _real_statvfs = os.statvfs
    def _low_statvfs(path):
        result = _real_statvfs(path)
        try:
            target = os.path.realpath(os.fspath(path))
        except Exception:
            target = ""
        if target == "/home/user/device_data" or target.startswith("/home/user/device_data/"):
            values = list(result)
            values[3] = 0
            values[4] = 0
            return os.statvfs_result(values)
        return result
    os.statvfs = _low_statvfs

    _real_disk_usage = shutil.disk_usage
    def _low_disk_usage(path):
        try:
            target = os.path.realpath(os.fspath(path))
        except Exception:
            target = ""
        if target == "/home/user/device_data" or target.startswith("/home/user/device_data/"):
            return shutil._ntuple_diskusage(10 * 1024 * 1024, 10 * 1024 * 1024, 0)
        return _real_disk_usage(path)
    shutil.disk_usage = _low_disk_usage

    try:
        import psutil
        _real_psutil_disk_usage = psutil.disk_usage
        def _low_psutil_disk_usage(path):
            target = os.path.realpath(os.fspath(path))
            if target == "/home/user/device_data" or target.startswith("/home/user/device_data/"):
                return psutil._common.sdiskusage(10 * 1024 * 1024, 10 * 1024 * 1024, 0, 100.0)
            return _real_psutil_disk_usage(path)
        psutil.disk_usage = _low_psutil_disk_usage
    except Exception:
        pass

# Record actual use of pexpect.spawn by the submitted process.
try:
    import pexpect
    _real_spawn = pexpect.spawn
    def _tracked_spawn(command, args=[], *pargs, **kwargs):
        with open("/tmp/verifier_pexpect_trace", "a") as trace:
            trace.write(repr((command, args)) + "\n")
        return _real_spawn(command, args, *pargs, **kwargs)
    pexpect.spawn = _tracked_spawn
except Exception:
    pass
HOOK_EOF

cat << 'DF_EOF' > /tmp/verifier_bin/df
#!/bin/sh
if [ "$VERIFIER_LOW_STORAGE" = "1" ]; then
    echo 'Filesystem 1K-blocks Used Available Use% Mounted on'
    echo 'verifier 10240 10240 0 100% /home/user/device_data'
else
    exec /bin/df "$@"
fi
DF_EOF
chmod +x /tmp/verifier_bin/df

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import subprocess
import sys
import time

SCRIPT = "/home/user/edge_manager.py"
STATUS = "/home/user/edge_status.log"
BACKEND = "/home/user/cli_backend.log"
TRACE = "/tmp/verifier_pexpect_trace"


def lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def clear_outputs():
    for path in (STATUS, BACKEND, TRACE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_manager(extra_env=None):
    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/verifier_hooks" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["PATH"] = "/tmp/verifier_bin:" + env.get("PATH", "")
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )


def assert_port_closed():
    deadline = time.time() + 3
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            if sock.connect_ex(("127.0.0.1", 9090)) != 0:
                return
        time.sleep(0.05)
    raise AssertionError("Port 9090 is unexpectedly occupied; cannot test connectivity failure")


def start_service():
    code = r'''
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 9090))
s.listen(8)
while True:
    c, _ = s.accept()
    c.close()
'''
    proc = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError("Verifier mock service failed to start")
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            if sock.connect_ex(("127.0.0.1", 9090)) == 0:
                return proc
        time.sleep(0.05)
    proc.terminate()
    raise AssertionError("Verifier mock service did not become reachable")


def test_edge_manager_script_exists():
    path = "/home/user/edge_manager.py"
    assert os.path.exists(path), f"The script {path} does not exist. Did you create it?"
    assert os.path.isfile(path), f"{path} is not a file."


def test_device_data_directory_exists():
    path = "/home/user/device_data"
    assert os.path.exists(path), f"The directory {path} does not exist."
    assert os.path.isdir(path), f"{path} is not a directory."


def test_execute_edge_manager_and_failure_paths():
    os.makedirs("/home/user/device_data", exist_ok=True)
    assert_port_closed()

    # A derived low-space condition must stop before connectivity or CLI work.
    clear_outputs()
    run_manager({"VERIFIER_LOW_STORAGE": "1"})
    assert os.path.exists(STATUS), "Low-storage run did not create edge_status.log"
    assert lines(STATUS) == ["STORAGE: FAILED"]
    assert not os.path.exists(BACKEND), "CLI was invoked after storage failure"

    # With normal storage but no listener, connectivity must fail before the CLI.
    clear_outputs()
    assert_port_closed()
    run_manager()
    assert os.path.exists(STATUS), "Connectivity-failure run did not create edge_status.log"
    assert lines(STATUS) == ["STORAGE: OK", "CONNECTIVITY: FAILED"]
    assert not os.path.exists(BACKEND), "CLI was invoked after connectivity failure"

    # Finally run the artifact against a verifier-controlled service and CLI.
    clear_outputs()
    service = start_service()
    try:
        result = run_manager()
    finally:
        service.terminate()
        try:
            service.wait(timeout=3)
        except subprocess.TimeoutExpired:
            service.kill()
            service.wait()
    assert result.returncode == 0, f"edge_manager.py failed: {result.stderr}"
    assert os.path.exists(TRACE), "The deployment did not use pexpect.spawn"
    assert "interactive_cli.py" in open(TRACE, "r").read(), "pexpect did not launch the required interactive CLI"


def test_edge_status_log_contents():
    path = "/home/user/edge_status.log"
    assert os.path.exists(path), f"The log file {path} was not created."

    with open(path, "r") as f:
        content = [line.strip() for line in f.readlines() if line.strip()]

    expected = [
        "STORAGE: OK",
        "CONNECTIVITY: OK",
        "DEPLOYMENT: SUCCESS"
    ]

    assert content == expected, f"Contents of {path} do not match the expected output. Got: {content}"


def test_cli_backend_log_contents():
    path = "/home/user/cli_backend.log"
    assert os.path.exists(path), f"The backend log file {path} was not created. Did the interactive script run successfully?"

    with open(path, "r") as f:
        content = [line.strip() for line in f.readlines() if line.strip()]

    expected = [
        "AUTH_SUCCESS",
        "STOPPED:legacy-sensor",
        "STARTED:vision-sensor-v2",
        "EXITED"
    ]

    assert content == expected, f"Contents of {path} do not match the expected sequence. Got: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
