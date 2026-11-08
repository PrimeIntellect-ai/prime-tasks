#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import subprocess
import tempfile
import uuid

SCRIPT_PATH = "/home/user/find_stable.sh"
FASTA_PATH = "/home/user/proteins.fasta"
SOLVER_PATH = "/home/user/bin/simulate_ode.sh"
RESULTS_DIR = "/home/user/results"
RESULTS_PATH = "/home/user/results/stability.csv"
DTS = ["0.1", "0.05", "0.02", "0.01", "0.005", "0.002"]


def run_pipeline():
    return subprocess.run(
        [SCRIPT_PATH], capture_output=True, text=True, timeout=30
    )


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_find_stable_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_find_stable_script_execution_and_output():
    # Preserve the original fixed-fixture assertions.
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    result = run_pipeline()
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"
    assert os.path.isfile(RESULTS_PATH), f"Expected output file {RESULTS_PATH} was not created."

    expected_lines = [
        "protein_A,0.02",
        "protein_B,0.01",
        "protein_C,0.1",
        "protein_D,0.005"
    ]
    actual_lines = read_nonempty_lines(RESULTS_PATH)

    assert len(actual_lines) == len(expected_lines), \
        f"Expected {len(expected_lines)} lines in CSV, found {len(actual_lines)}."
    for expected in expected_lines:
        assert expected in actual_lines, \
            f"Expected row '{expected}' not found in {RESULTS_PATH}."


def test_pipeline_parses_dynamic_fasta_and_invokes_solver():
    rng = random.SystemRandom()
    token = uuid.uuid4().hex[:10]

    # Give every sequence a unique length and a different first stable dt.
    lengths = rng.sample(range(23, 280), len(DTS))
    thresholds = list(range(len(DTS)))
    rng.shuffle(thresholds)
    records = []
    for i, (length, threshold) in enumerate(zip(lengths, thresholds)):
        records.append((f"dynamic_{token}_{i}", length, threshold))

    trace_path = f"/tmp/solver_trace_{token}"
    backup_dir = tempfile.mkdtemp(prefix="pipeline-verifier-")
    fasta_backup = os.path.join(backup_dir, "proteins.fasta")
    solver_backup = os.path.join(backup_dir, "simulate_ode.sh")
    shutil.copy2(FASTA_PATH, fasta_backup)
    shutil.copy2(SOLVER_PATH, solver_backup)

    try:
        # Use multiline records with varying line widths so answers cannot come
        # from the original fixture or from counting one line per sequence.
        with open(FASTA_PATH, "w") as f:
            for i, (seq_id, length, _) in enumerate(records):
                f.write(f">{seq_id}\n")
                sequence = ("ACDEFGHIKLMNPQRSTVWY" * ((length // 20) + 1))[:length]
                width = 7 + (i * 5)
                for pos in range(0, length, width):
                    f.write(sequence[pos:pos + width] + "\n")

        threshold_cases = "\n".join(
            f"  {length}) threshold={threshold} ;;"
            for _, length, threshold in records
        )
        solver = f'''#!/bin/bash
L="$1"
dt="$2"
printf '%s,%s\\n' "$L" "$dt" >> {trace_path!r}
case "$L" in
{threshold_cases}
  *) echo "DIVERGED"; exit 1 ;;
esac
case "$dt" in
  0.1) idx=0 ;;
  0.05) idx=1 ;;
  0.02) idx=2 ;;
  0.01) idx=3 ;;
  0.005) idx=4 ;;
  0.002) idx=5 ;;
  *) echo "DIVERGED"; exit 1 ;;
esac
if [ "$idx" -ge "$threshold" ]; then
  echo "STABLE"
  exit 0
fi
echo "DIVERGED"
exit 1
'''
        with open(SOLVER_PATH, "w") as f:
            f.write(solver)
        os.chmod(SOLVER_PATH, 0o755)

        # The script is required to create the output directory itself.
        if os.path.isdir(RESULTS_DIR):
            shutil.rmtree(RESULTS_DIR)
        elif os.path.exists(RESULTS_DIR):
            os.remove(RESULTS_DIR)
        if os.path.exists(trace_path):
            os.remove(trace_path)

        result = run_pipeline()
        assert result.returncode == 0, \
            f"Script failed on dynamic FASTA. stdout: {result.stdout} stderr: {result.stderr}"
        assert os.path.isfile(RESULTS_PATH), \
            f"Expected output file {RESULTS_PATH} was not created."

        expected = {
            seq_id: DTS[threshold]
            for seq_id, _, threshold in records
        }
        lines = read_nonempty_lines(RESULTS_PATH)
        assert len(lines) == len(expected), \
            f"Expected {len(expected)} dynamic CSV rows, found {len(lines)}: {lines}"

        actual = {}
        for line in lines:
            parts = line.split(",")
            assert len(parts) == 2, f"Malformed CSV row: {line!r}"
            seq_id, dt = parts
            assert seq_id not in actual, f"Duplicate CSV row for {seq_id!r}"
            actual[seq_id] = dt
        assert actual == expected, f"Dynamic results were {actual}, expected {expected}"

        assert os.path.isfile(trace_path), "The pipeline did not invoke simulate_ode.sh."
        calls = []
        for line in read_nonempty_lines(trace_path):
            length_text, dt = line.split(",", 1)
            calls.append((int(length_text), dt))

        # For each sequence, the solver must have been exercised in descending
        # order through the first stable value. Continuing through all values is
        # also allowed.
        for _, length, threshold in records:
            observed = [dt for called_length, dt in calls if called_length == length]
            required_prefix = DTS[:threshold + 1]
            cursor = 0
            for dt in observed:
                if cursor < len(required_prefix) and dt == required_prefix[cursor]:
                    cursor += 1
            assert cursor == len(required_prefix), \
                f"Solver was not tested correctly for parsed length {length}; calls were {observed}"
    finally:
        shutil.copy2(fasta_backup, FASTA_PATH)
        shutil.copy2(solver_backup, SOLVER_PATH)
        os.chmod(SOLVER_PATH, os.stat(solver_backup).st_mode & 0o777)
        if os.path.exists(trace_path):
            os.remove(trace_path)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
