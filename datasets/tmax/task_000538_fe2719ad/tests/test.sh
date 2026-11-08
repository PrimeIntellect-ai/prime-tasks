#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import subprocess
import math
import random


def compute_pearson(x, y):
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n

    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den_x = sum((xi - mean_x) ** 2 for xi in x)
    den_y = sum((yi - mean_y) ** 2 for yi in y)

    den = math.sqrt(den_x * den_y)
    if den == 0:
        return 0.0
    return num / den


def get_expected_top_match(target_user_id=1):
    ratings_file = "/home/user/ratings.csv"
    assert os.path.exists(ratings_file), f"Missing {ratings_file}"

    users = {}
    with open(ratings_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            user_id = int(parts[0])
            ratings = [float(p) for p in parts[1:]]
            users[user_id] = ratings

    assert target_user_id in users, f"Target user {target_user_id} not found in dataset."

    target_ratings = users[target_user_id]

    best_match = None
    best_score = -float('inf')

    for uid, ratings in users.items():
        if uid == target_user_id:
            continue
        score = compute_pearson(target_ratings, ratings)

        if score > best_score:
            best_score = score
            best_match = uid
        elif score == best_score:
            if best_match is None or uid < best_match:
                best_match = uid

    return best_match, best_score


def test_files_exist():
    """Verify all required files exist."""
    required_files = [
        "/home/user/recommender.c",
        "/home/user/Makefile",
        "/home/user/run_pipeline.sh"
    ]
    for f in required_files:
        assert os.path.isfile(f), f"Required file {f} is missing."


def test_makefile_contents():
    """Verify Makefile contains math library linking."""
    with open("/home/user/Makefile", "r") as f:
        content = f.read()
    assert "-lm" in content, "Makefile does not appear to link the math library (-lm)."


def test_script_executable():
    """Verify run_pipeline.sh is executable."""
    script_path = "/home/user/run_pipeline.sh"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."


def test_pipeline_execution():
    """Run the pipeline script and verify it succeeds."""
    script_path = "/home/user/run_pipeline.sh"

    # Remove top_match.txt if it exists to ensure the script generates it
    output_file = "/home/user/top_match.txt"
    if os.path.exists(output_file):
        os.remove(output_file)

    result = subprocess.run(["bash", script_path], cwd="/home/user", capture_output=True, text=True)
    assert result.returncode == 0, f"Pipeline script failed with return code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert os.path.isfile(output_file), f"Pipeline script did not generate {output_file}."


def test_top_match_output():
    """Verify the contents of top_match.txt against the expected ground truth."""
    output_file = "/home/user/top_match.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    with open(output_file, "r") as f:
        content = f.read().strip()

    expected_match, expected_score = get_expected_top_match(1)
    expected_str = f"Match: {expected_match}, Score: {expected_score:.4f}"

    assert content == expected_str, f"Output content mismatch.\nExpected: '{expected_str}'\nFound: '{content}'"


def write_dataset(rows):
    with open("/home/user/ratings.csv", "w") as f:
        for uid, ratings in rows:
            f.write(str(uid) + "," + ",".join(f"{value:.6f}" for value in ratings) + "\n")


def run_and_check_all_users():
    with open("/home/user/ratings.csv", "r") as f:
        user_ids = [int(line.split(",", 1)[0]) for line in f if line.strip()]

    for target_id in user_ids:
        output_file = "/home/user/top_match.txt"
        if os.path.exists(output_file):
            os.remove(output_file)

        result = subprocess.run(
            ["/home/user/recommender", str(target_id)],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"recommender failed for target {target_id}.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )
        assert os.path.isfile(output_file), f"recommender did not create {output_file} for target {target_id}."

        with open(output_file, "r") as f:
            actual = f.read().strip()
        expected_match, expected_score = get_expected_top_match(target_id)
        expected = f"Match: {expected_match}, Score: {expected_score:.4f}"
        assert actual == expected, (
            f"Incorrect direct recommender result for target {target_id}.\n"
            f"Expected: '{expected}'\nFound: '{actual}'"
        )


def make_random_dataset():
    rng = random.SystemRandom()
    while True:
        ids = rng.sample(range(100, 1000), 5)
        rows = [
            (uid, [round(rng.uniform(1.0, 5.0), 6) for _ in range(5)])
            for uid in ids
        ]

        # Avoid numerically marginal best-match decisions while retaining
        # verification-time-generated inputs unknown to the submission.
        well_separated = True
        for target_uid, target_ratings in rows:
            scores = sorted(
                (compute_pearson(target_ratings, ratings), uid)
                for uid, ratings in rows
                if uid != target_uid
            )
            if scores[-1][0] - scores[-2][0] <= 0.02:
                well_separated = False
                break
        if well_separated:
            rng.shuffle(rows)
            return rows


def test_recommender_directly_on_all_and_generated_inputs():
    """Build and invoke the C artifact directly for varied targets and datasets."""
    clean = subprocess.run(["make", "clean"], cwd="/home/user", capture_output=True, text=True)
    assert clean.returncode == 0, f"make clean failed.\nStdout: {clean.stdout}\nStderr: {clean.stderr}"
    build = subprocess.run(["make"], cwd="/home/user", capture_output=True, text=True)
    assert build.returncode == 0, f"make failed.\nStdout: {build.stdout}\nStderr: {build.stderr}"

    executable = "/home/user/recommender"
    assert os.path.isfile(executable), "Makefile did not create /home/user/recommender."
    assert os.access(executable, os.X_OK), "/home/user/recommender is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "recommender is not a compiled ELF executable."

    ratings_path = "/home/user/ratings.csv"
    output_path = "/home/user/top_match.txt"
    with open(ratings_path, "rb") as f:
        original_ratings = f.read()
    output_existed = os.path.exists(output_path)
    original_output = None
    if output_existed:
        with open(output_path, "rb") as f:
            original_output = f.read()

    try:
        # Exercise every target in the provided dataset, not only user 1.
        run_and_check_all_users()

        # Exercise parsing and Pearson computation on verification-time-generated data.
        write_dataset(make_random_dataset())
        run_and_check_all_users()

        # Exercise exact ties, lowest-ID tie breaking, and zero denominators.
        tie_rows = [
            (17, [1.0, 2.0, 3.0, 4.0, 5.0]),
            (91, [1.0, 2.0, 3.0, 4.0, 5.0]),
            (8, [1.0, 2.0, 3.0, 4.0, 5.0]),
            (42, [3.0, 3.0, 3.0, 3.0, 3.0]),
            (63, [5.0, 4.0, 3.0, 2.0, 1.0]),
        ]
        write_dataset(tie_rows)
        run_and_check_all_users()
    finally:
        with open(ratings_path, "wb") as f:
            f.write(original_ratings)
        if output_existed:
            with open(output_path, "wb") as f:
                f.write(original_output)
        elif os.path.exists(output_path):
            os.remove(output_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
