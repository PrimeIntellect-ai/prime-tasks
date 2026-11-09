#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest


def test_bad_commit_hash_correct():
    bad_commit_file = "/home/user/bad_commit.txt"
    assert os.path.isfile(bad_commit_file), f"File {bad_commit_file} does not exist."

    with open(bad_commit_file, "r") as f:
        student_hash = f.read().strip()

    repo_dir = "/home/user/sorter_repo"
    try:
        result = subprocess.run(
            ["git", "-C", repo_dir, "log", "--format=%H", "--grep=Commit 137"],
            capture_output=True, text=True, check=True
        )
        expected_hash = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to query git repository for the bad commit: {e.stderr}")

    assert expected_hash, "Could not find the expected bad commit in the repository."
    assert len(student_hash) == 40, "The submitted commit hash is not a full 40-character hash."
    assert student_hash == expected_hash, (
        f"Incorrect commit hash in {bad_commit_file}. "
        f"Expected {expected_hash}, got {student_hash}"
    )


def test_fixed_sort_c_compiles_and_sorts():
    fixed_sort = "/home/user/fixed_sort.c"
    assert os.path.isfile(fixed_sort), f"File {fixed_sort} does not exist."

    repo_dir = "/home/user/sorter_repo"
    main_c = os.path.join(repo_dir, "main.c")
    assert os.path.isfile(main_c), f"Original main.c is missing from {repo_dir}."

    with tempfile.TemporaryDirectory() as tmpdir:
        out_bin = os.path.join(tmpdir, "sorter")
        compile_res = subprocess.run(
            ["gcc", "-O0", "-g", main_c, fixed_sort, "-o", out_bin],
            capture_output=True, text=True
        )
        assert compile_res.returncode == 0, (
            f"Compilation of fixed_sort.c failed:\n{compile_res.stderr}"
        )

        # Preserve the original regression test and add varied edge cases.
        cases = [
            [10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
            [1],
            [2, 1],
            [1, 2],
            [0, -1, 1, -1, 0, 1],
            [7] * 19,
            list(range(-40, 41)),
            list(range(70, -71, -1)),
            [2147483647, 0, -2147483648, 42, -42],
        ]

        # Verification-time random inputs prevent a solution tailored to a fixed sequence.
        rng = secrets.SystemRandom()
        for _ in range(30):
            length = rng.randint(2, 180)
            cases.append([rng.randint(-1000000, 1000000) for _ in range(length)])

        for values in cases:
            args = [str(value) for value in values]
            try:
                run_res = subprocess.run(
                    [out_bin] + args,
                    capture_output=True,
                    text=True,
                    timeout=2
                )
            except subprocess.TimeoutExpired:
                pytest.fail(
                    f"The compiled program timed out for an input of length {len(values)} "
                    "(likely infinite recursion/hang is still present)."
                )

            assert run_res.returncode == 0, (
                f"Program crashed or returned non-zero for input {values!r}:\n"
                f"{run_res.stderr}"
            )
            output = run_res.stdout.strip()
            expected_output = " ".join(str(value) for value in sorted(values))
            assert output == expected_output, (
                f"Sorting output is incorrect for input {values!r}. "
                f"Expected '{expected_output}', but got '{output}'."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
