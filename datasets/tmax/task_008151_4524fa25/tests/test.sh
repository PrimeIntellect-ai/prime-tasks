#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math
from PIL import Image


def test_stat_result():
    stat_file = "/home/user/stat_result.txt"
    raw_data = "/home/user/raw_data.csv"

    assert os.path.exists(stat_file), f"File {stat_file} is missing."
    assert os.path.isfile(stat_file), f"Path {stat_file} is not a file."

    # Compute the expected result
    vals_A = []
    vals_B = []
    with open(raw_data, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            val = float(row['value'])
            if row['category'] == 'A':
                vals_A.append(val)
            elif row['category'] == 'B':
                vals_B.append(val)

    sum_A = math.fsum(vals_A)
    sum_B = math.fsum(vals_B)
    diff = sum_A - sum_B
    expected_str = f"{diff:.15f}"

    with open(stat_file, 'r') as f:
        actual_str = f.read().strip()

    assert actual_str == expected_str, f"Expected {expected_str} in {stat_file}, but got {actual_str}"


def test_plot_png():
    plot_file = "/home/user/plot.png"
    assert os.path.exists(plot_file), f"File {plot_file} is missing."
    assert os.path.isfile(plot_file), f"Path {plot_file} is not a file."

    # Preserve the original PNG signature assertion.
    with open(plot_file, 'rb') as f:
        header = f.read(8)

    png_magic = b'\x89PNG\r\n\x1a\n'
    assert header == png_magic, f"File {plot_file} is not a valid PNG image."

    # Decode and verify the complete PNG rather than accepting signature bytes.
    with Image.open(plot_file) as image:
        assert image.format == "PNG", f"File {plot_file} is not a PNG image."
        image.verify()

    # Reopen after verify(), force full pixel decoding, and require nontrivial
    # plotted content rather than an empty or single-color canvas.
    with Image.open(plot_file) as image:
        image.load()
        width, height = image.size
        assert width >= 100 and height >= 100, "The plot is too small to be a usable comparative histogram."

        sample = image.convert("RGBA")
        sample.thumbnail((512, 512))
        background = Image.new("RGBA", sample.size, (255, 255, 255, 255))
        background.alpha_composite(sample)
        rgb = background.convert("RGB")
        colors = rgb.getcolors(maxcolors=rgb.width * rgb.height)

        assert colors is not None and len(colors) >= 4, "The plot does not contain enough distinct visual content for a comparative histogram."
        dominant_count = max(count for count, _ in colors)
        non_dominant = rgb.width * rgb.height - dominant_count
        assert non_dominant >= max(100, (rgb.width * rgb.height) // 1000), "The plot appears blank or lacks meaningful histogram content."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
