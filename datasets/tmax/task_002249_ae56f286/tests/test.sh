#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess


def test_fixed_pipeline_exists_and_executable():
    path = "/home/user/fixed_pipeline.sh"
    assert os.path.isfile(path), f"Expected fixed pipeline script at {path} does not exist."
    assert os.access(path, os.X_OK), f"Fixed pipeline script at {path} is not executable."


def test_helper_compiles_and_works():
    src_dir = "/home/user/src"
    helper_path = os.path.join(src_dir, "helper")

    # Force a rebuild so a pre-created fake executable cannot satisfy this test.
    result = subprocess.run(
        ["make", "-B", "helper"],
        cwd=src_dir,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Running make failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(helper_path), f"Expected compiled helper binary at {helper_path} does not exist."
    assert os.access(helper_path, os.X_OK), f"Helper binary at {helper_path} is not executable."

    inputs = [-37, -11, -1, 0, 2, 5, 19, 46]
    for x in inputs:
        run = subprocess.run(
            [helper_path, str(x)], capture_output=True, text=True, timeout=5
        )
        assert run.returncode == 0, f"Helper failed for input {x}: {run.stderr}"
        assert run.stdout.strip() == str(x * x), (
            f"Helper produced incorrect output for input {x}: {run.stdout.strip()}"
        )


def test_fuzz_equivalence():
    agent_script = "/home/user/fixed_pipeline.sh"
    assert os.path.isfile(agent_script), f"Agent script {agent_script} not found."

    random.seed(42)
    inputs = [random.randint(-500, 500) for _ in range(100)]

    for x in inputs:
        expected = str(14 * x * x - 3 * x + 19)
        agent_res = subprocess.run(
            ["/bin/bash", agent_script, str(x)],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert agent_res.returncode == 0, (
            f"Agent script failed on input {x}: {agent_res.stderr}"
        )
        agent_out = agent_res.stdout.strip()
        assert agent_out == expected, (
            f"Output mismatch on input {x}.\n"
            f"Expected: {expected}\n"
            f"Got:      {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
