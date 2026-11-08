#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile


def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def commit_accepts_negatives(repo_dir, commit):
    shown = run(["git", "show", f"{commit}:src/math_utils.sh"], cwd=repo_dir)
    assert shown.returncode == 0, f"Could not inspect src/math_utils.sh at {commit}."

    with tempfile.TemporaryDirectory() as tmpdir:
        script = os.path.join(tmpdir, "math_utils.sh")
        input_path = os.path.join(tmpdir, "input.txt")
        output_path = os.path.join(tmpdir, "output.txt")
        with open(script, "w") as f:
            f.write(shown.stdout)
        with open(input_path, "w") as f:
            f.write("-12.4\n8.0\n")

        result = run(["bash", script, input_path, output_path])
        if result.returncode != 0 or not os.path.isfile(output_path):
            return False
        with open(output_path) as f:
            return f.read().splitlines() == ["-12.4", "8.0"]


def derive_bad_commit(repo_dir):
    base = run(["git", "rev-parse", "v1.0^{commit}"], cwd=repo_dir)
    assert base.returncode == 0, "The v1.0 tag is missing."
    base_commit = base.stdout.strip()

    history = run(["git", "rev-list", "--reverse", "v1.0..HEAD"], cwd=repo_dir)
    assert history.returncode == 0, "Could not inspect repository history."
    commits = [base_commit] + history.stdout.splitlines()

    previous_was_good = commit_accepts_negatives(repo_dir, commits[0])
    assert previous_was_good, "The commit tagged v1.0 is not behaviorally good."
    for commit in commits[1:]:
        current_is_good = commit_accepts_negatives(repo_dir, commit)
        if previous_was_good and not current_is_good:
            return commit
        previous_was_good = current_is_good
    raise AssertionError("No good-to-bad filtering transition was found in repository history.")


def test_solution_file_exists():
    assert os.path.isfile("/home/user/solution.txt"), "/home/user/solution.txt does not exist."


def test_solution_content():
    solution_path = "/home/user/solution.txt"
    repo_dir = "/home/user/legacy_pipeline"
    expected_bad_commit = derive_bad_commit(repo_dir)

    with open(solution_path, "r") as f:
        content = f.read().strip().splitlines()

    solution_dict = {}
    for line in content:
        if "=" in line:
            key, val = line.split("=", 1)
            solution_dict[key.strip()] = val.strip()

    assert "BAD_COMMIT" in solution_dict, "BAD_COMMIT not found in solution.txt."
    assert solution_dict["BAD_COMMIT"] == expected_bad_commit, f"BAD_COMMIT is incorrect. Expected {expected_bad_commit}, got {solution_dict['BAD_COMMIT']}."

    assert "BUG_FILE" in solution_dict, "BUG_FILE not found in solution.txt."
    assert solution_dict["BUG_FILE"] == "src/math_utils.sh", f"BUG_FILE is incorrect. Expected src/math_utils.sh, got {solution_dict['BUG_FILE']}."

    assert "DROPPED_TX_ID" in solution_dict, "DROPPED_TX_ID not found in solution.txt."
    assert solution_dict["DROPPED_TX_ID"] == "TX_002", f"DROPPED_TX_ID is incorrect. Expected TX_002, got {solution_dict['DROPPED_TX_ID']}."


def test_pipeline_output():
    repo_dir = "/home/user/legacy_pipeline"
    script_path = os.path.join(repo_dir, "run_pipeline.sh")

    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    result = run([script_path], cwd=repo_dir)
    assert result.returncode == 0, f"run_pipeline.sh failed with return code {result.returncode}."

    stats_path = os.path.join(repo_dir, "output/stats.txt")
    assert os.path.isfile(stats_path), f"Output file {stats_path} was not generated."

    with open(stats_path, "r") as f:
        stats_content = f.read().strip()

    assert "Average: 2.86" in stats_content, f"Statistics output is incorrect. Expected 'Average: 2.86', got '{stats_content}'."


def test_filtering_logic_on_independent_input():
    repo_dir = "/home/user/legacy_pipeline"
    filter_script = os.path.join(repo_dir, "src", "math_utils.sh")
    assert os.path.isfile(filter_script), f"Filtering script {filter_script} is missing."

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, "values.txt")
        output_path = os.path.join(tmpdir, "filtered.txt")
        with open(input_path, "w") as f:
            f.write("-17.75\n0\n42.5\n-0.125\ninvalid\n+3\n")

        result = run(["bash", filter_script, input_path, output_path], cwd=repo_dir)
        assert result.returncode == 0, f"math_utils.sh failed with return code {result.returncode}."
        assert os.path.isfile(output_path), "math_utils.sh did not create its output file."
        with open(output_path) as f:
            actual = f.read().splitlines()

        assert actual == ["-17.75", "0", "42.5", "-0.125"], f"Filtering logic is incorrect on independent input: {actual}."


def test_git_commit_message():
    repo_dir = "/home/user/legacy_pipeline"

    branch_result = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo_dir)
    assert branch_result.stdout.strip() == "main", f"Expected to be on 'main' branch, but currently on '{branch_result.stdout.strip()}'."

    msg_result = run(["git", "log", "-1", "--pretty=%B"], cwd=repo_dir)
    commit_msg = msg_result.stdout.strip()
    assert commit_msg == "Fix statistical anomaly", f"Latest commit message is incorrect. Expected 'Fix statistical anomaly', got '{commit_msg}'."


def test_git_status_clean():
    repo_dir = "/home/user/legacy_pipeline"
    status_result = run(["git", "status", "--porcelain"], cwd=repo_dir)
    assert status_result.stdout.strip() == "", "Git working directory is not clean. Ensure all changes are committed."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
