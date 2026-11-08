#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from decimal import Decimal


def test_pipeline_exists_and_executable():
    """Test that pipeline.sh exists and is executable."""
    file_path = "/home/user/pipeline.sh"
    assert os.path.isfile(file_path), f"{file_path} is missing."
    assert os.access(file_path, os.X_OK), f"{file_path} is not executable."


def test_run_pipeline():
    """Test that pipeline.sh runs successfully."""
    file_path = "/home/user/pipeline.sh"
    result = subprocess.run([file_path], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Running {file_path} failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )


def test_cleaned_predictions_output():
    """Test that cleaned_predictions.csv contains the correct predictions."""
    file_path = "/home/user/cleaned_predictions.csv"
    assert os.path.isfile(file_path), f"{file_path} was not created."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 6, (
        f"Expected 6 lines in {file_path} (header + 5 rows), got {len(lines)}."
    )
    assert lines[0] == "user_id,predicted_LTV", (
        f"Incorrect header in {file_path}: {lines[0]}"
    )

    expected_predictions = {
        "U001": "523.80",
        "U002": "629.15",
        "U003": "31.25",
        "U004": ["1228.82", "1228.83"],
        "U005": "834.20",
    }

    seen = []
    for line in lines[1:]:
        parts = line.split(",")
        assert len(parts) == 2, f"Malformed line in {file_path}: {line}"
        user_id, predicted_LTV = parts
        assert user_id in expected_predictions, (
            f"Unexpected user_id {user_id} in {file_path}"
        )
        seen.append(user_id)
        expected = expected_predictions[user_id]
        if isinstance(expected, list):
            assert predicted_LTV in expected, (
                f"Incorrect prediction for {user_id}. Expected one of {expected}, "
                f"got {predicted_LTV}"
            )
        else:
            assert predicted_LTV == expected, (
                f"Incorrect prediction for {user_id}. Expected {expected}, "
                f"got {predicted_LTV}"
            )

    assert len(seen) == len(set(seen)), "Duplicate user_id rows were emitted."
    assert set(seen) == set(expected_predictions), (
        "Each expected user_id must appear exactly once."
    )


def test_nearest_to_U001_output():
    """Test that nearest_to_U001.txt contains the correct user_id."""
    file_path = "/home/user/nearest_to_U001.txt"
    assert os.path.isfile(file_path), f"{file_path} was not created."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "U004", (
        f"Incorrect content in {file_path}. Expected 'U004', got '{content}'"
    )


def test_pipeline_processes_runtime_input():
    """Replace the input at verification time and derive all expected results."""
    rng = secrets.SystemRandom()
    raw_path = "/home/user/raw_data.csv"
    prediction_path = "/home/user/cleaned_predictions.csv"
    nearest_path = "/home/user/nearest_to_U001.txt"

    with open(raw_path, "rb") as f:
        original_raw = f.read()

    # Scores use even hundredths, avoiding ambiguous half-cent rounding while
    # still varying every verification run.
    while True:
        ids = ["U001"] + ["R" + secrets.token_hex(4).upper() for _ in range(7)]
        if len(set(ids)) != len(ids):
            continue

        rows = []
        for i, user_id in enumerate(ids):
            age = "" if i in (1, 6) else str(rng.randrange(18, 76))
            income = str(-rng.randrange(1, 90000)) if i in (2, 5) else str(rng.randrange(1000, 180001))
            score1 = Decimal(rng.randrange(0, 51) * 2) / Decimal(100)
            score2 = Decimal(rng.randrange(0, 51) * 2) / Decimal(100)
            rows.append((user_id, age, income, score1, score2))

        base1, base2 = rows[0][3], rows[0][4]
        distances = []
        for row in rows[1:]:
            d = (row[3] - base1) ** 2 + (row[4] - base2) ** 2
            distances.append((d, row[0]))
        minimum = min(d for d, _ in distances)
        if sum(1 for d, _ in distances if d == minimum) == 1:
            expected_nearest = next(uid for d, uid in distances if d == minimum)
            break

    expected_predictions = {}
    csv_lines = ["user_id,age,income,score1,score2"]
    for user_id, age_text, income_text, score1, score2 in rows:
        csv_lines.append(
            f"{user_id},{age_text},{income_text},{score1:.2f},{score2:.2f}"
        )
        age = Decimal(35 if age_text == "" else age_text)
        income = max(Decimal(0), Decimal(income_text))
        value = (
            Decimal("0.5") * age
            + Decimal("0.01") * income
            + Decimal("2.0") * score1
            - Decimal("1.5") * score2
            + Decimal(10)
        )
        expected_predictions[user_id] = f"{value:.2f}"

    try:
        with open(raw_path, "w", newline="") as f:
            f.write("\n".join(csv_lines) + "\n")

        for path in (prediction_path, nearest_path):
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(
            ["/home/user/pipeline.sh"], capture_output=True, text=True
        )
        assert result.returncode == 0, (
            f"Pipeline failed on replacement input with return code "
            f"{result.returncode}. Stderr: {result.stderr}"
        )

        assert os.path.isfile(prediction_path), (
            "cleaned_predictions.csv was not recreated for replacement input."
        )
        with open(prediction_path, "r") as f:
            output_lines = [line.strip() for line in f if line.strip()]

        assert output_lines, "Prediction output is empty."
        assert output_lines[0] == "user_id,predicted_LTV", "Incorrect prediction header."
        assert len(output_lines) == len(rows) + 1, (
            "Prediction output must contain exactly one row per runtime input row."
        )

        actual = {}
        for line in output_lines[1:]:
            parts = line.split(",")
            assert len(parts) == 2, f"Malformed prediction row: {line}"
            user_id, value = parts
            assert user_id in expected_predictions, f"Unexpected user_id: {user_id}"
            assert user_id not in actual, f"Duplicate prediction for {user_id}"
            assert re.fullmatch(r"-?\d+\.\d{2}", value), (
                f"Prediction is not formatted to exactly two decimal places: {value}"
            )
            actual[user_id] = value

        assert set(actual) == set(expected_predictions), (
            "Runtime input users were omitted or replaced in prediction output."
        )
        assert actual == expected_predictions, (
            f"Predictions do not match the runtime input. Expected "
            f"{expected_predictions}, got {actual}"
        )

        assert os.path.isfile(nearest_path), (
            "nearest_to_U001.txt was not recreated for replacement input."
        )
        with open(nearest_path, "r") as f:
            nearest_content = f.read().strip()
        assert nearest_content == expected_nearest, (
            f"Incorrect nearest user for runtime input: expected "
            f"{expected_nearest}, got {nearest_content!r}"
        )
    finally:
        with open(raw_path, "wb") as f:
            f.write(original_raw)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
