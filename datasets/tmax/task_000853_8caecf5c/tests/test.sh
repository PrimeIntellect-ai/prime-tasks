#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import random
import subprocess
import tempfile


def test_raw_features_csv():
    csv_path = "/home/user/raw_features.csv"
    assert os.path.isfile(csv_path), f"{csv_path} does not exist."

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 15, f"Expected exactly 15 lines in {csv_path}, found {len(lines)}."

    parsed_rows = []
    for i, line in enumerate(lines, start=1):
        match = re.match(r"^(\d{4}),(\d+)$", line)
        assert match, f"Line {i} in {csv_path} is not formatted correctly: {line}"
        frame_num_str, size_str = match.groups()
        expected_frame_num = f"{i:04d}"
        assert frame_num_str == expected_frame_num, f"Expected frame number {expected_frame_num}, got {frame_num_str} on line {i}."
        assert int(size_str) > 0, f"Expected positive size on line {i}, got {size_str}."
        parsed_rows.append((frame_num_str, int(size_str)))

    # Independently extract the source video's frames at exactly 1 fps and verify
    # that the submitted CSV contains the actual JPEG file sizes.
    with tempfile.TemporaryDirectory() as tmpdir:
        output_pattern = os.path.join(tmpdir, "frame_%04d.jpg")
        proc = subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", "/app/dashcam.mp4", "-vf", "fps=1", output_pattern,
            ],
            capture_output=True,
            text=True,
        )
        assert proc.returncode == 0, f"Reference frame extraction failed: {proc.stderr}"

        frame_files = sorted(
            name for name in os.listdir(tmpdir)
            if re.match(r"^frame_\d{4}\.jpg$", name)
        )
        assert len(frame_files) == 15, f"Expected ffmpeg to extract 15 frames, got {len(frame_files)}."

        expected_rows = [
            (f"{i:04d}", os.path.getsize(os.path.join(tmpdir, filename)))
            for i, filename in enumerate(frame_files, start=1)
        ]
        assert parsed_rows == expected_rows, (
            "raw_features.csv does not contain the JPEG sizes of frames "
            "extracted from /app/dashcam.mp4 at 1 fps."
        )


def test_center_features_fuzz():
    agent_script = "/home/user/center_features.sh"
    oracle_script = "/opt/verifier/oracle_center_features.sh"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."
    assert os.access(oracle_script, os.X_OK), f"Oracle script {oracle_script} is not executable."

    random.seed(42)
    num_tests = 20

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(num_tests):
            n = random.randint(1, 100)
            num_rows = random.randint(n, 500)

            csv_path = os.path.join(tmpdir, f"test_{i}.csv")
            with open(csv_path, "w") as f:
                for row_idx in range(1, num_rows + 1):
                    frame_num = f"{row_idx:04d}"
                    size = random.randint(10000, 500000)
                    f.write(f"{frame_num},{size}\n")

            # Run oracle
            oracle_cmd = [oracle_script, csv_path, str(n)]
            oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert oracle_proc.returncode == 0, f"Oracle failed on test {i}."
            oracle_out = oracle_proc.stdout.strip()

            # Run agent
            agent_cmd = [agent_script, csv_path, str(n)]
            agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)
            assert agent_proc.returncode == 0, f"Agent script failed on test {i} with error: {agent_proc.stderr}"
            agent_out = agent_proc.stdout.strip()

            if oracle_out != agent_out:
                # Show first diff line
                oracle_lines = oracle_out.splitlines()
                agent_lines = agent_out.splitlines()
                diff_msg = f"Output mismatch on test {i} (N={n}, rows={num_rows}).\n"
                for j, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
                    if o_line != a_line:
                        diff_msg += f"Line {j+1}:\nOracle: {o_line}\nAgent : {a_line}\n"
                        break
                if len(oracle_lines) != len(agent_lines):
                    diff_msg += f"Line counts differ: Oracle={len(oracle_lines)}, Agent={len(agent_lines)}.\n"
                assert False, diff_msg
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
