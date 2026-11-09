#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import stat
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.request

import pytest


def test_phase1_backup_exists_and_valid():
    backup_path = "/home/user/backups/legacy_data.tar.gz"
    assert os.path.isfile(backup_path), f"Backup file {backup_path} does not exist."

    try:
        with tarfile.open(backup_path, "r:gz") as tar:
            names = tar.getnames()
            assert any("config.ini" in name for name in names), "config.ini not found in the backup archive."
    except tarfile.TarError:
        pytest.fail(f"File {backup_path} is not a valid gzip-compressed tar archive.")


def run_manager(*args):
    script_path = "/home/user/service_manager.sh"
    with tempfile.TemporaryFile(mode="w+") as stdout, tempfile.TemporaryFile(mode="w+") as stderr:
        result = subprocess.run(
            [script_path, *args],
            stdout=stdout,
            stderr=stderr,
            timeout=10,
            check=False,
        )
        stdout.seek(0)
        stderr.seek(0)
        return result.returncode, stdout.read().strip(), stderr.read().strip()


def process_is_running(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            fields = f.read().split()
        return len(fields) > 2 and fields[2] != "Z"
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return False


def assert_app_process(pid):
    assert process_is_running(pid), f"Process with PID {pid} is not running."
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    assert argv, f"Process with PID {pid} has no command line."
    assert os.path.basename(argv[0]).startswith("python3"), f"PID {pid} is not a python3 process: {argv}"
    assert "/home/user/app.py" in argv[1:], f"PID {pid} is not running /home/user/app.py: {argv}"


def read_pid():
    pid_file = "/home/user/app.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist. Did you start the service?"
    with open(pid_file, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid numeric PID."
    return int(pid_str)


def test_phase2_service_manager_and_lifecycle():
    script_path = "/home/user/service_manager.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert not os.path.islink(script_path), f"Script {script_path} must be a regular file."
    st = os.stat(script_path)
    assert stat.S_ISREG(st.st_mode), f"Script {script_path} is not a regular file."
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    initial_pid = read_pid()
    assert_app_process(initial_pid)

    rc, out, _ = run_manager("status")
    assert rc == 0, "status failed while the service was running."
    assert out == "Service is running", f"Unexpected running status output: {out!r}"

    rc, _, _ = run_manager()
    assert rc != 0, "The service manager must reject calls with no argument."
    rc, _, _ = run_manager("status", "extra")
    assert rc != 0, "The service manager must reject calls with more than one argument."
    rc, _, _ = run_manager("bogus")
    assert rc != 0, "The service manager must reject unsupported actions."

    rc, out, _ = run_manager("stop")
    assert rc == 0, "stop action failed."
    assert out == "Service stopped", f"Unexpected stop output: {out!r}"
    assert not os.path.exists("/home/user/app.pid"), "stop did not delete /home/user/app.pid."

    deadline = time.time() + 5
    while process_is_running(initial_pid) and time.time() < deadline:
        time.sleep(0.05)
    assert not process_is_running(initial_pid), "stop did not terminate the application process."

    rc, out, _ = run_manager("status")
    assert rc == 0, "status failed while the service was stopped."
    assert out == "Service is stopped", f"Unexpected stopped status output: {out!r}"

    rc, out, _ = run_manager("start")
    assert rc == 0, "start action failed."
    assert out == "Service started", f"Unexpected start output: {out!r}"

    new_pid = read_pid()
    deadline = time.time() + 5
    while not process_is_running(new_pid) and time.time() < deadline:
        time.sleep(0.05)
    assert_app_process(new_pid)

    rc, out, _ = run_manager("status")
    assert rc == 0, "status failed after starting the service."
    assert out == "Service is running", f"Unexpected running status output: {out!r}"

    last_error = None
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            req = urllib.request.Request("http://localhost:8080")
            with urllib.request.urlopen(req, timeout=1) as response:
                assert response.status == 200, "Service is not returning HTTP 200."
                return
        except (urllib.error.URLError, TimeoutError) as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail(f"Service is not listening on port 8080 or failed to respond: {last_error}")


def admins_from_csv(path):
    admins = []
    with open(path, newline="") as f:
        for row in csv.reader(f):
            if len(row) >= 2 and row[1].strip() == "admin":
                admins.append(row[0].strip())
    return admins


def effective_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip() and not line.lstrip().startswith("#")]


def validate_generated(expected_admins):
    admins_path = "/home/user/create_admins.sh"
    rules_path = "/home/user/firewall.rules"

    assert os.path.isfile(admins_path), f"Script {admins_path} does not exist."
    assert not os.path.islink(admins_path), f"Script {admins_path} must be a regular file."
    st = os.stat(admins_path)
    assert stat.S_ISREG(st.st_mode), f"Script {admins_path} is not a regular file."
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {admins_path} is not executable."

    admin_lines = effective_lines(admins_path)
    expected_commands = [f"useradd -m -G admin {username}" for username in expected_admins]
    assert sorted(admin_lines) == sorted(expected_commands), (
        f"Generated admin commands are incorrect. Expected {expected_commands!r}, got {admin_lines!r}."
    )

    assert os.path.isfile(rules_path), f"Firewall rules file {rules_path} does not exist."
    assert not os.path.islink(rules_path), f"Firewall rules file {rules_path} must be a regular file."
    expected_rule1 = "iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080"
    expected_rule2 = "iptables -A INPUT -p tcp --dport 8080 -j ACCEPT"
    rule_lines = effective_lines(rules_path)
    assert rule_lines == [expected_rule1, expected_rule2], (
        f"Firewall file must contain exactly the two required rules in order; got {rule_lines!r}."
    )


def execute_builder():
    builder = "/home/user/migration_builder.py"
    assert os.path.isfile(builder), f"Migration builder {builder} does not exist."
    assert not os.path.islink(builder), f"Migration builder {builder} must be a regular file."
    assert stat.S_ISREG(os.stat(builder).st_mode), f"Migration builder {builder} is not a regular file."

    for path in ("/home/user/create_admins.sh", "/home/user/firewall.rules"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["python3", builder],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, f"migration_builder.py failed: {result.stderr}"


def test_phase3_builder_generates_artifacts_from_csv():
    csv_path = "/home/user/legacy_users.csv"
    with open(csv_path, "rb") as f:
        original_csv = f.read()

    dynamic_admin = "verifyadmin" + secrets.token_hex(4)
    dynamic_user = "verifyuser" + secrets.token_hex(4)
    dynamic_csv = original_csv
    if dynamic_csv and not dynamic_csv.endswith(b"\n"):
        dynamic_csv += b"\n"
    dynamic_csv += f"{dynamic_admin},admin,{dynamic_admin}@example.test\n".encode()
    dynamic_csv += f"{dynamic_user},user,{dynamic_user}@example.test\n".encode()

    try:
        with open(csv_path, "wb") as f:
            f.write(dynamic_csv)
        expected_dynamic_admins = admins_from_csv(csv_path)
        execute_builder()
        validate_generated(expected_dynamic_admins)
    finally:
        with open(csv_path, "wb") as f:
            f.write(original_csv)

    expected_original_admins = admins_from_csv(csv_path)
    execute_builder()
    validate_generated(expected_original_admins)

    with open("/home/user/create_admins.sh", "r") as f:
        content = f.read()
    assert "useradd -m -G admin admin" in content, "Missing useradd command for 'admin'."
    assert "useradd -m -G admin msmith" in content, "Missing useradd command for 'msmith'."
    assert "jdoe" not in content, "Script should not contain useradd command for non-admin 'jdoe'."

    with open("/home/user/firewall.rules", "r") as f:
        content = f.read()
    expected_rule1 = "iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080"
    expected_rule2 = "iptables -A INPUT -p tcp --dport 8080 -j ACCEPT"
    assert expected_rule1 in content, "Missing expected iptables PREROUTING rule."
    assert expected_rule2 in content, "Missing expected iptables INPUT rule."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
