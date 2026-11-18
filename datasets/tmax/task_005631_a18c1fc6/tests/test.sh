#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import subprocess
import tempfile

SOURCE = "/home/user/prepare_cv.c"
EXECUTABLE = "/home/user/prepare_cv"
RESULTS = "/home/user/cv_results.txt"
EXPECTED_LINES = [
    "Fold 1: train_threshold = 60.00, val_accuracy = 1.00",
    "Fold 2: train_threshold = 47.50, val_accuracy = 0.50",
    "Fold 3: train_threshold = 27.50, val_accuracy = 1.00",
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.digest()


def run_checked(argv, **kwargs):
    return subprocess.run(argv, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=10, **kwargs)


def test_executable_exists_and_matches_source():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist. Did you compile the C code?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "prepare_cv is not a compiled ELF executable."

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "prepare_cv")
        run_checked(["gcc", "-O2", SOURCE, "-o", rebuilt])
        assert sha256(rebuilt) == sha256(EXECUTABLE), \
            "The executable does not match gcc -O2 compilation of prepare_cv.c."


def test_results_file_contents_and_executable_output():
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} does not exist. Did you run the executable and redirect output?"
    with open(RESULTS, "rb") as f:
        saved = f.read()

    executed = run_checked([EXECUTABLE]).stdout
    assert executed == saved, "cv_results.txt is not the actual standard output of the compiled executable."

    content = saved.decode("utf-8").strip().split("\n")
    assert len(content) == 3, f"Expected 3 lines in {RESULTS}, but found {len(content)}."
    for i, expected in enumerate(EXPECTED_LINES):
        assert content[i].strip() == expected, \
            f"Line {i+1} in {RESULTS} is incorrect. Expected: '{expected}', Got: '{content[i].strip()}'"


def replace_dataset(source, xs, ys):
    x_init = "{" + ", ".join(f"{x}.0" for x in xs) + "}"
    y_init = "{" + ", ".join(str(y) for y in ys) + "}"

    source, nx = re.subn(
        r"(\b(?:const\s+)?double\s+X\s*\[[^\]]*\]\s*=\s*)\{[^{}]*\}",
        lambda m: m.group(1) + x_init, source, count=1)
    source, ny = re.subn(
        r"(\b(?:const\s+)?int\s+y\s*\[[^\]]*\]\s*=\s*)\{[^{}]*\}",
        lambda m: m.group(1) + y_init, source, count=1)
    assert nx == 1 and ny == 1, "Could not locate the program's X and y dataset initializers for behavioral testing."
    return source


def expected_output(xs, ys):
    lines = []
    fold_size = 2
    for fold in range(3):
        start = fold * fold_size
        end = start + fold_size
        training = [xs[i] for i in range(6) if not (start <= i < end)]
        threshold = sum(training) / len(training)
        correct = 0
        for i in range(start, end):
            pred = 1 if xs[i] > threshold else 0
            correct += int(pred == ys[i])
        lines.append(
            f"Fold {fold + 1}: train_threshold = {threshold:.2f}, "
            f"val_accuracy = {correct / fold_size:.2f}"
        )
    return "\n".join(lines) + "\n"


def test_training_threshold_is_computed_from_each_training_fold():
    with open(SOURCE, "r", encoding="utf-8") as f:
        original = f.read()

    rng = secrets.SystemRandom()
    for case in range(4):
        while True:
            xs = rng.sample(range(1, 301), 6)
            global_mean = sum(xs) / 6
            thresholds = [
                sum(xs[i] for i in range(6) if not (2 * fold <= i < 2 * fold + 2)) / 4
                for fold in range(3)
            ]
            if len(set(thresholds)) == 3 and all(t != global_mean for t in thresholds):
                break
        ys = [rng.randrange(2) for _ in range(6)]
        tested_source = replace_dataset(original, xs, ys)

        with tempfile.TemporaryDirectory(dir="/home/user") as td:
            source_path = os.path.join(td, "prepare_cv_test.c")
            binary_path = os.path.join(td, "prepare_cv_test")
            with open(source_path, "w", encoding="utf-8") as f:
                f.write(tested_source)
            run_checked(["gcc", "-O2", source_path, "-o", binary_path])
            actual = run_checked([binary_path]).stdout.decode("utf-8")

        expected = expected_output(xs, ys)
        assert actual == expected, \
            f"Program failed randomized per-fold training-only mean test {case + 1}.\nExpected:\n{expected}Got:\n{actual}"


def test_c_code_fixed():
    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."
    with open(SOURCE, "r", encoding="utf-8") as f:
        content = f.read()
    assert "double train_threshold = global_threshold;" not in content, \
        "The file still assigns the global threshold directly to train_threshold. Data leakage is not fixed."


if __name__ == "__main__":
    test_executable_exists_and_matches_source()
    test_results_file_contents_and_executable_output()
    test_training_threshold_is_computed_from_each_training_fold()
    test_c_code_fixed()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
