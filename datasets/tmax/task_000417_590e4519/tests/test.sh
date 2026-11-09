#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import pathlib
import subprocess
import tempfile


def expected_lines(dataset_path):
    valid_rows = []
    with open(dataset_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                feature_x = float(row['feature_x'])
                target = int(row['target'])
            except ValueError:
                continue

            if feature_x == -999:
                continue

            feat_bin = 1 if feature_x > 50 else 0
            valid_rows.append({'feat_bin': feat_bin, 'target': target})

    total_valid = len(valid_rows)
    assert total_valid > 0, "No valid rows found in dataset."

    target_1_count = sum(1 for r in valid_rows if r['target'] == 1)
    target_0_count = sum(1 for r in valid_rows if r['target'] == 0)

    prior_t1 = target_1_count / total_valid
    likelihood_f1_t1 = (
        sum(1 for r in valid_rows if r['target'] == 1 and r['feat_bin'] == 1) / target_1_count
        if target_1_count > 0 else 0.0
    )
    likelihood_f1_t0 = (
        sum(1 for r in valid_rows if r['target'] == 0 and r['feat_bin'] == 1) / target_0_count
        if target_0_count > 0 else 0.0
    )

    return [
        f"Prior_T1: {prior_t1:.4f}",
        f"Likelihood_F1_given_T1: {likelihood_f1_t1:.4f}",
        f"Likelihood_F1_given_T0: {likelihood_f1_t0:.4f}",
    ]


def read_result(results_path):
    with open(results_path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def test_bayes_results_correctness():
    dataset_path = "/home/user/dataset.csv"
    results_path = "/home/user/bayes_results.txt"

    assert os.path.exists(dataset_path), f"Dataset file missing at {dataset_path}"
    assert os.path.exists(results_path), f"Results file missing at {results_path}"

    expected = expected_lines(dataset_path)
    actual_lines = read_result(results_path)

    assert len(actual_lines) == 3, f"Expected 3 lines in {results_path}, found {len(actual_lines)}"
    assert actual_lines[0] == expected[0], f"Line 1 mismatch. Expected '{expected[0]}', got '{actual_lines[0]}'"
    assert actual_lines[1] == expected[1], f"Line 2 mismatch. Expected '{expected[1]}', got '{actual_lines[1]}'"
    assert actual_lines[2] == expected[2], f"Line 3 mismatch. Expected '{expected[2]}', got '{actual_lines[2]}'"


def test_c_program_compiles_and_generates_results():
    dataset_path = pathlib.Path('/home/user/dataset.csv')
    results_path = pathlib.Path('/home/user/bayes_results.txt')
    sources = sorted(p for p in pathlib.Path('/home/user').rglob('*.c') if p.is_file())
    assert sources, "No C source program was found under /home/user"

    original_dataset = dataset_path.read_bytes()
    original_results = results_path.read_bytes() if results_path.exists() else None

    datasets = [
        """id,feature_x,target
1,-999,1
2,50,1
3,51,1
4,90,0
5,10,0
6,-999,0
""",
        """id,feature_x,target
11,5,1
12,60,1
13,80,1
14,51,0
15,50,0
16,20,0
17,-999,0
""",
    ]

    groups = [(p,) for p in sources]
    for parent in sorted({p.parent for p in sources}, key=str):
        group = tuple(p for p in sources if p.parent == parent)
        if len(group) > 1 and group not in groups:
            groups.append(group)
    all_sources = tuple(sources)
    if len(all_sources) > 1 and all_sources not in groups:
        groups.append(all_sources)

    failures = []
    passed = False
    try:
        with tempfile.TemporaryDirectory() as td:
            for index, group in enumerate(groups):
                executable = pathlib.Path(td) / f'bayes_program_{index}'
                compile_result = subprocess.run(
                    ['gcc', '-std=c11', '-O2', *map(str, group), '-lm', '-o', str(executable)],
                    cwd='/home/user', text=True, stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, timeout=30
                )
                if compile_result.returncode != 0:
                    failures.append(f"{', '.join(map(str, group))}: compilation failed")
                    continue
                if not os.access(executable, os.X_OK) or executable.read_bytes()[:4] != b'\x7fELF':
                    failures.append(f"{', '.join(map(str, group))}: compiler did not produce an executable ELF")
                    continue

                candidate_ok = True
                for data in datasets:
                    dataset_path.write_text(data)
                    if results_path.exists():
                        results_path.unlink()
                    try:
                        run_result = subprocess.run(
                            [str(executable)], cwd='/home/user', text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
                        )
                    except subprocess.TimeoutExpired:
                        failures.append(f"{', '.join(map(str, group))}: execution timed out")
                        candidate_ok = False
                        break
                    if run_result.returncode != 0:
                        failures.append(f"{', '.join(map(str, group))}: execution failed")
                        candidate_ok = False
                        break
                    if not results_path.is_file():
                        failures.append(f"{', '.join(map(str, group))}: did not generate bayes_results.txt")
                        candidate_ok = False
                        break
                    actual = read_result(results_path)
                    expected = expected_lines(dataset_path)
                    if len(actual) != 3 or actual != expected:
                        failures.append(f"{', '.join(map(str, group))}: incorrect output for a verification dataset")
                        candidate_ok = False
                        break

                if candidate_ok:
                    passed = True
                    break
    finally:
        dataset_path.write_bytes(original_dataset)
        if original_results is None:
            if results_path.exists():
                results_path.unlink()
        else:
            results_path.write_bytes(original_results)

    assert passed, "No submitted C program compiled and correctly processed verification datasets. " + "; ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
