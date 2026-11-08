#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import pathlib
import subprocess
import sys

import numpy as np
import pytest
from scipy.io import wavfile

ORIGINAL = "/app/chime_recording.wav"
RECONSTRUCTED = "/home/user/reconstructed.wav"
PARAMETERS = "/home/user/parameters.csv"
POSTERIORS = "/home/user/posteriors.png"


def compute_mse(original_path, reconstructed_path):
    sr1, y1 = wavfile.read(original_path)
    sr2, y2 = wavfile.read(reconstructed_path)

    if sr1 != sr2:
        return float("inf")

    y1 = y1.astype(np.float64)
    y2 = y2.astype(np.float64)

    if np.max(np.abs(y1)) > 0:
        y1 = y1 / np.max(np.abs(y1))
    if np.max(np.abs(y2)) > 0:
        y2 = y2 / np.max(np.abs(y2))

    min_len = min(len(y1), len(y2))
    y1 = y1[:min_len]
    y2 = y2[:min_len]
    return np.mean((y1 - y2) ** 2)


def find_submission_script():
    candidates = []
    excluded = {"/tmp/test_final_state.py", "/tmp/verifier_hook/sitecustomize.py"}
    for root in ("/home/user", "/app", "/workspace", "/root", "/tmp"):
        if not os.path.isdir(root):
            continue
        for path in pathlib.Path(root).rglob("*.py"):
            resolved = str(path.resolve())
            if resolved in excluded:
                continue
            try:
                source = path.read_text(errors="replace")
                ast.parse(source)
            except (OSError, SyntaxError):
                continue
            score = sum(name in source for name in
                        ("reconstructed.wav", "parameters.csv", "posteriors.png"))
            score += 2 if ("multiprocessing" in source or
                           "ProcessPoolExecutor" in source or
                           "mpi4py" in source) else 0
            score += 1 if ("random" in source or "MCMC" in source or
                           "mcmc" in source) else 0
            if score >= 3:
                candidates.append((score, path.stat().st_mtime, resolved))
    assert candidates, "No runnable Python analysis/MCMC script was found"
    candidates.sort(reverse=True)
    return candidates[0][2]


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    script = find_submission_script()

    # Instrument multiprocessing itself. A real run with four parallel chains
    # must start at least four worker processes.
    hook_dir = "/tmp/verifier_hook"
    os.makedirs(hook_dir, exist_ok=True)
    process_log = "/tmp/verifier_process_starts.log"
    try:
        os.remove(process_log)
    except FileNotFoundError:
        pass

    with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
        f.write(r'''
import os
try:
    from multiprocessing.process import BaseProcess
    _verifier_original_start = BaseProcess.start
    def _verifier_start(self, *args, **kwargs):
        try:
            fd = os.open(os.environ.get("VERIFIER_PROCESS_LOG", "/tmp/verifier_process_starts.log"),
                         os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
            os.write(fd, (str(os.getpid()) + "\\n").encode())
            os.close(fd)
        except Exception:
            pass
        return _verifier_original_start(self, *args, **kwargs)
    BaseProcess.start = _verifier_start
except Exception:
    pass
''')

    for output in (RECONSTRUCTED, PARAMETERS, POSTERIORS):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    env["VERIFIER_PROCESS_LOG"] = process_log
    env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
    try:
        result = subprocess.run(
            [sys.executable, script], cwd=os.path.dirname(script) or "/home/user",
            env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=300
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The submitted analysis script did not finish within 300 seconds")
    assert result.returncode == 0, "Submitted script failed:\n" + result.stdout[-4000:]

    try:
        with open(process_log) as f:
            starts = [line for line in f if line.strip()]
    except FileNotFoundError:
        starts = []
    assert len(starts) >= 4, (
        f"The executed sampler started only {len(starts)} worker processes; "
        "at least four parallel chains are required"
    )


def test_posteriors_plot_exists():
    assert os.path.exists(POSTERIORS), f"Expected plot file not found at {POSTERIORS}"
    assert os.path.getsize(POSTERIORS) > 0, f"Plot file at {POSTERIORS} is empty"
    with open(POSTERIORS, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "posteriors.png is not a valid PNG file"


def read_parameters():
    assert os.path.exists(PARAMETERS), f"Expected parameter log not found at {PARAMETERS}"
    with open(PARAMETERS, newline="") as f:
        reader = csv.DictReader(f)
        expected = {"component", "amplitude", "decay", "frequency", "phase"}
        assert expected.issubset(set(reader.fieldnames or [])), (
            f"CSV at {PARAMETERS} is missing required columns. Found: {reader.fieldnames}"
        )
        rows = list(reader)
    assert len(rows) == 3, f"Expected 3 components in the CSV, found {len(rows)}"
    values = []
    for row in rows:
        try:
            values.append([float(row[k]) for k in
                           ("amplitude", "decay", "frequency", "phase")])
        except (TypeError, ValueError) as exc:
            pytest.fail(f"CSV contains a nonnumeric parameter: {exc}")
    values = np.asarray(values, dtype=np.float64)
    assert np.all(np.isfinite(values)), "CSV parameters must all be finite"
    return values


def test_parameters_csv():
    read_parameters()


def test_reconstructed_audio_mse_and_model_consistency():
    assert os.path.exists(RECONSTRUCTED), (
        f"Expected reconstructed audio not found at {RECONSTRUCTED}"
    )

    sr1, original = wavfile.read(ORIGINAL)
    sr2, reconstructed = wavfile.read(RECONSTRUCTED)
    assert sr1 == sr2, "Reconstructed WAV must use the original sample rate"
    assert reconstructed.dtype == np.int16, "Reconstructed WAV must be 16-bit PCM"
    assert reconstructed.ndim == 1, "Reconstructed WAV must be mono"
    assert len(reconstructed) == len(original), (
        "Reconstructed WAV must have the same number of samples as the observation"
    )
    assert not np.array_equal(original, reconstructed), (
        "Reconstructed WAV is an unchanged copy of the observational recording"
    )

    mse = compute_mse(ORIGINAL, RECONSTRUCTED)
    assert mse <= 0.02, f"Reconstruction failed: MSE={mse:.5f} > 0.02"

    params = read_parameters()
    t = np.arange(len(reconstructed), dtype=np.float64) / sr2
    modeled = np.zeros_like(t)
    for amplitude, decay, frequency, phase in params:
        modeled += amplitude * np.exp(-decay * t) * np.sin(
            2 * np.pi * frequency * t + phase
        )

    assert np.max(np.abs(modeled)) > 0, "CSV parameters produce a silent model"
    modeled /= np.max(np.abs(modeled))
    reconstructed_float = reconstructed.astype(np.float64)
    reconstructed_float /= np.max(np.abs(reconstructed_float))
    model_mse = np.mean((modeled - reconstructed_float) ** 2)
    assert model_mse <= 5e-4, (
        f"Reconstructed WAV is not generated by the logged three-component model: "
        f"MSE={model_mse:.6f}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
