#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess
import tempfile

import cv2


def run_detector(script_path, candidate):
    try:
        return subprocess.run(
            ["bash", script_path, candidate],
            capture_output=True,
            timeout=10,
        ).returncode
    except subprocess.TimeoutExpired:
        return None


def test_restart_count():
    count_file = "/home/user/restart_count.txt"
    video_file = "/app/telemetry.mp4"
    assert os.path.isfile(count_file), f"Restart count file is missing at {count_file}"
    assert os.path.isfile(video_file), f"Telemetry video is missing at {video_file}"

    with open(count_file, "r") as f:
        content = f.read().strip()

    capture = cv2.VideoCapture(video_file)
    assert capture.isOpened(), f"Could not open telemetry video at {video_file}"

    expected = 0
    frames_seen = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        frames_seen += 1
        blue = float(frame[:, :, 0].mean())
        green = float(frame[:, :, 1].mean())
        red = float(frame[:, :, 2].mean())
        if red > 250 and green < 10 and blue < 10:
            expected += 1
    capture.release()

    assert frames_seen > 0, "Telemetry video contained no readable frames"
    assert content == str(expected), (
        f"Expected restart count to be '{expected}', but got '{content}'"
    )


def test_check_leakage_script_exists_and_executable():
    script_path = "/home/user/check_leakage.sh"
    assert os.path.isfile(script_path), f"Leakage detector script is missing at {script_path}"


def test_existing_adversarial_corpus():
    script_path = "/home/user/check_leakage.sh"
    assert os.path.isfile(script_path), f"Leakage detector script is missing at {script_path}"

    evil_files = glob.glob("/app/corpora/evil/*.py")
    clean_files = glob.glob("/app/corpora/clean/*.py")
    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = [
        os.path.basename(path) for path in evil_files
        if run_detector(script_path, path) != 1
    ]
    clean_modified = [
        os.path.basename(path) for path in clean_files
        if run_detector(script_path, path) != 0
    ]

    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_bypassed)
        )
    if clean_modified:
        errors.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): "
            + ", ".join(clean_modified)
        )
    assert not errors, " | ".join(errors)


def identifier(prefix):
    return prefix + secrets.token_hex(6)


def make_case(leaking):
    data = identifier("dataset_")
    target = identifier("target_")
    scaler = identifier("scaler_")
    train = identifier("train_")
    test = identifier("test_")
    ytrain = identifier("ytrain_")
    ytest = identifier("ytest_")
    scaled = identifier("scaled_")
    method = random.choice(["fit", "fit_transform"])
    gap1 = "\n" * random.randint(1, 3)
    gap2 = "\n" * random.randint(1, 3)

    header = (
        "from sklearn.preprocessing import StandardScaler\n"
        "from sklearn.model_selection import train_test_split\n"
        f"{scaler} = StandardScaler()\n"
        f"{data} = source_features\n"
        f"{target} = source_labels\n"
    )

    split = (
        f"{train}, {test}, {ytrain}, {ytest} = train_test_split(\n"
        f"    {data}, {target}, test_size=0.25\n"
        ")\n"
    )
    if method == "fit_transform":
        fit_full = f"{scaled} = {scaler}.fit_transform({data})\n"
        fit_train = f"{scaled} = {scaler}.fit_transform({train})\n"
    else:
        fit_full = f"{scaler}.fit({data})\n"
        fit_train = f"{scaler}.fit({train})\n"

    if leaking:
        return header + gap1 + fit_full + gap2 + split
    return header + gap1 + split + gap2 + fit_train


def test_randomized_adversarial_corpus():
    script_path = "/home/user/check_leakage.sh"
    assert os.path.isfile(script_path), f"Leakage detector script is missing at {script_path}"

    cases = [(make_case(True), 1) for _ in range(32)]
    cases += [(make_case(False), 0) for _ in range(32)]
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="pipeline_checks_") as corpus:
        for index, (source, expected) in enumerate(cases):
            filename = secrets.token_hex(12) + ".py"
            path = os.path.join(corpus, filename)
            with open(path, "w") as handle:
                handle.write(source)
            actual = run_detector(script_path, path)
            if actual != expected:
                failures.append(
                    f"case {index}: expected exit {expected}, got {actual}"
                )

    assert not failures, (
        f"Detector failed {len(failures)} of {len(cases)} randomized cases: "
        + "; ".join(failures[:10])
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
