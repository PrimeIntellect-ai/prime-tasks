#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess

SCRIPT = "/home/user/process_inventory.sh"
INVENTORY = "/home/user/inventory.csv"
LOG = "/home/user/process.log"
CONF = "/home/user/active_servers.conf"


def run_pipeline():
    for path in (LOG, CONF):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, (
        f"Script failed to execute properly. Error: {result.stderr}"
    )


def write_inventory(rows):
    with open(INVENTORY, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["ServerID", "Hostname", "OS", "Notes", "Status"])
        writer.writerows(rows)


def expected_outputs(rows):
    cleaned = [row for row in rows if "\n" not in row[3]]
    dropped = len(rows) - len(cleaned)

    last_index = {}
    for index, row in enumerate(cleaned):
        last_index[row[0]] = index
    deduplicated = [
        row for index, row in enumerate(cleaned)
        if last_index[row[0]] == index
    ]

    blocks = []
    for server_id, hostname, operating_system, notes, status in deduplicated:
        if status == "active":
            blocks.append(
                f"[{hostname.lower()}]\n"
                f"ServerID={server_id}\n"
                f"OperatingSystem={operating_system.upper()}\n"
                f"Info={notes}\n"
                "---"
            )

    expected_log = (
        "[INFO] Pipeline started\n"
        f"[INFO] Dropped rows with embedded newlines: {dropped}\n"
        f"[INFO] Total unique servers after deduplication: {len(deduplicated)}\n"
        f"[INFO] Active servers written to config: {len(blocks)}\n"
        "[INFO] Pipeline finished"
    )
    return expected_log, "\n".join(blocks)


def assert_outputs(expected_log, expected_conf):
    assert os.path.isfile(LOG), f"Log file {LOG} was not created."
    with open(LOG) as f:
        actual_log = f.read().strip()
    assert actual_log == expected_log, (
        "Log file contents do not match expected metrics.\n"
        f"Expected:\n{expected_log}\nActual:\n{actual_log}"
    )

    assert os.path.isfile(CONF), f"Config file {CONF} was not created."
    with open(CONF) as f:
        actual_conf = f.read().strip()
    assert actual_conf == expected_conf, (
        "Config file contents do not match expected output.\n"
        f"Expected:\n{expected_conf}\nActual:\n{actual_conf}"
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_original_pipeline_and_exact_outputs():
    original_rows = [
        ["101", "WEB-front-01", "ubuntu", "Primary web node", "active"],
        ["102", "DB-master", "centos", "Requires immediate attention\nand restart", "active"],
        ["103", "CACHE-01", "debian", "Redis cluster node", "inactive"],
        ["101", "web-front-01", "Ubuntu", "Primary web node, upgraded", "active"],
        ["104", "API-gw", "rhel", "API Gateway\nv2.0 deployment\ndo not reboot", "active"],
        ["105", "WORKER-node", "Alpine", "Background jobs", "inactive"],
        ["106", "LB-01", "haproxy", "Load balancer", "active"],
        ["105", "worker-node", "alpine", "Background jobs (migrated)", "active"],
        ["107", "Metrics-01", "Ubuntu", "Prometheus\nGrafana", "inactive"],
    ]
    write_inventory(original_rows)
    run_pipeline()

    expected_log = """[INFO] Pipeline started
[INFO] Dropped rows with embedded newlines: 3
[INFO] Total unique servers after deduplication: 4
[INFO] Active servers written to config: 3
[INFO] Pipeline finished"""
    expected_conf = """[web-front-01]
ServerID=101
OperatingSystem=UBUNTU
Info=Primary web node, upgraded
---
[lb-01]
ServerID=106
OperatingSystem=HAPROXY
Info=Load balancer
---
[worker-node]
ServerID=105
OperatingSystem=ALPINE
Info=Background jobs (migrated)
---"""
    assert_outputs(expected_log, expected_conf)


def test_pipeline_on_unseen_inventories():
    for iteration in range(3):
        token = secrets.token_hex(6)
        base = str(200000 + secrets.randbelow(700000))
        ids = [str(int(base) + i) for i in range(6)]
        a, b, d, e, f, g = ids

        rows = [
            [a, f"Old-A-{token}", "linux", "superseded active row", "active"],
            [b, f"Old-B-{token}", "bsd", "old inactive row", "inactive"],
            [str(int(base) + 20), f"Dirty-{token}", "unix", "line one\nline two", "active"],
            [d, f"KePt-D-{token}", "uBuNtU", f"clean row {iteration}", "active"],
            [e, f"Comma-E-{token}", "rHeL", f"contains, comma and a \"quote\" {token}", "active"],
            [g, f"Earlier-G-{token}", "alpine", "earlier duplicate", "active"],
            [a, f"Final-A-{token}", "SOLARIS", "last A is inactive", "inactive"],
            [b, f"Final-B-{token}", "dEbIaN", "last B is active", "active"],
            [d, f"Dropped-D-{token}", "wrongos", "bad embedded\nnewline", "active"],
            [f, f"Case-F-{token}", "centOS", "status case must not match", "Active"],
            [g, f"Final-G-{token}", "hApRoXy", "last duplicate wins", "active"],
        ]

        expected_log, expected_conf = expected_outputs(rows)
        write_inventory(rows)
        run_pipeline()
        assert_outputs(expected_log, expected_conf)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
