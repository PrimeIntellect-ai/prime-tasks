#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
from pathlib import Path

import joblib
import numpy as np

HOME = Path('/home/user')
MODELS_DIR = HOME / 'models'
X_PATH = HOME / 'X.npy'
Y_PATH = HOME / 'y_target.npy'
OUTPUT_PATH = HOME / 'best_model.txt'


def read_output():
    assert OUTPUT_PATH.is_file(), f'The file {OUTPUT_PATH} does not exist.'
    return OUTPUT_PATH.read_text().strip()


def calculate_best_model():
    X = np.load(X_PATH)
    y = np.load(Y_PATH)
    scores = {}
    for model_path in sorted(MODELS_DIR.glob('*.pkl')):
        model = joblib.load(model_path)
        predictions = np.asarray(model.predict(X))
        assert predictions.shape == y.shape, f'Prediction shape mismatch for {model_path.name}'
        scores[model_path.name] = float(np.mean((predictions - y) ** 2))
    assert scores, 'No .pkl model artifacts were found.'
    return min(scores, key=scores.get)


def run_script(script_path):
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    result = subprocess.run(
        ['python3', str(script_path)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'Evaluation script {script_path} failed.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    return read_output()


def test_00_evaluation_script_executes_and_recomputes_mse():
    scripts = sorted(
        path for path in HOME.rglob('*.py')
        if path.is_file() and not path.is_symlink()
    )
    assert scripts, 'No Python evaluation script was found under /home/user.'

    original_y = Y_PATH.read_bytes()
    original_models = {
        path: path.read_bytes() for path in sorted(MODELS_DIR.glob('*.pkl'))
    }

    def restore_inputs():
        Y_PATH.write_bytes(original_y)
        for path, data in original_models.items():
            path.write_bytes(data)

    restore_inputs()
    expected_original = calculate_best_model()
    # Preserve the original verifier's known-answer assertion.
    assert expected_original == 'model_gamma.pkl'

    X = np.load(X_PATH)
    challenge_model_path = MODELS_DIR / 'model_alpha.pkl'
    assert challenge_model_path.is_file()
    challenge_target = np.asarray(joblib.load(challenge_model_path).predict(X))

    passing_script = None
    failures = []
    try:
        for script in scripts:
            try:
                restore_inputs()
                original_result = run_script(script)
                assert original_result == expected_original

                np.save(Y_PATH, challenge_target)
                expected_challenge = calculate_best_model()
                assert expected_challenge != expected_original
                challenge_result = run_script(script)
                assert challenge_result == expected_challenge

                passing_script = script
                break
            except Exception as exc:
                failures.append(f'{script}: {exc}')

        assert passing_script is not None, (
            'No evaluation script correctly handled both the supplied data and an '
            'independently derived evaluation target.\n' + '\n'.join(failures)
        )
    finally:
        restore_inputs()

    # Leave the required final artifact produced by the working script on the
    # original supplied dataset.
    final_result = run_script(passing_script)
    assert final_result == expected_original


def test_best_model_file_exists():
    """Verify that the best_model.txt file was created."""
    file_path = '/home/user/best_model.txt'
    assert os.path.isfile(file_path), f'The file {file_path} does not exist.'


def test_best_model_content():
    """Verify that best_model.txt contains the correct model filename."""
    file_path = '/home/user/best_model.txt'
    assert os.path.isfile(file_path), f'The file {file_path} does not exist.'

    with open(file_path, 'r') as f:
        content = f.read().strip()

    expected = 'model_gamma.pkl'
    assert content == expected, f"Expected '{expected}' in {file_path}, but found '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
