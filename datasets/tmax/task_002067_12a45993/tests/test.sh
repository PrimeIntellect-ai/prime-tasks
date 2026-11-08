#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import shutil
import subprocess
from collections import Counter, defaultdict

SCRIPT = "/home/user/analyze_configs.sh"
INVENTORY = "/home/user/inventory.csv"
LOGS = "/home/user/config_logs.txt"
OUTPUT = "/home/user/output"
STATS = os.path.join(OUTPUT, "daily_region_stats.csv")
SIMILARITY = os.path.join(OUTPUT, "host_similarity.csv")


def write_inputs(inventory_text, log_text):
    with open(INVENTORY, "w", newline="") as f:
        f.write(inventory_text)
    with open(LOGS, "w", newline="") as f:
        f.write(log_text)


def run_script():
    shutil.rmtree(OUTPUT, ignore_errors=True)
    result = subprocess.run([SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute. STDERR:\n{result.stderr}"
    assert os.path.isfile(STATS), f"Output file {STATS} was not created."
    assert os.path.isfile(SIMILARITY), f"Output file {SIMILARITY} was not created."
    with open(STATS, newline="") as f:
        stats = list(csv.reader(f))
    with open(SIMILARITY, newline="") as f:
        similarity = list(csv.reader(f))
    return stats, similarity


def derive_expected(inventory_text, log_text):
    inventory_rows = list(csv.DictReader(inventory_text.splitlines()))
    host_region = {row["host_id"]: row["region"] for row in inventory_rows}

    records = []
    pattern = re.compile(
        r"^\[(\d{4}-\d{2}-\d{2})\] EVENT: config_update HOST: (\S+) PARAM: (\S+) VAL:.*$"
    )
    for line in log_text.splitlines():
        match = pattern.match(line)
        assert match, f"Invalid generated fixture line: {line}"
        date, host, parameter = match.groups()
        records.append((date, host, parameter))

    totals = Counter()
    for date, host, _ in records:
        totals[(date, host_region[host])] += 1

    previous = {}
    expected_stats = [["date", "region", "daily_total", "rolling_avg"]]
    for date, region in sorted(totals):
        total = totals[(date, region)]
        average = total if region not in previous else (previous[region] + total) / 2.0
        expected_stats.append([date, region, str(total), f"{average:.1f}"])
        previous[region] = total

    profiles = defaultdict(Counter)
    east_hosts = set()
    for _, host, parameter in records:
        if host_region[host] == "us-east":
            east_hosts.add(host)
            profiles[host][parameter] += 1

    expected_similarity = []
    ordered_hosts = sorted(east_hosts)
    for index, host1 in enumerate(ordered_hosts):
        for host2 in ordered_hosts[index + 1:]:
            parameters = set(profiles[host1]) | set(profiles[host2])
            distance = sum(abs(profiles[host1][p] - profiles[host2][p]) for p in parameters)
            expected_similarity.append([host1, host2, str(distance)])

    return expected_stats, expected_similarity


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_original_fixture_and_outputs():
    inventory_text = """host_id,region,environment
web-01,us-east,prod
web-02,us-east,prod
db-01,us-east,prod
app-01,eu-west,dev
app-02,eu-west,prod
"""
    log_text = """[2023-11-01] EVENT: config_update HOST: web-01 PARAM: max_connections VAL: 100
[2023-11-01] EVENT: config_update HOST: web-01 PARAM: timeout VAL: 30
[2023-11-01] EVENT: config_update HOST: web-02 PARAM: max_connections VAL: 150
[2023-11-01] EVENT: config_update HOST: app-01 PARAM: debug_mode VAL: true
[2023-11-02] EVENT: config_update HOST: web-01 PARAM: max_connections VAL: 200
[2023-11-02] EVENT: config_update HOST: db-01 PARAM: buffer_pool VAL: 4G
[2023-11-02] EVENT: config_update HOST: db-01 PARAM: cache_size VAL: 2G
[2023-11-02] EVENT: config_update HOST: app-02 PARAM: threads VAL: 16
[2023-11-03] EVENT: config_update HOST: web-02 PARAM: timeout VAL: 60
[2023-11-03] EVENT: config_update HOST: app-01 PARAM: debug_mode VAL: false
[2023-11-03] EVENT: config_update HOST: app-01 PARAM: threads VAL: 8
"""
    write_inputs(inventory_text, log_text)
    actual_stats, actual_similarity = run_script()

    expected_stats = [
        ["date", "region", "daily_total", "rolling_avg"],
        ["2023-11-01", "eu-west", "1", "1.0"],
        ["2023-11-01", "us-east", "3", "3.0"],
        ["2023-11-02", "eu-west", "1", "1.0"],
        ["2023-11-02", "us-east", "3", "3.0"],
        ["2023-11-03", "eu-west", "2", "1.5"],
        ["2023-11-03", "us-east", "1", "2.0"],
    ]
    expected_similarity = [
        ["db-01", "web-01", "5"],
        ["db-01", "web-02", "4"],
        ["web-01", "web-02", "1"],
    ]

    assert actual_stats == expected_stats, f"Expected {expected_stats}, got {actual_stats}"
    assert actual_similarity == expected_similarity, f"Expected {expected_similarity}, got {actual_similarity}"


def test_generated_fixture_is_actually_processed():
    rng = random.SystemRandom()
    inventory_rows = [
        ("api-11", "us-east", "prod"),
        ("batch-07", "eu-west", "dev"),
        ("cache-03", "us-east", "stage"),
        ("db-09", "ap-south", "prod"),
        ("worker-05", "us-east", "prod"),
        ("web-13", "eu-west", "prod"),
    ]
    shuffled_inventory = inventory_rows[:]
    rng.shuffle(shuffled_inventory)
    inventory_text = "host_id,region,environment\n" + "".join(
        f"{host},{region},{environment}\n"
        for host, region, environment in shuffled_inventory
    )

    dates = ["2024-01-02", "2024-01-05", "2024-02-01", "2024-02-04"]
    parameters = ["alpha_limit", "beta_mode", "cache_ttl", "delta_size", "retry_count"]
    events = []
    for host, region, _ in inventory_rows:
        for date_index, date in enumerate(dates):
            # Deliberately leave some region/date combinations absent so rolling
            # averages use the previous observed day for that region.
            if (host == "batch-07" and date_index == 1) or (host == "db-09" and date_index == 2):
                count = 0
            else:
                count = rng.randint(1, 4)
            for event_index in range(count):
                parameter = rng.choice(parameters)
                value = rng.randint(10, 9999)
                events.append(
                    f"[{date}] EVENT: config_update HOST: {host} PARAM: {parameter} VAL: {value}"
                )

    rng.shuffle(events)
    log_text = "\n".join(events) + "\n"
    expected_stats, expected_similarity = derive_expected(inventory_text, log_text)

    write_inputs(inventory_text, log_text)
    actual_stats, actual_similarity = run_script()

    assert actual_stats == expected_stats, f"Expected {expected_stats}, got {actual_stats}"
    assert actual_similarity == expected_similarity, f"Expected {expected_similarity}, got {actual_similarity}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
