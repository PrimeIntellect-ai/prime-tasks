#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import secrets
import subprocess
import pytest

BASE = "/home/user/mail_manager"
CONF_PATH = BASE + "/config/aliases.conf"
REPORT_PATH = BASE + "/report.log"
SCRIPT_PATH = BASE + "/generate_report.py"
JOB_PATH = BASE + "/run_job.sh"

EXPECTED_JOB = b"#!/usr/bin/env bash\nexport PATH=/usr/bin:/bin\ncd /tmp\npython3 /home/user/mail_manager/generate_report.py\n"


def run_job():
    result = subprocess.run([JOB_PATH], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, (
        f"run_job.sh failed with return code {result.returncode}. "
        f"Error: {result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), (
        "report.log was not generated at the correct absolute path "
        "(/home/user/mail_manager/report.log)."
    )
    with open(REPORT_PATH, "r") as f:
        return f.read().strip().split("\n")


def test_aliases_config_fixed():
    conf_path = "/home/user/mail_manager/config/aliases.conf"
    assert os.path.isfile(conf_path), f"{conf_path} does not exist."

    with open(conf_path, 'r') as f:
        lines = f.readlines()

    marketing_fixed = False
    devops_broken = False

    for line in lines:
        if "marketing" in line and "marketing@example.com" in line:
            assert ":" in line, "The 'marketing' line in aliases.conf is still missing a colon."
            marketing_fixed = True
        if "devops devops@example.com missingcolon" in line:
            devops_broken = True

    assert marketing_fixed, "The 'marketing' alias was not found or not fixed properly in aliases.conf."
    assert devops_broken, "The 'devops' alias was modified or removed. It should be left broken."

    active_lines = [line.strip() for line in lines if line.strip() and not line.strip().startswith("#")]
    assert "admin: admin@example.com" in active_lines, "The existing admin alias was removed or changed."
    assert "support: support@example.com" in active_lines, "The existing support alias was removed or changed."
    assert "marketing: marketing@example.com" in active_lines, (
        "The marketing alias must exactly map marketing to marketing@example.com."
    )


def test_generate_report_execution_and_output():
    # Remove report.log if it exists to ensure we are testing the script's current behavior
    report_path = "/home/user/mail_manager/report.log"
    if os.path.exists(report_path):
        os.remove(report_path)

    # Run the job script
    script_path = "/home/user/mail_manager/run_job.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"run_job.sh failed with return code {result.returncode}. Error: {result.stderr}"

    assert os.path.isfile(report_path), "report.log was not generated at the correct absolute path (/home/user/mail_manager/report.log)."

    with open(report_path, 'r') as f:
        report_content = f.read().strip().split('\n')

    expected_lines = [
        "admin -> admin@example.com",
        "support -> support@example.com",
        "marketing -> marketing@example.com",
        "ERROR: Malformed line - devops devops@example.com missingcolon"
    ]

    for expected in expected_lines:
        assert expected in report_content, f"Expected line '{expected}' not found in report.log."

    assert len(report_content) == len(expected_lines), f"report.log contains an unexpected number of lines. Expected {len(expected_lines)}, got {len(report_content)}."


def test_job_wrapper_was_not_modified_and_generator_exists():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    assert os.path.isfile(JOB_PATH), f"{JOB_PATH} does not exist."
    with open(JOB_PATH, "rb") as f:
        assert f.read() == EXPECTED_JOB, "run_job.sh was modified, despite the instruction not to modify it."


def test_generator_handles_runtime_generated_configurations():
    with open(CONF_PATH, "rb") as f:
        original_conf = f.read()

    had_report = os.path.exists(REPORT_PATH)
    original_report = None
    if had_report:
        with open(REPORT_PATH, "rb") as f:
            original_report = f.read()

    token = secrets.token_hex(10)
    alias1 = "alpha_" + token
    alias2 = "beta_" + token
    alias3 = "gamma_" + token
    missing1 = "missing_" + token + " no-colon@example.test"
    excess1 = "excess_" + token + ":first@example.test:unexpected"
    missing2 = "broken_" + secrets.token_hex(8)

    cases = [
        (
            "# generated fixture\n"
            "\n"
            f"  {alias1}  :  {alias1}@example.test  \n"
            f"{missing1}\n"
            f"{excess1}\n"
            f"{alias2}:{alias2}@example.test\n",
            [
                f"{alias1} -> {alias1}@example.test",
                f"ERROR: Malformed line - {missing1}",
                f"ERROR: Malformed line - {excess1}",
                f"{alias2} -> {alias2}@example.test",
            ],
        ),
        (
            "# a different number of output records\n"
            f"{alias3} : {alias3}@example.test\n"
            "\n"
            f"{missing2}\n"
            "# ignored comment\n",
            [
                f"{alias3} -> {alias3}@example.test",
                f"ERROR: Malformed line - {missing2}",
            ],
        ),
    ]

    try:
        for fixture, expected in cases:
            fixture_bytes = fixture.encode("utf-8")
            with open(CONF_PATH, "wb") as f:
                f.write(fixture_bytes)
            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)

            actual = run_job()
            assert collections.Counter(actual) == collections.Counter(expected), (
                f"Unexpected report for a runtime-generated aliases.conf. "
                f"Expected {expected!r}, got {actual!r}."
            )
            with open(CONF_PATH, "rb") as f:
                assert f.read() == fixture_bytes, "generate_report.py modified aliases.conf."
    finally:
        with open(CONF_PATH, "wb") as f:
            f.write(original_conf)
        if had_report:
            with open(REPORT_PATH, "wb") as f:
                f.write(original_report)
        elif os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
