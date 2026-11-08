#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import shlex
import signal
import stat
import subprocess
import tempfile

import pytest

EXPECT_SCRIPT = "/home/user/fix_mail.exp"
CONFIG_FILE = "/home/user/mail_config.conf"
WIZARD = "/home/user/mail_config_wizard.sh"
LOG_FILE = "/home/user/service_logs.txt"


def expected_from_fatal_log():
    with open(LOG_FILE, "r") as f:
        log = f.read()

    fatal = log.find("FATAL ERROR:")
    assert fatal >= 0, "The service log does not contain FATAL ERROR details."
    details = log[fatal:]

    email_match = re.search(r"Admin email must be set to\s+(\S+)", details)
    port_match = re.search(r"SMTP Port must be configured to\s+(\d+)", details)
    assert email_match, "Could not derive the Admin Email from the FATAL ERROR details."
    assert port_match, "Could not derive the SMTP Port from the FATAL ERROR details."
    return email_match.group(1), port_match.group(1)


@pytest.fixture(scope="module", autouse=True)
def execute_expect_script():
    assert os.path.isfile(EXPECT_SCRIPT), f"Expect script {EXPECT_SCRIPT} does not exist."
    assert os.path.isfile(WIZARD), f"Configuration wizard {WIZARD} does not exist."

    expected_email, expected_port = expected_from_fatal_log()
    workdir = tempfile.mkdtemp(prefix="mail-verifier-")
    os.chmod(workdir, 0o777)
    trace_file = os.path.join(workdir, "wizard-inputs")

    with open(WIZARD, "rb") as f:
        original_wizard = f.read()
    original_mode = stat.S_IMODE(os.stat(WIZARD).st_mode)

    controlled_wizard = f'''#!/bin/bash
read -p "Enter Admin Email: " email
read -p "Enter SMTP Port: " port
printf '%s\\n%s\\n' "$email" "$port" > {shlex.quote(trace_file)}
if [[ -n "$email" && -n "$port" ]]; then
    printf 'ADMIN_EMAIL=%s\\n' "$email" > /home/user/mail_config.conf
    printf 'SMTP_PORT=%s\\n' "$port" >> /home/user/mail_config.conf
    echo "Configuration saved successfully."
else
    echo "Error: Inputs cannot be empty."
    exit 1
fi
'''

    if os.path.lexists(CONFIG_FILE):
        os.remove(CONFIG_FILE)

    with open(WIZARD, "w") as f:
        f.write(controlled_wizard)
    os.chmod(WIZARD, 0o755)

    pw = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(pw.pw_gid)
        os.setuid(pw.pw_uid)

    env = os.environ.copy()
    env["HOME"] = pw.pw_dir
    process = None
    try:
        process = subprocess.Popen(
            ["expect", EXPECT_SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
            preexec_fn=demote,
            start_new_session=True,
        )
        try:
            output, _ = process.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
            pytest.fail(f"Expect script timed out while running the wizard. Output:\n{output}")

        assert process.returncode == 0, (
            f"Expect script failed with exit code {process.returncode}. Output:\n{output}"
        )
        assert os.path.isfile(trace_file), (
            "The Expect script did not execute /home/user/mail_config_wizard.sh."
        )
        with open(trace_file, "r") as f:
            supplied = [line.rstrip("\n") for line in f.readlines()]
        assert supplied == [expected_email, expected_port], (
            "The Expect script did not provide the values derived from the FATAL ERROR details."
        )
    finally:
        with open(WIZARD, "wb") as f:
            f.write(original_wizard)
        os.chmod(WIZARD, original_mode)


def test_expect_script_exists_and_valid():
    expect_script = "/home/user/fix_mail.exp"
    assert os.path.isfile(expect_script), f"Expect script {expect_script} does not exist."

    with open(expect_script, "r") as f:
        content = f.read()

    assert "spawn" in content or "expect" in content, f"Expect script {expect_script} does not appear to contain valid Expect syntax."


def test_mail_config_generated_correctly():
    config_file = "/home/user/mail_config.conf"
    assert os.path.isfile(config_file), f"Configuration file {config_file} was not generated."

    with open(config_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert "ADMIN_EMAIL=sysadmin@company.local" in lines, "Admin email in config file is incorrect or missing."
    assert "SMTP_PORT=2525" in lines, "SMTP port in config file is incorrect or missing."

    expected_email, expected_port = expected_from_fatal_log()
    assert f"ADMIN_EMAIL={expected_email}" in lines, "Admin email does not match the FATAL ERROR details."
    assert f"SMTP_PORT={expected_port}" in lines, "SMTP port does not match the FATAL ERROR details."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
