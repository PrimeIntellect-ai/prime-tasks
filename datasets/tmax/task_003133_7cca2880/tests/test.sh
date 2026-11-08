#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import time
import subprocess
import numpy as np
from PIL import Image
from scapy.all import rdpcap, TCP


def test_evidence_extraction_performance_and_accuracy():
    script_path = "/home/user/extract_evidence.sh"
    evidence_path = "/home/user/evidence.jpg"

    assert os.path.isfile(script_path), f"Script missing at {script_path}"

    # Remove evidence if it exists to ensure we are testing the script's output.
    if os.path.exists(evidence_path):
        os.remove(evidence_path)

    # Run the script and measure duration before deriving the expected frame, so
    # no expected image is available to the submitted script.
    start_time = time.time()
    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    duration = time.time() - start_time

    assert result.returncode == 0, f"Script failed with return code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert duration <= 3.0, f"Script took {duration:.2f}s, which is above the 3.0s threshold."
    assert os.path.isfile(evidence_path), f"Output file {evidence_path} was not created by the script."

    try:
        img_evidence = np.array(Image.open(evidence_path).convert('L'))
    except Exception as e:
        assert False, f"Failed to open {evidence_path} as an image: {e}"

    # Independently derive the trigger time from the pcap after the submitted
    # script has finished, then decode the expected frame directly into memory.
    packets = rdpcap("/app/trigger.pcap")
    assert packets, "Capture contains no packets"
    capture_start = float(packets[0].time)
    trigger_time = None
    for packet in packets:
        if TCP in packet and int(packet[TCP].dport) == 1337 and (int(packet[TCP].flags) & 0x02):
            trigger_time = float(packet.time) - capture_start
            break
    assert trigger_time is not None, "No TCP SYN packet to destination port 1337 found"

    truth_result = subprocess.run(
        [
            "ffmpeg", "-loglevel", "error", "-ss", f"{trigger_time:.9f}",
            "-i", "/app/camera.mp4", "-frames:v", "1",
            "-f", "image2pipe", "-vcodec", "mjpeg", "pipe:1"
        ],
        capture_output=True,
    )
    assert truth_result.returncode == 0, f"Failed to derive expected frame: {truth_result.stderr.decode(errors='replace')}"
    assert truth_result.stdout, "ffmpeg produced no expected frame"

    try:
        img_truth = np.array(Image.open(io.BytesIO(truth_result.stdout)).convert('L'))
    except Exception as e:
        assert False, f"Failed to decode expected frame: {e}"

    assert img_evidence.shape == img_truth.shape, f"Image shapes differ: {img_evidence.shape} vs {img_truth.shape}"

    try:
        from skimage.metrics import structural_similarity as ssim
        score, _ = ssim(img_evidence, img_truth, full=True)
    except ImportError:
        mse = np.mean((img_evidence.astype(float) - img_truth.astype(float)) ** 2)
        max_pixel = 255.0
        score = 1.0 - (mse / (max_pixel ** 2))

    assert score >= 0.95, f"Image similarity score {score:.4f} is below threshold 0.95"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
