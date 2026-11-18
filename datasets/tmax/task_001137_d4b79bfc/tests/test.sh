#!/bin/bash
mkdir -p /logs/verifier

overall_ok=1
CSV_PATH=/home/user/legacy_topology.csv
SCRIPT_PATH=/home/user/deploy_migration.sh

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import subprocess
import pytest

CSV_PATH = "/home/user/legacy_topology.csv"
SCRIPT_PATH = "/home/user/deploy_migration.sh"
SERVICES_DIR = "/home/user/services"
CONFIGS_DIR = "/home/user/system_configs"
REPORT_PATH = "/home/user/migration_report.json"

def get_csv_data():
    if not os.path.exists(CSV_PATH):
        pytest.fail(f"CSV file {CSV_PATH} is missing.")

    services = []
    with open(CSV_PATH, "r", newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            services.append(row)
    return services

def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Deployment script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Deployment script {SCRIPT_PATH} is not executable."

def test_script_is_valid_bash():
    result = subprocess.run(
        ["/bin/bash", "-n", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"{SCRIPT_PATH} is not valid Bash: {result.stderr}"

def test_directories_created():
    services = get_csv_data()

    assert os.path.exists(SERVICES_DIR), f"Services directory {SERVICES_DIR} does not exist."
    assert os.path.isdir(SERVICES_DIR), f"{SERVICES_DIR} is not a directory."

    assert os.path.exists(CONFIGS_DIR), f"System configs directory {CONFIGS_DIR} does not exist."
    assert os.path.isdir(CONFIGS_DIR), f"{CONFIGS_DIR} is not a directory."

    for svc in services:
        svc_dir = os.path.join(SERVICES_DIR, svc["ServiceName"])
        assert os.path.exists(svc_dir), f"Service directory {svc_dir} does not exist."
        assert os.path.isdir(svc_dir), f"{svc_dir} is not a directory."

def test_profile_files_content():
    services = get_csv_data()

    for svc in services:
        profile_path = os.path.join(SERVICES_DIR, svc["ServiceName"], ".app_profile")
        assert os.path.exists(profile_path), f"Profile file {profile_path} does not exist."

        expected_content = (
            f'export APP_ENV="cloud_migration"\n'
            f'export CLOUD_DB_HOST="{svc["CloudDBHost"]}"\n'
            f'export APP_PORT="{svc["NewPort"]}"\n'
            f'export MIGRATION_STATUS="ACTIVE"'
        )

        with open(profile_path, "r") as f:
            content = f.read().strip()

        assert content == expected_content, f"Content of {profile_path} does not match expected."

def test_config_files_content():
    services = get_csv_data()

    for svc in services:
        config_path = os.path.join(CONFIGS_DIR, f'{svc["ServiceName"]}_proxy.conf')
        assert os.path.exists(config_path), f"Config file {config_path} does not exist."

        expected_content = (
            f'[ProxyConfig]\n'
            f'ListenPort={svc["NewPort"]}\n'
            f'Upstream={svc["LegacyIP"]}:{svc["LegacyPort"]}\n'
            f'RequireGroup={svc["TargetGroup"]}'
        )

        with open(config_path, "r") as f:
            content = f.read().strip()

        assert content == expected_content, f"Content of {config_path} does not match expected."

def test_json_report_content():
    services = get_csv_data()

    assert os.path.exists(REPORT_PATH), f"JSON report {REPORT_PATH} does not exist."

    with open(REPORT_PATH, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")

    assert "migrated_services" in report_data, f"'migrated_services' key missing in {REPORT_PATH}."
    assert "total_services" in report_data, f"'total_services' key missing in {REPORT_PATH}."

    assert report_data["total_services"] == len(services), "Total services count in JSON does not match CSV."

    expected_migrated = []
    for svc in services:
        expected_migrated.append({
            "name": svc["ServiceName"],
            "port": int(svc["NewPort"]),
            "profile_path": f"/home/user/services/{svc['ServiceName']}/.app_profile"
        })

    expected_migrated.sort(key=lambda x: x["name"])

    assert report_data["migrated_services"] == expected_migrated, "Migrated services list in JSON does not match expected structure and sorting."
TEST_EOF

original_csv=$(mktemp)
challenge_csv=$(mktemp)

if [ ! -f "$CSV_PATH" ] || ! cp -- "$CSV_PATH" "$original_csv"; then
    overall_ok=0
else
    cp -- "$original_csv" "$challenge_csv" || overall_ok=0
    if ! python3 - "$challenge_csv" <<'PY'
import csv
import secrets
import sys

path = sys.argv[1]
token = secrets.token_hex(8)
with open(path, "a", newline="") as f:
    csv.writer(f).writerow([
        "Service" + token,
        f"172.20.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}",
        str(secrets.randbelow(30000) + 10000),
        "db-" + token + ".cloud.internal",
        str(secrets.randbelow(20000) + 30000),
        "group_" + token,
    ])
PY
    then
        overall_ok=0
    fi
fi

run_clean_deployment() {
    rm -rf -- /home/user/services /home/user/system_configs
    rm -f -- /home/user/migration_report.json
    timeout 30s runuser -u user -- "$SCRIPT_PATH"
}

# Exercise the submitted script from a clean state using an additional,
# verifier-generated CSV row so hard-coded or no-op scripts cannot pass.
if [ "$overall_ok" -eq 1 ] && [ -f "$SCRIPT_PATH" ] && [ -x "$SCRIPT_PATH" ]; then
    if cp -- "$challenge_csv" "$CSV_PATH" && run_clean_deployment; then
        # Restore the trusted challenge input in case the script altered it.
        cp -- "$challenge_csv" "$CSV_PATH"
        if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
            overall_ok=0
        fi
    else
        overall_ok=0
        cp -- "$challenge_csv" "$CSV_PATH" 2>/dev/null || true
    fi
else
    overall_ok=0
fi

# Restore the supplied topology, execute the script again from a clean state,
# and retain the requested final deployment state.
if [ -s "$original_csv" ]; then
    cp -- "$original_csv" "$CSV_PATH" || overall_ok=0
    if [ -f "$SCRIPT_PATH" ] && [ -x "$SCRIPT_PATH" ] && run_clean_deployment; then
        cp -- "$original_csv" "$CSV_PATH"
        if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
            overall_ok=0
        fi
    else
        overall_ok=0
        cp -- "$original_csv" "$CSV_PATH" 2>/dev/null || true
    fi
else
    overall_ok=0
fi

rm -f -- "$original_csv" "$challenge_csv"

if [ "$overall_ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
