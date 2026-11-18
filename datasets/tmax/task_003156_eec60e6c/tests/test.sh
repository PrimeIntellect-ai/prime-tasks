#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/exercise_pipeline.py
import json
import os
import secrets
import shutil
import string
import subprocess
from pathlib import Path

SCRIPT = Path('/home/user/run_pipeline.sh')
RAW = Path('/home/user/data/raw.txt')
ANALYZE = Path('/home/user/scripts/analyze.py')
TOKENS = Path('/home/user/data/tokens.txt')
ARTIFACTS = Path('/home/user/artifacts')
VENV = Path('/home/user/venv')
MARKER = Path('/tmp/analyze_execution_marker.json')
STATUS = Path('/tmp/pipeline_verification.json')

result = {'ok': False, 'checks': [], 'error': ''}
original_raw = RAW.read_bytes()
original_analyze = ANALYZE.read_bytes()

def check(condition, message):
    if not condition:
        raise AssertionError(message)
    result['checks'].append(message)

def clean_outputs(remove_venv=False):
    for path in (TOKENS, ARTIFACTS / 'plot.png', ARTIFACTS / 'eigen_metrics.txt', MARKER):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    if remove_venv and VENV.exists():
        shutil.rmtree(VENV)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)

def execute_pipeline(run_token):
    env = os.environ.copy()
    env.pop('MPLBACKEND', None)
    env['VERIFIER_RUN_TOKEN'] = run_token
    completed = subprocess.run(
        [str(SCRIPT)], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=300
    )
    check(completed.returncode == 0,
          'run_pipeline.sh exits successfully when executed')
    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    check(bool(lines) and lines[-1] == 'Pipeline completed successfully',
          'the final non-empty output line is the required completion message')
    return completed.stdout

try:
    check(SCRIPT.is_file(), 'run_pipeline.sh exists')
    check(os.access(SCRIPT, os.X_OK), 'run_pipeline.sh is executable')

    nonce = secrets.token_hex(8)
    dynamic_text = (
        f'Audit-{nonce}, MIXED Case!\n'
        "Punctuation: can't; remain? No.\n"
    )
    expected_tokens = dynamic_text.lower().translate(
        str.maketrans('', '', string.punctuation)
    ).split()
    run_token = secrets.token_hex(16)

    instrumentation = b'''\n# Verification instrumentation: records that this supplied analysis script ran.\nimport json as _verification_json\nwith open('/tmp/analyze_execution_marker.json', 'w') as _verification_file:\n    _verification_json.dump({\n        'token': os.environ.get('VERIFIER_RUN_TOKEN'),\n        'backend': os.environ.get('MPLBACKEND'),\n        'prefix': sys.prefix,\n    }, _verification_file)\n'''
    ANALYZE.write_bytes(original_analyze + instrumentation)
    RAW.write_text(dynamic_text)
    clean_outputs(remove_venv=True)
    execute_pipeline(run_token)

    check(TOKENS.is_file(), 'the executed pipeline creates tokens.txt')
    actual_tokens = [line.strip() for line in TOKENS.read_text().splitlines() if line.strip()]
    check(actual_tokens == expected_tokens,
          'the executed pipeline tokenizes a verifier-generated input correctly')

    check((VENV / 'pyvenv.cfg').is_file(), 'the executed pipeline creates a real virtual environment')
    python_path = VENV / 'bin/python'
    if not python_path.is_file():
        python_path = VENV / 'bin/python3'
    check(python_path.is_file(), 'the virtual environment contains Python')

    probe = subprocess.run(
        [str(python_path), '-c',
         "import json,sys,numpy,matplotlib; print(json.dumps({'prefix':sys.prefix,'numpy':numpy.__file__,'matplotlib':matplotlib.__file__}))"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    check(probe.returncode == 0, 'numpy and matplotlib import successfully in the created virtual environment')
    probe_data = json.loads(probe.stdout.strip().splitlines()[-1])
    check(Path(probe_data['prefix']).resolve() == VENV.resolve(),
          'the created environment has the expected sys.prefix')
    check(str(VENV.resolve()) in str(Path(probe_data['numpy']).resolve()) and
          str(VENV.resolve()) in str(Path(probe_data['matplotlib']).resolve()),
          'numpy and matplotlib are installed inside the created virtual environment')

    check(MARKER.is_file(), 'the provided analyze.py was actually executed')
    marker = json.loads(MARKER.read_text())
    check(marker.get('token') == run_token, 'analyze.py ran during this verification execution')
    check(marker.get('backend') == 'Agg', 'analyze.py ran with MPLBACKEND=Agg')
    check(Path(marker.get('prefix', '')).resolve() == VENV.resolve(),
          'analyze.py ran using the created virtual environment')

    metrics = ARTIFACTS / 'eigen_metrics.txt'
    plot = ARTIFACTS / 'plot.png'
    check(metrics.is_file(), 'the executed analysis creates eigen_metrics.txt')
    check(plot.is_file(), 'the executed analysis creates plot.png')

    expected_metric = subprocess.run(
        [str(python_path), '-c',
         'import numpy as np; n=int(__import__("sys").argv[1]); np.random.seed(42); m=np.random.rand(n,n); m=(m+m.T)/2; e=np.linalg.eigh(m)[0]; print(f"Vocab size: {n}\\nMax Eigenvalue: {np.max(e):.4f}")',
         str(len(set(expected_tokens)))],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True, timeout=60
    ).stdout.strip()
    check(metrics.read_text().strip() == expected_metric,
          'eigen_metrics.txt contains the values derived from the generated input')
    plot_bytes = plot.read_bytes()
    check(plot_bytes.startswith(b'\x89PNG\r\n\x1a\n') and len(plot_bytes) > 1000,
          'plot.png is a nontrivial PNG generated by the analysis')

    # Restore the supplied files and execute once more on the original dataset so
    # the original final-state assertions remain meaningful.
    ANALYZE.write_bytes(original_analyze)
    RAW.write_bytes(original_raw)
    clean_outputs(remove_venv=False)
    execute_pipeline(secrets.token_hex(16))
    result['ok'] = True
except BaseException as exc:
    result['error'] = f'{type(exc).__name__}: {exc}'
finally:
    try:
        ANALYZE.write_bytes(original_analyze)
        RAW.write_bytes(original_raw)
    except BaseException as restore_exc:
        result['ok'] = False
        result['error'] += f' Restore failed: {restore_exc}'
    STATUS.write_text(json.dumps(result))
RUNNER_EOF

python3 /tmp/exercise_pipeline.py || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import pytest

def test_pipeline_was_executed_and_exercised():
    with open('/tmp/pipeline_verification.json', 'r') as f:
        result = json.load(f)
    assert result['ok'], result.get('error', 'Pipeline execution verification failed')

def test_run_pipeline_script_exists_and_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The script {script_path} is not executable."

def test_tokens_file_created_and_correct():
    tokens_path = "/home/user/data/tokens.txt"
    assert os.path.isfile(tokens_path), f"The tokens file {tokens_path} was not created."

    with open(tokens_path, "r") as f:
        tokens = [line.strip() for line in f if line.strip()]

    expected_tokens = [
        "hello", "world", "this", "is", "a", "test", "dataset",
        "data", "science", "involves", "linear", "algebra", "tokenization", "and", "environments",
        "testing", "1", "2", "3", "the", "quick", "brown", "fox", "jumps"
    ]

    assert tokens == expected_tokens, f"The tokens in {tokens_path} do not match the expected lowercase, punctuation-free output."

def test_venv_created():
    venv_path = "/home/user/venv"
    assert os.path.isdir(venv_path), f"The virtual environment directory {venv_path} was not created."
    assert os.path.isfile(os.path.join(venv_path, "bin", "python")) or os.path.isfile(os.path.join(venv_path, "bin", "python3")), \
        "The virtual environment does not seem to contain a valid Python executable."

def test_artifacts_generated():
    plot_path = "/home/user/artifacts/plot.png"
    metrics_path = "/home/user/artifacts/eigen_metrics.txt"

    assert os.path.isfile(plot_path), f"The plot artifact {plot_path} was not generated. Ensure the Python script ran successfully with the correct Matplotlib backend."
    assert os.path.isfile(metrics_path), f"The metrics artifact {metrics_path} was not generated. Ensure the Python script ran successfully."

    with open(metrics_path, "r") as f:
        content = f.read()

    assert "Vocab size:" in content, f"The metrics file {metrics_path} does not contain expected content."
    assert "Max Eigenvalue:" in content, f"The metrics file {metrics_path} does not contain expected content."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
