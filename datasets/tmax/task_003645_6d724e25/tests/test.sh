#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import subprocess
import urllib.error
import urllib.request
import uuid
from email import policy
from email.parser import BytesParser

import pytest


def test_fetch_costs_exp_exists():
    path = "/home/user/fetch_costs.exp"
    assert os.path.isfile(path), f"Expect script {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "expect" in content, f"File {path} does not seem to contain expect commands."


def test_deploy_sh_exists_and_executable():
    path = "/home/user/deploy.sh"
    assert os.path.isfile(path), f"Deployment script {path} does not exist."
    assert os.access(path, os.X_OK), f"Deployment script {path} is not executable."


def test_staging_report_json():
    path = "/home/user/staging/report.json"
    assert os.path.isfile(path), f"Staging report {path} does not exist."
    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    assert data.get("total_cost") == 4250.75, "Staging report total_cost is incorrect."
    assert data.get("status") == "success", "Staging report status is incorrect."


def test_prod_report_json():
    staging_path = "/home/user/staging/report.json"
    prod_path = "/home/user/prod/report.json"
    assert os.path.isfile(prod_path), f"Production report {prod_path} does not exist."

    with open(staging_path, "r") as f:
        staging_data = f.read()
    with open(prod_path, "r") as f:
        prod_data = f.read()

    assert staging_data == prod_data, "Production report does not match staging report."


def test_web_server_running():
    url = "http://localhost:8080/report.json"
    try:
        response = urllib.request.urlopen(url, timeout=2)
        assert response.status == 200, f"Web server returned status {response.status} instead of 200."
        data = json.loads(response.read().decode("utf-8"))
        assert data.get("total_cost") == 4250.75, "Web server did not serve the correct report.json."
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to web server on port 8080: {e}")
    except json.JSONDecodeError:
        pytest.fail("Web server did not return valid JSON.")


def test_email_notification_sent():
    log_path = "/home/user/mail.log"
    assert os.path.isfile(log_path), f"Mail log {log_path} does not exist. Was the email sent?"

    with open(log_path, "r") as f:
        log_content = f.read()

    assert "finops@localhost" in log_content, "Sender finops@localhost not found in mail log."
    assert "cfo@example.com" in log_content, "Recipient cfo@example.com not found in mail log."
    assert "Cost Report Deployed" in log_content, "Subject 'Cost Report Deployed' not found in mail log."
    assert "The latest cost report has been deployed to the web server." in log_content, "Expected email body not found in mail log."

    valid_message = False
    for block in log_content.split("\n---\n"):
        if not block.startswith("FROM: ") or "\nTO: " not in block or "\nDATA:\n" not in block:
            continue
        envelope, raw_message = block.split("\nDATA:\n", 1)
        lines = envelope.splitlines()
        if lines[0].strip() != "FROM: finops@localhost":
            continue
        if "cfo@example.com" not in lines[1]:
            continue
        try:
            message = BytesParser(policy=policy.default).parsebytes(raw_message.encode("utf-8"))
        except Exception:
            continue
        if message.get("Subject") != "Cost Report Deployed":
            continue
        if message.is_multipart():
            body = "\n".join(
                part.get_content()
                for part in message.walk()
                if part.get_content_type() == "text/plain"
            )
        else:
            try:
                body = message.get_content()
            except Exception:
                body = str(message.get_payload())
        if "The latest cost report has been deployed to the web server." in body:
            valid_message = True
            break
    assert valid_message, "Mail log does not contain a complete SMTP message with the required envelope, subject, and body."


def test_expect_retrieval_and_dynamic_deployment_gate():
    fetch_path = "/home/user/fetch_costs.exp"
    deploy_path = "/home/user/deploy.sh"
    legacy_path = "/home/user/bin/legacy_billing"
    staging_path = "/home/user/staging/report.json"
    prod_path = "/home/user/prod/report.json"
    auth_log = "/tmp/verifier_billing_auth"

    with open(deploy_path, "r", errors="replace") as f:
        deploy_content = f.read()
    assert fetch_path in deploy_content, "deploy.sh does not invoke /home/user/fetch_costs.exp."

    def snapshot(path):
        if not os.path.exists(path):
            return None
        with open(path, "rb") as f:
            return (f.read(), stat.S_IMODE(os.stat(path).st_mode))

    def restore(path, saved):
        if saved is None:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        else:
            data, mode = saved
            with open(path, "wb") as f:
                f.write(data)
            os.chmod(path, mode)

    saved_legacy = snapshot(legacy_path)
    saved_staging = snapshot(staging_path)
    saved_prod = snapshot(prod_path)

    nonce = uuid.uuid4().hex
    stub = f'''#!/usr/bin/env bash
IFS= read -r -p "Username: " user
IFS= read -r -s -p "Password: " pass
printf "\\n"
printf "%s\\n%s\\n" "$user" "$pass" >> {auth_log}
if [[ "$user" == "finops" && "$pass" == "CostCut2024!" ]]; then
    printf '{{"status":"success","total_cost":%s,"currency":"USD","nonce":"%s"}}\\n' "$BILLING_COST" "$BILLING_NONCE"
else
    printf '{{"status":"error","message":"Authentication failed"}}\\n'
    exit 1
fi
'''.encode()

    try:
        with open(legacy_path, "wb") as f:
            f.write(stub)
        os.chmod(legacy_path, 0o755)

        env = os.environ.copy()
        env["BILLING_NONCE"] = nonce

        # Execute the submitted Expect artifact against an answer generated only
        # at verification time, and verify that it supplied both credentials.
        direct_cost = round(random.uniform(1100.0, 3900.0), 2)
        env["BILLING_COST"] = str(direct_cost)
        for path in (auth_log, staging_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        subprocess.run(["expect", fetch_path], env=env, check=True, timeout=10,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        with open(auth_log, "r") as f:
            auth = f.read().splitlines()
        assert auth[-2:] == ["finops", "CostCut2024!"], "Expect script did not supply the required credentials."
        with open(staging_path, "r") as f:
            direct_data = json.load(f)
        assert direct_data == {
            "status": "success", "total_cost": direct_cost,
            "currency": "USD", "nonce": nonce
        }, "Expect script did not save exactly the dynamically returned billing JSON."

        # Exercise deploy.sh with an unpredictable passing value.
        low_cost = round(random.uniform(1000.0, 4999.0), 2)
        env["BILLING_COST"] = str(low_cost)
        for path in (auth_log, staging_path, prod_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        subprocess.run([deploy_path], env=env, check=True, timeout=15,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert os.path.isfile(auth_log), "deploy.sh did not run the interactive billing retrieval."
        with open(staging_path, "rb") as f:
            staging_bytes = f.read()
        with open(prod_path, "rb") as f:
            prod_bytes = f.read()
        low_data = json.loads(staging_bytes)
        assert low_data["total_cost"] == low_cost and low_data["nonce"] == nonce
        assert prod_bytes == staging_bytes, "deploy.sh did not deploy a report at or below the gate."

        # Exercise the rejection branch after removing prod, so an old file cannot
        # conceal an unconditional or hard-coded copy.
        high_cost = round(random.uniform(5000.01, 9000.0), 2)
        env["BILLING_COST"] = str(high_cost)
        for path in (auth_log, staging_path, prod_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        subprocess.run([deploy_path], env=env, check=True, timeout=15,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert os.path.isfile(auth_log), "deploy.sh did not retrieve billing data for the rejection case."
        with open(staging_path, "r") as f:
            high_data = json.load(f)
        assert high_data["total_cost"] == high_cost and high_data["nonce"] == nonce
        assert not os.path.exists(prod_path), "deploy.sh copied a report whose total_cost exceeds 5000."
    finally:
        restore(legacy_path, saved_legacy)
        restore(staging_path, saved_staging)
        restore(prod_path, saved_prod)
        try:
            os.remove(auth_log)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
