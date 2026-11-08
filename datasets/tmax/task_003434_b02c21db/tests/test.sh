#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import tempfile
import json
import shutil
import pytest

def generate_random_video(path, duration):
    cmd = [
        "ffmpeg", "-y", "-f", "lavfi",
        "-i", f"testsrc=duration={duration}:rate=24",
        "-pix_fmt", "yuv420p", path
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

def generate_random_archive(path, encoding):
    with tempfile.TemporaryDirectory() as tmpdir:
        meta_path = os.path.join(tmpdir, "meta.json")
        with open(meta_path, "w") as f:
            json.dump({"encoding": encoding}, f)

        logs_dir = os.path.join(tmpdir, "logs")
        os.makedirs(logs_dir)

        num_logs = random.randint(2, 8)
        for _ in range(num_logs):
            name_len = random.randint(4, 8)
            name = "".join(random.choices(string.ascii_lowercase + string.digits, k=name_len)) + ".log"
            content_len = random.randint(20, 200)
            content = "".join(random.choices(string.ascii_letters + string.digits + " \n.,!?", k=content_len))

            log_path = os.path.join(logs_dir, name)
            with open(log_path, "wb") as f:
                f.write(content.encode(encoding))

        data_zip_path = os.path.join(tmpdir, "data.zip")
        # shutil.make_archive adds the extension automatically, so we strip it from the path
        shutil.make_archive(data_zip_path[:-4], 'zip', logs_dir)

        cmd = ["tar", "-czf", path, "-C", tmpdir, "meta.json", "data.zip"]
        subprocess.run(cmd, check=True)

def test_fuzz_equivalence():
    agent_prog = "/home/user/process_backup"
    oracle_prog = "/tests/process_backup_oracle"

    assert os.path.exists(agent_prog), f"Agent program missing at {agent_prog}"
    assert os.access(agent_prog, os.X_OK), f"Agent program at {agent_prog} is not executable"

    random.seed(1337)
    encodings = ['UTF-16LE', 'ISO-8859-1', 'WINDOWS-1252', 'MACINTOSH', 'UTF-8']

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(15):
            video_path = os.path.join(tmpdir, f"video_{i}.mp4")
            archive_path = os.path.join(tmpdir, f"archive_{i}.tar.gz")

            duration = round(random.uniform(0.5, 5.0), 2)
            generate_random_video(video_path, duration)

            encoding = random.choice(encodings)
            generate_random_archive(archive_path, encoding)

            oracle_proc = subprocess.run([oracle_prog, archive_path, video_path], capture_output=True, text=True)
            agent_proc = subprocess.run([agent_prog, archive_path, video_path], capture_output=True, text=True)

            assert agent_proc.returncode == oracle_proc.returncode, (
                f"Return code mismatch on iteration {i} (encoding={encoding}, duration={duration}).\n"
                f"Oracle exit code: {oracle_proc.returncode}\n"
                f"Agent exit code: {agent_proc.returncode}\n"
                f"Agent stderr:\n{agent_proc.stderr}"
            )

            if agent_proc.stdout != oracle_proc.stdout:
                pytest.fail(
                    f"Output mismatch on iteration {i} (encoding={encoding}, duration={duration}).\n"
                    f"Oracle output (length {len(oracle_proc.stdout)}):\n{oracle_proc.stdout}\n"
                    f"---\n"
                    f"Agent output (length {len(agent_proc.stdout)}):\n{agent_proc.stdout}\n"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
