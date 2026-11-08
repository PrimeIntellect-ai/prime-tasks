#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pandas as pd
import numpy as np

def test_audit_scores_mae():
    """Test that the agent's audit scores have an MAE <= 0.05 compared to truth."""
    agent_csv = '/home/user/audit_scores.csv'
    truth_csv = '/app/truth_scores.csv'

    assert os.path.exists(agent_csv), f"Agent output {agent_csv} does not exist."
    assert os.path.exists(truth_csv), f"Truth file {truth_csv} does not exist."

    try:
        agent_df = pd.read_csv(agent_csv, header=None, names=['filepath', 'score'])
    except Exception as e:
        assert False, f"Failed to parse {agent_csv}: {e}"

    try:
        truth_df = pd.read_csv(truth_csv, header=None, names=['filepath', 'truth_score'])
    except Exception as e:
        assert False, f"Failed to parse {truth_csv}: {e}"

    merged = pd.merge(truth_df, agent_df, on='filepath', how='left').fillna(0)
    mae = np.mean(np.abs(merged['truth_score'] - merged['score']))

    assert mae <= 0.05, f"MAE {mae} exceeds threshold 0.05"

def test_malware_elf_extracted():
    """Test that the malware.elf file was carved and is a valid ELF binary."""
    elf_path = '/home/user/malware.elf'
    assert os.path.exists(elf_path), f"Extracted ELF {elf_path} does not exist."

    with open(elf_path, 'rb') as f:
        magic = f.read(4)
    assert magic == b'\x7fELF', f"File {elf_path} does not have a valid ELF header."

def test_audit_script_exists():
    """Test that the audit_system.sh script exists."""
    script_path = '/home/user/audit_system.sh'
    assert os.path.exists(script_path), f"Audit script {script_path} does not exist."

def test_red_frames_if_extracted():
    """The bonus output, when present, must reflect that the supplied video has no red frames."""
    frames_path = '/home/user/red_frames.txt'
    if not os.path.exists(frames_path):
        return

    with open(frames_path, 'r') as f:
        content = f.read().splitlines()

    parsed_frames = []
    for line in content:
        try:
            parsed_frames.append(float(line.strip()))
        except ValueError:
            pass

    assert not parsed_frames, f"Unexpected red-frame timestamps found in {frames_path}: {parsed_frames}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
