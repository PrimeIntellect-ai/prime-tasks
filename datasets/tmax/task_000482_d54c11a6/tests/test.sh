#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess
import uuid


def run_checked(argv, timeout=10):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, (
        f"Command {argv!r} failed with return code {result.returncode}. "
        f"stdout={result.stdout!r} stderr={result.stderr!r}"
    )
    return result


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def write_bytes(path, data):
    with open(path, "wb") as f:
        f.write(data)


def report_lines(path):
    with open(path, "r") as f:
        content = f.read().strip()
    return [line.strip() for line in content.splitlines() if line.strip()]


def test_mailer_config_exists_and_correct():
    config_path = "/home/user/mailer_config.txt"
    assert os.path.isfile(config_path), f"Configuration file {config_path} is missing."
    with open(config_path, "r") as f:
        content = f.read()
    assert "ADMIN=admin@backup.local" in content, "Admin email in config is incorrect or missing."
    assert "PORT=2525" in content, "SMTP port in config is incorrect or missing."
    assert "STAGE=staging" in content, "Stage in config is incorrect or missing."


def test_expect_script_exists():
    script_path = "/home/user/setup_mailer.exp"
    assert os.path.isfile(script_path), f"Expect script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Expect script {script_path} is not executable."


def test_deploy_script_idempotent():
    script_path = "/home/user/deploy.sh"
    assert os.path.isfile(script_path), f"Deploy script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Deploy script {script_path} is not executable."

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"deploy.sh failed with return code {result.returncode}"
    assert "Configuration already applied." in result.stdout, "deploy.sh did not output the expected idempotency message."


def test_c_program_and_binary_exist():
    c_source = "/home/user/check_spool.c"
    c_binary = "/home/user/check_spool"
    assert os.path.isfile(c_source), f"C source file {c_source} is missing."
    assert os.path.isfile(c_binary), f"Compiled binary {c_binary} is missing."
    assert os.access(c_binary, os.X_OK), f"Compiled binary {c_binary} is not executable."


def test_final_report_contents():
    report_path = "/home/user/final_report.txt"
    assert os.path.isfile(report_path), f"Final report {report_path} is missing."

    expected_lines = [
        "Admin: admin@backup.local",
        "Port: 2525",
        "Stage: staging",
        "Valid Emails: 2"
    ]
    actual_lines = report_lines(report_path)

    assert len(actual_lines) == len(expected_lines), f"Final report has {len(actual_lines)} lines, expected {len(expected_lines)}."
    for i, expected in enumerate(expected_lines):
        assert actual_lines[i] == expected, f"Line {i+1} of final report mismatch. Expected '{expected}', got '{actual_lines[i]}'."


def test_expect_script_actually_automates_interactive_setup():
    expect_script = "/home/user/setup_mailer.exp"
    tool = "/home/user/bin/interactive_setup"
    config = "/home/user/mailer_config.txt"

    if os.path.exists(config):
        os.remove(config)
    run_checked(["/usr/bin/expect", expect_script])
    assert read_bytes(config) == (
        b"ADMIN=admin@backup.local\n"
        b"PORT=2525\n"
        b"STAGE=staging\n"
    ), "Expect script did not configure the real interactive tool correctly."

    original_tool = read_bytes(tool)
    original_mode = stat.S_IMODE(os.stat(tool).st_mode)
    marker = f"/tmp/interactive_setup_called_{uuid.uuid4().hex}"
    probe = f'''#!/bin/bash
printf "Enter Admin Email: "
IFS= read -r admin
printf "Enter SMTP Port: "
IFS= read -r port
printf "Enter Deployment Stage (staging/prod): "
IFS= read -r stage
printf "%s\\n%s\\n%s\\n" "$admin" "$port" "$stage" > {marker}
printf "ADMIN=%s\\nPORT=%s\\nSTAGE=%s\\n" "$admin" "$port" "$stage" > /home/user/mailer_config.txt
'''.encode()
    try:
        write_bytes(tool, probe)
        os.chmod(tool, 0o755)
        if os.path.exists(marker):
            os.remove(marker)
        if os.path.exists(config):
            os.remove(config)
        run_checked(["/usr/bin/expect", expect_script])
        assert os.path.isfile(marker), "Expect script did not invoke /home/user/bin/interactive_setup."
        assert read_bytes(marker) == b"admin@backup.local\n2525\nstaging\n", "Expect script supplied incorrect responses."
    finally:
        write_bytes(tool, original_tool)
        os.chmod(tool, original_mode)
        if os.path.exists(marker):
            os.remove(marker)


def test_deploy_runs_expect_only_when_configuration_needed():
    deploy = "/home/user/deploy.sh"
    expect_script = "/home/user/setup_mailer.exp"
    config = "/home/user/mailer_config.txt"
    marker = f"/tmp/deploy_expect_called_{uuid.uuid4().hex}"

    original_expect = read_bytes(expect_script)
    original_expect_mode = stat.S_IMODE(os.stat(expect_script).st_mode)
    original_config = read_bytes(config) if os.path.exists(config) else None
    probe = f'''#!/usr/bin/expect -f
set f [open "{marker}" "w"]
puts $f "called"
close $f
set c [open "/home/user/mailer_config.txt" "w"]
puts $c "ADMIN=admin@backup.local"
puts $c "PORT=2525"
puts $c "STAGE=staging"
close $c
'''.encode()

    try:
        write_bytes(expect_script, probe)
        os.chmod(expect_script, 0o755)

        write_bytes(config, b"ADMIN=admin@backup.local\nPORT=2525\nSTAGE=staging\n")
        if os.path.exists(marker):
            os.remove(marker)
        result = run_checked([deploy])
        assert "Configuration already applied." in result.stdout
        assert not os.path.exists(marker), "deploy.sh ran the Expect script despite an existing staging configuration."

        write_bytes(config, b"ADMIN=old@example.invalid\nPORT=25\nSTAGE=prod\n")
        if os.path.exists(marker):
            os.remove(marker)
        run_checked([deploy])
        assert os.path.isfile(marker), "deploy.sh did not run /home/user/setup_mailer.exp for a non-staging configuration."
        assert b"STAGE=staging" in read_bytes(config), "deploy.sh did not allow the Expect script to update the configuration."
    finally:
        write_bytes(expect_script, original_expect)
        os.chmod(expect_script, original_expect_mode)
        if original_config is None:
            if os.path.exists(config):
                os.remove(config)
        else:
            write_bytes(config, original_config)
        if os.path.exists(marker):
            os.remove(marker)


def test_c_source_and_binary_process_dynamic_spool():
    source = "/home/user/check_spool.c"
    submitted_binary = "/home/user/check_spool"
    config = "/home/user/mailer_config.txt"
    spool = "/home/user/spool"
    report = "/home/user/final_report.txt"
    rebuilt_binary = f"/tmp/check_spool_rebuilt_{uuid.uuid4().hex}"
    spool_backup = f"/tmp/spool_backup_{uuid.uuid4().hex}"

    original_config = read_bytes(config) if os.path.exists(config) else None
    original_report = read_bytes(report) if os.path.exists(report) else None
    os.rename(spool, spool_backup)
    os.mkdir(spool)

    token = secrets.token_hex(8)
    admin = f"restore-{token}@backup.local"
    port = str(3000 + secrets.randbelow(30000))
    stage = "prod"
    valid_count = 1 + secrets.randbelow(7)
    total = 9

    try:
        write_bytes(config, f"ADMIN={admin}\nPORT={port}\nSTAGE={stage}\n".encode())
        for i in range(total):
            path = os.path.join(spool, f"dynamic_{token}_{i}.txt")
            if i < valid_count:
                body = f"Subject: dynamic {i}\nX-Token: {token}\nBody prefix To: list@backup.local body suffix\n"
            else:
                body = f"Subject: dynamic {i}\nTo: other-{token}@backup.local\nNo matching recipient here\n"
            write_bytes(path, body.encode())

        expected = [
            f"Admin: {admin}",
            f"Port: {port}",
            f"Stage: {stage}",
            f"Valid Emails: {valid_count}",
        ]

        if os.path.exists(report):
            os.remove(report)
        run_checked([submitted_binary])
        assert os.path.isfile(report), "The submitted check_spool binary did not create final_report.txt."
        assert report_lines(report) == expected, "The submitted check_spool binary produced an incorrect dynamic report."

        run_checked(["gcc", "-std=c11", "-O2", source, "-o", rebuilt_binary], timeout=20)
        if os.path.exists(report):
            os.remove(report)
        run_checked([rebuilt_binary])
        assert os.path.isfile(report), "A binary rebuilt from check_spool.c did not create final_report.txt."
        assert report_lines(report) == expected, "check_spool.c produced an incorrect report when rebuilt and run."
    finally:
        if os.path.exists(rebuilt_binary):
            os.remove(rebuilt_binary)
        if os.path.isdir(spool):
            shutil.rmtree(spool)
        os.rename(spool_backup, spool)
        if original_config is None:
            if os.path.exists(config):
                os.remove(config)
        else:
            write_bytes(config, original_config)
        if original_report is None:
            if os.path.exists(report):
                os.remove(report)
        else:
            write_bytes(report, original_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
