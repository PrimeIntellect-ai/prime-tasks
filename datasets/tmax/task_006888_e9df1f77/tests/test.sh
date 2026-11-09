#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess

import matplotlib.image as mpimg
import pytest


def test_run_experiment_script_fixed_and_runs_headless():
    """Verify that run_experiment.py is fixed and actually runs headlessly."""
    script_path = '/home/user/run_experiment.py'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, 'r') as f:
        content = f.read()

    assert "TkAgg" not in content, "The script still contains 'TkAgg' which requires a GUI."

    # Require the submitted script itself to create fresh artifacts without X11.
    for path in ('/home/user/results.json', '/home/user/plot.png'):
        if os.path.exists(path):
            os.remove(path)

    env = os.environ.copy()
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    env.pop('MPLBACKEND', None)
    result = subprocess.run(
        ['python3', script_path],
        cwd='/home/user',
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"run_experiment.py failed headlessly with code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_artifacts_generated():
    """Verify that results.json and plot.png were freshly generated and valid."""
    results_path = '/home/user/results.json'
    plot_path = '/home/user/plot.png'

    assert os.path.isfile(results_path), f"Artifact {results_path} was not generated."
    assert os.path.isfile(plot_path), f"Artifact {plot_path} was not generated."
    assert os.path.getsize(plot_path) > 0, f"Artifact {plot_path} is empty."

    with open(results_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{results_path} does not contain valid JSON.")

    assert 'accuracy' in data, "results.json is missing the 'accuracy' key."
    assert isinstance(data['accuracy'], (int, float)) and not isinstance(data['accuracy'], bool), \
        "results.json accuracy must be numeric."
    assert data['accuracy'] == pytest.approx(0.865), \
        "run_experiment.py did not preserve the experiment's accuracy result."
    assert data.get('loss') == pytest.approx(0.23), \
        "run_experiment.py did not preserve the experiment's loss result."

    with open(plot_path, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', "plot.png is not a PNG file."
    try:
        image = mpimg.imread(plot_path)
    except Exception as exc:
        pytest.fail(f"plot.png is not a valid readable PNG: {exc}")
    assert image.ndim in (2, 3) and image.shape[0] > 1 and image.shape[1] > 1, \
        "plot.png does not contain a valid image."


def test_eval_script_exists_and_executable():
    """Verify that eval.sh exists and is executable."""
    eval_path = '/home/user/eval.sh'
    assert os.path.isfile(eval_path), f"Script {eval_path} does not exist."

    st = os.stat(eval_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {eval_path} is not executable."


def test_eval_script_behavior():
    """Verify the strict greater-than-0.80 rule on fixed and unpredictable inputs."""
    eval_path = '/home/user/eval.sh'
    results_path = '/home/user/results.json'

    # Preserve the original check against the generated experiment result.
    result = subprocess.run([eval_path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"eval.sh exited with code {result.returncode}, expected 0."
    assert result.stdout.strip() == "PASS", \
        f"eval.sh outputted '{result.stdout.strip()}', expected 'PASS'."

    with open(results_path, 'r') as f:
        original_data = json.load(f)

    rng = secrets.SystemRandom()
    cases = [
        (0.75, 0.5, "FAIL", 1),       # Preserve the original fixed FAIL check.
        (0.80, rng.random(), "FAIL", 1),  # Strict boundary.
    ]
    # Values are selected only at verification time to prevent fixed-subset scripts.
    for _ in range(5):
        cases.append((rng.randint(1, 799999) / 1000000, rng.random(), "FAIL", 1))
        cases.append((rng.randint(800001, 999999) / 1000000, rng.random(), "PASS", 0))

    try:
        for accuracy, loss, expected_output, expected_code in cases:
            with open(results_path, 'w') as f:
                json.dump({"loss": loss, "accuracy": accuracy}, f)

            evaluated = subprocess.run(
                [eval_path], capture_output=True, text=True, timeout=10
            )
            assert evaluated.returncode == expected_code, (
                f"eval.sh exited with code {evaluated.returncode} for accuracy "
                f"{accuracy}, expected {expected_code}."
            )
            assert evaluated.stdout.strip() == expected_output, (
                f"eval.sh outputted '{evaluated.stdout.strip()}' for accuracy "
                f"{accuracy}, expected '{expected_output}'."
            )
    finally:
        with open(results_path, 'w') as f:
            json.dump(original_data, f)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
