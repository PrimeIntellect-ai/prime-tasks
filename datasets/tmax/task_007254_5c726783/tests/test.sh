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

SCRIPT_PATH = "/home/user/analyze_backups.sh"
REPORT_PATH = "/home/user/report.csv"
BACKUPS_PATH = "/home/user/backups.json"
GRAPH_PATH = "/home/user/replication_graph.csv"


def expected_report():
    assert os.path.isfile(BACKUPS_PATH), f"Data file {BACKUPS_PATH} is missing."
    assert os.path.isfile(GRAPH_PATH), f"Data file {GRAPH_PATH} is missing."

    with open(BACKUPS_PATH, "r") as f:
        backups = json.load(f)

    backup_info = {}
    for b in backups:
        backup_info[b["db_instance"]] = {
            "status": b["status"],
            "size_gb": b["size_gb"],
        }

    primary_to_replicas = {}
    with open(GRAPH_PATH, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            p = row["primary"].strip()
            r = row["replica"].strip()
            primary_to_replicas.setdefault(p, []).append(r)

    expected_rows = []
    for primary, replicas in primary_to_replicas.items():
        has_failed_replica = any(
            backup_info.get(r, {}).get("status") == "failed" for r in replicas
        )
        if has_failed_replica:
            num_replicas = len(replicas)
            total_size = 0
            if backup_info.get(primary, {}).get("status") == "success":
                total_size += backup_info[primary]["size_gb"]
            for replica in replicas:
                if backup_info.get(replica, {}).get("status") == "success":
                    total_size += backup_info[replica]["size_gb"]
            expected_rows.append(f"{primary},{num_replicas},{total_size}")

    expected_rows.sort()
    return "\n".join(expected_rows)


def run_script_and_check():
    expected_content = expected_report()
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), (
        f"Script did not generate report {REPORT_PATH}."
    )

    with open(REPORT_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    actual_content = "\n".join(actual_lines)

    assert actual_content == expected_content, (
        f"Report content in {REPORT_PATH} does not match expected output.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_report_content_generated_from_original_inputs():
    run_script_and_check()


def test_script_handles_changed_inputs():
    token = secrets.token_hex(6)
    names = {
        "p1": f"alpha-primary-{token}",
        "p2": f"middle-primary-{token}",
        "p3": f"zulu-primary-{token}",
        "p4": f"beta-primary-{token}",
        "r1": f"replica-a-{token}",
        "r2": f"replica-b-{token}",
        "r3": f"replica-c-{token}",
        "r4": f"replica-d-{token}",
        "r5": f"replica-e-{token}",
        "r6": f"replica-f-{token}",
        "r7": f"replica-g-{token}",
    }
    sizes = [secrets.randbelow(400) + 1 for _ in range(11)]
    instances = [
        (names["p1"], "success"),
        (names["r1"], "failed"),
        (names["r2"], "success"),
        (names["p2"], "success"),
        (names["r3"], "success"),
        (names["p3"], "failed"),
        (names["r4"], "failed"),
        (names["r5"], "failed"),
        (names["r6"], "success"),
        (names["p4"], "success"),
        (names["r7"], "failed"),
    ]
    backups = [
        {
            "id": f"random-{i}",
            "db_instance": instance,
            "status": status,
            "size_gb": sizes[i],
        }
        for i, (instance, status) in enumerate(instances)
    ]
    with open(BACKUPS_PATH, "w") as f:
        json.dump(backups, f)

    edges = [
        (names["p3"], names["r4"]),
        (names["p1"], names["r1"]),
        (names["p2"], names["r3"]),
        (names["p3"], names["r5"]),
        (names["p4"], names["r7"]),
        (names["p1"], names["r2"]),
        (names["p3"], names["r6"]),
    ]
    with open(GRAPH_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["primary", "replica"])
        writer.writerows(edges)

    run_script_and_check()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
