#!/bin/bash
set +e
mkdir -p /logs/verifier
SERVER_PID=""

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}

verify() {
    local workspace=/home/user/workspace
    local fleet=/home/user/edge_fleet

    [ -f "$workspace/monitor.c" ] && [ ! -L "$workspace/monitor.c" ] || return 1
    [ -f "$workspace/deploy.sh" ] && [ ! -L "$workspace/deploy.sh" ] || return 1

    # Independently compile the submitted C source so a fabricated deployment
    # tree cannot substitute for an implementation of the monitoring agent.
    gcc "$workspace/monitor.c" -o /tmp/monitor_from_source || return 1
    [ -x /tmp/monitor_from_source ] || return 1

    rm -f /tmp/edge_test_ports
    python3 - <<'PY' &
import socket
import threading
import time

listeners = []
for _ in range(2):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 0))
    sock.listen(16)
    listeners.append(sock)

probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
probe.bind(("127.0.0.1", 0))
down_port = probe.getsockname()[1]
probe.close()

ports = [listeners[0].getsockname()[1], down_port, listeners[1].getsockname()[1]]
with open("/tmp/edge_test_ports", "w") as f:
    f.write("%d %d %d\n" % tuple(ports))

def serve(sock):
    while True:
        try:
            conn, _ = sock.accept()
            conn.close()
        except OSError:
            return

for sock in listeners:
    threading.Thread(target=serve, args=(sock,), daemon=True).start()

while True:
    time.sleep(60)
PY
    SERVER_PID=$!

    for _ in $(seq 1 100); do
        [ -s /tmp/edge_test_ports ] && break
        sleep 0.05
    done
    [ -s /tmp/edge_test_ports ] || return 1

    read -r port1 port2 port3 < /tmp/edge_test_ports || return 1
    [ -n "$port1" ] && [ -n "$port2" ] && [ -n "$port3" ] || return 1

    rm -f "$workspace/deploy.log" "$workspace/monitor_v2"
    for i in 1 2 3; do
        rm -rf "$fleet/node_$i/versions/v2"
        rm -f "$fleet/node_$i/status.log" "$fleet/node_$i/current"
        ln -s "$fleet/node_$i/versions/v1" "$fleet/node_$i/current" || return 1
    done
    printf '%s\n' "$port1" > "$fleet/node_1/config.txt"
    printf '%s\n' "$port2" > "$fleet/node_2/config.txt"
    printf '%s\n' "$port3" > "$fleet/node_3/config.txt"

    # Execute the requested deployment against two live endpoints and one
    # closed endpoint. Running from the workspace also supports a relative
    # monitor_v2 output name.
    if ! (cd "$workspace" && timeout 30 bash ./deploy.sh) >/tmp/deploy.stdout 2>/tmp/deploy.stderr; then
        cat /tmp/deploy.stdout /tmp/deploy.stderr
        return 1
    fi

    cleanup
    SERVER_PID=""

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import subprocess
import tempfile
import threading

WORKSPACE = "/home/user/workspace"
FLEET = "/home/user/edge_fleet"


def test_deploy_log_contents():
    log_path = f"{WORKSPACE}/deploy.log"
    assert os.path.isfile(log_path), f"Deployment log {log_path} is missing."
    with open(log_path, "r") as f:
        lines = [line.rstrip("\n") for line in f]

    assert "[node_1]: SUCCESS" in lines, "Expected '[node_1]: SUCCESS' in deploy.log"
    assert "[node_2]: ROLLBACK" in lines, "Expected '[node_2]: ROLLBACK' in deploy.log"
    assert "[node_3]: SUCCESS" in lines, "Expected '[node_3]: SUCCESS' in deploy.log"


def test_symlink_states():
    expected_targets = {1: "versions/v2", 2: "versions/v1", 3: "versions/v2"}
    for i in range(1, 4):
        symlink_path = f"{FLEET}/node_{i}/current"
        assert os.path.islink(symlink_path), f"{symlink_path} is missing or not a symlink"
        target = os.readlink(symlink_path)
        if not os.path.isabs(target):
            assert target.endswith(expected_targets[i]), (
                f"Symlink {symlink_path} points to {target}, expected it to point to {expected_targets[i]}"
            )
        else:
            expected_abs = f"{FLEET}/node_{i}/{expected_targets[i]}"
            assert target == expected_abs, (
                f"Symlink {symlink_path} points to {target}, expected {expected_abs}"
            )


def test_status_logs():
    expected_status = {1: "STATUS: UP", 2: "STATUS: DOWN", 3: "STATUS: UP"}
    for i in range(1, 4):
        log_path = f"{FLEET}/node_{i}/status.log"
        assert os.path.isfile(log_path), f"Status log {log_path} is missing."
        with open(log_path, "r") as f:
            content = f.read().strip()
        assert content == expected_status[i], (
            f"Expected '{expected_status[i]}' in {log_path}, got '{content}'"
        )


def test_v2_directories_and_real_binaries_exist():
    built = f"{WORKSPACE}/monitor_v2"
    assert os.path.isfile(built) and not os.path.islink(built), "monitor_v2 was not compiled as a regular file"
    assert os.access(built, os.X_OK), "monitor_v2 is not executable"
    with open(built, "rb") as f:
        built_bytes = f.read()
    assert built_bytes.startswith(b"\x7fELF"), "monitor_v2 is not a compiled native executable"

    for i in range(1, 4):
        v2_dir = f"{FLEET}/node_{i}/versions/v2"
        assert os.path.isdir(v2_dir), f"Directory {v2_dir} was not created."
        monitor_binary = os.path.join(v2_dir, "monitor")
        assert os.path.isfile(monitor_binary), f"Monitor binary {monitor_binary} is missing."
        assert not os.path.islink(monitor_binary), f"Monitor binary {monitor_binary} must be a copied regular file."
        assert os.access(monitor_binary, os.X_OK), f"Monitor binary {monitor_binary} is not executable."
        with open(monitor_binary, "rb") as f:
            assert f.read() == built_bytes, f"{monitor_binary} is not a copy of monitor_v2"


def run_monitor(binary, node, expected_code, expected_status):
    result = subprocess.run([binary, node], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == expected_code, (
        f"{binary} returned {result.returncode}; expected {expected_code}. stderr={result.stderr!r}"
    )
    with open(os.path.join(node, "status.log"), "r") as f:
        assert f.read().strip() == expected_status


def test_compiled_source_and_deployed_agents_perform_tcp_diagnostics():
    binaries = [
        "/tmp/monitor_from_source",
        f"{WORKSPACE}/monitor_v2",
        f"{FLEET}/node_1/versions/v2/monitor",
        f"{FLEET}/node_2/versions/v2/monitor",
        f"{FLEET}/node_3/versions/v2/monitor",
    ]

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(16)
    up_port = listener.getsockname()[1]

    def accept_connections():
        while True:
            try:
                conn, _ = listener.accept()
                conn.close()
            except OSError:
                return

    thread = threading.Thread(target=accept_connections, daemon=True)
    thread.start()

    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    down_port = probe.getsockname()[1]
    probe.close()

    try:
        with tempfile.TemporaryDirectory(prefix="monitor-node-") as node:
            for binary in binaries:
                with open(os.path.join(node, "config.txt"), "w") as f:
                    f.write(f"{up_port}\n")
                run_monitor(binary, node, 0, "STATUS: UP")

                with open(os.path.join(node, "config.txt"), "w") as f:
                    f.write(f"{down_port}\n")
                run_monitor(binary, node, 1, "STATUS: DOWN")
    finally:
        listener.close()


def test_agent_requires_exactly_one_argument():
    binary = "/tmp/monitor_from_source"
    no_arg = subprocess.run([binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    two_args = subprocess.run([binary, "/tmp", "/tmp"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert no_arg.returncode != 0
    assert two_args.returncode != 0
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

if verify; then
    cleanup
    echo "1" > /logs/verifier/reward.txt
else
    cleanup
    echo "0" > /logs/verifier/reward.txt
fi
