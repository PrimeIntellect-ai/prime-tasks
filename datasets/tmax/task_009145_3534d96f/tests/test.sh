#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

DATA_PATH = "/home/user/data_pipeline/vectors.csv"
SCRIPT_PATH = "/home/user/data_pipeline/recommend.sh"


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_top2_recommendations_file():
    """Verify that the output file for target_1 exists and has the correct recommendations."""
    output_path = "/home/user/data_pipeline/top2_recommendations.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    lines = read_nonempty_lines(output_path)
    assert len(lines) == 2, f"Expected exactly 2 lines in {output_path}, found {len(lines)}."
    assert lines[0] == "item_E", f"Expected first recommendation to be 'item_E', got '{lines[0]}'."
    assert lines[1] == "item_C", f"Expected second recommendation to be 'item_C', got '{lines[1]}'."


def test_recommend_script_functionality():
    """Verify that the recommend.sh script computes distances and sorts correctly for a different target."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    test_output_path = "/tmp/test_out.txt"
    if os.path.exists(test_output_path):
        os.unlink(test_output_path)

    result = subprocess.run(
        [SCRIPT_PATH, "item_A", test_output_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    assert os.path.isfile(test_output_path), "Script did not create the output file."

    lines = read_nonempty_lines(test_output_path)
    assert len(lines) == 2, f"Expected exactly 2 lines in output, found {len(lines)}."
    assert lines[0] == "item_E", f"Expected first recommendation for item_A to be 'item_E', got '{lines[0]}'."
    assert lines[1] == "target_1", f"Expected second recommendation for item_A to be 'target_1', got '{lines[1]}'."


def manhattan(a, b):
    return sum(abs(x - y) for x, y in zip(a, b))


def make_random_dataset():
    """Create unpredictable data with unique pairwise Manhattan distances."""
    for _ in range(1000):
        names = ["id_" + secrets.token_hex(5) for _ in range(9)]
        points = {
            name: tuple(secrets.randbelow(10000) for _ in range(3))
            for name in names
        }

        pair_distances = []
        for i, left in enumerate(names):
            for right in names[i + 1:]:
                pair_distances.append(manhattan(points[left], points[right]))

        if 0 in pair_distances or len(pair_distances) != len(set(pair_distances)):
            continue

        # Ensure this dataset also exposes lexicographical rather than numeric sorting.
        has_lexical_trap = False
        for target in names:
            values = [manhattan(points[target], points[other]) for other in names if other != target]
            if sorted(values)[:2] != sorted(values, key=lambda value: str(value))[:2]:
                has_lexical_trap = True
                break
        if has_lexical_trap:
            return names, points

    raise AssertionError("Could not generate a suitable randomized test dataset")


def test_recommend_script_on_unpredictable_targets():
    """Exercise every target on verifier-generated data to prevent fixed-target hardcoding."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    names, points = make_random_dataset()
    csv_data = "ID,V1,V2,V3\n" + "".join(
        f"{name},{points[name][0]},{points[name][1]},{points[name][2]}\n"
        for name in names
    )

    try:
        for index, target in enumerate(names):
            # Reset the input before each invocation so each target sees identical data.
            with open(DATA_PATH, "w") as f:
                f.write(csv_data)

            expected = sorted(
                (manhattan(points[target], points[other]), other)
                for other in names
                if other != target
            )[:2]
            expected_ids = [item_id for _, item_id in expected]

            output_path = f"/tmp/random_recommendations_{index}.txt"
            if os.path.exists(output_path):
                os.unlink(output_path)

            result = subprocess.run(
                [SCRIPT_PATH, target, output_path],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"Script failed for generated target {target}: {result.stderr}"
            )
            assert os.path.isfile(output_path), (
                f"Script did not create an output file for generated target {target}."
            )

            actual = read_nonempty_lines(output_path)
            assert len(actual) == 2, (
                f"Expected exactly 2 recommendations for generated target {target}, "
                f"found {len(actual)}."
            )
            assert actual == expected_ids, (
                f"Wrong recommendations for generated target {target}: "
                f"expected {expected_ids}, got {actual}."
            )
            assert target not in actual, f"Target {target} was not excluded from its recommendations."
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
