#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import pytest

SCRIPT_PATH = '/home/user/process_math.py'
JSON_PATH = '/home/user/extracted_math.json'
RAW_DIR = '/home/user/raw_math_data'


def run_script():
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'process_math.py failed with exit code {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )


def test_script_exists():
    """Test that the python script process_math.py exists."""
    script_path = '/home/user/process_math.py'
    assert os.path.isfile(script_path), f"The script {script_path} is missing."


def test_script_executes_and_generates_output():
    """Execute the submitted script and require it to create a fresh output file."""
    if os.path.exists(JSON_PATH):
        os.unlink(JSON_PATH)
    run_script()
    assert os.path.isfile(JSON_PATH), f"The output file {JSON_PATH} is missing."


def test_json_output_exists():
    """Test that the output JSON file exists."""
    json_path = '/home/user/extracted_math.json'
    assert os.path.isfile(json_path), f"The output file {json_path} is missing."


def test_json_output_content():
    """Test that the output JSON file contains the correct extracted and evaluated math data."""
    json_path = '/home/user/extracted_math.json'
    assert os.path.isfile(json_path), f"The output file {json_path} is missing."

    with open(json_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    expected = {
        "doc1.txt": {"trace": 7, "poly_eval_10": 229},
        "doc2.dat": {"trace": 2, "poly_eval_10": 90},
        "doc3.log": {"trace": 11, "poly_eval_10": 43}
    }

    assert isinstance(data, dict), "The JSON root should be a dictionary."

    for doc, expected_values in expected.items():
        assert doc in data, f"Missing key '{doc}' in the JSON output."
        assert "trace" in data[doc], f"Missing 'trace' for '{doc}'."
        assert "poly_eval_10" in data[doc], f"Missing 'poly_eval_10' for '{doc}'."

        assert data[doc]["trace"] == expected_values["trace"], \
            f"Incorrect trace for '{doc}'. Expected {expected_values['trace']}, got {data[doc]['trace']}."
        assert data[doc]["poly_eval_10"] == expected_values["poly_eval_10"], \
            f"Incorrect poly_eval_10 for '{doc}'. Expected {expected_values['poly_eval_10']}, got {data[doc]['poly_eval_10']}."

    # Check for unexpected extra keys
    extra_keys = set(data.keys()) - set(expected.keys())
    assert not extra_keys, f"Unexpected extra keys in JSON output: {extra_keys}"


def format_polynomial(a, b, c):
    terms = []
    for coefficient, variable in ((a, 'x^2'), (b, 'x'), (c, '')):
        if coefficient == 0:
            continue
        magnitude = abs(coefficient)
        body = variable if variable and magnitude == 1 else f'{magnitude}{variable}'
        if not terms:
            terms.append(('-' if coefficient < 0 else '') + body)
        else:
            terms.append((' - ' if coefficient < 0 else ' + ') + body)
    return ''.join(terms) if terms else '0'


def nonzero_integer(rng, low=-12, high=12):
    value = 0
    while value == 0:
        value = rng.randint(low, high)
    return value


def test_processes_changed_encoded_inputs_instead_of_hardcoding_results():
    """Exercise the ETL workflow on fresh values encoded like the supplied reports."""
    paths = {
        name: os.path.join(RAW_DIR, name)
        for name in ('doc1.txt', 'doc2.dat', 'doc3.log')
    }
    original_inputs = {name: open(path, 'rb').read() for name, path in paths.items()}
    original_output = open(JSON_PATH, 'rb').read() if os.path.exists(JSON_PATH) else None
    rng = random.SystemRandom()

    try:
        for round_number in range(2):
            expected = {}
            reports = {}
            for index, name in enumerate(('doc1.txt', 'doc2.dat', 'doc3.log')):
                matrix = [rng.randint(-30, 30) for _ in range(4)]
                if index == 0:
                    coefficients = (1, nonzero_integer(rng), nonzero_integer(rng))
                elif index == 1:
                    coefficients = (nonzero_integer(rng), -1, nonzero_integer(rng))
                else:
                    coefficients = (0, nonzero_integer(rng), nonzero_integer(rng))

                a, b, c = coefficients
                polynomial = format_polynomial(a, b, c)
                m1, m2, m3, m4 = matrix
                expected[name] = {
                    'trace': m1 + m4,
                    'poly_eval_10': a * 100 + b * 10 + c,
                }
                reports[name] = (
                    f'Laboratory report round {round_number + 1}.\n'
                    f'Observed matrix = [[ {m1}, {m2} ], [ {m3}, {m4} ]].\n'
                    f'Formula P(x) = {polynomial}.\n'
                )

            with open(paths['doc1.txt'], 'wb') as f:
                f.write(reports['doc1.txt'].encode('utf-8'))
            with open(paths['doc2.dat'], 'wb') as f:
                f.write(reports['doc2.dat'].encode('utf-16le'))
            reports['doc3.log'] = 'Gamma ± tolerance.\n' + reports['doc3.log']
            with open(paths['doc3.log'], 'wb') as f:
                f.write(reports['doc3.log'].encode('iso-8859-1'))

            if os.path.exists(JSON_PATH):
                os.unlink(JSON_PATH)
            run_script()
            assert os.path.isfile(JSON_PATH), 'The script did not generate extracted_math.json.'
            with open(JSON_PATH, 'r', encoding='utf-8') as f:
                try:
                    actual = json.load(f)
                except json.JSONDecodeError as exc:
                    pytest.fail(f'The generated output is not valid JSON: {exc}')
            assert actual == expected, (
                'The script did not decode, extract, and evaluate the changed input reports correctly. '
                f'Expected {expected!r}, got {actual!r}.'
            )
    finally:
        for name, content in original_inputs.items():
            with open(paths[name], 'wb') as f:
                f.write(content)
        if original_output is None:
            if os.path.exists(JSON_PATH):
                os.unlink(JSON_PATH)
        else:
            with open(JSON_PATH, 'wb') as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
