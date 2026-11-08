#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import re
import datetime
import pytest

REPORT_PATH = "/home/user/config_report.json"
LOG_PATH = "/home/user/config_stream.log"
TARGET_SERVERS = ["srv-web-01", "srv-web-02", "srv-web-03"]

def compute_expected_state():
    state = {s: {"max_connections": 100, "timeout": 30} for s in TARGET_SERVERS}
    daily_records = {s: {} for s in TARGET_SERVERS}

    pattern = re.compile(r'\[(.*?)\] \[(.*?)\] \[INFO\] deploy_bot: "Updated config\. max_connections=(\d+), timeout=(.*?)"')

    current_date = datetime.date(2024, 1, 1)

    if os.path.exists(LOG_PATH):
        with open(LOG_PATH, "r") as f:
            for line in f:
                m = pattern.search(line)
                if m:
                    dt_str, srv, mc, to = m.groups()
                    if srv not in TARGET_SERVERS:
                        continue
                    dt = datetime.datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S")
                    date_val = dt.date()

                    while current_date < date_val:
                        if current_date.month == 1 and current_date.year == 2024:
                            for s in TARGET_SERVERS:
                                daily_records[s][current_date.strftime("%Y-%m-%d")] = dict(state[s])
                        current_date += datetime.timedelta(days=1)

                    mc = int(mc)
                    if to.endswith('s'):
                        to_sec = int(to[:-1])
                    elif to.endswith('m'):
                        to_sec = int(to[:-1]) * 60
                    else:
                        to_sec = int(to)

                    state[srv] = {"max_connections": mc, "timeout": to_sec}

    end_date = datetime.date(2024, 1, 31)
    while current_date <= end_date:
        if current_date.month == 1 and current_date.year == 2024:
            for s in TARGET_SERVERS:
                daily_records[s][current_date.strftime("%Y-%m-%d")] = dict(state[s])
        current_date += datetime.timedelta(days=1)

    anomalies = {s: [] for s in TARGET_SERVERS}
    for s in TARGET_SERVERS:
        prev_mc = 100
        for day in range(1, 32):
            date_str = f"2024-01-{day:02d}"
            curr_mc = daily_records[s][date_str]["max_connections"]
            if curr_mc > prev_mc * 1.5:
                anomalies[s].append(date_str)
            prev_mc = curr_mc

    return daily_records, anomalies

@pytest.fixture(scope="module")
def expected_data():
    return compute_expected_state()

@pytest.fixture(scope="module")
def report_data():
    assert os.path.exists(REPORT_PATH), f"Output file {REPORT_PATH} is missing."
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

def test_servers_exist(report_data):
    for srv in TARGET_SERVERS:
        assert srv in report_data, f"Server {srv} is missing from the report."

def test_structure_and_days(report_data):
    for srv in TARGET_SERVERS:
        data = report_data[srv]
        assert "daily_state" in data, f"Missing 'daily_state' for server {srv}."
        assert "anomalies" in data, f"Missing 'anomalies' for server {srv}."

        daily_state = data["daily_state"]
        assert len(daily_state) == 31, f"Expected 31 days in Jan 2024 for {srv}, got {len(daily_state)}."

def test_daily_state_values(report_data, expected_data):
    expected_daily, _ = expected_data
    for srv in TARGET_SERVERS:
        daily_state = report_data[srv]["daily_state"]
        for day in range(1, 32):
            date_str = f"2024-01-{day:02d}"
            assert date_str in daily_state, f"Missing date {date_str} for server {srv}."

            actual = daily_state[date_str]
            expected = expected_daily[srv][date_str]

            assert "max_connections" in actual, f"Missing max_connections for {srv} on {date_str}."
            assert "timeout" in actual, f"Missing timeout for {srv} on {date_str}."

            assert isinstance(actual["timeout"], int), f"Timeout for {srv} on {date_str} must be an integer."
            assert actual["max_connections"] == expected["max_connections"], \
                f"Incorrect max_connections for {srv} on {date_str}. Expected {expected['max_connections']}, got {actual['max_connections']}."
            assert actual["timeout"] == expected["timeout"], \
                f"Incorrect timeout for {srv} on {date_str}. Expected {expected['timeout']}, got {actual['timeout']}."

def test_anomalies(report_data, expected_data):
    _, expected_anomalies = expected_data
    for srv in TARGET_SERVERS:
        actual_anomalies = report_data[srv]["anomalies"]
        expected = expected_anomalies[srv]
        assert actual_anomalies == expected, \
            f"Incorrect anomalies for {srv}. Expected {expected}, got {actual_anomalies}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
