#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import math
import os
import random
import re
import shutil
import subprocess
import time

import requests

VIDEO = "/app/dashcam.mp4"
PIPELINE = "/home/user/pipeline.sh"
EXPERIMENTS = "/home/user/experiments"
TOKEN = {"Authorization": "Bearer mlops-track-99"}
_rng = random.SystemRandom()
_brightnesses = None


def get_frame_brightnesses(video_path=VIDEO):
    global _brightnesses
    if _brightnesses is not None:
        return _brightnesses

    frame_dir = f"/tmp/test_frames_{os.getpid()}"
    shutil.rmtree(frame_dir, ignore_errors=True)
    os.makedirs(frame_dir)
    subprocess.run([
        "ffmpeg", "-y", "-i", video_path, "-vf", "fps=1",
        os.path.join(frame_dir, "frame_%04d.jpg")
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

    frames = sorted(glob.glob(os.path.join(frame_dir, "*.jpg")))
    assert frames, "ffmpeg extracted no frames from the supplied video"
    values = []
    for frame in frames:
        result = subprocess.run([
            "convert", frame, "-colorspace", "gray", "-format",
            "%[fx:mean*255]", "info:"
        ], capture_output=True, text=True, check=True)
        values.append(float(result.stdout.strip()))
    _brightnesses = values
    return values


def expected_trace(prior, threshold, brightnesses):
    probability = prior
    result = []
    for index, brightness in enumerate(brightnesses, 1):
        evidence = 1 if brightness >= threshold else 0
        likelihood_s1, likelihood_s0 = ((0.85, 0.40) if evidence else (0.15, 0.60))
        denominator = likelihood_s1 * probability + likelihood_s0 * (1.0 - probability)
        probability = 0.0 if denominator == 0 else likelihood_s1 * probability / denominator
        result.append((index, brightness, evidence, probability))
    return result


def parse_only_probability(stdout):
    text = stdout.strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", text), \
        f"pipeline stdout must contain only one numeric probability, got {stdout!r}"
    value = float(text)
    assert 0.0 <= value <= 1.0, f"invalid probability {value}"
    return value


def find_run(prior_text, threshold):
    pattern = os.path.join(EXPERIMENTS, f"run_*_prior_{prior_text}_thresh_{threshold}")
    deadline = time.time() + 2
    while time.time() < deadline:
        matches = [path for path in glob.glob(pattern) if os.path.isdir(path)]
        if matches:
            return max(matches, key=os.path.getmtime)
        time.sleep(0.05)
    raise AssertionError(f"No tracking directory matching {pattern}")


def validate_tracking(run_dir, prior, prior_text, threshold, brightnesses):
    config_path = os.path.join(run_dir, "config.txt")
    trace_path = os.path.join(run_dir, "trace.csv")
    assert os.path.isfile(config_path), f"config.txt missing in {run_dir}"
    assert os.path.isfile(trace_path), f"trace.csv missing in {run_dir}"

    config = open(config_path, encoding="utf-8").read()
    lower = config.lower()
    assert "prior" in lower, "config.txt does not identify the prior"
    assert "threshold" in lower or "thresh" in lower, "config.txt does not identify the threshold"
    numbers = [float(x) for x in re.findall(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)", config)]
    assert any(abs(x - prior) < 1e-9 for x in numbers), f"config.txt does not contain prior {prior_text}"
    assert any(abs(x - threshold) < 1e-9 for x in numbers), f"config.txt does not contain threshold {threshold}"

    with open(trace_path, newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    assert len(rows) > 1, "trace.csv should have at least a header and one data row"
    assert "," in open(trace_path, encoding="utf-8").readline(), "trace.csv is not comma-separated"
    assert len(rows) == len(brightnesses) + 1, \
        f"trace.csv has {len(rows)-1} frame rows; expected {len(brightnesses)}"

    header = [cell.strip().lower() for cell in rows[0]]
    assert len(header) >= 4, "trace.csv must have four columns"
    assert "frame" in header[0], "first trace column must identify the frame"
    assert "bright" in header[1], "second trace column must identify brightness"
    assert "evidence" in header[2], "third trace column must identify Evidence"
    assert any(term in header[3] for term in ("posterior", "prob", "p(s=1)")), \
        "fourth trace column must identify the updated probability"

    expected = expected_trace(prior, threshold, brightnesses)
    indices = []
    for row, (index, exp_brightness, exp_evidence, exp_probability) in zip(rows[1:], expected):
        assert len(row) >= 4, f"Malformed trace row: {row}"
        try:
            frame_index = int(row[0].strip())
            brightness = float(row[1].strip())
            evidence = int(row[2].strip())
            probability = float(row[3].strip())
        except ValueError as exc:
            raise AssertionError(f"Non-numeric trace row: {row}") from exc
        indices.append(frame_index)
        assert abs(brightness - exp_brightness) <= 1.0, \
            f"Incorrect brightness in frame {index}: expected {exp_brightness}, got {brightness}"
        assert evidence == exp_evidence, \
            f"Incorrect Evidence in frame {index}: expected {exp_evidence}, got {evidence}"
        assert abs(probability - exp_probability) <= 0.001, \
            f"Incorrect posterior in frame {index}: expected {exp_probability}, got {probability}"
    assert indices in (list(range(len(expected))), list(range(1, len(expected) + 1))), \
        f"Frame indices are not consecutive and ordered: {indices}"


def run_pipeline_case(prior_text, threshold):
    prior = float(prior_text)
    completed = subprocess.run(
        [PIPELINE, prior_text, str(threshold)], capture_output=True, text=True, timeout=60, check=True
    )
    actual = parse_only_probability(completed.stdout)
    brightnesses = get_frame_brightnesses()
    expected = expected_trace(prior, threshold, brightnesses)[-1][3]
    assert abs(actual - expected) < 0.01, f"Expected probability ~{expected}, got {actual}"
    run_dir = find_run(prior_text, threshold)
    validate_tracking(run_dir, prior, prior_text, threshold, brightnesses)


def test_pipeline_script_exists_and_executes_real_work():
    assert os.path.isfile(PIPELINE), "pipeline.sh is missing"
    assert os.access(PIPELINE, os.X_OK), "pipeline.sh is not executable"

    brightnesses = get_frame_brightnesses()
    low_max = max(0, min(255, int(math.floor(min(brightnesses)))))
    high_min = min(255, int(math.floor(max(brightnesses))) + 1)
    low_threshold = _rng.randint(0, low_max)
    high_threshold = _rng.randint(high_min, 255)
    run_pipeline_case(f"{_rng.uniform(0.12, 0.42):.6f}", low_threshold)
    run_pipeline_case(f"{_rng.uniform(0.58, 0.88):.6f}", high_threshold)


def test_inference_service_unauthorized():
    url = "http://localhost:8080/infer?prior=0.5&threshold=100"
    response = requests.get(url, timeout=10)
    assert response.status_code == 401, "Expected 401 Unauthorized without auth header"
    response = requests.get(url, headers={"Authorization": "Bearer wrong-token"}, timeout=10)
    assert response.status_code == 401, "Expected 401 Unauthorized with wrong auth header"


def test_inference_service_success_and_pipeline_invocation():
    brightnesses = get_frame_brightnesses()
    backup = f"/home/user/.pipeline_verifier_original_{os.getpid()}.sh"
    marker = f"/tmp/pipeline_invocations_{os.getpid()}.txt"
    assert not os.path.exists(backup)
    os.replace(PIPELINE, backup)
    wrapper = f'''#!/bin/bash
printf '%s\\t%s\\n' "$1" "$2" >> {marker!r}
exec {backup!r} "$@"
'''
    with open(PIPELINE, "w", encoding="utf-8") as handle:
        handle.write(wrapper)
    os.chmod(PIPELINE, 0o755)

    cases = [("0.5", 100)]
    cases.extend([
        (f"{_rng.uniform(0.15, 0.85):.6f}", _rng.randint(0, 255)),
        (f"{_rng.uniform(0.15, 0.85):.6f}", _rng.randint(0, 255)),
    ])
    try:
        for prior_text, threshold in cases:
            response = requests.get(
                "http://localhost:8080/infer",
                params={"prior": prior_text, "threshold": str(threshold)},
                headers=TOKEN,
                timeout=60,
            )
            assert response.status_code == 200, \
                f"Expected 200 OK, got {response.status_code}. Body: {response.text}"
            data = response.json()
            assert "final_probability" in data, "Response JSON missing 'final_probability' key"
            expected = expected_trace(float(prior_text), threshold, brightnesses)[-1][3]
            assert abs(float(data["final_probability"]) - expected) < 0.01, \
                f"Expected probability ~{expected}, got {data['final_probability']}"
            validate_tracking(
                find_run(prior_text, threshold), float(prior_text), prior_text, threshold, brightnesses
            )

        assert os.path.isfile(marker), "The inference service did not invoke /home/user/pipeline.sh"
        calls = [line.rstrip("\n").split("\t") for line in open(marker, encoding="utf-8")]
        for prior_text, threshold in cases:
            assert [prior_text, str(threshold)] in calls, \
                f"Service did not invoke pipeline.sh with {prior_text} {threshold}"
    finally:
        if os.path.exists(backup):
            os.replace(backup, PIPELINE)
            os.chmod(PIPELINE, 0o755)


def test_experiment_tracking_files():
    run_dirs = glob.glob("/home/user/experiments/run_*")
    assert len(run_dirs) > 0, "No experiment tracking directories found in /home/user/experiments/"
    latest_run = max(run_dirs, key=os.path.getmtime)
    config_path = os.path.join(latest_run, "config.txt")
    trace_path = os.path.join(latest_run, "trace.csv")
    assert os.path.isfile(config_path), f"config.txt missing in {latest_run}"
    assert os.path.isfile(trace_path), f"trace.csv missing in {latest_run}"
    with open(trace_path, "r", encoding="utf-8") as handle:
        lines = handle.readlines()
    assert len(lines) > 1, "trace.csv should have at least a header and one data row"
    assert "," in lines[0], "trace.csv does not appear to be comma-separated"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
