#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from decimal import Decimal, ROUND_HALF_UP


def derive_parameters():
    pairs = []
    with open('/app/raw_metrics.log', 'r', encoding='utf-8') as handle:
        for line in handle:
            if '[METRIC]' not in line or 'ERROR' in line or 'TIMEOUT' in line:
                continue
            x_match = re.search(r'CPU_Load=([-+]?\d+(?:\.\d+)?)', line)
            y_match = re.search(r'Response_Latency=([-+]?\d+(?:\.\d+)?)', line)
            if x_match and y_match:
                pairs.append((Decimal(x_match.group(1)), Decimal(y_match.group(1))))

    assert len(pairs) >= 2, 'Not enough valid metric rows to calculate a regression.'
    count = Decimal(len(pairs))
    sum_x = sum((x for x, _ in pairs), Decimal(0))
    sum_y = sum((y for _, y in pairs), Decimal(0))
    sum_xy = sum((x * y for x, y in pairs), Decimal(0))
    sum_x2 = sum((x * x for x, _ in pairs), Decimal(0))
    denominator = count * sum_x2 - sum_x * sum_x
    assert denominator != 0, 'Regression denominator is zero.'

    slope = (count * sum_xy - sum_x * sum_y) / denominator
    intercept = (sum_y - slope * sum_x) / count
    slope = slope.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
    intercept = intercept.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)

    ocr = subprocess.run(
        ['tesseract', '/app/system_specs.png', 'stdout'],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    alpha_match = re.search(r'Alpha\s*:\s*([-+]?\d+(?:\.\d+)?)', ocr, re.IGNORECASE)
    beta_match = re.search(r'Beta\s*:\s*([-+]?\d+(?:\.\d+)?)', ocr, re.IGNORECASE)
    assert alpha_match, f'Could not extract Alpha from OCR output: {ocr!r}'
    assert beta_match, f'Could not extract Beta from OCR output: {ocr!r}'

    return slope, intercept, Decimal(alpha_match.group(1)), Decimal(beta_match.group(1))


def test_predictor_fuzz_equivalence():
    agent_script = '/home/user/predictor.sh'

    assert os.path.isfile(agent_script), f'{agent_script} does not exist. Did you create it?'
    assert os.access(agent_script, os.X_OK), f'{agent_script} is not executable. Did you run chmod +x?'

    slope, intercept, alpha, beta = derive_parameters()

    random.seed(42)
    inputs = [random.randint(0, 1000000000) for _ in range(100)]

    for val in inputs:
        str_val = str(val)
        agent_res = subprocess.run([agent_script, str_val], capture_output=True, text=True)

        assert agent_res.returncode == 0, (
            f'Agent script failed on input {str_val}. Stderr: {agent_res.stderr}'
        )

        expected_value = alpha * (slope * Decimal(val) + intercept) + beta
        expected = format(
            expected_value.quantize(Decimal('0.001'), rounding=ROUND_HALF_UP),
            '.3f',
        )
        agent_out = agent_res.stdout.strip()

        assert agent_out == expected, (
            f'Output mismatch on input CPU_Load={str_val}.\n'
            f"Expected: '{expected}'\n"
            f"Got:      '{agent_out}'\n"
            'Check your linear regression calculations, rounding, and formula application.'
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
