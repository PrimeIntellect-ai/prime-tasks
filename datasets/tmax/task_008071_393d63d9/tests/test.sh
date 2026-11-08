#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/process_loc.py"
CRON_PATH = "/home/user/cron_schedule.txt"
MASTER_PATH = "/home/user/master_en.json"
INCOMING_PATH = "/home/user/incoming_fr.json"
REPORT_PATH = "/home/user/loc_report.json"
APPROVED_PATH = "/home/user/approved_fr.json"


def test_cron_schedule():
    """Test that the cron schedule file exists and contains the correct crontab entry."""
    assert os.path.isfile(CRON_PATH), f"Missing file: {CRON_PATH}"

    with open(CRON_PATH, "r") as f:
        content = f.read().strip()

    expected_cron = "0 2 * * * python3 /home/user/process_loc.py"
    assert expected_cron in content, f"Crontab entry is incorrect. Expected '{expected_cron}', but got '{content}'"


def test_script_exists_and_runs():
    """Test that the python script exists and runs without errors."""
    assert os.path.isfile(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"

    result = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to run: {result.stderr}"


def test_loc_report():
    """Test that loc_report.json is generated correctly."""
    assert os.path.isfile(REPORT_PATH), f"Missing file: {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} is not valid JSON")

    assert "anomalies" in report, "Missing 'anomalies' key in loc_report.json"
    assert "missing" in report, "Missing 'missing' key in loc_report.json"

    assert report["anomalies"] == ["login_button"], "Anomalies list is incorrect"
    assert report["missing"] == ["footer_text", "promo_code"], "Missing list is incorrect"


def test_approved_fr():
    """Test that approved_fr.json is generated correctly."""
    assert os.path.isfile(APPROVED_PATH), f"Missing file: {APPROVED_PATH}"

    with open(APPROVED_PATH, "r") as f:
        try:
            approved = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{APPROVED_PATH} is not valid JSON")

    expected_approved = {
        "checkout_cart": "Caisse",
        "error_404": "Page non trouvee.",
        "welcome_message": "Bienvenue!"
    }

    assert approved == expected_approved, f"Approved translations are incorrect. Expected {expected_approved}, got {approved}"


def expected_outputs(master, incoming):
    normalized = {key.lower().replace(" ", "_"): value for key, value in incoming.items()}
    missing = sorted(key for key in master if key not in normalized)
    anomalies = sorted(
        key for key, english in master.items()
        if key in normalized and len(normalized[key]) > 3 * len(english)
    )
    anomaly_set = set(anomalies)
    approved = {
        key: value for key, value in normalized.items()
        if key in master and key not in anomaly_set
    }
    return {"anomalies": anomalies, "missing": missing}, approved


def load_json(path):
    assert os.path.isfile(path), f"Missing file: {path}"
    try:
        with open(path, "r") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"{path} is not valid JSON: {exc}")


def test_general_processing_with_generated_inputs():
    """Exercise normalization, missing keys, strict thresholds, sorting, and filtering."""
    with open(MASTER_PATH, "rb") as f:
        original_master = f.read()
    with open(INCOMING_PATH, "rb") as f:
        original_incoming = f.read()

    try:
        for _ in range(3):
            token = secrets.token_hex(8)
            boundary_len = secrets.randbelow(10) + 1
            anomaly_len_a = secrets.randbelow(10) + 1
            anomaly_len_z = secrets.randbelow(10) + 1

            master = {
                f"z_missing_{token}": "missing z",
                f"z_anomaly_{token}": "z" * anomaly_len_z,
                f"mixed_key_{token}": "ordinary",
                f"double__space_{token}": "spacing",
                f"boundary_{token}": "b" * boundary_len,
                f"a_anomaly_{token}": "a" * anomaly_len_a,
                f"a_missing_{token}": "missing a"
            }
            incoming = {
                f"Z ANOMALY {token.upper()}": "Z" * (3 * anomaly_len_z + 1),
                f"MiXeD KeY {token.upper()}": f"approved-{secrets.token_hex(4)}",
                f"DOUBLE  SPACE {token.upper()}": f"double-{secrets.token_hex(4)}",
                f"BOUNDARY {token.upper()}": "B" * (3 * boundary_len),
                f"A ANOMALY {token.upper()}": "A" * (3 * anomaly_len_a + 1),
                f"UNKNOWN VENDOR {token.upper()}": "must be excluded"
            }
            expected_report, expected_approved = expected_outputs(master, incoming)
            assert len(expected_report["anomalies"]) == 2
            assert len(expected_report["missing"]) == 2

            with open(MASTER_PATH, "w") as f:
                json.dump(master, f)
            with open(INCOMING_PATH, "w") as f:
                json.dump(incoming, f)

            result = subprocess.run(
                ["python3", SCRIPT_PATH], capture_output=True, text=True, timeout=10
            )
            assert result.returncode == 0, f"Script failed on generated input: {result.stderr}"

            actual_report = load_json(REPORT_PATH)
            actual_approved = load_json(APPROVED_PATH)
            assert actual_report == expected_report, (
                f"Report is incorrect for generated input. Expected {expected_report}, got {actual_report}"
            )
            assert actual_approved == expected_approved, (
                f"Approved translations are incorrect for generated input. "
                f"Expected {expected_approved}, got {actual_approved}"
            )
    finally:
        with open(MASTER_PATH, "wb") as f:
            f.write(original_master)
        with open(INCOMING_PATH, "wb") as f:
            f.write(original_incoming)
        subprocess.run(["python3", SCRIPT_PATH], capture_output=True, text=True, timeout=10)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
