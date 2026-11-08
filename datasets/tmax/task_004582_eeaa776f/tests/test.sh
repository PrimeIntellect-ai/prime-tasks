#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import time
import filecmp
import subprocess
import shutil
import pytest

def compare_dirs(dir1, dir2):
    dirs_cmp = filecmp.dircmp(dir1, dir2)
    assert not dirs_cmp.left_only, f"Files missing in agent output: {dirs_cmp.left_only}"
    assert not dirs_cmp.right_only, f"Extra files in agent output: {dirs_cmp.right_only}"
    assert not dirs_cmp.diff_files, f"Mismatched files: {dirs_cmp.diff_files}"
    for common_dir in dirs_cmp.common_dirs:
        compare_dirs(os.path.join(dir1, common_dir), os.path.join(dir2, common_dir))

def test_speedup_and_correctness():
    large_wals_dir = "/home/user/large_wals"
    agent_out_dir = "/home/user/final_state"
    legacy_out_dir = "/tmp/legacy_final_state"
    agent_project_dir = "/home/user/fast_tracker"

    assert os.path.exists(agent_project_dir), f"Agent project directory {agent_project_dir} does not exist."
    assert os.path.exists(agent_out_dir), f"Agent output directory {agent_out_dir} does not exist."

    # 1. Run legacy binary and measure time
    if os.path.exists(legacy_out_dir):
        shutil.rmtree(legacy_out_dir)

    start_time = time.time()
    subprocess.run(["/app/legacy_tracker", large_wals_dir, legacy_out_dir], check=True)
    legacy_time = time.time() - start_time

    # 2. Check correctness of agent's pre-existing output
    compare_dirs(legacy_out_dir, agent_out_dir)

    # 3. Compile agent's project to ensure we don't measure compilation time
    subprocess.run(
        ["cargo", "build", "--release"],
        cwd=agent_project_dir,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    # 4. Measure agent's runtime
    agent_temp_out = "/tmp/agent_test_out"
    if os.path.exists(agent_temp_out):
        shutil.rmtree(agent_temp_out)

    start_time = time.time()
    subprocess.run(
        ["cargo", "run", "--release", "--", large_wals_dir, agent_temp_out],
        cwd=agent_project_dir,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    agent_time = time.time() - start_time

    # Verify that the executed Rust program produced the correct output.
    assert os.path.isdir(agent_temp_out), f"Agent did not create output directory {agent_temp_out}."
    compare_dirs(legacy_out_dir, agent_temp_out)

    # 5. Assert speedup
    speedup = legacy_time / agent_time if agent_time > 0 else float('inf')
    assert speedup >= 15.0, f"Speedup is {speedup:.2f}x, which is less than the required 15.0x (Legacy: {legacy_time:.2f}s, Agent: {agent_time:.2f}s)"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
