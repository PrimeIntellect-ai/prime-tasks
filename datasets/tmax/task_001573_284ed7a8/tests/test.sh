#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import os
import pwd
import re
import secrets
import shlex
import signal
import subprocess
import time
import zipfile

HOME = "/home/user"


def run_as_user(argv, timeout=20):
    return subprocess.run(
        ["runuser", "-u", "user", "--"] + argv,
        check=True,
        timeout=timeout,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env={"HOME": HOME, "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin")},
    )


def stop_existing_supervisord():
    pid_path = f"{HOME}/supervisord.pid"
    try:
        with open(pid_path) as f:
            pid = int(f.read().strip())
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
        if "supervisord" in cmdline:
            os.kill(pid, signal.SIGTERM)
            for _ in range(50):
                if not os.path.exists(f"/proc/{pid}"):
                    break
                time.sleep(0.1)
    except (FileNotFoundError, ValueError, ProcessLookupError, PermissionError):
        pass
    try:
        os.unlink(pid_path)
    except FileNotFoundError:
        pass


def zip_member_for_basename(zf, basename):
    matches = [n for n in zf.namelist() if not n.endswith("/") and os.path.basename(n) == basename]
    assert len(matches) == 1, f"Expected exactly one ZIP member named {basename}, got {matches}"
    return matches[0]


def test_00_artifacts_and_randomized_pipeline():
    required_files = [
        f"{HOME}/sanitize.sh",
        f"{HOME}/backup_mail.py",
        f"{HOME}/processor_v2.py",
        f"{HOME}/deploy.sh",
        f"{HOME}/supervisord.conf",
    ]
    for path in required_files:
        assert os.path.isfile(path), f"Required artifact missing: {path}"
        assert not os.path.islink(path), f"Required artifact must be a real file, not a symlink: {path}"

    assert os.access(f"{HOME}/sanitize.sh", os.X_OK), "sanitize.sh is not executable"
    assert os.access(f"{HOME}/deploy.sh", os.X_OK), "deploy.sh is not executable"

    with open(f"{HOME}/sanitize.sh", errors="replace") as f:
        sanitize_source = f.read()
    assert re.search(r"\b(sed|grep|awk)\b", sanitize_source), "sanitize.sh must use sed, grep, or awk"

    with open(f"{HOME}/deploy.sh", errors="replace") as f:
        deploy_source = f.read()
    assert "/home/user/backup_mail.py" in deploy_source, "deploy.sh does not execute backup_mail.py"
    assert "/home/user/sanitize.sh" in deploy_source, "deploy.sh does not execute sanitize.sh"
    assert "/home/user/current_processor.py" in deploy_source, "deploy.sh does not update current_processor.py"
    assert "/home/user/processor_v2.py" in deploy_source, "deploy.sh does not deploy processor_v2.py"
    assert "supervisord" in deploy_source and "/home/user/supervisord.conf" in deploy_source, \
        "deploy.sh does not start supervisord with supervisord.conf"
    assert re.search(r"\bsleep\s+5(?:\s|;|$)", deploy_source), "deploy.sh does not sleep for 5 seconds"

    cfg = configparser.RawConfigParser()
    assert cfg.read(f"{HOME}/supervisord.conf") == [f"{HOME}/supervisord.conf"]
    assert cfg.has_section("supervisord"), "supervisord.conf lacks [supervisord]"
    assert cfg.has_section("rpcinterface:supervisor"), "supervisord.conf lacks [rpcinterface:supervisor]"
    assert cfg.has_section("program:mail_processor"), "supervisord.conf lacks [program:mail_processor]"
    assert cfg.get("supervisord", "pidfile", fallback="").strip() == f"{HOME}/supervisord.pid"
    assert cfg.get("rpcinterface:supervisor", "supervisor.rpcinterface_factory", fallback="").strip(), \
        "RPC interface factory is not configured"
    command = cfg.get("program:mail_processor", "command", fallback="")
    command_argv = shlex.split(command)
    assert command_argv and os.path.basename(command_argv[0]) == "python3", \
        "mail_processor command must use python3"
    assert f"{HOME}/current_processor.py" in command_argv[1:], \
        "mail_processor command must execute /home/user/current_processor.py"
    assert cfg.get("program:mail_processor", "stdout_logfile", fallback="").strip() == f"{HOME}/mail_processor.log"

    stop_existing_supervisord()

    token = secrets.token_hex(12)
    eml_name = f"audit_{token}.eml"
    extra_name = f"attachment_{token}.txt"
    eml_path = f"{HOME}/mail/incoming/{eml_name}"
    extra_path = f"{HOME}/mail/incoming/{extra_name}"
    original = (
        f"From: audit-{token}@example.com\n"
        f"X-Internal-Route: secret-{token}\n"
        f"Subject: randomized-{token}\n"
        f"x-internal-route: preserve-{token}\n"
        f" X-Internal-Route: preserve-leading-space-{token}\n"
        "\n"
        f"Body {token}\n"
    )
    expected_sanitized = (
        f"From: audit-{token}@example.com\n"
        f"Subject: randomized-{token}\n"
        f"x-internal-route: preserve-{token}\n"
        f" X-Internal-Route: preserve-leading-space-{token}\n"
        "\n"
        f"Body {token}\n"
    )
    extra_bytes = (f"random backup payload {token}\n").encode()
    with open(eml_path, "w", newline="") as f:
        f.write(original)
    with open(extra_path, "wb") as f:
        f.write(extra_bytes)

    # Exercise the required helper artifacts independently.
    run_as_user(["python3", f"{HOME}/backup_mail.py"])
    with zipfile.ZipFile(f"{HOME}/mail/backup/backup_current.zip") as zf:
        assert zf.read(zip_member_for_basename(zf, eml_name)) == original.encode()
        assert zf.read(zip_member_for_basename(zf, extra_name)) == extra_bytes

    run_as_user(["/bin/bash", f"{HOME}/sanitize.sh"])
    sanitized_path = f"{HOME}/mail/sanitized/{eml_name}"
    with open(sanitized_path, "r", newline="") as f:
        assert f.read() == expected_sanitized, "sanitize.sh did not remove exactly the targeted lines"
    os.unlink(sanitized_path)

    # Execute the actual deployment with a randomized fixture unknown to the agent.
    started = time.monotonic()
    run_as_user([f"{HOME}/deploy.sh"], timeout=25)
    elapsed = time.monotonic() - started
    assert elapsed >= 4.5, "deploy.sh returned without the required five-second wait"

    processed_path = f"{HOME}/mail/processed/{eml_name}"
    assert os.path.isfile(processed_path), "Randomized message was not processed by the deployment"
    with open(processed_path, "r", newline="") as f:
        processed = f.read()
    lines = processed.splitlines()
    assert lines and lines[-1] == "Status: Processed"
    assert lines.count("Status: Processed") == 1
    assert lines[:-1] == expected_sanitized.splitlines(), "Message content was changed beyond sanitization/status"

    # The deployment must have recreated a nonempty backup from the current incoming data.
    with zipfile.ZipFile(f"{HOME}/mail/backup/backup_current.zip") as zf:
        expected_files = {}
        for name in os.listdir(f"{HOME}/mail/incoming"):
            path = f"{HOME}/mail/incoming/{name}"
            if os.path.isfile(path):
                with open(path, "rb") as f:
                    expected_files[name] = f.read()
        for name, data in expected_files.items():
            assert zf.read(zip_member_for_basename(zf, name)) == data, f"Incorrect backup data for {name}"

    # Verify that a live daemon, rather than deploy.sh fabrication, handles a new unpredictable file.
    live_name = f"live_{secrets.token_hex(12)}.eml"
    live_path = f"{HOME}/mail/sanitized/{live_name}"
    live_content = f"Subject: live test {token}\nX-Internal-Route: processor-must-preserve-this\n\nLive body {token}\n"
    with open(live_path, "w", newline="") as f:
        f.write(live_content)
    live_processed = f"{HOME}/mail/processed/{live_name}"
    deadline = time.time() + 7
    while time.time() < deadline and not os.path.isfile(live_processed):
        time.sleep(0.2)
    assert os.path.isfile(live_processed), "The supervised processor did not process a newly created file"
    assert not os.path.exists(live_path), "Processor did not move the sanitized file"
    with open(live_processed, "r", newline="") as f:
        live_result = f.read()
    live_lines = live_result.splitlines()
    assert live_lines[-1] == "Status: Processed"
    assert live_lines.count("Status: Processed") == 1
    assert live_lines[:-1] == live_content.splitlines(), "Processor altered existing message content"


def test_backup_created():
    backup_path = "/home/user/mail/backup/backup_current.zip"
    assert os.path.isfile(backup_path), f"Backup zip file missing at {backup_path}"

    with zipfile.ZipFile(backup_path, 'r') as z:
        namelist = [os.path.basename(name) for name in z.namelist()]
        assert "msg1.eml" in namelist, "msg1.eml not found in the backup zip"
        assert "msg2.eml" in namelist, "msg2.eml not found in the backup zip"
        assert z.read(zip_member_for_basename(z, "msg1.eml")), "msg1.eml is empty in the backup zip"
        assert z.read(zip_member_for_basename(z, "msg2.eml")), "msg2.eml is empty in the backup zip"


def test_processed_msg1():
    msg1_path = "/home/user/mail/processed/msg1.eml"
    assert os.path.isfile(msg1_path), f"Processed msg1.eml missing at {msg1_path}"
    with open(msg1_path, 'r') as f:
        content = f.read()
    assert "X-Internal-Route:" not in content, "X-Internal-Route header was not removed from msg1.eml"
    assert content.strip().endswith("Status: Processed"), "msg1.eml does not end with 'Status: Processed'"


def test_processed_msg2():
    msg2_path = "/home/user/mail/processed/msg2.eml"
    assert os.path.isfile(msg2_path), f"Processed msg2.eml missing at {msg2_path}"
    with open(msg2_path, 'r') as f:
        content = f.read()
    assert "X-Internal-Route:" not in content, "X-Internal-Route header was not removed from msg2.eml"
    assert "X-Safe-Header: true" in content, "X-Safe-Header was incorrectly removed from msg2.eml"
    assert content.strip().endswith("Status: Processed"), "msg2.eml does not end with 'Status: Processed'"


def test_symlink_created():
    symlink_path = "/home/user/current_processor.py"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink"
    target = os.readlink(symlink_path)
    assert os.path.basename(target) == "processor_v2.py" or target == "/home/user/processor_v2.py", \
        f"Symlink points to {target} instead of processor_v2.py"


def test_deployment_success_log():
    log_path = "/home/user/deploy_success.log"
    assert os.path.isfile(log_path), f"Deployment success log missing at {log_path}"
    with open(log_path, 'r') as f:
        content = f.read()
    assert "DEPLOYMENT COMPLETE" in content, "deploy_success.log does not contain 'DEPLOYMENT COMPLETE'"


def test_supervisord_running():
    pid_path = "/home/user/supervisord.pid"
    assert os.path.isfile(pid_path), f"Supervisord pid file missing at {pid_path}. Is supervisord running?"
    with open(pid_path) as f:
        pid = int(f.read().strip())
    os.kill(pid, 0)
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
    assert "supervisord" in cmdline, f"PID {pid} is not supervisord: {cmdline}"
    assert "/home/user/supervisord.conf" in cmdline, "Supervisord was not started with the required config"
    assert os.stat(f"/proc/{pid}").st_uid == pwd.getpwnam("user").pw_uid, "Supervisord is not running as user"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
