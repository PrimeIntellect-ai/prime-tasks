#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import stat
import subprocess

SCRIPT = "/home/user/verify_backups.py"
OUTPUT = "/home/user/team_summary.json"
BACKUP_DIR = "/home/user/backups"


def run_script():
    return subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )


def test_script_exists_and_runs():
    assert os.path.exists(SCRIPT), f"Expected script {SCRIPT} is missing."
    assert not os.path.islink(SCRIPT), f"Expected {SCRIPT} to be a regular Python script, not a symlink."
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"Expected {SCRIPT} to be a regular file."
    result = run_script()
    assert result.returncode == 0, (
        f"{SCRIPT} did not run successfully.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_team_summary_exists():
    filepath = "/home/user/team_summary.json"
    assert os.path.isfile(filepath), f"Expected output file {filepath} is missing."


def test_team_summary_content():
    filepath = "/home/user/team_summary.json"
    assert os.path.isfile(filepath), f"Expected output file {filepath} is missing."

    with open(filepath, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{filepath} does not contain valid JSON."

    expected_data = {
        "TeamAlpha": {
            "total_endpoints": 3,
            "outbound_dependencies": 1
        },
        "TeamBeta": {
            "total_endpoints": 5,
            "outbound_dependencies": 4
        },
        "TeamGamma": {
            "total_endpoints": 2,
            "outbound_dependencies": 2
        }
    }

    assert isinstance(data, dict), f"Expected a JSON object at the root of {filepath}."

    for team, expected_metrics in expected_data.items():
        assert team in data, f"Missing team '{team}' in {filepath}."
        metrics = data[team]
        assert "total_endpoints" in metrics, f"Missing 'total_endpoints' for team '{team}'."
        assert "outbound_dependencies" in metrics, f"Missing 'outbound_dependencies' for team '{team}'."

        assert metrics["total_endpoints"] == expected_metrics["total_endpoints"], \
            f"Incorrect total_endpoints for '{team}'. Expected {expected_metrics['total_endpoints']}, got {metrics['total_endpoints']}."
        assert metrics["outbound_dependencies"] == expected_metrics["outbound_dependencies"], \
            f"Incorrect outbound_dependencies for '{team}'. Expected {expected_metrics['outbound_dependencies']}, got {metrics['outbound_dependencies']}."

    # Check for extra unexpected teams
    for team in data.keys():
        assert team in expected_data, f"Unexpected team '{team}' found in {filepath}."


def test_script_processes_changed_backups():
    paths = {
        "services": os.path.join(BACKUP_DIR, "services.csv"),
        "endpoints": os.path.join(BACKUP_DIR, "endpoints.jsonl"),
        "dependencies": os.path.join(BACKUP_DIR, "dependencies.json"),
    }
    originals = {name: open(path, "rb").read() for name, path in paths.items()}

    token = secrets.token_hex(8)
    teams = [f"Red_{token}", f"Blue_{token}", f"Green_{token}"]
    services = [
        (f"A_{token}", "ServiceA", teams[0]),
        (f"B_{token}", "ServiceB", teams[0]),
        (f"C_{token}", "ServiceC", teams[1]),
        (f"D_{token}", "ServiceD", teams[2]),
    ]
    endpoint_records = [
        {"service_id": services[0][0], "endpoints": [f"/{token}/one", f"/{token}/shared", f"/{token}/one"]},
        {"service_id": services[1][0], "endpoints": [f"/{token}/shared", f"/{token}/two"]},
        {"service_id": services[2][0], "endpoints": [f"/{token}/three"]},
        {"service_id": services[3][0], "endpoints": [f"/{token}/four", f"/{token}/five"]},
    ]
    edges = [
        {"source": services[0][0], "target": services[2][0]},
        {"source": services[1][0], "target": services[2][0]},
        {"source": services[1][0], "target": services[3][0]},
        {"source": services[2][0], "target": services[0][0]},
        {"source": services[3][0], "target": services[0][0]},
        {"source": services[3][0], "target": services[1][0]},
    ]

    service_to_team = {service_id: team for service_id, _, team in services}
    endpoint_sets = {team: set() for team in teams}
    dependency_counts = {team: 0 for team in teams}
    for record in endpoint_records:
        endpoint_sets[service_to_team[record["service_id"]]].update(record["endpoints"])
    for edge in edges:
        dependency_counts[service_to_team[edge["source"]]] += 1
    expected = {
        team: {
            "total_endpoints": len(endpoint_sets[team]),
            "outbound_dependencies": dependency_counts[team],
        }
        for team in teams
    }

    try:
        with open(paths["services"], "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["service_id", "service_name", "team_owner"])
            writer.writerows(services)
        with open(paths["endpoints"], "w") as f:
            for record in endpoint_records:
                f.write(json.dumps(record) + "\n")
        with open(paths["dependencies"], "w") as f:
            json.dump(edges, f)

        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        result = run_script()
        assert result.returncode == 0, (
            f"{SCRIPT} failed on valid changed backups.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} is missing after running the script."
        with open(OUTPUT, "r") as f:
            actual = json.load(f)
        assert actual == expected, f"Script did not derive the expected summary from changed backups: {actual!r}"
    finally:
        for name, path in paths.items():
            with open(path, "wb") as f:
                f.write(originals[name])
        run_script()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
