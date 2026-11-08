#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile
import uuid

import cv2
import numpy as np
import pytest

HOME = "/home/user"
VIDEO = "/app/dashboard_recording.mp4"


def assert_executable(path):
    assert os.path.isfile(path), f"Missing script: {path}"
    mode = os.stat(path).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), f"Script is not executable: {path}"


def decoded_alert_count(path):
    cap = cv2.VideoCapture(path)
    assert cap.isOpened(), f"Could not open video: {path}"
    count = 0
    frames = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames += 1
        assert frame.shape[0] >= 100 and frame.shape[1] >= 100
        region = frame[0:100, frame.shape[1] - 100:frame.shape[1]]
        b, g, r = region.mean(axis=(0, 1))
        if r > 150 and g < 50 and b < 50:
            count += 1
    cap.release()
    assert frames > 0, f"No frames decoded from {path}"
    return count


def run_integer_script(path):
    result = subprocess.run(["python3", path], text=True, capture_output=True, timeout=60)
    assert result.returncode == 0, result.stderr
    output = result.stdout.strip()
    assert re.fullmatch(r"[0-9]+", output), f"Expected one integer on stdout, got {result.stdout!r}"
    return int(output)


def test_required_scripts_exist_and_are_executable():
    for name in ("setup_pipeline.sh", "filter_logs.py", "analyze_video.py", "run_pipeline.sh"):
        assert_executable(os.path.join(HOME, name))


def test_setup_is_idempotent_and_creates_directories():
    setup = os.path.join(HOME, "setup_pipeline.sh")
    for _ in range(2):
        result = subprocess.run([setup], text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, result.stderr

    expected_dirs = [
        "/home/user/pipeline/logs/incoming",
        "/home/user/pipeline/logs/processed",
        "/home/user/pipeline/video_frames",
    ]
    for directory in expected_dirs:
        assert os.path.isdir(directory), f"Expected directory {directory} was not created."


def test_filter_logs_adversarial_corpus():
    script_path = "/home/user/filter_logs.py"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"

    clean_corpus = "/app/corpus/clean"
    evil_corpus = "/app/corpus/evil"

    with tempfile.TemporaryDirectory() as clean_out, tempfile.TemporaryDirectory() as evil_out:
        clean_run = subprocess.run(["python3", script_path, clean_corpus, clean_out], capture_output=True, text=True)
        evil_run = subprocess.run(["python3", script_path, evil_corpus, evil_out], capture_output=True, text=True)
        assert clean_run.returncode == 0, clean_run.stderr
        assert evil_run.returncode == 0, evil_run.stderr

        clean_input_files = set(os.listdir(clean_corpus))
        clean_output_files = set(os.listdir(clean_out))
        evil_input_files = set(os.listdir(evil_corpus))
        evil_output_files = set(os.listdir(evil_out))

        missing_clean = clean_input_files - clean_output_files
        bypassed_evil = evil_output_files

        errors = []
        if missing_clean:
            errors.append(f"{len(missing_clean)} of {len(clean_input_files)} clean modified/rejected: {', '.join(missing_clean)}")
        if bypassed_evil:
            errors.append(f"{len(bypassed_evil)} of {len(evil_input_files)} evil bypassed: {', '.join(bypassed_evil)}")
        if errors:
            pytest.fail(" | ".join(errors))


def make_random_corpus(directory):
    token = uuid.uuid4().hex
    valid = {
        f"{token}_zero.json": {"timestamp": token, "service_name": "api-safe", "cpu_usage": 0},
        f"{token}_hundred.json": {"timestamp": token, "service_name": "worker_01", "cpu_usage": 100},
        f"{token}_float.json": {"timestamp": token, "service_name": "db backend", "cpu_usage": 37.25},
    }
    invalid = {
        f"{token}_low.json": {"timestamp": token, "service_name": "safe", "cpu_usage": -0.5},
        f"{token}_high.json": {"timestamp": token, "service_name": "safe", "cpu_usage": 100.5},
        f"{token}_string.json": {"timestamp": token, "service_name": "safe", "cpu_usage": "42"},
        f"{token}_missing.json": {"timestamp": token, "service_name": "safe"},
        f"{token}_nonstring.json": {"timestamp": token, "service_name": 123, "cpu_usage": 20},
    }
    for index, char in enumerate("<>|&;$"):
        invalid[f"{token}_injection_{index}.json"] = {
            "timestamp": token,
            "service_name": f"safe{char}bad",
            "cpu_usage": random.randint(1, 99),
        }

    os.makedirs(directory, exist_ok=True)
    contents = {}
    for name, value in {**valid, **invalid}.items():
        data = json.dumps(value, separators=(",", ":")) + "\n"
        with open(os.path.join(directory, name), "w") as handle:
            handle.write(data)
        if name in valid:
            contents[name] = data

    with open(os.path.join(directory, f"{token}_broken.json"), "w") as handle:
        handle.write("{ definitely not json")
    with open(os.path.join(directory, f"{token}_ignored.txt"), "w") as handle:
        json.dump(next(iter(valid.values())), handle)
    return contents


def assert_exact_outputs(output_dir, expected):
    actual = set(os.listdir(output_dir))
    assert actual == set(expected), f"Expected output files {set(expected)}, got {actual}"
    for name, original_content in expected.items():
        path = os.path.join(output_dir, name)
        assert os.path.isfile(path)
        with open(path) as handle:
            assert handle.read() == original_content, f"{name} was not copied unchanged"


def test_filter_logs_on_unpredictable_mixed_input():
    script = os.path.join(HOME, "filter_logs.py")
    with tempfile.TemporaryDirectory(prefix="unclassified_input_") as source, tempfile.TemporaryDirectory() as output:
        expected = make_random_corpus(source)
        result = subprocess.run(["python3", script, source, output], text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, result.stderr
        assert_exact_outputs(output, expected)


def test_analyze_video_executes_and_handles_unpredictable_video():
    script = os.path.join(HOME, "analyze_video.py")
    original_expected = decoded_alert_count(VIDEO)
    assert original_expected == 27
    assert run_integer_script(script) == original_expected

    backup = f"{VIDEO}.verifier_backup_{uuid.uuid4().hex}"
    replacement = f"{VIDEO}.verifier_new_{uuid.uuid4().hex}.mp4"
    os.rename(VIDEO, backup)
    try:
        writer = cv2.VideoWriter(replacement, cv2.VideoWriter_fourcc(*"mp4v"), 10, (200, 200))
        assert writer.isOpened()
        flash_count = random.randint(4, 18)
        flags = [True] * flash_count + [False] * (31 - flash_count)
        random.shuffle(flags)
        for is_flash in flags:
            frame = np.zeros((200, 200, 3), dtype=np.uint8)
            if is_flash:
                frame[0:100, 100:200] = [5, 8, random.randint(190, 240)]
            else:
                frame[0:100, 100:200] = [random.randint(55, 100), 10, 230]
            writer.write(frame)
        writer.release()
        os.rename(replacement, VIDEO)

        expected = decoded_alert_count(VIDEO)
        assert expected == flash_count
        assert run_integer_script(script) == expected
    finally:
        if os.path.exists(VIDEO):
            os.remove(VIDEO)
        if os.path.exists(replacement):
            os.remove(replacement)
        os.rename(backup, VIDEO)


def test_master_pipeline_runs_all_components_on_mixed_input():
    mixed = "/app/corpus/mixed_logs"
    mixed_backup = f"{mixed}.verifier_backup_{uuid.uuid4().hex}"
    processed = "/home/user/pipeline/logs/processed"
    marker_dir = tempfile.mkdtemp(prefix="pipeline_markers_")
    suffix = f".verifier_original_{uuid.uuid4().hex}"
    component_names = ("setup_pipeline.sh", "filter_logs.py", "analyze_video.py")
    backups = {}

    os.rename(mixed, mixed_backup)
    os.makedirs(mixed)
    expected_logs = make_random_corpus(mixed)
    shutil.rmtree(processed, ignore_errors=True)

    try:
        for name in component_names:
            path = os.path.join(HOME, name)
            backup = path + suffix
            os.rename(path, backup)
            backups[path] = backup

        setup_path = os.path.join(HOME, "setup_pipeline.sh")
        with open(setup_path, "w") as handle:
            handle.write(f"#!/bin/bash\ntouch {marker_dir}/setup\nexec {backups[setup_path]} \"$@\"\n")
        os.chmod(setup_path, 0o755)

        filter_path = os.path.join(HOME, "filter_logs.py")
        with open(filter_path, "w") as handle:
            handle.write("#!/usr/bin/env python3\nimport os, runpy, sys\n")
            handle.write(f"open({marker_dir!r} + '/filter', 'w').write('\\n'.join(sys.argv[1:]))\n")
            handle.write(f"runpy.run_path({backups[filter_path]!r}, run_name='__main__')\n")
        os.chmod(filter_path, 0o755)

        analyze_path = os.path.join(HOME, "analyze_video.py")
        with open(analyze_path, "w") as handle:
            handle.write("#!/usr/bin/env python3\nimport runpy\n")
            handle.write(f"open({marker_dir!r} + '/analyze', 'w').write('called')\n")
            handle.write(f"runpy.run_path({backups[analyze_path]!r}, run_name='__main__')\n")
        os.chmod(analyze_path, 0o755)

        master = os.path.join(HOME, "run_pipeline.sh")
        result = subprocess.run([master], text=True, capture_output=True, timeout=120)
        assert result.returncode == 0, f"stdout={result.stdout}\nstderr={result.stderr}"

        assert os.path.isfile(os.path.join(marker_dir, "setup")), "run_pipeline.sh did not run setup_pipeline.sh"
        assert os.path.isfile(os.path.join(marker_dir, "filter")), "run_pipeline.sh did not run filter_logs.py"
        assert os.path.isfile(os.path.join(marker_dir, "analyze")), "run_pipeline.sh did not run analyze_video.py"
        with open(os.path.join(marker_dir, "filter")) as handle:
            args = handle.read().splitlines()
        assert args == ["/app/corpus/mixed_logs/", "/home/user/pipeline/logs/processed/"], f"Wrong filter arguments: {args}"

        assert_exact_outputs(processed, expected_logs)
        count_file = "/home/user/pipeline/video_alert_count.txt"
        assert os.path.isfile(count_file), f"Missing video alert count file: {count_file}"
        with open(count_file) as handle:
            content = handle.read().strip()
        expected_video_count = decoded_alert_count(VIDEO)
        assert content == str(expected_video_count)
        assert content == "27", f"Expected video alert count to be '27', but got '{content}'"
    finally:
        for path, backup in backups.items():
            if os.path.exists(path):
                os.remove(path)
            if os.path.exists(backup):
                os.rename(backup, path)
        shutil.rmtree(marker_dir, ignore_errors=True)
        shutil.rmtree(mixed, ignore_errors=True)
        if os.path.exists(mixed_backup):
            os.rename(mixed_backup, mixed)


def test_pipeline_directories_created():
    expected_dirs = [
        "/home/user/pipeline/logs/incoming",
        "/home/user/pipeline/logs/processed",
        "/home/user/pipeline/video_frames",
    ]
    for directory in expected_dirs:
        assert os.path.isdir(directory), f"Expected directory {directory} was not created."


def test_video_alert_count():
    count_file = "/home/user/pipeline/video_alert_count.txt"
    assert os.path.isfile(count_file), f"Missing video alert count file: {count_file}"
    with open(count_file) as handle:
        content = handle.read().strip()
    assert content == "27", f"Expected video alert count to be '27', but got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
