#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile

SCRIPT = "/home/user/analyze_backups.sh"
CSV_PATH = "/home/user/restore_chain.csv"
LOG_DIR = "/home/user/backup_logs"


def run_script():
    if os.path.exists(CSV_PATH):
        os.unlink(CSV_PATH)
    env = os.environ.copy()
    env["HOME"] = "/home/user"
    result = subprocess.run(
        ["runuser", "-u", "user", "--", SCRIPT],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} is missing after execution."


def read_output():
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def valid_record(record):
    required = {
        "job_id", "cluster", "type", "parent_job_id", "status",
        "size_bytes", "timestamp"
    }
    return (
        isinstance(record, dict)
        and required.issubset(record)
        and record["type"] in ("full", "incremental")
        and isinstance(record["size_bytes"], int)
        and not isinstance(record["size_bytes"], bool)
        and isinstance(record["timestamp"], int)
        and not isinstance(record["timestamp"], bool)
    )


def derive_expected(records):
    records = [
        r for r in records
        if valid_record(r)
        and r["status"] == "success"
        and r["cluster"] == "db-cluster-omega"
    ]
    by_id = {r["job_id"]: r for r in records}
    children = {}
    for r in records:
        if r["type"] == "incremental":
            children.setdefault(r["parent_job_id"], []).append(r)

    chains = []

    def walk(chain, seen):
        next_nodes = [
            child for child in children.get(chain[-1]["job_id"], [])
            if child["job_id"] not in seen
        ]
        if not next_nodes:
            chains.append(chain)
            return
        for child in next_nodes:
            walk(chain + [child], seen | {child["job_id"]})

    for record in records:
        if record["type"] == "full":
            walk([record], {record["job_id"]})

    assert chains, "Verifier fixture unexpectedly has no restoration chain"
    chosen = max(chains, key=lambda chain: (len(chain), chain[-1]["size_bytes"]))
    lines = ["job_id,type,cumulative_size_bytes"]
    cumulative = 0
    for record in chosen:
        cumulative += record["size_bytes"]
        lines.append(f'{record["job_id"]},{record["type"]},{cumulative}')
    return lines


def install_dynamic_logs():
    shutil.rmtree(LOG_DIR)
    os.makedirs(LOG_DIR, mode=0o777)
    os.chmod(LOG_DIR, 0o777)

    prefix = "v" + secrets.token_hex(6)
    base_size = 11000 + secrets.randbelow(2000)
    first_inc = 300 + secrets.randbelow(100)
    low_final = 1000 + secrets.randbelow(200)
    high_final = 9000 + secrets.randbelow(200)
    other_final = 4000 + secrets.randbelow(200)

    def rec(suffix, cluster, kind, parent, status, size, timestamp):
        return {
            "job_id": prefix + suffix,
            "cluster": cluster,
            "type": kind,
            "parent_job_id": parent,
            "status": status,
            "size_bytes": size,
            "timestamp": timestamp,
        }

    full = rec("-full", "db-cluster-omega", "full", None, "success", base_size, 1700000000)
    common = rec("-common", "db-cluster-omega", "incremental", full["job_id"], "success", first_inc, 1700000100)
    low_mid = rec("-low-mid", "db-cluster-omega", "incremental", common["job_id"], "success", 210, 1700000200)
    low_end = rec("-low-end", "db-cluster-omega", "incremental", low_mid["job_id"], "success", low_final, 1700000300)
    high_mid = rec("-high-mid", "db-cluster-omega", "incremental", common["job_id"], "success", 470, 1700000400)
    high_end = rec("-high-end", "db-cluster-omega", "incremental", high_mid["job_id"], "success", high_final, 1700000500)

    other_full = rec("-other-full", "db-cluster-omega", "full", None, "success", 7000, 1700000600)
    other_1 = rec("-other-1", "db-cluster-omega", "incremental", other_full["job_id"], "success", 100, 1700000700)
    other_2 = rec("-other-2", "db-cluster-omega", "incremental", other_1["job_id"], "success", 100, 1700000800)
    other_3 = rec("-other-3", "db-cluster-omega", "incremental", other_2["job_id"], "success", other_final, 1700000900)

    records = [full, common, low_mid, low_end, high_mid, high_end,
               other_full, other_1, other_2, other_3]

    invalid = [
        rec("-failed", "db-cluster-omega", "incremental", high_end["job_id"], "failed", 50000, 1700001000),
        rec("-wrong-cluster", "db-cluster-alpha", "incremental", high_end["job_id"], "success", 60000, 1700001100),
        rec("-orphan", "db-cluster-omega", "incremental", prefix + "-absent", "success", 70000, 1700001200),
    ]
    missing_timestamp = rec("-missing", "db-cluster-omega", "incremental", high_end["job_id"], "success", 80000, 1700001300)
    del missing_timestamp["timestamp"]
    invalid.append(missing_timestamp)

    for index, record in enumerate(records + invalid):
        with open(os.path.join(LOG_DIR, f"case_{index}.json"), "w", encoding="utf-8") as f:
            json.dump(record, f)
    with open(os.path.join(LOG_DIR, "malformed.json"), "w", encoding="utf-8") as f:
        f.write('{"job_id": "broken", this is not valid JSON')

    for name in os.listdir(LOG_DIR):
        os.chmod(os.path.join(LOG_DIR, name), 0o644)
    return records + invalid


def test_script_execution_and_behavior():
    # Preserve all original verifier assertions.
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} is missing."

    expected_original = [
        "job_id,type,cumulative_size_bytes",
        "j002,full,10000",
        "j003,incremental,10500",
        "j006,incremental,10700",
        "j007,incremental,11000",
    ]

    temp_dir = tempfile.mkdtemp(prefix="backup-verifier-")
    saved_logs = os.path.join(temp_dir, "backup_logs")
    shutil.copytree(LOG_DIR, saved_logs)
    saved_csv = os.path.join(temp_dir, "restore_chain.csv")
    shutil.copy2(CSV_PATH, saved_csv)

    try:
        # Remove the pre-generated artifact and require the submitted script to recreate it.
        run_script()
        assert read_output() == expected_original, (
            f"Contents of {CSV_PATH} do not match the expected output after execution.\n"
            f"Expected:\n{chr(10).join(expected_original)}\n"
            f"Actual:\n{chr(10).join(read_output())}"
        )

        # Replace the logs with unpredictable data and derive the answer independently.
        fixture_records = install_dynamic_logs()
        expected_dynamic = derive_expected(fixture_records)
        run_script()
        actual_dynamic = read_output()
        assert actual_dynamic == expected_dynamic, (
            "Script failed validation, filtering, graph selection, tie-breaking, or aggregation "
            "on dynamically generated logs.\n"
            f"Expected:\n{chr(10).join(expected_dynamic)}\n"
            f"Actual:\n{chr(10).join(actual_dynamic)}"
        )
    finally:
        if os.path.exists(LOG_DIR):
            shutil.rmtree(LOG_DIR)
        shutil.copytree(saved_logs, LOG_DIR)
        if os.path.exists(CSV_PATH):
            os.unlink(CSV_PATH)
        shutil.copy2(saved_csv, CSV_PATH)
        shutil.rmtree(temp_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
