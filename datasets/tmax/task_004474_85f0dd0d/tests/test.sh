#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import functools
import json
import os
import re
import secrets
import subprocess
import tempfile

import numpy as np
import pandas as pd
from scipy.integrate import odeint

SCRIPT_PATH = "/home/user/trace_filter.py"
VENV_PATH = "/home/user/sim_env"
VENV_PYTHON = os.path.join(VENV_PATH, "bin", "python")
SCAN_PATH = "/app/lab_notes_scan.png"
CLEAN_CORPUS = "/app/corpora/clean"
EVIL_CORPUS = "/app/corpora/evil"


def run_filter(input_dir, output_dir):
    cmd = ["python3", SCRIPT_PATH, "--input", input_dir, "--output", output_dir]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, (
        f"Script failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


@functools.lru_cache(maxsize=1)
def extracted_parameters():
    code = r'''
import json
import re
import numpy
import scipy
import pandas
import pytesseract
from PIL import Image

text = pytesseract.image_to_string(Image.open("/app/lab_notes_scan.png")).lower()
values = {}
for name in ("alpha", "beta", "delta", "gamma"):
    match = re.search(r"%s\s*=\s*([0-9]+(?:\.[0-9]+)?)" % name, text)
    if match:
        values[name] = float(match.group(1))
print(json.dumps({"text": text, "values": values}))
'''
    result = subprocess.run(
        [VENV_PYTHON, "-c", code], capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, (
        "The requested virtual environment cannot import its scientific/OCR "
        f"dependencies or run OCR:\n{result.stderr}"
    )
    payload = json.loads(result.stdout.strip().splitlines()[-1])
    values = payload["values"]
    assert set(values) == {"alpha", "beta", "delta", "gamma"}, (
        f"Could not extract all parameters from the supplied scan. OCR text: {payload['text']!r}"
    )
    expected = {"alpha": 1.2, "beta": 0.4, "delta": 0.1, "gamma": 0.8}
    for name, value in expected.items():
        assert abs(values[name] - value) < 1e-9, (
            f"OCR parameter {name} was {values[name]}, expected {value}"
        )
    return values


def test_trace_filter_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Agent script missing: {SCRIPT_PATH}"


def test_virtual_environment_and_ocr_parameters():
    assert os.path.isfile(os.path.join(VENV_PATH, "pyvenv.cfg")), (
        f"Python virtual environment missing: {VENV_PATH}"
    )
    assert os.path.isfile(VENV_PYTHON) and os.access(VENV_PYTHON, os.X_OK), (
        f"Virtual-environment Python missing: {VENV_PYTHON}"
    )
    extracted_parameters()


def test_clean_corpus_accepted():
    assert os.path.isfile(SCRIPT_PATH), f"Agent script missing: {SCRIPT_PATH}"

    with tempfile.TemporaryDirectory() as tmpdir:
        cmd = ["python3", SCRIPT_PATH, "--input", CLEAN_CORPUS, "--output", tmpdir]
        result = subprocess.run(cmd, capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on clean corpus:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

        accepted_dir = os.path.join(tmpdir, "accepted")
        rejected_dir = os.path.join(tmpdir, "rejected")

        accepted_files = set(os.listdir(accepted_dir)) if os.path.isdir(accepted_dir) else set()
        rejected_files = set(os.listdir(rejected_dir)) if os.path.isdir(rejected_dir) else set()

        clean_input_files = set(f for f in os.listdir(CLEAN_CORPUS) if f.endswith('.csv'))

        missing_accepted = clean_input_files - accepted_files
        false_rejected = rejected_files.intersection(clean_input_files)

        assert not false_rejected, f"{len(false_rejected)} of {len(clean_input_files)} clean files were incorrectly rejected. Examples: {list(false_rejected)[:5]}"
        assert not missing_accepted, f"{len(missing_accepted)} clean files were missing from accepted directory. Examples: {list(missing_accepted)[:5]}"


def test_evil_corpus_rejected():
    assert os.path.isfile(SCRIPT_PATH), f"Agent script missing: {SCRIPT_PATH}"

    with tempfile.TemporaryDirectory() as tmpdir:
        cmd = ["python3", SCRIPT_PATH, "--input", EVIL_CORPUS, "--output", tmpdir]
        result = subprocess.run(cmd, capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on evil corpus:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

        accepted_dir = os.path.join(tmpdir, "accepted")
        rejected_dir = os.path.join(tmpdir, "rejected")

        accepted_files = set(os.listdir(accepted_dir)) if os.path.isdir(accepted_dir) else set()
        rejected_files = set(os.listdir(rejected_dir)) if os.path.isdir(rejected_dir) else set()

        evil_input_files = set(f for f in os.listdir(EVIL_CORPUS) if f.endswith('.csv'))

        missing_rejected = evil_input_files - rejected_files
        false_accepted = accepted_files.intersection(evil_input_files)

        assert not false_accepted, f"{len(false_accepted)} of {len(evil_input_files)} evil files bypassed the filter (incorrectly accepted). Examples: {list(false_accepted)[:5]}"
        assert not missing_rejected, f"{len(missing_rejected)} evil files were missing from rejected directory. Examples: {list(missing_rejected)[:5]}"


def test_unseen_mixed_traces_and_exact_copies():
    params = extracted_parameters()
    t = np.linspace(0.0, 50.0, 500)

    def lv(y, time):
        prey, predator = y
        return [
            params["alpha"] * prey - params["beta"] * prey * predator,
            params["delta"] * prey * predator - params["gamma"] * predator,
        ]

    baseline = odeint(lv, [10.0, 5.0], t, rtol=1e-10, atol=1e-10)
    wobble = np.column_stack((0.5 * np.sin(t), 0.5 * np.cos(0.7 * t)))

    cases = [
        (baseline.copy(), "accepted"),
        (np.maximum(baseline + wobble, 0.0), "accepted"),
        (baseline + 1.8, "accepted"),
        (baseline + np.column_stack((np.full(len(t), 3.0), np.zeros(len(t)))), "rejected"),
        (baseline + np.column_stack((np.zeros(len(t)), np.full(len(t), 3.0))), "rejected"),
    ]
    negative = baseline.copy()
    negative[0, 0] = -0.01
    cases.append((negative, "rejected"))

    with tempfile.TemporaryDirectory(prefix="observations_") as input_dir, \
         tempfile.TemporaryDirectory(prefix="classified_") as output_dir:
        expected = {"accepted": set(), "rejected": set()}
        source_bytes = {}
        for values, classification in cases:
            filename = f"trace_{secrets.token_hex(12)}.csv"
            path = os.path.join(input_dir, filename)
            pd.DataFrame({
                "time": t,
                "prey": values[:, 0],
                "predator": values[:, 1],
            }).to_csv(path, index=False)
            expected[classification].add(filename)
            with open(path, "rb") as handle:
                source_bytes[filename] = handle.read()

        with open(os.path.join(input_dir, f"ignore_{secrets.token_hex(8)}.txt"), "w") as handle:
            handle.write("not a CSV trace")

        run_filter(input_dir, output_dir)

        for classification in ("accepted", "rejected"):
            directory = os.path.join(output_dir, classification)
            assert os.path.isdir(directory), f"Missing output directory: {directory}"
            actual = set(os.listdir(directory))
            assert actual == expected[classification], (
                f"Wrong files in {classification}: expected {expected[classification]}, got {actual}"
            )
            for filename in actual:
                destination = os.path.join(directory, filename)
                assert os.path.isfile(destination), f"Output is not a file: {destination}"
                with open(destination, "rb") as handle:
                    assert handle.read() == source_bytes[filename], (
                        f"{filename} was not copied with its original contents"
                    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
