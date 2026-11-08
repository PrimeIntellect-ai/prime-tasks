#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_organizer_log_exists_and_correct():
    log_path = "/home/user/organizer.log"
    assert os.path.exists(log_path), f"{log_path} does not exist. The tool was not run or failed to produce output."

    expected_lines = [
        "[1000] ACCEPTED fileA.txt 879",
        "[1450] ACCEPTED fileE.txt 883",
        "[1650] ACCEPTED fileG.txt 885",
        "[1850] ACCEPTED fileH.txt 886"
    ]

    with open(log_path, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, f"Log contents are incorrect.\nExpected: {expected_lines}\nGot: {actual_lines}"

def test_no_memory_leak_fixed():
    # We can also check if the memory leak was fixed by inspecting main.rs
    main_path = "/home/user/file_manager/src/main.rs"
    assert os.path.exists(main_path), "main.rs is missing"

    with open(main_path, "r") as f:
        content = f.read()

    assert "CString::from_raw" in content or "into_raw" not in content or "free" in content, \
        "The memory leak in process_filename does not appear to be fixed."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
