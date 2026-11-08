#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import secrets
import subprocess

import pytest
import yaml

PLANNER = "/home/user/planner.py"
ALLOCATIONS = "/home/user/allocations.json"
COMPOSE = "/home/user/docker-compose.yml"
REPORT = "/home/user/report.txt"


def test_planner_script_exists():
    filepath = "/home/user/planner.py"
    assert os.path.exists(filepath), f"Missing script file: {filepath}"
    assert os.path.isfile(filepath), f"{filepath} should be a file"


def test_report_txt_exists_and_correct():
    filepath = "/home/user/report.txt"
    assert os.path.exists(filepath), f"Missing report file: {filepath}"
    assert os.path.isfile(filepath), f"{filepath} should be a file"

    with open(filepath, "r") as f:
        content = f.read().strip()

    expected_content = "Conflict: requested 10.10.10.128/25 overlaps with metrics_net (10.10.10.0/24)"

    assert content == expected_content, (
        f"Incorrect content in {filepath}. "
        f"Expected: '{expected_content}', but got: '{content}'"
    )


def _run_planner(expected):
    if os.path.lexists(REPORT):
        os.remove(REPORT)

    result = subprocess.run(
        ["python3", PLANNER],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"planner.py exited with status {result.returncode}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(REPORT), "planner.py did not create /home/user/report.txt"

    with open(REPORT, "r") as f:
        actual = f.read().strip()
    assert actual == expected, f"Expected report '{expected}', but got '{actual}'"


def _write_inputs(allocations, requested_subnets):
    with open(ALLOCATIONS, "w") as f:
        json.dump(allocations, f)

    network_names = [f"requested_{i}" for i in range(len(requested_subnets))]
    compose = {
        "version": "3",
        "services": {
            "analyzer": {
                "image": "capacity-analyzer:latest",
                "networks": network_names,
            }
        },
        "networks": {
            name: {
                "ipam": {
                    "driver": "default",
                    "config": [{"subnet": subnet}],
                }
            }
            for name, subnet in zip(network_names, requested_subnets)
        },
    }
    with open(COMPOSE, "w") as f:
        yaml.safe_dump(compose, f, sort_keys=False)


def test_planner_executes_and_handles_varied_inputs():
    paths = [ALLOCATIONS, COMPOSE, REPORT]
    backups = {}
    for path in paths:
        with open(path, "rb") as f:
            backups[path] = f.read()

    try:
        # The supplied inputs must be processed by the script, not merely matched
        # by a report that existed before verification.
        _run_planner(
            "Conflict: requested 10.10.10.128/25 overlaps with metrics_net (10.10.10.0/24)"
        )

        octets = secrets.SystemRandom().sample(range(30, 220), 4)
        a, b, c, d = octets
        token = secrets.token_hex(4)

        # Detect a proper-subnet overlap using values and a network name selected
        # only at verification time.
        overlap_name = f"allocated_{token}"
        requested = f"10.{a}.231.128/25"
        existing = f"10.{a}.0.0/16"
        _write_inputs(
            {overlap_name: existing, f"other_{token}": f"10.{b}.0.0/16"},
            [requested],
        )
        _run_planner(
            f"Conflict: requested {requested} overlaps with {overlap_name} ({existing})"
        )

        # A non-overlapping request must produce the required no-conflict result.
        _write_inputs({f"occupied_{token}": f"10.{b}.0.0/16"}, [f"10.{c}.0.0/24"])
        _run_planner("No conflicts found")

        # Parse multiple requested networks and report only the first allocated
        # network encountered when the later request has multiple conflicts.
        first_name = f"first_{token}"
        second_name = f"second_{token}"
        broad_request = f"10.{d}.0.0/16"
        first_subnet = f"10.{d}.0.0/17"
        second_subnet = f"10.{d}.128.0/17"
        _write_inputs(
            {first_name: first_subnet, second_name: second_subnet},
            ["192.0.2.0/28", broad_request],
        )
        _run_planner(
            f"Conflict: requested {broad_request} overlaps with {first_name} ({first_subnet})"
        )
    finally:
        for path, data in backups.items():
            with open(path, "wb") as f:
                f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
