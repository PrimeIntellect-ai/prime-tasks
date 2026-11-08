#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import ssl
import subprocess
import tempfile
import urllib.request
from pathlib import Path

import pytest


def test_c_file_modified():
    c_file = "/home/user/account_monitor.c"
    assert os.path.isfile(c_file), f"File {c_file} is missing."
    with open(c_file, "r") as f:
        content = f.read()
    assert "/home/user/users.db" in content, "Absolute path '/home/user/users.db' missing in account_monitor.c."
    assert "/home/user/public_html/report.html" in content, "Absolute path '/home/user/public_html/report.html' missing in account_monitor.c."


def test_binary_compiled():
    source = Path("/home/user/account_monitor.c")
    binary = Path("/home/user/account_monitor")
    database = Path("/home/user/users.db")
    report_dir = Path("/home/user/public_html")
    report = report_dir / "report.html"

    assert binary.is_file(), f"Compiled binary {binary} is missing."
    assert os.access(binary, os.X_OK), f"File {binary} is not executable."
    assert binary.read_bytes()[:4] == b"\x7fELF", f"File {binary} is not a compiled ELF binary."

    old_db = database.read_bytes()
    old_report = report.read_bytes() if report.exists() else None
    token1 = "audit_" + secrets.token_hex(12)
    token2 = "audit_" + secrets.token_hex(12)
    controlled_db = f"{token1}:x:4101\n{token2}:x:4102\n".encode()
    expected = (
        "<html><body><h1>User Report</h1><ul>\n"
        f"<li>{token1}:x:4101\n</li>\n"
        f"<li>{token2}:x:4102\n</li>\n"
        "</ul></body></html>\n"
    ).encode()

    report_dir.mkdir(parents=True, exist_ok=True)
    try:
        database.write_bytes(controlled_db)

        # Run the submitted binary from /tmp, the working directory called out
        # in the task, and verify its output from verifier-derived input.
        result = subprocess.run(
            [str(binary)], cwd="/tmp", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10
        )
        assert result.returncode == 0, (
            f"Submitted monitor failed from /tmp: {result.stderr.decode(errors='replace')}"
        )
        assert report.is_file(), "Submitted monitor did not create report.html."
        assert report.read_bytes() == expected, "Submitted monitor generated an incorrect report."

        # The delivered source must itself compile and exhibit the same required
        # behavior, rather than merely containing the required path strings.
        with tempfile.TemporaryDirectory(prefix="monitor-build-", dir="/tmp") as td:
            rebuilt = Path(td) / "account_monitor"
            build = subprocess.run(
                ["gcc", str(source), "-o", str(rebuilt)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
            )
            assert build.returncode == 0, (
                f"account_monitor.c does not compile: {build.stderr.decode(errors='replace')}"
            )
            report.unlink(missing_ok=True)
            run = subprocess.run(
                [str(rebuilt)], cwd="/tmp", stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=10
            )
            assert run.returncode == 0, (
                f"Monitor rebuilt from source failed from /tmp: {run.stderr.decode(errors='replace')}"
            )
            assert report.is_file(), "Monitor rebuilt from source did not create report.html."
            assert report.read_bytes() == expected, "Monitor rebuilt from source generated an incorrect report."
    finally:
        database.write_bytes(old_db)
        if old_report is None:
            report.unlink(missing_ok=True)
        else:
            report.write_bytes(old_report)


def test_expect_script_exists():
    exp_file = "/home/user/add_user.exp"
    assert os.path.isfile(exp_file), f"Expect script {exp_file} is missing."
    with open(exp_file, "r") as f:
        content = f.read()
    assert "spawn" in content, "Expect script does not contain 'spawn'."
    assert "expect" in content, "Expect script does not contain 'expect'."


def test_user_added():
    db_file = "/home/user/users.db"
    assert os.path.isfile(db_file), f"Database file {db_file} is missing."
    with open(db_file, "r") as f:
        content = f.read()
    assert "charlie" in content, "User 'charlie' was not added to users.db."


def test_expect_script_workflow():
    exp_file = Path("/home/user/add_user.exp")
    admin_file = Path("/home/user/interactive_admin.sh")
    db_file = Path("/home/user/users.db")
    monitor = Path("/home/user/account_monitor")

    old_admin = admin_file.read_bytes()
    old_admin_mode = admin_file.stat().st_mode
    old_db = db_file.read_bytes()
    capture = Path("/tmp") / ("expect-capture-" + secrets.token_hex(16))

    instrumented_admin = f'''#!/bin/bash
read -r -p "Enter new username: " uname
read -r -s -p "Enter password: " pass
printf '\\n'
printf '%s\\n%s\\n' "$uname" "$pass" > {capture}
printf '%s:x:1777\\n' "$uname" >> /home/user/users.db
echo "User added."
'''.encode()

    try:
        # Use a controlled database and an instrumented version of the required
        # interactive program so both prompt responses can be verified.
        db_file.write_text("alice:x:1001\nbob:x:1002\n")
        admin_file.write_bytes(instrumented_admin)
        os.chmod(admin_file, 0o755)

        result = subprocess.run(
            ["/usr/bin/expect", str(exp_file)], cwd="/tmp",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert result.returncode == 0, (
            "add_user.exp failed while driving interactive_admin.sh: "
            + result.stdout.decode(errors="replace")
            + result.stderr.decode(errors="replace")
        )
        assert capture.is_file(), "add_user.exp did not run /home/user/interactive_admin.sh."
        responses = capture.read_text().splitlines()
        assert responses == ["charlie", "secure_pass_123"], (
            "add_user.exp did not provide the required username and password to the interactive script."
        )
        assert "charlie:x:1777" in db_file.read_text(), (
            "The Expect-driven interactive workflow did not add charlie to users.db."
        )
    finally:
        admin_file.write_bytes(old_admin)
        os.chmod(admin_file, old_admin_mode)
        db_file.write_bytes(old_db)
        capture.unlink(missing_ok=True)
        # Restore the latest report from the real database for subsequent HTTPS checks.
        subprocess.run([str(monitor)], cwd="/tmp", stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)


def test_tls_certs_exist():
    cert_file = "/home/user/certs/cert.pem"
    key_file = "/home/user/certs/key.pem"
    assert os.path.isfile(cert_file), f"Certificate file {cert_file} is missing."
    assert os.path.isfile(key_file), f"Key file {key_file} is missing."


def test_systemd_service_active():
    service_file = "/home/user/.config/systemd/user/monitor-web.service"
    assert os.path.isfile(service_file), f"Systemd service file {service_file} is missing."

    env = os.environ.copy()
    env["XDG_RUNTIME_DIR"] = "/run/user/1000"
    try:
        result = subprocess.run(
            ["systemctl", "--user", "is-active", "monitor-web.service"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            check=True
        )
        assert result.stdout.strip() == "active", "monitor-web.service is not active."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"systemctl --user is-active monitor-web.service failed. Output: {e.stdout.strip()} {e.stderr.strip()}")


def test_web_server_running_and_report_generated():
    url = "https://localhost:8443/report.html"
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            content = response.read().decode("utf-8")
            assert "charlie" in content, "User 'charlie' not found in the generated report.html served by the web server."
    except Exception as e:
        pytest.fail(f"Failed to fetch {url}: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
