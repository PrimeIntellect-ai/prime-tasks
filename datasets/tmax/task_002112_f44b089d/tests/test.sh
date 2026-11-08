#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import time
from pathlib import Path

import pytest
from PIL import Image, ImageDraw, ImageFont

PROVISION_SCRIPT = "/home/user/provision.py"
IMAGE_PATH = "/app/provision_specs.png"
INSTALLER_PATH = "/app/legacy_installer.py"


def write_specs_image(username, start_port, rotate_size):
    image = Image.new("RGB", (1000, 260), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 48)
    text = (
        f"Username: {username}\n"
        f"StartPort: {start_port}\n"
        f"RotateSize: {rotate_size}"
    )
    draw.multiline_text((25, 20), text, fill="black", font=font, spacing=15)
    image.save(IMAGE_PATH)


def install_traced_installer(trace_path):
    installer = '''#!/usr/bin/env python3
import json
import os
import sys
import time

TRACE_PATH = %r


def record(kind, instance_id):
    try:
        cmdline = open("/proc/self/cmdline", "rb").read().decode("utf-8", "replace").split("\\0")
    except Exception:
        cmdline = []
    entry = json.dumps({
        "kind": kind,
        "id": str(instance_id),
        "time": time.monotonic(),
        "pid": os.getpid(),
        "cmdline": cmdline,
    }) + "\\n"
    fd = os.open(TRACE_PATH, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, entry.encode("utf-8"))
    finally:
        os.close(fd)


if len(sys.argv) != 2:
    print("Usage: legacy_installer.py <instance_id>")
    sys.exit(1)

instance_id = sys.argv[1]
record("start", instance_id)
print("Starting interactive installer...")
sys.stdout.flush()
time.sleep(1.0)
print("Enter Admin Username: ", end="")
sys.stdout.flush()
user = sys.stdin.readline().strip()
time.sleep(0.5)
print("Enter Service Port: ", end="")
sys.stdout.flush()
port = sys.stdin.readline().strip()
time.sleep(0.5)

os.makedirs("/home/user/logs", exist_ok=True)
with open(f"/home/user/logs/service_{instance_id}.log", "w") as f:
    f.write(f"Provisioned instance {instance_id} for {user} on port {port}\\n")
record("end", instance_id)
''' % trace_path
    Path(INSTALLER_PATH).write_text(installer)
    os.chmod(INSTALLER_PATH, 0o755)


def clean_outputs():
    for path in (
        "/home/user/create_users.sh",
        "/home/user/service_logrotate.conf",
        "/home/user/firewall.sh",
    ):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    logs = Path("/home/user/logs")
    logs.mkdir(parents=True, exist_ok=True)
    for path in logs.glob("service_*.log"):
        path.unlink()


def run_provision():
    start_time = time.time()
    result = subprocess.run(
        ["python3", PROVISION_SCRIPT],
        capture_output=True,
        text=True,
        timeout=8,
    )
    runtime = time.time() - start_time
    return result, runtime


def read_trace(trace_path):
    assert os.path.exists(trace_path), "The legacy installer was never executed"
    with open(trace_path, "r") as f:
        return [json.loads(line) for line in f if line.strip()]


def assert_installer_executions(trace_path):
    events = read_trace(trace_path)
    starts = [event for event in events if event["kind"] == "start"]
    ends = [event for event in events if event["kind"] == "end"]

    expected_ids = [str(i) for i in range(10)]
    assert sorted(event["id"] for event in starts) == expected_ids, \
        f"Installer must be started exactly once for IDs 0-9; got: {starts}"
    assert sorted(event["id"] for event in ends) == expected_ids, \
        f"Installer must complete exactly once for IDs 0-9; got: {ends}"

    for event in starts:
        cmdline = event.get("cmdline", [])
        assert INSTALLER_PATH in cmdline, \
            f"Expected execution of {INSTALLER_PATH}; command line was {cmdline}"
        assert cmdline[-1] == event["id"], \
            f"Installer ID argument was incorrect: {cmdline}"

    timeline = []
    for event in starts:
        timeline.append((event["time"], 1))
    for event in ends:
        timeline.append((event["time"], -1))
    timeline.sort(key=lambda item: (item[0], item[1]))

    active = 0
    max_active = 0
    for _, delta in timeline:
        active += delta
        max_active = max(max_active, active)
    assert max_active >= 2, \
        f"Installer executions did not overlap; maximum concurrency was {max_active}"


def assert_generated_content(username, start_port, rotate_size):
    create_users_path = "/home/user/create_users.sh"
    assert os.path.exists(create_users_path), f"Missing file: {create_users_path}"
    with open(create_users_path, "r") as f:
        create_users_content = f.read()
    for i in range(10):
        expected_cmd = f"useradd -m -s /bin/bash {username}_{i}"
        assert expected_cmd in create_users_content, \
            f"Missing expected command in {create_users_path}: {expected_cmd}"

    logrotate_path = "/home/user/service_logrotate.conf"
    assert os.path.exists(logrotate_path), f"Missing file: {logrotate_path}"
    with open(logrotate_path, "r") as f:
        logrotate_content = f.read()
    assert "/home/user/logs/service_*.log" in logrotate_content, "Missing target log path in logrotate config"
    assert "daily" in logrotate_content, "Missing 'daily' directive in logrotate config"
    assert f"size {rotate_size}" in logrotate_content or f"size={rotate_size}" in logrotate_content.replace(" ", ""), \
        f"Missing 'size {rotate_size}' directive in logrotate config"
    assert "rotate 7" in logrotate_content, "Missing 'rotate 7' directive in logrotate config"
    assert "missingok" in logrotate_content, "Missing 'missingok' directive in logrotate config"
    assert "compress" in logrotate_content, "Missing 'compress' directive in logrotate config"

    firewall_path = "/home/user/firewall.sh"
    assert os.path.exists(firewall_path), f"Missing file: {firewall_path}"
    with open(firewall_path, "r") as f:
        firewall_content = f.read()
    for i in range(10):
        ext_port = 8000 + i
        int_port = start_port + i
        expected_rule = f"iptables -t nat -A PREROUTING -p tcp --dport {ext_port} -j REDIRECT --to-port {int_port}"
        assert expected_rule in firewall_content, \
            f"Missing expected iptables rule in {firewall_path}: {expected_rule}"

    for i in range(10):
        log_path = f"/home/user/logs/service_{i}.log"
        assert os.path.exists(log_path), f"Missing log file: {log_path}"
        with open(log_path, "r") as f:
            log_content = f.read().strip()
        expected_log = f"Provisioned instance {i} for {username}_{i} on port {start_port + i}"
        assert expected_log in log_content, \
            f"Incorrect log content in {log_path}. Expected: '{expected_log}', Got: '{log_content}'"


@pytest.fixture(scope="session")
def original_run(tmp_path_factory):
    assert os.path.exists(PROVISION_SCRIPT), f"Missing script: {PROVISION_SCRIPT}"
    assert os.access(PROVISION_SCRIPT, os.X_OK), f"Script is not executable: {PROVISION_SCRIPT}"

    trace_path = str(tmp_path_factory.mktemp("trace") / "original.jsonl")
    write_specs_image("omega_admin", 7000, "100M")
    install_traced_installer(trace_path)
    clean_outputs()
    result, runtime = run_provision()
    return result, runtime, trace_path


def test_provisioning_script_execution_and_speedup(original_run):
    result, runtime, trace_path = original_run
    assert result.returncode == 0, \
        f"Script failed with return code {result.returncode}.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"

    reference_time = 20.0
    speedup = reference_time / runtime if runtime > 0 else 0
    assert speedup >= 5.0, \
        f"Speedup too low: {speedup:.2f} (Runtime: {runtime:.2f}s). Expected speedup >= 5.0 (Runtime <= 4.0s)"
    assert_installer_executions(trace_path)


def test_generated_files_content(original_run):
    create_users_path = "/home/user/create_users.sh"
    assert os.path.exists(create_users_path), f"Missing file: {create_users_path}"
    with open(create_users_path, "r") as f:
        create_users_content = f.read()

    for i in range(10):
        expected_cmd = f"useradd -m -s /bin/bash omega_admin_{i}"
        assert expected_cmd in create_users_content, f"Missing expected command in {create_users_path}: {expected_cmd}"

    logrotate_path = "/home/user/service_logrotate.conf"
    assert os.path.exists(logrotate_path), f"Missing file: {logrotate_path}"
    with open(logrotate_path, "r") as f:
        logrotate_content = f.read()

    assert "/home/user/logs/service_*.log" in logrotate_content, "Missing target log path in logrotate config"
    assert "daily" in logrotate_content, "Missing 'daily' directive in logrotate config"
    assert "size 100M" in logrotate_content or "size=100M" in logrotate_content.replace(" ", ""), "Missing 'size 100M' directive in logrotate config"
    assert "rotate 7" in logrotate_content, "Missing 'rotate 7' directive in logrotate config"
    assert "missingok" in logrotate_content, "Missing 'missingok' directive in logrotate config"
    assert "compress" in logrotate_content, "Missing 'compress' directive in logrotate config"

    firewall_path = "/home/user/firewall.sh"
    assert os.path.exists(firewall_path), f"Missing file: {firewall_path}"
    with open(firewall_path, "r") as f:
        firewall_content = f.read()

    for i in range(10):
        ext_port = 8000 + i
        int_port = 7000 + i
        expected_rule = f"iptables -t nat -A PREROUTING -p tcp --dport {ext_port} -j REDIRECT --to-port {int_port}"
        assert expected_rule in firewall_content, f"Missing expected iptables rule in {firewall_path}: {expected_rule}"


def test_legacy_installer_logs(original_run):
    for i in range(10):
        log_path = f"/home/user/logs/service_{i}.log"
        assert os.path.exists(log_path), f"Missing log file: {log_path}"
        with open(log_path, "r") as f:
            log_content = f.read().strip()

        expected_log = f"Provisioned instance {i} for omega_admin_{i} on port {7000 + i}"
        assert expected_log in log_content, f"Incorrect log content in {log_path}. Expected: '{expected_log}', Got: '{log_content}'"


def test_ocr_driven_values_and_concurrent_real_installer_execution(original_run, tmp_path):
    usernames = ["deltaops", "vectorops", "summitops", "harborops"]
    username = secrets.choice(usernames)
    start_port = 7200 + secrets.randbelow(500)
    rotate_size = f"{120 + secrets.randbelow(80)}M"
    trace_path = str(tmp_path / "challenge.jsonl")

    write_specs_image(username, start_port, rotate_size)
    install_traced_installer(trace_path)
    clean_outputs()
    result, runtime = run_provision()

    assert result.returncode == 0, \
        f"Script failed on changed OCR specifications.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    assert runtime <= 4.0, f"Concurrent challenge run took {runtime:.2f}s; expected <= 4.0s"
    assert_installer_executions(trace_path)
    assert_generated_content(username, start_port, rotate_size)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
