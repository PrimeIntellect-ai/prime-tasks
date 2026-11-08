#!/bin/bash
set -e
mkdir -p /logs/verifier

READY_FILE=/tmp/verifier_vnc_ready
CONNECT_FILE=/tmp/verifier_vnc_connections
rm -f "$READY_FILE" "$CONNECT_FILE"

cat > /tmp/verifier_vnc_server.py <<'PY_EOF'
import socket

ready = "/tmp/verifier_vnc_ready"
connections = "/tmp/verifier_vnc_connections"

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("127.0.0.1", 5901))
sock.listen(8)
with open(ready, "w") as f:
    f.write("ready\n")

while True:
    conn, addr = sock.accept()
    with open(connections, "a") as f:
        f.write(f"{addr[0]}:{addr[1]}\n")
    conn.close()
PY_EOF

python3 /tmp/verifier_vnc_server.py >/tmp/verifier_vnc_server.out 2>&1 &
SERVER_PID=$!
cleanup() {
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 50); do
    if [ -f "$READY_FILE" ]; then
        break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "0" > /logs/verifier/reward.txt
        exit 0
    fi
    sleep 0.1
done
if [ ! -f "$READY_FILE" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import subprocess
from pathlib import Path

APP_DIR = "/home/user/app"
GO_BINARY = os.path.join(APP_DIR, "vnc-monitor")
ENV_FILE = os.path.join(APP_DIR, "monitor.env")
LOG_FILE = os.path.join(APP_DIR, "status.log")
SIMULATOR = os.path.join(APP_DIR, "systemd_sim.sh")
CONNECT_FILE = Path("/tmp/verifier_vnc_connections")
EXPECTED_CONTENT = "STATUS: OK | TZ: Etc/UTC | LANG: C.UTF-8 | VNC_TARGET: 127.0.0.1:5901"


def test_go_binary_exists_and_executable():
    assert os.path.isfile(GO_BINARY), f"Compiled Go binary {GO_BINARY} does not exist. Did you compile it?"
    assert os.access(GO_BINARY, os.X_OK), f"Go binary {GO_BINARY} is not executable."


def test_env_file_exists():
    assert os.path.isfile(ENV_FILE), f"Environment file {ENV_FILE} does not exist."


def test_status_log_exists():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} does not exist. The application may not have run successfully."


def test_status_log_content():
    with open(LOG_FILE, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_CONTENT, f"Log file content does not match expected output.\nExpected: {EXPECTED_CONTENT}\nGot: {content}"


def test_binary_is_a_go_elf_executable():
    with open(GO_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "vnc-monitor is not an ELF executable."
    result = subprocess.run(
        ["/usr/bin/go", "version", "-m", GO_BINARY],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert result.returncode == 0 and "go1." in result.stdout, \
        f"vnc-monitor does not contain valid Go build information:\n{result.stdout}"


def test_environment_file_defines_required_values():
    lines = []
    for line in Path(ENV_FILE).read_text().splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            lines.append(stripped)
    tokens = shlex.split(" ".join(lines))
    assert all("=" in token for token in tokens), "monitor.env contains an invalid assignment."
    values = dict(token.split("=", 1) for token in tokens)
    assert values.get("LANG") == "C.UTF-8"
    assert values.get("TZ") == "Etc/UTC"
    assert values.get("QEMU_VNC_PORT") == "5901"


def test_systemd_simulator_is_present_and_unchanged():
    expected = '''#!/bin/bash
if [ ! -f /home/user/app/monitor.env ]; then
    echo "Error: /home/user/app/monitor.env not found"
    exit 1
fi

if [ ! -x /home/user/app/vnc-monitor ]; then
    echo "Error: Executable /home/user/app/vnc-monitor not found or not executable"
    exit 1
fi

# Simulate systemd EnvironmentFile
env -i bash -c "export \$(grep -v '^#' /home/user/app/monitor.env | xargs) && /home/user/app/vnc-monitor"
'''
    assert Path(SIMULATOR).is_file()
    assert os.access(SIMULATOR, os.X_OK)
    assert Path(SIMULATOR).read_text() == expected, "systemd_sim.sh was modified."


def test_binary_rejects_invalid_startup_environments_and_simulator_runs_it():
    log = Path(LOG_FILE)
    log.unlink(missing_ok=True)
    CONNECT_FILE.unlink(missing_ok=True)

    invalid_envs = [
        {"LANG": "bad", "TZ": "Etc/UTC", "QEMU_VNC_PORT": "5901"},
        {"LANG": "C.UTF-8", "TZ": "bad", "QEMU_VNC_PORT": "5901"},
        {"LANG": "C.UTF-8", "TZ": "Etc/UTC"},
    ]
    for env in invalid_envs:
        result = subprocess.run(
            [GO_BINARY], env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
        )
        assert result.returncode != 0, f"Binary accepted invalid environment {env}."
        assert not log.exists(), "Binary wrote a success log for an invalid environment."
        assert not CONNECT_FILE.exists(), "Binary contacted VNC despite an invalid startup environment."

    result = subprocess.run(
        [SIMULATOR], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
    )
    assert result.returncode == 0, f"systemd_sim.sh failed:\n{result.stdout}"
    assert "Service started successfully." in result.stdout
    assert CONNECT_FILE.is_file() and CONNECT_FILE.read_text().strip(), \
        "No connection to the verifier's VNC server on port 5901 was observed."
    assert log.is_file(), "The executed application did not generate status.log."
    assert log.read_text().strip() == EXPECTED_CONTENT
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
