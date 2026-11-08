#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import csv
import secrets
import subprocess

SUMMARY_PATH = '/home/user/summary.json'


def test_summary_json_exists():
    """Test that the summary.json file was created."""
    assert os.path.isfile(SUMMARY_PATH), "The file /home/user/summary.json does not exist."


def test_summary_json_content():
    """Test that summary.json contains the correct structure and accurately computed counts."""
    with open(SUMMARY_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{SUMMARY_PATH} is not a valid JSON file."

    assert "distribution" in data, "The key 'distribution' is missing from the JSON."
    dist = data["distribution"]

    assert "exact" in dist, "The key 'exact' is missing from 'distribution'."
    assert "under" in dist, "The key 'under' is missing from 'distribution'."
    assert "over" in dist, "The key 'over' is missing from 'distribution'."

    # Recompute the expected distribution based on the actual files
    reference_data = {}
    ref_path = '/home/user/reference.csv'
    assert os.path.isfile(ref_path), f"Reference file {ref_path} is missing."

    with open(ref_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            reference_data[row['run_id']] = float(row['expected_sum'])

    expected_exact = 0
    expected_under = 0
    expected_over = 0

    for i in range(1, 21):
        run_id = f'run_{i}'
        output_file = f'/home/user/sim_runs/{run_id}/output.dat'

        assert os.path.isfile(output_file), f"Simulation output file {output_file} is missing."

        with open(output_file, 'r') as f:
            numbers = [float(line.strip()) for line in f if line.strip()]

        computed_sum = math.fsum(numbers)
        expected_sum = reference_data[run_id]

        diff = computed_sum - expected_sum
        if diff == 0.0:
            expected_exact += 1
        elif diff < 0.0:
            expected_under += 1
        else:
            expected_over += 1

    assert dist["exact"] == expected_exact, f"Expected 'exact' count to be {expected_exact}, but got {dist['exact']}."
    assert dist["under"] == expected_under, f"Expected 'under' count to be {expected_under}, but got {dist['under']}."
    assert dist["over"] == expected_over, f"Expected 'over' count to be {expected_over}, but got {dist['over']}."


def _find_pipeline_scripts():
    candidates = []
    excluded = {os.path.realpath('/tmp/test_final_state.py')}
    roots = ['/home/user', '/tmp']

    for root in roots:
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {'sim_runs', '__pycache__', '.pytest_cache'}]
            for name in files:
                path = os.path.join(directory, name)
                if os.path.realpath(path) in excluded or path == SUMMARY_PATH:
                    continue
                try:
                    with open(path, 'rb') as f:
                        first_line = f.readline(256).decode('utf-8', errors='ignore').lower()
                except OSError:
                    continue

                lower = name.lower()
                if lower.endswith(('.sh', '.bash')) or ('#!' in first_line and ('sh' in first_line or 'bash' in first_line)):
                    candidates.append((path, ['bash', path]))
                elif lower.endswith('.py') or ('#!' in first_line and 'python' in first_line):
                    candidates.append((path, ['python3', path]))
                elif lower.endswith('.awk') or ('#!' in first_line and 'awk' in first_line):
                    candidates.append((path, ['awk', '-f', path]))

    return candidates


def test_pipeline_reexecutes_on_unseen_inputs():
    """Require an actual pipeline and exercise it on unpredictable adversarial data."""
    candidates = _find_pipeline_scripts()
    assert candidates, "No Bash, Python, or Awk computation pipeline was found."

    rng = secrets.SystemRandom()
    categories = ['exact', 'under', 'over'] + [rng.choice(['exact', 'under', 'over']) for _ in range(17)]
    rng.shuffle(categories)

    files = {}
    reference_rows = []
    expected = {'exact': 0, 'under': 0, 'over': 0}

    for i, category in enumerate(categories, 1):
        # An odd addend is lost by ordinary sequential summation in this order,
        # while exact floating-point summation recovers it.
        small = float(rng.randrange(1, 100, 2))
        numbers = [1e16, small, -1e16]
        computed = math.fsum(numbers)

        if category == 'exact':
            reference = computed
        elif category == 'under':
            reference = computed + 0.5
        else:
            reference = computed - 0.5
        expected[category] += 1

        output_path = f'/home/user/sim_runs/run_{i}/output.dat'
        files[output_path] = ''.join(f'{value!r}\n' for value in numbers)
        reference_rows.append((f'run_{i}', reference))

    reference_text = 'run_id,expected_sum\n' + ''.join(
        f'{run_id},{value!r}\n' for run_id, value in reference_rows
    )

    errors = []
    for path, command in candidates:
        # Restore the unseen challenge before every candidate so one failed helper
        # cannot corrupt the inputs used by the actual wrapper script.
        for output_path, content in files.items():
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            with open(output_path, 'w') as f:
                f.write(content)
        with open('/home/user/reference.csv', 'w') as f:
            f.write(reference_text)
        try:
            os.remove(SUMMARY_PATH)
        except FileNotFoundError:
            pass

        try:
            result = subprocess.run(
                command,
                cwd=os.path.dirname(path) or '/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            errors.append(f'{path}: {exc}')
            continue

        if result.returncode != 0 or not os.path.isfile(SUMMARY_PATH):
            errors.append(f'{path}: exited {result.returncode} without producing summary.json')
            continue

        try:
            with open(SUMMARY_PATH, 'r') as f:
                data = json.load(f)
            dist = data['distribution']
        except (OSError, ValueError, KeyError, TypeError) as exc:
            errors.append(f'{path}: invalid summary.json ({exc})')
            continue

        if all(dist.get(key) == expected[key] for key in ('exact', 'under', 'over')):
            return
        errors.append(f'{path}: produced {dist!r}, expected {expected!r}')

    assert False, "No submitted pipeline correctly processed unseen inputs. " + '; '.join(errors[-5:])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
