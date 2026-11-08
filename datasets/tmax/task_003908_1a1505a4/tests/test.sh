#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

PROJECT = "/home/user/stat_sim"
SOURCE = os.path.join(PROJECT, "src/main.rs")
RESULT = "/home/user/result.txt"


def compute_expected_steps(start):
    x = start
    steps = 0
    while x < 100:
        diff = 100 - x
        step = diff // 2
        if step == 0:
            step = 1
        x += step
        steps += 1
    return steps


def compute_expected_total_steps():
    return sum(compute_expected_steps(start) for start in range(-100, 51))


def test_main_rs_exists_and_failsafe_remains():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist. Did you delete the source file?"

    with open(SOURCE, "r", encoding="utf-8") as f:
        source = f.read()

    # The requested 10,000-step fallback must still be present and tied to steps.
    source_without_comments = re.sub(r"//.*?$|/\*.*?\*/", "", source, flags=re.MULTILINE | re.DOTALL)
    assert re.search(r"10_?000", source_without_comments), "The 10_000-step failsafe limit was removed"
    assert re.search(
        r"(?:steps\s*<\s*10_?000|steps\s*>=\s*10_?000|10_?000\s*>\s*steps|10_?000\s*<=\s*steps)",
        source_without_comments,
    ), "The 10_000 limit is not used as a fallback based on the step count"


def test_simulation_behavior_for_every_start_value():
    # Test the submitted simulate implementation directly, so a hard-coded total
    # in result.txt or main() cannot substitute for repairing the simulation.
    with tempfile.TemporaryDirectory(prefix="stat_sim_verify_") as tempdir:
        copied_project = os.path.join(tempdir, "stat_sim")
        shutil.copytree(
            PROJECT,
            copied_project,
            ignore=shutil.ignore_patterns("target", ".git"),
        )
        copied_source = os.path.join(copied_project, "src/main.rs")
        with open(copied_source, "a", encoding="utf-8") as f:
            f.write(r'''

#[cfg(test)]
mod __verifier_behavior_tests {
    use super::simulate;

    fn expected_steps(start: i32) -> i64 {
        let mut x = start;
        let mut steps: i64 = 0;
        while x < 100 {
            let diff = 100 - x;
            let mut step = diff / 2;
            if step == 0 && x < 100 {
                step = 1;
            }
            x += step;
            steps += 1;
        }
        steps
    }

    #[test]
    fn all_required_start_values_converge_in_the_expected_steps() {
        for start in -100_i8..=50_i8 {
            let got = simulate(start.into()) as i64;
            assert_eq!(got, expected_steps(start as i32), "wrong result for start={}", start);
            assert!(got < 10_000, "start={} reached the failsafe", start);
        }
    }
}
''')

        completed = subprocess.run(
            ["cargo", "test", "--quiet"],
            cwd=copied_project,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=90,
        )
        assert completed.returncode == 0, "Submitted simulation failed behavioral tests:\n" + completed.stdout


def test_result_file_exists_and_correct_and_matches_application():
    assert os.path.isfile(RESULT), f"{RESULT} does not exist. Did you redirect the output?"

    with open(RESULT, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_steps = str(compute_expected_total_steps())
    # Preserve the original aggregate assertion.
    assert expected_steps in content.split(), f"Expected {expected_steps} in {RESULT}, but got '{content}'"

    completed = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=90,
    )
    assert completed.returncode == 0, f"Application failed to run:\n{completed.stderr}"

    stdout = completed.stdout.strip()
    assert re.fullmatch(r"[+-]?\d+", stdout), f"Application output is not a single integer: {completed.stdout!r}"
    assert stdout == expected_steps, f"Application produced {stdout}, expected {expected_steps}"
    assert content == stdout, f"{RESULT} does not exactly match the submitted application's standard output"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
