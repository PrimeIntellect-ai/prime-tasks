#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import tempfile

ORACLE_BIN = "/tests/oracle_hasher"


def test_frames_extracted():
    """Check that the numbered frames exactly match ffmpeg extraction from the supplied video."""
    frames_dir = "/home/user/frames"
    assert os.path.isdir(frames_dir), f"Frames directory missing: {frames_dir}"

    files = [f for f in os.listdir(frames_dir) if f.startswith("frame_") and f.endswith(".bin")]
    assert len(files) >= 2, "At least two frames should have been extracted."

    for name in files:
        path = os.path.join(frames_dir, name)
        assert os.path.getsize(path) == 4096, f"Frame {name} is not exactly 4096 bytes."

    proc = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", "/app/input_video.mp4",
            "-vf", "fps=1,scale=64:64,format=gray",
            "-f", "rawvideo", "-pix_fmt", "gray", "-"
        ],
        capture_output=True,
    )
    assert proc.returncode == 0, f"Could not derive expected frames: {proc.stderr.decode(errors='replace')}"
    assert len(proc.stdout) % 4096 == 0, "Reference extraction produced incomplete frame data."

    expected_frames = [proc.stdout[i:i + 4096] for i in range(0, len(proc.stdout), 4096)]
    expected_names = [f"frame_{i:03d}.bin" for i in range(1, len(expected_frames) + 1)]
    assert sorted(files) == expected_names, "Frame filenames/count do not match extraction at exactly 1 fps."

    for name, expected in zip(expected_names, expected_frames):
        with open(os.path.join(frames_dir, name), "rb") as f:
            actual = f.read()
        assert actual == expected, f"{name} does not match the required ffmpeg extraction and transformation."


def test_fuzz_equivalence():
    """Compile the submitted source and compare both submitted artifacts with the protected oracle."""
    agent_source = "/home/user/frame_hasher.c"
    agent_bin = "/home/user/frame_hasher"

    assert os.path.isfile(agent_source), f"Agent source missing: {agent_source}"
    assert os.path.isfile(agent_bin), f"Agent binary missing: {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary not executable: {agent_bin}"
    assert os.path.isfile(ORACLE_BIN), f"Oracle binary missing: {ORACLE_BIN}"
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle binary not executable: {ORACLE_BIN}"

    with open(agent_bin, "rb") as f:
        agent_bytes = f.read()
    with open(ORACLE_BIN, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Submitted executable must not be a byte-for-byte copy of the oracle."

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        compiled_bin = os.path.join(tmpdir, "compiled_frame_hasher")
        compile_proc = subprocess.run(
            ["gcc", "-O2", agent_source, "-o", compiled_bin],
            capture_output=True,
            text=True,
        )
        assert compile_proc.returncode == 0, f"Submitted C source does not compile:\n{compile_proc.stderr}"

        file1 = os.path.join(tmpdir, "input1.bin")
        file2 = os.path.join(tmpdir, "input2.bin")

        for i in range(500):
            data1 = bytes([random.randint(0, 255) for _ in range(4096)])
            data2 = bytes([random.randint(0, 255) for _ in range(4096)])

            with open(file1, "wb") as f1, open(file2, "wb") as f2:
                f1.write(data1)
                f2.write(data2)

            oracle_proc = subprocess.run([ORACLE_BIN, file1, file2], capture_output=True, text=True)
            agent_proc = subprocess.run([agent_bin, file1, file2], capture_output=True, text=True)
            source_proc = subprocess.run([compiled_bin, file1, file2], capture_output=True, text=True)

            assert agent_proc.returncode == oracle_proc.returncode, f"Return code mismatch on iteration {i}"
            assert agent_proc.stdout == oracle_proc.stdout, (
                f"Output mismatch on iteration {i}.\nOracle:\n{oracle_proc.stdout}\nAgent:\n{agent_proc.stdout}"
            )
            assert source_proc.returncode == oracle_proc.returncode, f"Compiled source return code mismatch on iteration {i}"
            assert source_proc.stdout == oracle_proc.stdout, (
                f"Compiled source output mismatch on iteration {i}.\n"
                f"Oracle:\n{oracle_proc.stdout}\nCompiled source:\n{source_proc.stdout}"
            )


def test_sample_output():
    """Check sample_output.txt against the oracle for the first two extracted frames."""
    sample_out = "/home/user/sample_output.txt"
    assert os.path.isfile(sample_out), f"Sample output missing: {sample_out}"

    frame1 = "/home/user/frames/frame_001.bin"
    frame2 = "/home/user/frames/frame_002.bin"
    assert os.path.isfile(frame1), f"Missing {frame1}"
    assert os.path.isfile(frame2), f"Missing {frame2}"

    oracle_proc = subprocess.run([ORACLE_BIN, frame1, frame2], capture_output=True, text=True)
    assert oracle_proc.returncode == 0, "Oracle failed on the extracted frames."

    with open(sample_out, "r") as f:
        student_out = f.read()

    assert student_out.strip() == oracle_proc.stdout.strip(), "Sample output content does not match expected oracle output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
