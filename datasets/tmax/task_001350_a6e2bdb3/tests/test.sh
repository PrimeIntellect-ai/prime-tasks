#!/bin/bash
mkdir -p /logs/verifier
ok=1

# Restore the canonical inputs, then require the submitted artifact to execute.
mkdir -p /home/user/data
cat << 'EOF' > /home/user/data/measurements.csv
id,spring_id,displacement
1,A,0.1
2,A,0.2
3,A,0.3
4,B,0.15
5,B,0.25
6,B,0.35
7,C,0.05
8,C,0.10
9,C,0.15
EOF
cat << 'EOF' > /home/user/data/forces.csv
id,force
1,2.1
2,4.0
3,5.9
4,12.0
5,20.0
6,28.0
7,2.5
8,5.0
9,7.5
EOF
rm -f /home/user/results.csv /home/user/stiff_springs.txt

if ! timeout 10 /home/user/analyze.sh; then
    ok=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_analyze_sh_exists_and_executable():
    script_path = "/home/user/analyze.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

def test_results_csv_content():
    results_path = "/home/user/results.csv"
    assert os.path.isfile(results_path), f"The results file {results_path} does not exist."

    expected_content = (
        "spring_id,k,num_samples\n"
        "A,19.86,3\n"
        "B,80.00,3\n"
        "C,50.00,3"
    )

    with open(results_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"The contents of {results_path} do not match the expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )

def test_stiff_springs_txt_content():
    stiff_path = "/home/user/stiff_springs.txt"
    assert os.path.isfile(stiff_path), f"The file {stiff_path} does not exist."

    expected_content = "B"

    with open(stiff_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"The contents of {stiff_path} do not match the expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )
TEST_EOF

if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    ok=0
fi

# Exercise schema rejection, joining, regression, sorting, rounding, sample counts,
# and the strict k > 50 threshold on fresh inputs with unpredictable spring IDs.
if [ "$ok" -eq 1 ]; then
python3 << 'PY_EOF' || ok=0
import os
import random
import subprocess
import uuid
from collections import defaultdict

script = "/home/user/analyze.sh"
measurements_path = "/home/user/data/measurements.csv"
forces_path = "/home/user/data/forces.csv"
results_path = "/home/user/results.csv"
stiff_path = "/home/user/stiff_springs.txt"

assert os.path.isfile(script)
assert os.access(script, os.X_OK)

def write(path, text):
    with open(path, "w", newline="") as f:
        f.write(text)

def run_script():
    return subprocess.run([script], timeout=10, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True)

# Exact schema validation must reject either incorrect header with status 1.
valid_measurements = "id,spring_id,displacement\n1,T,1\n"
valid_forces = "id,force\n1,2\n"
write(measurements_path, "id,spring,displacement\n1,T,1\n")
write(forces_path, valid_forces)
r = run_script()
assert r.returncode == 1, f"bad measurements header returned {r.returncode}, not 1"

write(measurements_path, valid_measurements)
write(forces_path, "id,forces\n1,2\n")
r = run_script()
assert r.returncode == 1, f"bad forces header returned {r.returncode}, not 1"

# Generate shuffled, non-fixed IDs and spring names. The data include unmatched
# rows and non-intercept-linear noise, so the expected result requires an ID join
# and the specified sum(x*y)/sum(x*x) regression.
rng = random.SystemRandom()
names = ["S_" + uuid.uuid4().hex[:10] for _ in range(3)]
targets = [20.0, 50.0, 80.0]
ids = rng.sample(range(1000, 9000), 11)
measurements = []
forces = []
idx = 0
for name, target in zip(names, targets):
    xs = [1.0, 2.0, 4.0]
    deltas = [0.0, 0.0, 0.0] if target == 50.0 else [1.0, -3.0, 2.0]
    for x, delta in zip(xs, deltas):
        row_id = ids[idx]
        idx += 1
        measurements.append((row_id, name, x))
        forces.append((row_id, target * x + delta))

# One measurement and one force deliberately have no joining counterpart.
measurements.append((ids[9], "UNMATCHED_" + uuid.uuid4().hex[:8], 3.0))
forces.append((ids[10], 9999.0))
rng.shuffle(measurements)
rng.shuffle(forces)

m_text = "id,spring_id,displacement\n" + "".join(
    f"{row_id},{spring},{x:g}\n" for row_id, spring, x in measurements
)
f_text = "id,force\n" + "".join(
    f"{row_id},{force:g}\n" for row_id, force in forces
)
write(measurements_path, m_text)
write(forces_path, f_text)
for path in (results_path, stiff_path):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass

r = run_script()
assert r.returncode == 0, f"valid-input execution failed: {r.stderr}"

force_by_id = {row_id: force for row_id, force in forces}
groups = defaultdict(list)
for row_id, spring, x in measurements:
    if row_id in force_by_id:
        groups[spring].append((x, force_by_id[row_id]))

expected_rows = []
expected_stiff = []
for spring in sorted(groups):
    samples = groups[spring]
    k = sum(x * y for x, y in samples) / sum(x * x for x, _ in samples)
    expected_rows.append(f"{spring},{k:.2f},{len(samples)}")
    if k > 50:
        expected_stiff.append(spring)

expected_results = "spring_id,k,num_samples\n" + "\n".join(expected_rows)
expected_stiff_text = "\n".join(expected_stiff)
assert os.path.isfile(results_path), "results.csv was not produced"
assert os.path.isfile(stiff_path), "stiff_springs.txt was not produced"
with open(results_path) as f:
    actual_results = f.read().strip()
with open(stiff_path) as f:
    actual_stiff = f.read().strip()
assert actual_results == expected_results, (
    f"dynamic results mismatch\nExpected:\n{expected_results}\nActual:\n{actual_results}"
)
assert actual_stiff == expected_stiff_text, (
    f"dynamic stiff list mismatch\nExpected:\n{expected_stiff_text}\nActual:\n{actual_stiff}"
)
PY_EOF
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
