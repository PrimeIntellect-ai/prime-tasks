#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import random
import shutil
import stat
import subprocess
from collections import Counter


def oracle_score_func(seq1, seq2):
    total = 0
    for i in range(len(seq1) - 2):
        kmer = seq1[i:i+3]
        if kmer in seq2:
            total += 3
    total -= abs(len(seq1) - len(seq2))
    return total


def expected_matrix(csv_path, ref_seq):
    data = {}
    read_ids = set()
    with open(csv_path, newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            sid = row['sample_id']
            rid = row['read_id']
            score = oracle_score_func(ref_seq, row['sequence'])
            data.setdefault(sid, {})[rid] = score
            read_ids.add(rid)

    sorted_rids = sorted(read_ids)
    rows = [['sample_id'] + sorted_rids]
    for sid in sorted(data):
        rows.append([sid] + [str(data[sid].get(rid, 0)) for rid in sorted_rids])
    return rows


def read_matrix(path):
    with open(path, newline='') as f:
        return [row for row in csv.reader(f) if row]


def run_pipeline():
    proc = subprocess.run(
        ['bash', '/home/user/process_data.sh'],
        cwd='/home/user', capture_output=True, text=True, timeout=60
    )
    assert proc.returncode == 0, (
        f"process_data.sh failed.\nStdout: {proc.stdout}\nStderr: {proc.stderr}"
    )


def test_fuzz_equivalence_score_py():
    agent_script = '/home/user/score.py'
    oracle_bin = '/app/bin/oracle_score'

    assert os.path.exists(agent_script), f'Agent script missing at {agent_script}'

    random.seed(42)
    chars = ['A', 'T', 'G', 'C']

    for _ in range(100):
        len1 = random.randint(10, 50)
        len2 = random.randint(10, 50)
        seq1 = ''.join(random.choices(chars, k=len1))
        seq2 = ''.join(random.choices(chars, k=len2))

        oracle_proc = subprocess.run(
            [oracle_bin, seq1, seq2], capture_output=True, text=True
        )
        assert oracle_proc.returncode == 0, 'Oracle failed to execute'
        oracle_out = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            ['python3', agent_script, seq1, seq2],
            capture_output=True, text=True
        )
        assert agent_proc.returncode == 0, (
            f'Agent script failed on inputs {seq1}, {seq2}. '
            f'Stderr: {agent_proc.stderr}'
        )
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f'Mismatch on inputs:\nSeq1: {seq1}\nSeq2: {seq2}\n'
            f'Oracle: {oracle_out}\nAgent: {agent_out}'
        )


def test_pipeline_exists_runs_and_creates_original_matrix():
    pipeline = '/home/user/process_data.sh'
    features_csv = '/home/user/features.csv'
    patient_reads_csv = '/app/patient_reads.csv'

    assert os.path.exists(pipeline), f'Pipeline missing at {pipeline}'
    assert stat.S_ISREG(os.stat(pipeline).st_mode), f'{pipeline} is not a regular file'
    assert os.path.exists(patient_reads_csv), f'Input file missing at {patient_reads_csv}'

    if os.path.exists(features_csv):
        os.remove(features_csv)
    run_pipeline()

    assert os.path.exists(features_csv), f'Output file missing at {features_csv}'
    expected_rows = expected_matrix(patient_reads_csv, 'ATGCCGTAACTGG')
    actual_rows = read_matrix(features_csv)
    assert actual_rows == expected_rows, (
        f'Contents of {features_csv} do not match expected output.\n'
        f'Expected: {expected_rows}\nActual: {actual_rows}'
    )


def test_pipeline_uses_score_py_and_handles_changed_input():
    pipeline = '/home/user/process_data.sh'
    score_path = '/home/user/score.py'
    input_path = '/app/patient_reads.csv'
    output_path = '/home/user/features.csv'
    score_backup = '/tmp/agent_score_original.py'
    input_backup = '/tmp/patient_reads_original.csv'
    call_log = '/tmp/score_calls.jsonl'
    ref_seq = 'ATGCCGTAACTGG'

    shutil.copy2(score_path, score_backup)
    shutil.copy2(input_path, input_backup)

    fixture_rows = [
        ['sample_id', 'read_id', 'sequence'],
        ['S20', 'R9', 'CCCCCCCC'],
        ['S03', 'R2', 'ATGCCGTAACTGG'],
        ['S20', 'R2', 'TGCATGCATGCA'],
        ['S11', 'R5', 'AAAATTTTGGGG'],
        ['S03', 'R9', 'GCTAGCTAGCTA'],
    ]

    wrapper = '''#!/usr/bin/env python3
import json
import subprocess
import sys
with open("/tmp/score_calls.jsonl", "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
p = subprocess.run(["python3", "/tmp/agent_score_original.py"] + sys.argv[1:], capture_output=True, text=True)
sys.stdout.write(p.stdout)
sys.stderr.write(p.stderr)
raise SystemExit(p.returncode)
'''

    try:
        with open(input_path, 'w', newline='') as f:
            csv.writer(f).writerows(fixture_rows)
        with open(score_path, 'w') as f:
            f.write(wrapper)
        os.chmod(score_path, 0o755)
        if os.path.exists(call_log):
            os.remove(call_log)
        if os.path.exists(output_path):
            os.remove(output_path)

        run_pipeline()

        assert os.path.exists(output_path), 'Pipeline did not recreate features.csv'
        expected_rows = expected_matrix(input_path, ref_seq)
        actual_rows = read_matrix(output_path)
        assert actual_rows == expected_rows, (
            f'Pipeline failed on changed observational data.\n'
            f'Expected: {expected_rows}\nActual: {actual_rows}'
        )

        assert os.path.exists(call_log), 'process_data.sh did not invoke /home/user/score.py'
        with open(call_log) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        expected_calls = Counter(
            (ref_seq, row[2]) for row in fixture_rows[1:]
        )
        actual_calls = Counter(
            tuple(call) for call in calls if len(call) == 2
        )
        assert actual_calls == expected_calls, (
            'process_data.sh must call score.py once for each input row with the '
            f'reference as Sequence 1 and the read as Sequence 2. '
            f'Expected calls: {expected_calls}; actual calls: {actual_calls}'
        )
    finally:
        shutil.copy2(score_backup, score_path)
        shutil.copy2(input_backup, input_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
