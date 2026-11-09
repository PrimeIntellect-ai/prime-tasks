#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import sys
import pytest

ORACLE_PATH = '/tests/processor_oracle.py'
TARGET_PATH = '/home/user/processor'
IMAGE_PATH = '/app/priors.png'


def generate_csv():
    num_rows = random.randint(5, 50)
    lines = []
    for _ in range(num_rows):
        num_words = random.randint(1, 20)
        words = [''.join(random.choices(string.ascii_letters, k=random.randint(1, 10))) for _ in range(num_words)]
        text_data = ' '.join(words)
        float_x = f"{random.uniform(0.1, 0.9):.3f}"
        float_y = f"{random.uniform(0.1, 0.9):.3f}"
        lines.append(f"{text_data},{float_x},{float_y}")
    return '\n'.join(lines)


def expected_output(csv_input, prior):
    rows = []
    xs = []
    ys = []
    for line in csv_input.strip().split('\n'):
        parts = line.split(',', 2)
        if len(parts) < 3:
            continue
        text, x_str, y_str = parts
        x = float(x_str)
        y = float(y_str)
        rows.append(f"{len(text.split())},{x:.4f},{y:.4f}")
        xs.append(x)
        ys.append(y)

    mean_x = sum(xs) / len(xs)
    mean_y = sum(ys) / len(ys)
    covariance = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / len(xs)

    prod_x = 1.0
    prod_y = 1.0
    for x in xs:
        prod_x *= x
    for y in ys:
        prod_y *= y

    numerator = prior * prod_x
    denominator = numerator + (1.0 - prior) * prod_y
    posterior = 0.0 if denominator == 0 else numerator / denominator

    return '\n'.join(rows + ['', f"COVARIANCE: {covariance:.4f}", f"POSTERIOR: {posterior:.4f}"])


def test_fuzz_equivalence():
    assert os.path.exists(TARGET_PATH), f"Target executable not found at {TARGET_PATH}"
    assert os.access(TARGET_PATH, os.X_OK), f"Target {TARGET_PATH} is not executable"
    assert os.path.isfile(ORACLE_PATH), f"Verification oracle not found at {ORACLE_PATH}"

    random.seed(42)
    for i in range(100):
        csv_input = generate_csv()

        oracle_proc = subprocess.run(
            [sys.executable, ORACLE_PATH], input=csv_input, text=True, capture_output=True
        )
        target_proc = subprocess.run(
            [TARGET_PATH], input=csv_input, text=True, capture_output=True
        )

        assert oracle_proc.returncode == 0, f"Oracle failed on run {i}:\n{oracle_proc.stderr}"
        assert target_proc.returncode == 0, f"Target failed on run {i}:\n{target_proc.stderr}"

        oracle_out = oracle_proc.stdout.strip()
        target_out = target_proc.stdout.strip()
        if oracle_out != target_out:
            pytest.fail(
                f"Mismatch on run {i}.\nInput:\n{csv_input}\n\n"
                f"Expected Output:\n{oracle_out}\n\nActual Output:\n{target_out}"
            )


def test_prior_is_extracted_from_image():
    original_image = open(IMAGE_PATH, 'rb').read()
    prior_hundredths = secrets.choice([17, 23, 41, 58, 62, 73, 81])
    prior = prior_hundredths / 100.0
    csv_input = (
        "alpha beta,0.800,0.200\n"
        "one   two three,0.700,0.300\n"
        "single,0.600,0.400\n"
        "tabs\talso\tcount,0.900,0.100\n"
        "last row,0.550,0.450"
    )

    try:
        subprocess.run(
            [
                'convert', '-background', 'white', '-fill', 'black',
                '-font', 'Courier', '-pointsize', '24',
                f'label:BAYES_PRIOR=0.{prior_hundredths:02d}',
                '+set', 'label', IMAGE_PATH
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        proc = subprocess.run([TARGET_PATH], input=csv_input, text=True, capture_output=True)
        assert proc.returncode == 0, f"Target failed with changed prior image:\n{proc.stderr}"
        assert proc.stdout.strip() == expected_output(csv_input, prior).strip(), (
            f"Target did not use the prior from the current image.\n"
            f"Expected:\n{expected_output(csv_input, prior)}\n\nActual:\n{proc.stdout}"
        )
    finally:
        with open(IMAGE_PATH, 'wb') as image_file:
            image_file.write(original_image)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
