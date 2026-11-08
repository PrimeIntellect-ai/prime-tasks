#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess

DATASET = "/home/user/dataset.csv"
SOURCE = "/home/user/cv_tune.c"
RESULT = "/home/user/result.txt"
BINARY = "/tmp/cv_tune_submission"


def derive_best(lines):
    y = []
    texts = []
    for i, line in enumerate(lines):
        parts = line.strip().split(',', 1)
        assert len(parts) == 2, f"Line {i} is malformed."
        y.append(int(parts[0]))
        texts.append(parts[1].split(' '))

    best_acc = -1
    best_M = None
    best_T = None
    for M in [2, 3, 4, 5]:
        for T in [1, 2, 3]:
            fold_accuracies = []
            for fold in range(5):
                correct = 0
                for i in range(fold * 20, (fold + 1) * 20):
                    count = sum(1 for token in texts[i] if len(token) > M)
                    pred = 1 if count >= T else 0
                    if pred == y[i]:
                        correct += 1
                fold_accuracies.append(correct / 20)
            acc = sum(fold_accuracies) / 5
            if acc > best_acc:
                best_acc = acc
                best_M = M
                best_T = T
    return f"{best_M},{best_T}", best_acc


def run_submission():
    if os.path.exists(RESULT):
        os.unlink(RESULT)
    proc = subprocess.run([BINARY], cwd="/home/user", capture_output=True,
                          text=True, timeout=10)
    assert proc.returncode == 0, (
        f"Compiled program exited with status {proc.returncode}. "
        f"stderr: {proc.stderr}"
    )
    assert os.path.exists(RESULT), f"Result file {RESULT} was not created by the program."
    with open(RESULT, 'r') as f:
        return f.read().strip()


def make_case(target_M, target_T):
    pairs = [(m, t) for m in [2, 3, 4, 5] for t in [1, 2, 3]]
    target = (target_M, target_T)

    for _ in range(200):
        rows = []
        distinguished = {pair: False for pair in pairs if pair != target}
        for _ in range(100):
            lengths = [1 + secrets.randbelow(8) for _ in range(1 + secrets.randbelow(7))]
            target_count = sum(length > target_M for length in lengths)
            label = 1 if target_count >= target_T else 0
            for pair in distinguished:
                m, t = pair
                prediction = 1 if sum(length > m for length in lengths) >= t else 0
                if prediction != label:
                    distinguished[pair] = True
            words = [chr(97 + secrets.randbelow(26)) * length for length in lengths]
            rows.append(f"{label},{' '.join(words)}\n")
        if all(distinguished.values()):
            expected, _ = derive_best(rows)
            if expected == f"{target_M},{target_T}":
                return rows
    raise AssertionError(f"Could not generate behavioral case for {target_M},{target_T}")


def test_hyperparameter_tuning_result():
    assert os.path.exists(DATASET), f"Dataset file {DATASET} is missing."
    assert os.path.lexists(SOURCE), f"C source file {SOURCE} is missing."
    source_stat = os.lstat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode) and not os.path.islink(SOURCE), \
        f"{SOURCE} must be a regular C source file."

    compile_proc = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", BINARY],
        capture_output=True, text=True, timeout=20
    )
    assert compile_proc.returncode == 0, (
        f"Failed to compile {SOURCE}. stderr: {compile_proc.stderr}"
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), \
        "Compilation did not produce an executable."

    with open(DATASET, 'rb') as f:
        original_dataset = f.read()

    try:
        # Execute the submitted C program on the supplied dataset before retaining
        # the original verifier's dataset and exact-result assertions.
        run_submission()

        with open(DATASET, 'r') as f:
            lines = f.readlines()

        assert len(lines) == 100, f"Expected 100 lines in {DATASET}, found {len(lines)}."

        y = []
        texts = []
        for i, line in enumerate(lines):
            parts = line.strip().split(',', 1)
            assert len(parts) == 2, f"Line {i} is malformed."
            y.append(int(parts[0]))
            texts.append(parts[1].split(' '))

        best_acc = -1
        best_M = None
        best_T = None
        for M in [2, 3, 4, 5]:
            for T in [1, 2, 3]:
                correct = 0
                for label, tokens in zip(y, texts):
                    count = sum(1 for token in tokens if len(token) > M)
                    pred = 1 if count >= T else 0
                    if pred == label:
                        correct += 1
                acc = correct / len(y)
                if acc > best_acc:
                    best_acc = acc
                    best_M = M
                    best_T = T

        expected_result = f"{best_M},{best_T}"
        assert os.path.exists(RESULT), f"Result file {RESULT} was not created."
        with open(RESULT, 'r') as f:
            actual_result = f.read().strip()
        assert actual_result == expected_result, (
            f"Incorrect result in {RESULT}. Expected '{expected_result}' "
            f"(M={best_M}, T={best_T} with accuracy {best_acc}), "
            f"but got '{actual_result}'."
        )

        # Exercise the compiled artifact on unpredictable valid datasets whose
        # correct answers are independently derived by the verifier.
        for target in [(2, 1), (3, 2), (4, 1), (5, 3)]:
            case_lines = make_case(*target)
            with open(DATASET, 'w') as f:
                f.writelines(case_lines)
            expected, _ = derive_best(case_lines)
            actual = run_submission()
            assert actual == expected, (
                f"Program produced '{actual}' on a behavioral test; expected '{expected}'."
            )
    finally:
        with open(DATASET, 'wb') as f:
            f.write(original_dataset)
        if os.path.isfile(BINARY) and os.access(BINARY, os.X_OK):
            try:
                run_submission()
            except Exception:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
