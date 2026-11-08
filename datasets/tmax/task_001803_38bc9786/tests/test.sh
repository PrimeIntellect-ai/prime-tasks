#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import importlib.machinery
import os
import shutil
import subprocess
import sys

import numpy as np
import pytest
from PIL import Image
from scipy.ndimage import gaussian_filter

PROJECT = "/workspace/vid_project"
VIDEO = "/app/test_video.mp4"
OUTPUT = "/workspace/output_frames"
EXPECTED_LIBS = ["avformat", "avcodec", "avutil", "swscale"]


def calculate_ssim(img1, img2):
    C1 = (0.01 * 255) ** 2
    C2 = (0.03 * 255) ** 2
    ssim_channels = []
    for i in range(img1.shape[2]):
        im1 = img1[:, :, i].astype(np.float64)
        im2 = img2[:, :, i].astype(np.float64)
        mu1 = gaussian_filter(im1, 1.5)
        mu2 = gaussian_filter(im2, 1.5)
        mu1_sq = mu1 ** 2
        mu2_sq = mu2 ** 2
        mu1_mu2 = mu1 * mu2
        sigma1_sq = gaussian_filter(im1 ** 2, 1.5) - mu1_sq
        sigma2_sq = gaussian_filter(im2 ** 2, 1.5) - mu2_sq
        sigma12 = gaussian_filter(im1 * im2, 1.5) - mu1_mu2
        ssim_map = ((2 * mu1_mu2 + C1) * (2 * sigma12 + C2)) / (
            (mu1_sq + mu2_sq + C1) * (sigma1_sq + sigma2_sq + C2)
        )
        ssim_channels.append(ssim_map.mean())
    return np.mean(ssim_channels)


def make_ground_truth(path):
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    subprocess.run([
        "ffmpeg", "-i", VIDEO, "-vf",
        "select='eq(n,10)+eq(n,20)+eq(n,30)'", "-vsync", "0",
        os.path.join(path, "frame_%d.jpg"), "-y", "-loglevel", "quiet"
    ], check=True)


def assert_frames_match(agent_dir, gt_dir):
    assert os.path.isdir(agent_dir), f"Agent output directory {agent_dir} does not exist."
    agent_files = sorted(f for f in os.listdir(agent_dir) if f.endswith(".jpg"))
    gt_files = sorted(f for f in os.listdir(gt_dir) if f.endswith(".jpg"))
    assert len(agent_files) > 0, "No jpg files found in agent output directory."
    assert len(agent_files) == len(gt_files), (
        f"Count mismatch. Expected {len(gt_files)} frames, got {len(agent_files)}."
    )

    scores = []
    for af, gf in zip(agent_files, gt_files):
        img_a = np.array(Image.open(os.path.join(agent_dir, af)).convert("RGB"))
        img_g = np.array(Image.open(os.path.join(gt_dir, gf)).convert("RGB"))
        if img_a.shape != img_g.shape:
            img_a = np.array(Image.fromarray(img_a).resize(
                (img_g.shape[1], img_g.shape[0]), Image.LANCZOS
            ))
        scores.append(calculate_ssim(img_a, img_g))

    avg_ssim = np.mean(scores)
    assert avg_ssim >= 0.95, (
        f"SSIM {avg_ssim:.4f} is below threshold 0.95. "
        "Extracted frames do not match ground truth closely enough."
    )


@pytest.fixture(scope="session", autouse=True)
def clean_build_extension():
    assert os.path.isfile(VIDEO), f"Video fixture {VIDEO} is missing."
    assert os.path.isfile(os.path.join(PROJECT, "setup.py")), "setup.py is missing."
    assert os.path.isfile(os.path.join(PROJECT, "extractor.cpp")), "extractor.cpp is missing."

    shutil.rmtree(os.path.join(PROJECT, "build"), ignore_errors=True)
    for suffix in importlib.machinery.EXTENSION_SUFFIXES:
        for artifact in glob.glob(os.path.join(PROJECT, "video_extractor*" + suffix)):
            os.remove(artifact)

    subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace"],
        cwd=PROJECT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )

    artifacts = []
    for suffix in importlib.machinery.EXTENSION_SUFFIXES:
        artifacts.extend(glob.glob(os.path.join(PROJECT, "video_extractor*" + suffix)))
    assert artifacts, "A clean build did not produce the video_extractor extension module."


def test_mre_parse_exists_and_runs():
    mre = os.path.join(PROJECT, "mre_parse.py")
    assert os.path.isfile(mre), (
        "mre_parse.py is missing. You must create a minimal reproducible example."
    )

    tree = ast.parse(open(mre, encoding="utf-8").read(), filename=mre)
    assert any(
        isinstance(node, ast.ImportFrom)
        and node.module == "setup"
        and any(alias.name == "get_libs" for alias in node.names)
        for node in ast.walk(tree)
    ), "mre_parse.py must import get_libs from setup.py."

    result = subprocess.run(
        [sys.executable, mre], cwd=PROJECT, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert lines, "mre_parse.py printed no result."
    try:
        parsed = ast.literal_eval(lines[-1])
    except Exception as exc:
        raise AssertionError("mre_parse.py must print the resulting Python list.") from exc
    assert parsed == EXPECTED_LIBS, f"Unexpected libraries from mre_parse.py: {parsed!r}"


def test_get_libs_handles_format_edges(tmp_path):
    conf = tmp_path / "edge-libs.conf"
    conf.write_text(
        "# full-line comment\n"
        "avformat    # inline comment\n"
        "avcodec   \t\n"
        "avutil \\\n"
        "    swscale   # continued line comment\n",
        encoding="utf-8",
    )
    probe = r'''
import runpy
import sys
from unittest.mock import patch
with patch("setuptools.setup"):
    namespace = runpy.run_path(sys.argv[1])
print(repr(namespace["get_libs"](sys.argv[2])))
'''
    result = subprocess.run(
        [sys.executable, "-c", probe, os.path.join(PROJECT, "setup.py"), str(conf)],
        cwd=PROJECT, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    parsed = ast.literal_eval(result.stdout.strip().splitlines()[-1])
    assert parsed == EXPECTED_LIBS, f"get_libs mishandled comments/whitespace/continuation: {parsed!r}"


def test_compiled_extension_imports_and_extracts():
    out_dir = "/tmp/extension_frames"
    gt_dir = "/tmp/gt_extension_frames"
    shutil.rmtree(out_dir, ignore_errors=True)
    os.makedirs(out_dir)
    make_ground_truth(gt_dir)

    probe = r'''
import os
import sys
import video_extractor
assert os.path.abspath(video_extractor.__file__).startswith(os.path.abspath(sys.argv[1]) + os.sep)
assert any(video_extractor.__file__.endswith(s) for s in __import__("importlib").machinery.EXTENSION_SUFFIXES)
video_extractor.extract_frames(sys.argv[2], sys.argv[3])
'''
    subprocess.run(
        [sys.executable, "-c", probe, PROJECT, VIDEO, out_dir],
        cwd=PROJECT, check=True, timeout=180
    )
    assert_frames_match(out_dir, gt_dir)


def test_extracted_frames_ssim():
    gt_dir = "/tmp/gt_frames"
    make_ground_truth(gt_dir)
    shutil.rmtree(OUTPUT, ignore_errors=True)

    subprocess.run(
        [sys.executable, "run_pipeline.py", VIDEO, OUTPUT],
        cwd=PROJECT, check=True, timeout=180
    )
    assert_frames_match(OUTPUT, gt_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
