#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import time
import ctypes
import pytest

SCRIPT_PATH = "/home/user/run_analysis.sh"
SO_PATH = "/home/user/interceptor/hook.so"
KEYS_FILE = "/home/user/extracted_keys.txt"
TRACE_FILE = "/run/verifier-malware-exec.trace"
C2_DIR = "/run/verifier-c2"
C2_LOG = os.path.join(C2_DIR, "issued_keys.txt")


def test_run_analysis_script_exists_and_executable():
    """Verify that the user created the run_analysis.sh script and made it executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Missing analysis script at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), (
        f"Analysis script at {SCRIPT_PATH} is not executable. Did you run chmod +x?"
    )


def test_interceptor_build_success():
    """Verify that the interceptor is a loadable shared object exporting recv."""
    assert os.path.isfile(SO_PATH), (
        f"Missing compiled interceptor at {SO_PATH}. The build.sh script may have failed or was not run."
    )

    result = subprocess.run(
        ["readelf", "-h", SO_PATH], capture_output=True, text=True, check=False
    )
    assert result.returncode == 0, f"{SO_PATH} is not a valid ELF file: {result.stderr}"
    assert re.search(r"Type:\s+DYN", result.stdout), f"{SO_PATH} is not a shared object"

    # Load in a child process so a defective interposer cannot damage pytest itself.
    load = subprocess.run(
        [
            "python3",
            "-c",
            "import ctypes; lib=ctypes.CDLL(%r); assert getattr(lib, 'recv')" % SO_PATH,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert load.returncode == 0, (
        f"{SO_PATH} could not be dynamically loaded or does not export recv.\n"
        f"Stdout: {load.stdout}\nStderr: {load.stderr}"
    )


def _wait_for_port(port, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Service on port {port} did not become ready")


def _install_controlled_c2():
    # Stop stale instances, then install a verifier-controlled C2 whose random
    # responses are recorded somewhere the unprivileged analysis script cannot read.
    subprocess.run(["pkill", "-f", "gunicorn.*127.0.0.1:5000"], check=False)
    subprocess.run(["pkill", "-x", "nginx"], check=False)
    time.sleep(0.5)

    os.makedirs(C2_DIR, exist_ok=True)
    os.chmod(C2_DIR, 0o700)
    with open(C2_LOG, "w"):
        pass
    os.chmod(C2_LOG, 0o600)

    app_source = r'''from flask import Flask
import os
import secrets

app = Flask(__name__)
LOG = "/run/verifier-c2/issued_keys.txt"

@app.route("/get_key")
def get_key():
    key = secrets.token_hex(16)
    fd = os.open(LOG, os.O_WRONLY | os.O_APPEND)
    try:
        os.write(fd, (key + "\\n").encode("ascii"))
    finally:
        os.close(fd)
    return key
'''
    with open("/app/c2/app.py", "w") as f:
        f.write(app_source)

    # Make the supplied service launcher idempotent so legitimate analysis scripts
    # may call it even though the verifier has already started the controlled C2.
    launcher = r'''#!/bin/bash
redis-server --daemonize yes >/dev/null 2>&1 || true
if ! pgrep -f 'gunicorn.*127.0.0.1:5000' >/dev/null; then
    cd /app/c2 && gunicorn -w 1 -b 127.0.0.1:5000 app:app --daemon
fi
if ! pgrep -x nginx >/dev/null; then
    nginx -c /app/nginx.conf
fi
exit 0
'''
    with open("/app/start_services.sh", "w") as f:
        f.write(launcher)

    # The analysis runs as user; prevent it from replacing the malware or C2 and
    # reading the verifier's issuance log.
    for path in ["/app", "/app/c2"]:
        os.chown(path, 0, 0)
        os.chmod(path, 0o755)
    for path in ["/app/malware.bin", "/app/c2/app.py", "/app/start_services.sh", "/app/nginx.conf"]:
        os.chown(path, 0, 0)
        os.chmod(path, 0o755 if path.endswith(("malware.bin", "start_services.sh")) else 0o644)

    subprocess.run(["/app/start_services.sh"], check=True)
    _wait_for_port(5000)
    _wait_for_port(8080)


def test_key_extraction_metric():
    """Execute the pipeline and verify executions, preload use, and C2 provenance."""
    _install_controlled_c2()

    for path in [KEYS_FILE, TRACE_FILE]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    try:
        result = subprocess.run(
            [
                "strace", "-f", "-v", "-s", "4096",
                "-e", "trace=execve", "-o", TRACE_FILE,
                "runuser", "-u", "user", "--", SCRIPT_PATH,
            ],
            check=False,
            timeout=300,
            capture_output=True,
            text=True,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(
            f"Execution of {SCRIPT_PATH} timed out after 300 seconds. "
            "Check for infinite loops in your retry logic."
        )

    assert result.returncode == 0, (
        f"Execution of {SCRIPT_PATH} failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    with open(TRACE_FILE, "r", errors="replace") as f:
        trace_lines = f.read().splitlines()

    malware_execs = [
        line for line in trace_lines
        if re.search(r'execve\("/app/malware\.bin"', line) and re.search(r'= 0$', line)
    ]
    assert len(malware_execs) == 100, (
        f"Expected exactly 100 successful executions of /app/malware.bin, "
        f"but observed {len(malware_execs)}."
    )
    for line in malware_execs:
        assert re.search(
            r'LD_PRELOAD=[^"\]]*/home/user/interceptor/hook\.so', line
        ), "Every malware execution must use /home/user/interceptor/hook.so via LD_PRELOAD"

    with open(C2_LOG, "r") as f:
        issued = [line.strip() for line in f if line.strip()]
    assert len(issued) == 100, (
        f"The controlled C2 observed {len(issued)} key requests for 100 malware executions; "
        "keys must be obtained by those malware executions rather than separate requests."
    )
    assert all(re.fullmatch(r"[0-9a-f]{32}", key) for key in issued)

    assert os.path.isfile(KEYS_FILE), f"Output file {KEYS_FILE} was not created by the analysis script."
    with open(KEYS_FILE, "r") as f:
        content = f.read().splitlines()

    normalized = [line.strip() for line in content]
    assert all(re.fullmatch(r"[a-fA-F0-9]{32}", line) for line in normalized), (
        "extracted_keys.txt must contain exactly one 32-character hexadecimal key per line"
    )

    valid_keys = set(normalized)
    issued_keys = set(issued)
    unissued = valid_keys - issued_keys
    assert not unissued, (
        f"Found {len(unissued)} keys that were not issued by the controlled C2 during malware execution."
    )

    expected_keys = 100
    score = len(valid_keys) / float(expected_keys)
    threshold = 0.95
    assert score >= threshold, (
        f"Extraction success rate is below the required threshold.\n"
        f"Metric (score): {score}\n"
        f"Threshold: >= {threshold}\n"
        f"Found {len(valid_keys)} unique, valid C2-issued keys out of {expected_keys} expected."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
