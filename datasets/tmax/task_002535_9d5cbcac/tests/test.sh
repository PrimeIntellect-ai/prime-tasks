#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import glob
import pytest

def get_expected_flag():
    log_file = "/home/user/legacy_project/logs/build_history.log"
    if not os.path.isfile(log_file):
        return "EXPERIMENT_BETA" # fallback if log is missing

    flag_stats = {}
    with open(log_file, "r") as f:
        lines = f.readlines()[1:] # skip header

    for line in lines:
        parts = line.strip().split(",")
        if len(parts) < 4:
            continue
        flags = parts[2].split()
        exit_code = int(parts[3])

        for flag in flags:
            if flag not in flag_stats:
                flag_stats[flag] = {"fail": 0, "success": 0}
            if exit_code != 0:
                flag_stats[flag]["fail"] += 1
            else:
                flag_stats[flag]["success"] += 1

    # Find the flag that has >0 fails and 0 successes
    for flag, stats in flag_stats.items():
        if stats["fail"] > 0 and stats["success"] == 0:
            return flag

    return "EXPERIMENT_BETA"

def get_expected_conflicting_files():
    src_dir = "/home/user/legacy_project/src"
    if not os.path.isdir(src_dir):
        return "module_14.c,module_73.c" # fallback

    conflicting_files = []
    for filepath in glob.glob(os.path.join(src_dir, "*.c")):
        with open(filepath, "r") as f:
            content = f.read()
            if "int system_state = 0;" in content:
                conflicting_files.append(os.path.basename(filepath))

    if len(conflicting_files) == 2:
        return ",".join(sorted(conflicting_files))
    return "module_14.c,module_73.c"

def test_debug_report_exists():
    report_path = "/home/user/debug_report.txt"
    assert os.path.isfile(report_path), f"The final report {report_path} does not exist."

def test_debug_report_content():
    report_path = "/home/user/debug_report.txt"
    assert os.path.isfile(report_path), f"The final report {report_path} does not exist."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {report_path}, but found {len(lines)}."

    expected_flag = get_expected_flag()
    expected_files = get_expected_conflicting_files()

    assert lines[0] == expected_flag, f"Line 1 should be the problematic flag. Expected '{expected_flag}', got '{lines[0]}'."
    assert lines[1] == expected_files, f"Line 2 should be the conflicting files. Expected '{expected_files}', got '{lines[1]}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
