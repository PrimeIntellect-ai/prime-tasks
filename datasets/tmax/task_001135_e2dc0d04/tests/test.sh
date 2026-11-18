#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import re
import subprocess

HOME = "/home/user"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, timeout=20, **kwargs)


def reference_accuracy(train_rows, test_rows):
    parsed_train = []
    for row in train_rows:
        feat, label = row.strip().split(",")
        if feat == "NaN":
            continue
        parsed_train.append((float(feat), int(label)))

    class0 = [x for x, y in parsed_train if y == 0]
    class1 = [x for x, y in parsed_train if y == 1]
    mean0 = sum(class0) / len(class0) if class0 else 0.0
    mean1 = sum(class1) / len(class1) if class1 else 0.0
    threshold = (mean0 + mean1) / 2.0
    direction = 1 if mean1 > mean0 else -1

    correct = total = 0
    for row in test_rows:
        feat, label = row.strip().split(",")
        if feat == "NaN":
            continue
        value = float(feat)
        label = int(label)
        pred = 0
        if direction == 1 and value >= threshold:
            pred = 1
        if direction == -1 and value <= threshold:
            pred = 1
        correct += pred == label
        total += 1
    return correct / total if total else 0.0


def exercise_classifier(executable):
    cases = [
        (
            ["0,0", "2,0", "8,1", "10,1", "NaN,0", "NaN,1"],
            ["0,0", "10,1", "1,1", "9,1", "NaN,1"],
        ),
        (
            ["10,0", "12,0", "0,1", "2,1", "NaN,0"],
            ["11,0", "1,1", "8,1", "4,0", "NaN,0"],
        ),
        (
            ["1,0", "3,0", "7,1", "9,1"],
            ["1,1", "2,0", "3,1", "7,0", "8,1", "9,0"],
        ),
    ]
    for index, (train, test) in enumerate(cases):
        train_path = f"/tmp/classifier_train_{index}.csv"
        test_path = f"/tmp/classifier_test_{index}.csv"
        with open(train_path, "w") as f:
            f.write("\n".join(train) + "\n")
        with open(test_path, "w") as f:
            f.write("\n".join(test) + "\n")

        result = run([executable, train_path, test_path])
        fields = result.stdout.strip().split()
        assert len(fields) == 1, f"{executable} must print one accuracy value, got {result.stdout!r}"
        actual = float(fields[0])
        expected = reference_accuracy(train, test)
        assert math.isclose(actual, expected, abs_tol=1e-6), (
            f"{executable} returned {actual} for case {index}, expected {expected}"
        )


def expected_cv(rows):
    folds = [rows[i:i + 20] for i in range(0, 100, 20)]
    scores = []
    for i in range(5):
        train = [row for j, fold in enumerate(folds) if j != i for row in fold]
        scores.append(reference_accuracy(train, folds[i]))
    return sum(scores) / 5.0


def execute_cv(rows, expected):
    dataset = os.path.join(HOME, "dataset.csv")
    with open(dataset, "w") as f:
        f.write("feature,label\n")
        f.write("\n".join(rows) + "\n")

    final_path = os.path.join(HOME, "final_accuracy.txt")
    if os.path.exists(final_path):
        os.remove(final_path)
    for path in glob.glob(os.path.join(HOME, "fold_*")):
        if os.path.isfile(path):
            os.remove(path)

    run(["bash", os.path.join(HOME, "run_cv.sh")], cwd=HOME)
    assert os.path.isfile(final_path), "run_cv.sh did not create final_accuracy.txt"
    with open(final_path) as f:
        content = f.read().strip()
    assert re.fullmatch(r"[0-9]+\.[0-9]{2}", content), (
        f"final_accuracy.txt must contain one value formatted to two decimal places, got {content!r}"
    )
    assert content == f"{expected:.2f}", (
        f"run_cv.sh produced {content}; expected the five-fold average {expected:.2f}"
    )


def test_complete_submission():
    final_path = os.path.join(HOME, "final_accuracy.txt")
    assert os.path.exists(final_path), f"{final_path} is missing. Did you run the cross-validation script?"
    with open(final_path) as f:
        content = f.read().strip()
    assert content == "1.00", f"Expected final accuracy to be exactly '1.00', but got '{content}'"

    source = os.path.join(HOME, "classifier.c")
    assert os.path.exists(source), f"{source} is missing."
    with open(source) as f:
        source_content = f.read()
    assert "NaN" in source_content, "classifier.c does not appear to contain logic checking for the string 'NaN'."

    classifier = os.path.join(HOME, "classifier")
    assert os.path.exists(classifier), f"Compiled executable {classifier} is missing."
    assert os.access(classifier, os.X_OK), f"{classifier} is not executable. Did you compile it correctly?"
    assert os.path.isfile(classifier), f"{classifier} is not a regular file."
    with open(classifier, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{classifier} is not a compiled ELF executable."

    script = os.path.join(HOME, "run_cv.sh")
    assert os.path.exists(script), f"{script} is missing."
    assert os.path.isfile(script), f"{script} is not a regular file."

    compiled_from_source = "/tmp/classifier_from_submitted_source"
    run(["gcc", "-O2", source, "-o", compiled_from_source])
    exercise_classifier(classifier)
    exercise_classifier(compiled_from_source)

    dataset = os.path.join(HOME, "dataset.csv")
    with open(dataset, "rb") as f:
        original_dataset = f.read()
    try:
        original_rows = original_dataset.decode().splitlines()[1:]
        assert len(original_rows) == 100
        execute_cv(original_rows, expected_cv(original_rows))

        synthetic = []
        flips_per_side = [0, 1, 2, 3, 4]
        for fold, flips in enumerate(flips_per_side):
            for j in range(10):
                label = 1 if j < flips else 0
                synthetic.append(f"{fold * 0.1 + j},{label}")
            for j in range(10):
                label = 0 if j < flips else 1
                synthetic.append(f"{100 + fold * 0.1 + j},{label}")
        synthetic[6] = "NaN,1"
        synthetic[27] = "NaN,0"
        synthetic[68] = "NaN,1"
        assert len(synthetic) == 100
        execute_cv(synthetic, expected_cv(synthetic))
    finally:
        with open(dataset, "wb") as f:
            f.write(original_dataset)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
