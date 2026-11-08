#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

import matplotlib.image as mpimg
import matplotlib.pyplot as plt
import numpy as np

AGENT_BIN = "/home/user/bin/seq_extractor"
PLOT_SCRIPT = "/home/user/plot_singular_values.sh"
PLOT_PATH = "/home/user/svd_variance.png"


def test_agent_binary_exists():
    assert os.path.isfile(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable"
    with open(AGENT_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "seq_extractor must be a compiled executable"


def test_plot_script_and_output_exist():
    assert os.path.isfile(PLOT_SCRIPT), f"Plot script not found at {PLOT_SCRIPT}"
    assert os.path.isfile(PLOT_PATH), f"Output plot not found at {PLOT_PATH}"


def test_plot_script_recreates_valid_plot():
    os.remove(PLOT_PATH)
    result = subprocess.run(
        ["bash", PLOT_SCRIPT],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, f"Plot script failed: {result.stderr}"
    assert os.path.isfile(PLOT_PATH), "Plot script did not create /home/user/svd_variance.png"
    assert os.path.getsize(PLOT_PATH) > 0, "Generated plot is empty"
    image = mpimg.imread(PLOT_PATH)
    assert image.ndim in (2, 3) and image.size > 0, "Generated plot is not a valid image"


def write_frame(path, nucleotide):
    row = "ACGT".index(nucleotide)
    image = np.zeros((16, 16), dtype=np.uint8)
    # This rank-one nonnegative matrix has e_row as its unique dominant left
    # singular vector. The supplied basis therefore projects it exactly onto
    # the corresponding A/C/G/T pure state.
    image[row, :] = np.arange(120, 248, 8, dtype=np.uint8)
    plt.imsave(path, image, cmap="gray", vmin=0, vmax=255, format="png")


def test_sequence_extraction_on_derived_inputs():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory() as base_tmp:
        for case in range(5):
            length = rng.randint(10, 30)
            expected_chars = list("ACGT")
            expected_chars.extend(rng.choice("ACGT") for _ in range(length - 4))
            rng.shuffle(expected_chars)
            expected = "".join(expected_chars)

            frame_dir = os.path.join(base_tmp, f"case_{case}")
            os.makedirs(frame_dir)
            for index, nucleotide in enumerate(expected_chars):
                write_frame(
                    os.path.join(frame_dir, f"frame_{index:04d}.png"),
                    nucleotide,
                )

            result = subprocess.run(
                [AGENT_BIN, frame_dir],
                capture_output=True,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, (
                f"Agent returned non-zero on case {case}: {result.stderr}"
            )
            actual = result.stdout.strip()
            assert len(actual) == length, (
                f"Expected one nucleotide per frame ({length}), got {len(actual)}"
            )
            assert set(actual) <= set("ACGT"), "Output must contain only A, C, G, and T"
            assert actual == expected, (
                f"Incorrect sequence or frame ordering on case {case}.\n"
                f"Expected: {expected}\nActual:   {actual}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
