#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import csv
import shutil

FRAMES_DIR = "/home/user/experiment_artifacts/frames"
REFERENCE_DIR = "/tmp/verifier_reference_frames"


def ensure_reference_frames():
    if os.path.isdir(REFERENCE_DIR) and all(
        os.path.isfile(f"{REFERENCE_DIR}/frame_{i:02d}.pgm") for i in range(1, 21)
    ):
        return

    shutil.rmtree(REFERENCE_DIR, ignore_errors=True)
    os.makedirs(REFERENCE_DIR)
    result = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y",
            "-i", "/app/sensor_feed.mp4",
            "-vf", "fps=1,format=gray",
            "-frames:v", "20",
            "-start_number", "1",
            f"{REFERENCE_DIR}/frame_%02d.pgm",
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Failed to decode reference video: {result.stderr}"
    for i in range(1, 21):
        assert os.path.isfile(f"{REFERENCE_DIR}/frame_{i:02d}.pgm"), "Reference extraction failed"


def read_pgm(filepath):
    with open(filepath, "rb") as f:
        header = f.readline().decode("ascii").strip()
        assert header == "P5", f"Expected P5 PGM, got {header}"

        while True:
            pos = f.tell()
            line = f.readline()
            assert line, f"Malformed PGM: {filepath}"
            if not line.startswith(b"#"):
                f.seek(pos)
                break

        dims = f.readline().decode("ascii").split()
        assert len(dims) == 2, f"Malformed PGM dimensions: {filepath}"
        width, height = int(dims[0]), int(dims[1])
        maxval = int(f.readline().decode("ascii").strip())
        data = f.read()

    assert maxval == 255, f"Expected 8-bit grayscale PGM, got maxval {maxval}"
    assert len(data) == width * height, f"Incorrect pixel data length in {filepath}"
    return width, height, maxval, data


def test_directories_exist():
    assert os.path.isdir(FRAMES_DIR), "Frames directory missing"
    assert os.path.isdir("/home/user/scripts"), "Scripts directory missing"


def test_frames_extracted():
    ensure_reference_frames()
    for i in range(1, 21):
        frame_path = f"{FRAMES_DIR}/frame_{i:02d}.pgm"
        reference_path = f"{REFERENCE_DIR}/frame_{i:02d}.pgm"
        assert os.path.isfile(frame_path), f"Missing frame {frame_path}"

        width, height, maxval, data = read_pgm(frame_path)
        ref_width, ref_height, ref_maxval, ref_data = read_pgm(reference_path)
        assert (width, height, maxval) == (ref_width, ref_height, ref_maxval), \
            f"Frame {i} has incorrect dimensions or grayscale depth"
        assert data == ref_data, \
            f"Frame {i} does not match the corresponding frame extracted from sensor_feed.mp4"


def read_pgm_block_avg(filepath, x, y, w, h):
    width, height, _, data = read_pgm(filepath)
    assert 0 <= x and 0 <= y and x + w <= width and y + h <= height

    sum_val = 0
    for row in range(y, y + h):
        for col in range(x, x + w):
            sum_val += data[row * width + col]

    return sum_val / (w * h)


def test_sensor_data_csv():
    ensure_reference_frames()
    csv_path = "/home/user/experiment_artifacts/sensor_data.csv"
    assert os.path.isfile(csv_path), "sensor_data.csv missing"

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 21, f"Expected 21 rows in CSV, got {len(rows)}"
    assert rows[0] == ["frame", "sensor_x", "sensor_y"], "Incorrect CSV header"

    for i in range(1, 21):
        assert len(rows[i]) == 3, f"Expected 3 columns in CSV row {i}"
        frame_id = rows[i][0]
        assert f"frame_{i:02d}" in frame_id, f"Unexpected frame ID {frame_id} in row {i}"

        frame_path = f"{FRAMES_DIR}/frame_{i:02d}.pgm"
        width, height, _, _ = read_pgm(frame_path)

        expected_x = read_pgm_block_avg(frame_path, 0, 0, 50, 50)
        expected_y = read_pgm_block_avg(frame_path, width - 50, height - 50, 50, 50)

        val_x = float(rows[i][1])
        val_y = float(rows[i][2])

        assert abs(val_x - expected_x) < 1.0, \
            f"Row {i} sensor_x mismatch: expected {expected_x}, got {val_x}"
        assert abs(val_y - expected_y) < 1.0, \
            f"Row {i} sensor_y mismatch: expected {expected_y}, got {val_y}"


def test_calc_cov_fuzz_equivalence():
    agent_script = "/home/user/scripts/calc_cov.sh"
    oracle_script = "/tests/oracle_calc_cov.sh"

    assert os.path.isfile(agent_script), f"Missing {agent_script}"
    assert os.access(agent_script, os.X_OK), f"{agent_script} is not executable"
    assert os.path.isfile(oracle_script), "Verification oracle missing"

    random.seed(42)

    for _ in range(200):
        k = random.randint(5, 50)
        args = [str(random.randint(0, 255)) for _ in range(2 * k)]

        oracle_cmd = ["bash", oracle_script] + args
        agent_cmd = ["bash", agent_script] + args

        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

        assert oracle_res.returncode == 0, f"Oracle failed on args: {' '.join(args)}"
        assert agent_res.returncode == 0, f"Agent script failed on args: {' '.join(args)}"

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, \
            f"Mismatch on args: {' '.join(args)}\nExpected: {oracle_out}\nGot: {agent_out}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
