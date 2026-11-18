#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_mail_routes.py
import configparser
import json
import os
import re
import secrets
import subprocess

SCRIPT = "/home/user/update_mail_routes.py"
DATA = "/home/user/deploy_data.json"
CONF = "/home/user/mail_routing.conf"
LOG = "/home/user/deploy_errors.log"

ORIGINAL_DATA = [
    {
        "service_name": "auth_mailer",
        "ip_address": "127.0.0.10",
        "port": 2525,
        "email_domain": "auth.corp.com",
    },
    {
        "service_name": "reports_mailer",
        "ip_address": "127.0.0.11",
    },
    {
        "service_name": "billing_mailer",
        "ip_address": "127.0.0.12",
        "port": 2526,
    },
    {
        "service_name": "legacy_mailer",
        "port": 2527,
        "email_domain": "legacy.corp.com",
    },
]

ORIGINAL_CONF = """[core_mailer]
target = 127.0.0.5:2500
domain = core.internal

[auth_mailer]
target = 10.0.0.1:25
domain = oldauth.corp.com
"""


def write_json(path, value):
    with open(path, "w") as f:
        json.dump(value, f, indent=2)
        f.write("\n")


def run_submission():
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_config():
    assert os.path.isfile(CONF), f"Config file {CONF} is missing."
    config = configparser.ConfigParser()
    with open(CONF, "r") as f:
        config.read_file(f)
    return config


def check_original_assertions():
    assert os.path.isfile(LOG), f"Error log file {LOG} is missing."
    with open(LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_errors = [
        "ERROR: Service reports_mailer has incomplete network configuration",
        "ERROR: Service legacy_mailer has incomplete network configuration",
    ]
    for err in expected_errors:
        assert err in lines, f"Expected error message not found in {LOG}: '{err}'"
    assert len(lines) == 2, f"Expected exactly 2 error lines in {LOG}, found {len(lines)}."

    config = read_config()
    assert "core_mailer" in config.sections(), "[core_mailer] section is missing."
    assert config.get("core_mailer", "target") == "127.0.0.5:2500", "core_mailer target was modified."
    assert config.get("core_mailer", "domain") == "core.internal", "core_mailer domain was modified."

    assert "auth_mailer" in config.sections(), "[auth_mailer] section is missing."
    assert config.get("auth_mailer", "target") == "127.0.0.10:2525", "auth_mailer target is incorrect."
    assert config.get("auth_mailer", "domain") == "auth.corp.com", "auth_mailer domain is incorrect."

    assert "billing_mailer" in config.sections(), "[billing_mailer] section is missing."
    assert config.get("billing_mailer", "target") == "127.0.0.12:2526", "billing_mailer target is incorrect."
    assert config.get("billing_mailer", "domain") == "billing_mailer.internal", "billing_mailer domain is incorrect."

    assert "reports_mailer" not in config.sections(), "[reports_mailer] should not be in the config."
    assert "legacy_mailer" not in config.sections(), "[legacy_mailer] should not be in the config."

    with open(CONF, "r") as f:
        content = f.read()
    assert "target = 127.0.0.10:2525" in content, "Formatting issue: expected 'target = 127.0.0.10:2525'"
    assert "domain = auth.corp.com" in content, "Formatting issue: expected 'domain = auth.corp.com'"
    assert "target = 127.0.0.12:2526" in content, "Formatting issue: expected 'target = 127.0.0.12:2526'"
    assert "domain = billing_mailer.internal" in content, "Formatting issue: expected 'domain = billing_mailer.internal'"


def check_block_format(content, expected_names):
    body = content.strip("\n")
    assert "\r" not in content, "Configuration must use normal newline characters."
    assert "\n\n\n" not in body, "Blocks must be separated by a single blank line."
    blocks = body.split("\n\n") if body else []
    assert len(blocks) == len(expected_names), "Unexpected number of configuration blocks."

    found = set()
    pattern = re.compile(r"^\[([^\]\n]+)\]\ntarget = ([^\n]+)\ndomain = ([^\n]+)$")
    for block in blocks:
        match = pattern.fullmatch(block)
        assert match, f"Configuration block has incorrect formatting:\n{block}"
        found.add(match.group(1))
    assert found == set(expected_names), "Configuration contains missing or unexpected blocks."


def check_dynamic_behavior():
    token = secrets.token_hex(6)
    existing = f"existing_{token}"
    updated = f"updated_{token}"
    defaulted = f"defaulted_{token}"
    missing_port = f"missing_port_{token}"
    missing_ip = f"missing_ip_{token}"

    octet = secrets.randbelow(180) + 20
    updated_ip = f"10.{octet}.1.20"
    defaulted_ip = f"10.{octet}.1.21"
    updated_port = 20000 + secrets.randbelow(10000)
    defaulted_port = 30000 + secrets.randbelow(10000)
    explicit_domain = f"{token}.example.test"

    dynamic_data = [
        {
            "service_name": updated,
            "ip_address": updated_ip,
            "port": updated_port,
            "email_domain": explicit_domain,
        },
        {
            "service_name": defaulted,
            "ip_address": defaulted_ip,
            "port": defaulted_port,
        },
        {
            "service_name": missing_port,
            "ip_address": f"10.{octet}.1.22",
        },
        {
            "service_name": missing_ip,
            "port": 41000,
            "email_domain": f"invalid-{token}.example.test",
        },
    ]

    initial_conf = (
        f"[{existing}]\n"
        f"target = 192.0.2.10:2500\n"
        f"domain = preserved-{token}.internal\n\n"
        f"[{updated}]\n"
        f"target = 192.0.2.11:25\n"
        f"domain = old-{token}.internal\n"
    )

    write_json(DATA, dynamic_data)
    with open(CONF, "w") as f:
        f.write(initial_conf)
    with open(LOG, "w") as f:
        f.write("ERROR: stale entry that must be cleared\n")

    run_submission()

    config = read_config()
    assert set(config.sections()) == {existing, updated, defaulted}
    assert config.get(existing, "target") == "192.0.2.10:2500"
    assert config.get(existing, "domain") == f"preserved-{token}.internal"
    assert config.get(updated, "target") == f"{updated_ip}:{updated_port}"
    assert config.get(updated, "domain") == explicit_domain
    assert config.get(defaulted, "target") == f"{defaulted_ip}:{defaulted_port}"
    assert config.get(defaulted, "domain") == f"{defaulted}.internal"
    assert missing_port not in config.sections()
    assert missing_ip not in config.sections()

    assert os.path.isfile(LOG), f"Error log file {LOG} is missing."
    with open(LOG, "r") as f:
        error_lines = [line.strip() for line in f if line.strip()]
    assert error_lines == [
        f"ERROR: Service {missing_port} has incomplete network configuration",
        f"ERROR: Service {missing_ip} has incomplete network configuration",
    ], f"Unexpected dynamic error log contents: {error_lines!r}"

    with open(CONF, "r") as f:
        first_conf = f.read()
    with open(LOG, "r") as f:
        first_log = f.read()
    check_block_format(first_conf, {existing, updated, defaulted})

    run_submission()
    with open(CONF, "r") as f:
        second_conf = f.read()
    with open(LOG, "r") as f:
        second_log = f.read()
    assert second_conf == first_conf, "Running the script twice changed the configuration."
    assert second_log == first_log, "Running the script twice changed or duplicated the error log."


def main():
    assert os.path.isfile(SCRIPT), f"Required script {SCRIPT} is missing."
    with open(SCRIPT, "rb") as f:
        compile(f.read(), SCRIPT, "exec")

    write_json(DATA, ORIGINAL_DATA)
    with open(CONF, "w") as f:
        f.write(ORIGINAL_CONF)
    if os.path.exists(LOG):
        os.remove(LOG)

    run_submission()
    check_original_assertions()
    check_dynamic_behavior()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_mail_routes.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
