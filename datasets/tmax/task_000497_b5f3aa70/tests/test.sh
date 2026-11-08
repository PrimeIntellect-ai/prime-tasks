#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import subprocess
import sys

import cv2
import numpy as np

INPUT_PATH = "/home/user/network_configs.json"
OUTPUT_PATH = "/home/user/fixed_network.json"
VIDEO_PATH = "/app/dashboard_traffic.mp4"


def derive_affected_users():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open {VIDEO_PATH}"
    red_frames = np.zeros(16, dtype=np.int32)
    frame_count = 0

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_count += 1
        height, width = frame.shape[:2]
        for row in range(4):
            for col in range(4):
                y0, y1 = row * height // 4, (row + 1) * height // 4
                x0, x1 = col * width // 4, (col + 1) * width // 4
                margin_y = max(1, (y1 - y0) // 10)
                margin_x = max(1, (x1 - x0) // 10)
                cell = frame[y0 + margin_y:y1 - margin_y,
                             x0 + margin_x:x1 - margin_x]
                b, g, r = cell.reshape(-1, 3).mean(axis=0)
                if r > 150 and r > 1.5 * g and r > 1.5 * b:
                    red_frames[row * 4 + col] += 1

    cap.release()
    assert frame_count > 0, "Video contained no readable frames"
    return {f"User{i:02d}" for i, count in enumerate(red_frames) if count >= 2}


def find_agent_scripts():
    roots = ["/home", "/app", "/root", "/workspace", "/workspaces", "/project", "/tmp"]
    this_test = os.path.realpath(__file__)
    scripts = []
    seen = set()

    for root in roots:
        if not os.path.isdir(root):
            continue
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [d for d in subdirs if d not in {
                "__pycache__", ".git", ".cache", "site-packages", "dist-packages"
            }]
            for name in files:
                if not name.endswith(".py"):
                    continue
                path = os.path.realpath(os.path.join(directory, name))
                if path == this_test or path in seen:
                    continue
                seen.add(path)
                try:
                    with open(path, "r", encoding="utf-8") as handle:
                        source = handle.read()
                except (OSError, UnicodeError):
                    continue
                scripts.append((path, source.lower()))
    return scripts


def run_script(path, timeout=40):
    return subprocess.run(
        [sys.executable, path],
        cwd=os.path.dirname(path) or "/",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def expected_output(original, affected):
    result = copy.deepcopy(original)
    for user in affected:
        result[user]["subnet"] = "10.1.0.0/24"
    return result


def load_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file is missing at {OUTPUT_PATH}"
    try:
        with open(OUTPUT_PATH, "r") as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"File at {OUTPUT_PATH} is not valid JSON: {exc}")


def assert_original_f1_check(data, affected):
    pred_affected = set()
    for user, config in data.items():
        if isinstance(config, dict) and config.get("subnet") == "10.1.0.0/24":
            pred_affected.add(user)

    tp = len(affected & pred_affected)
    fp = len(pred_affected - affected)
    fn = len(affected - pred_affected)
    f1 = 2 * tp / (2 * tp + fp + fn) if (2 * tp + fp + fn) > 0 else 0.0
    assert f1 >= 0.9, (
        f"F1 score of correctly modified subnets is {f1:.3f}, expected >= 0.9. "
        f"True affected: {affected}, Predicted affected: {pred_affected}"
    )


def test_complete_solution_and_scripts():
    affected = derive_affected_users()

    with open(INPUT_PATH, "r") as handle:
        original = json.load(handle)

    expected_users = {f"User{i:02d}" for i in range(16)}
    assert set(original) == expected_users, "The supplied configuration must contain all 16 users"
    expected = expected_output(original, affected)

    # Preserve the original quantitative assertion, then require the complete file.
    submitted = load_output()
    assert_original_f1_check(submitted, affected)
    assert set(submitted) == expected_users, "fixed_network.json must contain all 16 original users"
    assert submitted == expected, "Affected users must be updated and unaffected users must remain unchanged"

    scripts = find_agent_scripts()
    analyzers = []
    updaters = []
    for path, source in scripts:
        if ("cv2" in source and "numpy" in source and
                "dashboard_traffic.mp4" in source and "videocapture" in source):
            analyzers.append(path)
        if ("json" in source and "network_configs.json" in source and
                "fixed_network.json" in source):
            updaters.append(path)

    assert analyzers, "No Python/OpenCV video-analysis script was found"
    assert updaters, "No Python configuration-update script was found"

    analyzer_path = None
    analyzer_errors = []
    for path in analyzers:
        try:
            result = run_script(path)
        except subprocess.TimeoutExpired:
            analyzer_errors.append(f"{path}: timed out")
            continue
        if result.returncode == 0:
            analyzer_path = path
            break
        analyzer_errors.append(f"{path}: {result.stderr[-500:]}")
    assert analyzer_path is not None, "No video-analysis script ran successfully: " + "; ".join(analyzer_errors)

    # Select an updater by actually running it against the specified input and
    # requiring it to regenerate the complete expected output.
    updater_path = None
    updater_errors = []
    for path in updaters:
        if os.path.realpath(path) == os.path.realpath(analyzer_path):
            continue
        try:
            result = run_script(path)
            produced = load_output() if result.returncode == 0 else None
        except (subprocess.TimeoutExpired, AssertionError) as exc:
            updater_errors.append(f"{path}: {exc}")
            continue
        if result.returncode == 0 and produced == expected:
            updater_path = path
            break
        updater_errors.append(f"{path}: exit={result.returncode}, stderr={result.stderr[-500:]}")

    assert updater_path is not None, (
        "Two distinct working Python scripts are required; no configuration updater "
        "regenerated the complete output. " + "; ".join(updater_errors)
    )

    # Exercise preservation and idempotence with additional per-user data so a
    # script that merely emits the four affected entries cannot pass.
    with open(INPUT_PATH, "rb") as handle:
        original_bytes = handle.read()

    probe = copy.deepcopy(original)
    for index, user in enumerate(sorted(probe)):
        probe[user]["subnet"] = f"172.20.{index}.0/24"
        probe[user]["verifier_preserve"] = {"index": index, "enabled": index % 2 == 0}
    probe_expected = expected_output(probe, affected)

    try:
        with open(INPUT_PATH, "w") as handle:
            json.dump(probe, handle, indent=2)

        first_run = run_script(updater_path)
        assert first_run.returncode == 0, f"Updater failed on a valid configuration: {first_run.stderr}"
        first = load_output()
        assert first == probe_expected, "Updater did not preserve every unaffected user and field"

        second_run = run_script(updater_path)
        assert second_run.returncode == 0, f"Updater failed when run a second time: {second_run.stderr}"
        second = load_output()
        assert second == first, "Configuration updater is not idempotent"
    finally:
        with open(INPUT_PATH, "wb") as handle:
            handle.write(original_bytes)
        run_script(updater_path)

    final_data = load_output()
    assert_original_f1_check(final_data, affected)
    assert final_data == expected, "Updater did not restore the correct complete final configuration"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
