#!/bin/bash
set -u
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import re
import secrets
import shutil
import struct
import subprocess
import tempfile
import textwrap

import numpy as np
from sklearn.linear_model import LogisticRegression

SCRIPT = "/home/user/run_eval.sh"
TRAIN = "/home/user/train_and_plot.py"
METRICS = "/home/user/metrics.json"
PLOT = "/home/user/plot.png"


def expected_accuracy(seed):
    np.random.seed(seed)
    X = np.random.randn(100, 2)
    y = (X[:, 0] + X[:, 1] > 0).astype(int)
    noise = np.random.choice([0, 1], size=100, p=[0.9, 0.1])
    y = np.abs(y - noise)
    model = LogisticRegression()
    model.fit(X, y)
    return float(model.score(X, y))


def expected_metrics(values):
    mean = sum(values) / len(values)
    variance = sum((x - mean) ** 2 for x in values) / (len(values) - 1)
    margin = 1.96 * math.sqrt(variance) / math.sqrt(len(values))
    return round(mean, 4), round(margin, 4), (mean - margin) > 0.80


def load_and_check_metrics(expected):
    assert os.path.isfile(METRICS), f"File {METRICS} does not exist."
    with open(METRICS, "r", encoding="utf-8") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {METRICS} is not valid JSON: {exc}")

    for key in ("mean_accuracy", "margin_of_error", "hypothesis_passed"):
        assert key in metrics, f"Missing '{key}' in metrics.json"

    mean, margin, hypothesis = expected
    assert isinstance(metrics["mean_accuracy"], (int, float)) and not isinstance(metrics["mean_accuracy"], bool)
    assert isinstance(metrics["margin_of_error"], (int, float)) and not isinstance(metrics["margin_of_error"], bool)
    assert type(metrics["hypothesis_passed"]) is bool
    assert math.isclose(metrics["mean_accuracy"], mean, rel_tol=0, abs_tol=1e-4), \
        f"Expected mean_accuracy {mean}, got {metrics['mean_accuracy']}"
    assert math.isclose(metrics["margin_of_error"], margin, rel_tol=0, abs_tol=1e-4), \
        f"Expected margin_of_error {margin}, got {metrics['margin_of_error']}"
    assert metrics["hypothesis_passed"] == hypothesis, \
        f"Expected hypothesis_passed {hypothesis}, got {metrics['hypothesis_passed']}"


def assert_real_png(path):
    assert os.path.isfile(path), "plot.png was not generated."
    assert os.path.getsize(path) > 1000, "plot.png is empty or implausibly small."
    with open(path, "rb") as f:
        header = f.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n", "plot.png is not a PNG file."
    width, height = struct.unpack(">II", header[16:24])
    assert width >= 100 and height >= 100, "plot.png has implausible dimensions."
    try:
        from PIL import Image, ImageStat
        with Image.open(path) as image:
            image.verify()
        with Image.open(path).convert("RGB") as image:
            stat = ImageStat.Stat(image)
            assert any(v > 0 for v in stat.var), "plot.png appears blank."
    except ImportError:
        pass


def test_artifacts_and_bash_script():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    assert os.path.isfile(TRAIN), f"Python script {TRAIN} does not exist."

    with open(SCRIPT, "r", encoding="utf-8", errors="replace") as f:
        shell_source = f.read()
    first_line = shell_source.splitlines()[0] if shell_source.splitlines() else ""
    assert "bash" in first_line, "run_eval.sh must be a Bash script."
    assert re.search(r"\b(for|while|until)\b", shell_source), "run_eval.sh must contain a Bash loop."
    syntax = subprocess.run(["bash", "-n", SCRIPT], capture_output=True, text=True)
    assert syntax.returncode == 0, f"run_eval.sh has invalid Bash syntax: {syntax.stderr}"

    with open(TRAIN, "r", encoding="utf-8", errors="replace") as f:
        python_source = f.read()
    assert "LogisticRegression" in python_source, "The Logistic Regression evaluation was removed."
    assert re.search(r"\.fit\s*\(", python_source), "Model training code was removed."
    assert re.search(r"savefig\s*\(", python_source), "The plotting/savefig code was removed."
    assert re.search(r"\.(plot|scatter|contour|contourf)\s*\(", python_source), "The plotting code was removed."


def test_training_script_on_unannounced_seeds():
    seeds = [1000 + secrets.randbelow(1_000_000) for _ in range(4)]
    plot_hashes = []
    for seed in seeds:
        with tempfile.TemporaryDirectory() as workdir:
            result = subprocess.run(
                ["python3", TRAIN, str(seed)],
                cwd=workdir,
                capture_output=True,
                text=True,
                timeout=60,
            )
            assert result.returncode == 0, \
                f"Python script failed for seed {seed}: {result.stderr}"
            try:
                actual = float(result.stdout.strip())
            except ValueError:
                raise AssertionError(f"Could not parse accuracy from output: {result.stdout!r}")
            expected = expected_accuracy(seed)
            assert math.isclose(actual, expected, rel_tol=0, abs_tol=1e-10), \
                f"Incorrect model accuracy for seed {seed}: expected {expected}, got {actual}"
            plot = os.path.join(workdir, "plot.png")
            assert_real_png(plot)
            with open(plot, "rb") as f:
                plot_hashes.append(hashlib.sha256(f.read()).digest())
    assert len(set(plot_hashes)) > 1, "Plots do not vary when the generated data changes."


def test_run_eval_executes_all_seeds_and_aggregates_outputs():
    backup = TRAIN + ".verifier-backup"
    log_path = f"/tmp/run_eval_calls_{secrets.token_hex(12)}.log"
    shutil.copy2(TRAIN, backup)
    probe = textwrap.dedent(f'''\
        import os
        import sys

        if len(sys.argv) != 2:
            raise SystemExit(2)
        seed = int(sys.argv[1])
        with open({log_path!r}, "a", encoding="utf-8") as log:
            log.write(str(seed) + "\\n")
        with open("plot.png", "wb") as plot:
            plot.write(b"probe")
        print(f"{{0.55 + ((seed * 17) % 41) / 100.0:.12f}}")
    ''')
    try:
        with open(TRAIN, "w", encoding="utf-8") as f:
            f.write(probe)
        os.chmod(TRAIN, 0o755)
        for path in (METRICS, PLOT, log_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        result = subprocess.run([SCRIPT], cwd="/home/user", capture_output=True, text=True, timeout=120)
        assert result.returncode == 0, f"run_eval.sh failed with the probe: {result.stderr}"
        assert os.path.isfile(log_path), "run_eval.sh never executed train_and_plot.py."
        with open(log_path, "r", encoding="utf-8") as f:
            calls = [int(line.strip()) for line in f if line.strip()]
        assert calls == list(range(1, 31)), \
            f"Expected exactly seeds 1 through 30 in order, but observed {calls}"
        values = [0.55 + ((seed * 17) % 41) / 100.0 for seed in range(1, 31)]
        load_and_check_metrics(expected_metrics(values))
    finally:
        if os.path.exists(backup):
            os.replace(backup, TRAIN)
        try:
            os.remove(log_path)
        except FileNotFoundError:
            pass


def test_real_pipeline_and_final_outputs():
    for path in (METRICS, PLOT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run([SCRIPT], cwd="/home/user", capture_output=True, text=True, timeout=240)
    assert result.returncode == 0, f"run_eval.sh failed: {result.stderr}"

    values = [expected_accuracy(seed) for seed in range(1, 31)]
    load_and_check_metrics(expected_metrics(values))
    assert_real_png(PLOT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
exit 0
