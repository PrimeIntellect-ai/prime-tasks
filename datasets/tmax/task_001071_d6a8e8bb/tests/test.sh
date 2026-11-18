#!/bin/bash
set -u
mkdir -p /logs/verifier

SOCAT_REAL="/tmp/socat.verifier-real.$$"
SOCAT_PATH="$(command -v socat)"
SOCAT_CALLS="/tmp/verifier_socat_calls"
rm -f "$SOCAT_CALLS"

cleanup() {
    pkill -KILL -u user 2>/dev/null || true
    if [ -e "$SOCAT_REAL" ]; then
        rm -f "$SOCAT_PATH"
        mv "$SOCAT_REAL" "$SOCAT_PATH"
    fi
}
trap cleanup EXIT

mv "$SOCAT_PATH" "$SOCAT_REAL"
cat > "$SOCAT_PATH" <<EOF
#!/bin/bash
printf '%s %s\n' "\$(date +%s%N)" "\$*" >> "$SOCAT_CALLS"
exec "$SOCAT_REAL" "\$@"
EOF
chmod 755 "$SOCAT_PATH"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import socket
import subprocess
import threading
import time

OBS_STACK_DIR = "/home/user/obs_stack"
DASHBOARD_LOG = os.path.join(OBS_STACK_DIR, "dashboard.log")
AGGREGATOR_BIN = os.path.join(OBS_STACK_DIR, "aggregator")
AGGREGATOR_SOURCE = os.path.join(OBS_STACK_DIR, "aggregator.c")
START_SH = os.path.join(OBS_STACK_DIR, "start.sh")
TELEMETRY_SERVER = os.path.join(OBS_STACK_DIR, "telemetry_server.py")
SOCAT_CALLS = "/tmp/verifier_socat_calls"


def test_dashboard_log_exists():
    assert os.path.isfile(DASHBOARD_LOG), f"File {DASHBOARD_LOG} was not created. The start.sh script or aggregator failed."


def test_dashboard_log_content():
    with open(DASHBOARD_LOG, "r") as f:
        content = f.read().strip()
    expected = "[SUCCESS] Metrics received: cpu_usage=42% mem_usage=60%"
    assert expected in content, f"Content of {DASHBOARD_LOG} is incorrect. Expected to contain '{expected}', but got '{content}'."


def test_aggregator_binary_exists():
    assert os.path.isfile(AGGREGATOR_BIN), f"Compiled executable {AGGREGATOR_BIN} does not exist."
    assert os.access(AGGREGATOR_BIN, os.X_OK), f"File {AGGREGATOR_BIN} is not executable."
    with open(AGGREGATOR_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "aggregator is not a compiled native executable."


def test_start_sh_contains_socat():
    with open(START_SH, "r") as f:
        content = f.read()
    assert "socat" in content, "start.sh does not appear to use 'socat' for port forwarding as requested."


def run_delayed_server_test(executable, payload, delay=2.2):
    errors = []

    def server():
        try:
            time.sleep(delay)
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                s.bind(("127.0.0.1", 8080))
                s.listen(1)
                s.settimeout(8)
                conn, _ = s.accept()
                with conn:
                    conn.sendall((payload + "\n").encode())
        except Exception as exc:
            errors.append(exc)

    try:
        os.remove(DASHBOARD_LOG)
    except FileNotFoundError:
        pass
    thread = threading.Thread(target=server, daemon=True)
    thread.start()
    started = time.monotonic()
    result = subprocess.run(
        ["runuser", "-u", "user", "--", executable],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=14,
    )
    elapsed = time.monotonic() - started
    thread.join(timeout=2)
    assert not errors, f"Test endpoint failed: {errors}"
    assert not thread.is_alive(), "aggregator never connected to the delayed endpoint"
    assert result.returncode == 0, "aggregator failed instead of retrying until the endpoint became available"
    assert elapsed >= delay - 0.25, "aggregator did not actually wait and retry"
    with open(DASHBOARD_LOG) as f:
        actual = f.read().strip()
    assert actual == f"[SUCCESS] Metrics received: {payload}", f"Unexpected dynamic output: {actual!r}"


def test_source_and_binary_implement_retrying_client(tmp_path):
    subprocess.run(["pkill", "-KILL", "-u", "user"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert os.path.isfile(AGGREGATOR_SOURCE), "aggregator.c is missing"
    rebuilt = str(tmp_path / "aggregator_from_source")
    subprocess.run(["gcc", AGGREGATOR_SOURCE, "-o", rebuilt], check=True, timeout=20)

    run_delayed_server_test(rebuilt, "probe_source=" + secrets.token_hex(10))
    run_delayed_server_test(AGGREGATOR_BIN, "probe_binary=" + secrets.token_hex(10))

    # Ten attempts with one-second waits should not fail immediately or retry forever.
    subprocess.run(["pkill", "-KILL", "-u", "user"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    started = time.monotonic()
    result = subprocess.run(
        ["runuser", "-u", "user", "--", rebuilt],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=14,
    )
    elapsed = time.monotonic() - started
    assert result.returncode != 0, "aggregator reported success when no endpoint existed"
    assert 8.0 <= elapsed <= 12.5, f"retry duration {elapsed:.2f}s is inconsistent with ten one-second attempts"


def test_start_script_executes_ordered_forwarded_stack():
    subprocess.run(["pkill", "-KILL", "-u", "user"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for path in (DASHBOARD_LOG, SOCAT_CALLS, "/tmp/verifier_telemetry_started", "/tmp/verifier_aggregator_started"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    payload = "integration_" + secrets.token_hex(12)
    telemetry_backup = TELEMETRY_SERVER + ".verifier-backup"
    binary_backup = "/tmp/aggregator.verifier-real"
    shutil.copy2(TELEMETRY_SERVER, telemetry_backup)
    shutil.move(AGGREGATOR_BIN, binary_backup)

    telemetry_code = f'''import socket, time\nopen("/tmp/verifier_telemetry_started", "w").write(str(time.time_ns()))\ntime.sleep(2)\nwith socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:\n    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)\n    s.bind(("127.0.0.1", 9090))\n    s.listen(1)\n    conn, _ = s.accept()\n    with conn:\n        conn.sendall({(payload + chr(10)).encode()!r})\n'''
    with open(TELEMETRY_SERVER, "w") as f:
        f.write(telemetry_code)
    os.chmod(TELEMETRY_SERVER, 0o777)

    with open(AGGREGATOR_BIN, "w") as f:
        f.write("#!/bin/bash\ndate +%s%N > /tmp/verifier_aggregator_started\nexec " + binary_backup + " \"$@\"\n")
    os.chmod(AGGREGATOR_BIN, 0o755)

    try:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "env", "PATH=" + os.environ.get("PATH", ""), START_SH],
            cwd=OBS_STACK_DIR,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=16,
        )
        assert result.returncode == 0, "start.sh did not successfully execute the stack"
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline and not os.path.isfile(DASHBOARD_LOG):
            time.sleep(0.05)
        with open(DASHBOARD_LOG) as f:
            actual = f.read().strip()
        assert actual == f"[SUCCESS] Metrics received: {payload}", f"start.sh did not transport the dynamic metrics through 8080 to 9090: {actual!r}"

        assert os.path.isfile(SOCAT_CALLS), "start.sh never executed socat"
        with open(SOCAT_CALLS) as f:
            calls = [line.strip() for line in f if line.strip()]
        assert calls, "start.sh never executed socat"
        call = calls[-1]
        assert "8080" in call and "9090" in call and "TCP" in call.upper(), f"socat was not invoked as an 8080-to-9090 TCP forward: {call}"

        with open("/tmp/verifier_telemetry_started") as f:
            telemetry_time = int(f.read().strip())
        with open("/tmp/verifier_aggregator_started") as f:
            aggregator_time = int(f.read().strip())
        socat_time = int(call.split(None, 1)[0])
        assert telemetry_time <= aggregator_time, "aggregator was executed before the telemetry server was started"
        assert socat_time <= aggregator_time, "aggregator was executed before socat was established"
    finally:
        subprocess.run(["pkill", "-KILL", "-u", "user"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if os.path.exists(telemetry_backup):
            shutil.move(telemetry_backup, TELEMETRY_SERVER)
        if os.path.exists(binary_backup):
            try:
                os.remove(AGGREGATOR_BIN)
            except FileNotFoundError:
                pass
            shutil.move(binary_backup, AGGREGATOR_BIN)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
