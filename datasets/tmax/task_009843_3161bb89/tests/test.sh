#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import math
import random
import subprocess


def test_recommend_script_exists_and_executable():
    script_path = "/home/user/analysis/recommend.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_invalid_rows_log():
    log_path = "/home/user/analysis/invalid_rows.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_invalid_rows = {
        "U4,0.5,1.2,3.4,0.1,extra_col",
        "invalid_id,1.0,1.0,1.0,1.0",
        "U6,abc,1.1,3.3,0.2",
        "U9,0.5"
    }

    actual_invalid_rows = set(lines)

    missing = expected_invalid_rows - actual_invalid_rows
    extra = actual_invalid_rows - expected_invalid_rows

    assert not missing, f"Missing expected invalid rows in log: {missing}"
    assert not extra, f"Found unexpected invalid rows in log: {extra}"


def test_recommendations_txt():
    rec_path = "/home/user/analysis/recommendations.txt"
    assert os.path.isfile(rec_path), f"{rec_path} does not exist."

    with open(rec_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 recommendations, found {len(lines)}."

    # Parse the lines
    recommendations = []
    for line in lines:
        parts = line.split(",")
        assert len(parts) == 2, f"Invalid format in recommendations.txt: {line}"
        user_id, distance_str = parts
        try:
            distance = float(distance_str)
        except ValueError:
            assert False, f"Distance is not a valid float: {distance_str}"
        recommendations.append((user_id, distance_str))

    # Expected:
    # U10, 0.100
    # U2, 0.200
    # U5, 0.200

    assert recommendations[0] == ("U10", "0.100"), f"First recommendation should be U10,0.100, got {recommendations[0][0]},{recommendations[0][1]}"

    # U2 and U5 can be in any order since they have the same distance
    second_and_third = {recommendations[1], recommendations[2]}
    expected_second_and_third = {("U2", "0.200"), ("U5", "0.200")}

    assert second_and_third == expected_second_and_third, f"Expected second and third recommendations to be U2 and U5 with distance 0.200, got {second_and_third}"


def _read_nonempty(path):
    assert os.path.isfile(path), f"Expected output file {path} was not created."
    with open(path, "r") as f:
        return [line.rstrip("\n\r") for line in f if line.rstrip("\n\r")]


def _make_case(rng, case_number):
    while True:
        base = rng.randint(20000, 800000) + case_number * 1000000
        valid = []
        for i in range(8):
            values = [f"{rng.uniform(-20, 20):.4f}" for _ in range(4)]
            valid.append((f"U{base + i}", values))

        target_index = case_number % len(valid)
        target_values = [float(x) for x in valid[target_index][1]]
        distances = []
        for i, (user_id, values) in enumerate(valid):
            if i == target_index:
                continue
            distance = math.sqrt(sum(
                (float(values[j]) - target_values[j]) ** 2 for j in range(4)
            ))
            distances.append((distance, user_id))

        # Avoid rounded-distance ties so the required ascending order is unambiguous.
        rounded = [f"{distance:.3f}" for distance, _ in distances]
        if len(set(rounded)) == len(rounded):
            break

    invalid = [
        f"U{base + 100},1.0,2.0,3.0,4.0,extra",
        f"bad{base},1.0,2.0,3.0,4.0",
        f"U{base + 101},not_a_number,2.0,3.0,4.0",
        f"U{base + 102},1.0"
    ]

    rows = [f"{user_id},{','.join(values)}" for user_id, values in valid]
    rows.insert(1, invalid[0])
    rows.insert(4, invalid[1])
    rows.insert(7, invalid[2])
    rows.append(invalid[3])

    distances.sort(key=lambda item: item[0])
    expected = [f"{user_id},{distance:.3f}" for distance, user_id in distances[:3]]
    return rows, invalid, valid[target_index][0], expected, f"U{base + 101}", f"U{base + 999}"


def test_z_script_behavior_on_dynamic_inputs():
    script_path = "/home/user/analysis/recommend.sh"
    data_path = "/home/user/data/users.csv"
    log_path = "/home/user/analysis/invalid_rows.log"
    rec_path = "/home/user/analysis/recommendations.txt"

    with open(data_path, "rb") as f:
        original_data = f.read()
    original_outputs = {}
    for path in (log_path, rec_path):
        original_outputs[path] = open(path, "rb").read() if os.path.exists(path) else None

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    try:
        for case_number in range(2):
            rows, invalid, target, expected, invalid_target, missing_target = _make_case(rng, case_number)
            with open(data_path, "w") as f:
                f.write("user_id,f1,f2,f3,f4\n")
                f.write("\n".join(rows) + "\n")

            result = subprocess.run(
                [script_path, target],
                cwd="/home/user/analysis",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, (
                f"recommend.sh failed for valid dynamic target {target}: "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )

            actual_invalid = _read_nonempty(log_path)
            assert len(actual_invalid) == len(invalid) and set(actual_invalid) == set(invalid), (
                f"Invalid-row log was incorrect for dynamic data: {actual_invalid!r}"
            )
            actual_recommendations = _read_nonempty(rec_path)
            assert actual_recommendations == expected, (
                f"Recommendations for {target} were {actual_recommendations!r}; "
                f"expected {expected!r}"
            )

            invalid_result = subprocess.run(
                [script_path, invalid_target],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert invalid_result.returncode == 1, (
                f"An ID whose row is invalid must exit 1; got {invalid_result.returncode}"
            )
            actual_invalid = _read_nonempty(log_path)
            assert len(actual_invalid) == len(invalid) and set(actual_invalid) == set(invalid), (
                "The dataset must still be validated when the requested target is invalid."
            )

            missing_result = subprocess.run(
                [script_path, missing_target],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert missing_result.returncode == 1, (
                f"A missing target must exit 1; got {missing_result.returncode}"
            )
    finally:
        with open(data_path, "wb") as f:
            f.write(original_data)
        for path, contents in original_outputs.items():
            if contents is None:
                if os.path.exists(path):
                    os.unlink(path)
            else:
                with open(path, "wb") as f:
                    f.write(contents)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
