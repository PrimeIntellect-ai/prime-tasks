#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import stat
import pytest

def load_csv(path):
    d = {}
    with open(path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) == 2:
                d[row[0].strip()] = row[1].strip()
    return d

def test_libloc_fixed_and_built():
    makefile_path = "/app/libloc-0.1.0/Makefile"
    assert os.path.exists(makefile_path), f"Makefile not found at {makefile_path}."
    with open(makefile_path, "r") as f:
        content = f.read()
        assert "nonexistent-gcc-99" not in content, "Makefile still contains the perturbation 'nonexistent-gcc-99'."

    libloc_a_path = "/app/libloc-0.1.0/libloc.a"
    assert os.path.exists(libloc_a_path), f"{libloc_a_path} was not built. The library needs to be compiled."

def test_accuracy_metric():
    actual_path = "/home/user/final_fr.csv"
    golden_path = "/tests/golden_fr.csv"

    assert os.path.exists(actual_path), f"Output file {actual_path} does not exist."
    assert os.path.exists(golden_path), f"Golden file {golden_path} does not exist."

    actual = load_csv(actual_path)
    expected = load_csv(golden_path)

    correct = sum(1 for k, v in expected.items() if actual.get(k) == v)
    total = len(expected)
    accuracy = correct / total if total > 0 else 0

    assert accuracy >= 0.95, f"Accuracy metric failed: {accuracy:.4f} is below the threshold of 0.95."

def test_run_etl_script():
    script_path = "/home/user/run_etl.sh"
    assert os.path.exists(script_path), f"Wrapper script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."

def test_cron_txt():
    cron_path = "/home/user/cron.txt"
    assert os.path.exists(cron_path), f"Cron file {cron_path} does not exist."

    with open(cron_path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.split('\n') if line.strip() and not line.startswith('#')]
    assert len(lines) >= 1, "No valid uncommented cron line found in cron.txt."

    valid_cron = False
    for line in lines:
        parts = line.split()
        if len(parts) >= 6:
            min_field, hr_field, dom_field, mon_field, dow_field = parts[:5]
            if min_field == "0" and hr_field == "2" and dom_field == "*" and mon_field == "*" and dow_field in ["1-5", "1,2,3,4,5"]:
                if "run_etl.sh" in line:
                    valid_cron = True
                    break

    assert valid_cron, "cron.txt does not contain a valid schedule for 2:00 AM Mon-Fri running run_etl.sh."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
