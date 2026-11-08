#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess


def test_hasher_executable_exists():
    assert os.path.isfile("/home/user/hasher"), "/home/user/hasher does not exist."
    assert os.access("/home/user/hasher", os.X_OK), "/home/user/hasher is not executable."


def test_process_script_exists():
    assert os.path.isfile("/home/user/process.sh"), "/home/user/process.sh does not exist."
    assert os.access("/home/user/process.sh", os.X_OK), "/home/user/process.sh is not executable."


def expected_output(frame_num):
    ffmpeg_res = subprocess.run(
        [
            "ffmpeg", "-loglevel", "error", "-i", "/app/source.mp4",
            "-vf", f"select=eq(n\\,{frame_num})",
            "-vframes", "1", "-f", "image2pipe", "-vcodec", "rawvideo",
            "-pix_fmt", "rgb24", "-",
        ],
        capture_output=True,
    )
    assert ffmpeg_res.returncode == 0, (
        f"Reference frame extraction failed for frame {frame_num}:\n"
        f"{ffmpeg_res.stderr.decode(errors='replace')}"
    )
    return format(sum(ffmpeg_res.stdout), "x")


def test_fuzz_equivalence():
    random.seed(42)
    agent_path = "/home/user/process.sh"

    for _ in range(20):
        frame_num = random.randint(0, 100)
        url = f"http://localhost/api/frame?number={frame_num}"
        expected = expected_output(frame_num)

        agent_res = subprocess.run([agent_path, url], capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on {url}:\n{agent_res.stderr}"

        agent_out = agent_res.stdout.strip()
        assert expected == agent_out, (
            f"Mismatch on input: {url}\n"
            f"Expected: {expected}\n"
            f"Got: {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
