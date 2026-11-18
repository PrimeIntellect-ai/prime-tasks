#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest
from decimal import Decimal
from importlib import metadata
from pip._vendor.packaging.requirements import Requirement
from pip._vendor.packaging.utils import canonicalize_name

DATA_PATH = '/home/user/data.txt'
OUTPUT_PATH = '/home/user/output.txt'
CALC_PATH = '/home/user/calc.py'
REQUIREMENTS_PATH = '/home/user/requirements.txt'


def test_output_txt_content():
    assert os.path.exists(DATA_PATH), f"Data file missing: {DATA_PATH}"
    assert os.path.exists(OUTPUT_PATH), f"Output file missing: {OUTPUT_PATH}"

    # Calculate expected sum using Decimal to avoid floating point issues
    expected_sum = Decimal('0.0')
    with open(DATA_PATH, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                expected_sum += Decimal(line)

    expected_str = str(expected_sum)

    with open(OUTPUT_PATH, 'r') as f:
        output_content = f.read().strip()

    assert output_content == expected_str, f"Expected output {expected_str}, but got '{output_content}'. Make sure both the off-by-one error and floating-point precision issues are fixed."


def test_requirements_installed():
    assert os.path.isfile(REQUIREMENTS_PATH), f"Requirements file missing: {REQUIREMENTS_PATH}"

    parsed = []
    with open(REQUIREMENTS_PATH, 'r') as f:
        for raw_line in f:
            line = raw_line.split('#', 1)[0].strip()
            if line and not line.startswith('-'):
                parsed.append(Requirement(line))

    names = {canonicalize_name(req.name) for req in parsed}
    assert 'requests' in names, 'requirements.txt must retain the requests dependency'
    assert 'urllib3' in names, 'requirements.txt must retain the urllib3 dependency'

    install = subprocess.run(
        ['python3', '-m', 'pip', 'install', '-r', REQUIREMENTS_PATH],
        capture_output=True,
        text=True,
        timeout=180
    )
    assert install.returncode == 0, (
        'pip install -r failed; the dependency conflict was not resolved.\n'
        f'stdout:\n{install.stdout}\nstderr:\n{install.stderr}'
    )

    for req in parsed:
        if req.marker is not None and not req.marker.evaluate():
            continue
        installed_version = metadata.version(req.name)
        assert req.specifier.contains(installed_version, prereleases=True), (
            f"Installed {req.name} version {installed_version} does not satisfy {req.specifier}"
        )

    # Keep the original import assertion as an additional compatibility check.
    try:
        subprocess.run(
            ['python3', '-c', 'import requests'],
            capture_output=True,
            text=True,
            check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to import requests. Dependency conflict might not be resolved. Error: {e.stderr}")


def test_calc_script_computes_exact_totals_when_executed():
    assert os.path.isfile(CALC_PATH), f"Calculation script missing: {CALC_PATH}"

    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()
    output_existed = os.path.exists(OUTPUT_PATH)
    original_output = None
    if output_existed:
        with open(OUTPUT_PATH, 'rb') as f:
            original_output = f.read()

    cases = [
        ['7.125'],
        ['0.1', '0.2', '0.3'],
        ['12.34', '-2.11', '0.007', '5.003'],
        ['99999999999999999999.9', '0.1', '-0.2', '0.2'],
    ]

    try:
        for values in cases:
            with open(DATA_PATH, 'w') as f:
                f.write('\n'.join(values) + '\n')
            if os.path.lexists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)

            result = subprocess.run(
                ['python3', CALC_PATH],
                capture_output=True,
                text=True,
                timeout=30
            )
            assert result.returncode == 0, (
                f"calc.py failed when executed. stdout: {result.stdout} stderr: {result.stderr}"
            )
            assert os.path.isfile(OUTPUT_PATH), 'calc.py did not create /home/user/output.txt'

            expected = Decimal('0.0')
            for value in values:
                expected += Decimal(value)
            with open(OUTPUT_PATH, 'r') as f:
                actual = f.read().strip()
            assert actual == str(expected), (
                f"For inputs {values}, expected exact total {expected}, got {actual!r}"
            )
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
        if output_existed:
            with open(OUTPUT_PATH, 'wb') as f:
                f.write(original_output)
        elif os.path.lexists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
