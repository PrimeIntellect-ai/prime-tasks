#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import importlib.util
import json
import os
import re
import subprocess
import sys

import pytest

INVESTIGATION = '/home/user/investigation'
EXTRACTOR = os.path.join(INVESTIGATION, 'extractor.py')
MEMDUMP = os.path.join(INVESTIGATION, 'memdump.bin')
EXPECTED_URL = 'https://www.cample.com'


def load_extractor():
    assert os.path.isfile(EXTRACTOR), f'The file {EXTRACTOR} does not exist.'
    spec = importlib.util.spec_from_file_location('submitted_extractor', EXTRACTOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def reference_payload_and_url():
    with open(MEMDUMP, 'rb') as f:
        data = f.read()

    match = re.search(rb'C2CFG\{(\d{4})\}', data)
    assert match is not None, 'The supplied memory dump has no config block.'
    length = int(match.group(1))
    payload = data[match.end():match.end() + length].decode('ascii')

    current = payload
    for _ in range(10):
        if current.startswith(('http://', 'https://')):
            break
        encoded = current[4:] if current.startswith('b64:') else current
        encoded += '=' * ((-len(encoded)) % 4)
        try:
            decoded = base64.b64decode(encoded).decode('utf-8')
        except Exception:
            break
        if decoded == current:
            break
        current = decoded
    return payload, current


def run_decode(payload):
    code = r'''
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("submitted_extractor", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
result = module.decode_c2(sys.argv[2])
print(json.dumps(result))
'''
    proc = subprocess.run(
        [sys.executable, '-c', code, EXTRACTOR, payload],
        text=True,
        capture_output=True,
        timeout=3,
    )
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout.strip())


def test_c2_txt_exists_and_correct():
    c2_path = '/home/user/investigation/c2.txt'
    assert os.path.isfile(c2_path), f'The file {c2_path} does not exist. Did you save the extracted URL?'

    with open(c2_path, 'r') as f:
        content = f.read().strip()

    expected_url = 'https://www.cample.com'
    assert content == expected_url, f"The content of {c2_path} is incorrect. Expected '{expected_url}', but got '{content}'."


def test_minimal_crash_txt_exists_and_correct():
    crash_path = '/home/user/investigation/minimal_crash.txt'
    assert os.path.isfile(crash_path), f'The file {crash_path} does not exist. Did you save the minimal crashing string?'

    with open(crash_path, 'r') as f:
        content = f.read().strip()

    expected_crash_string = 'C2CFG{9001}'
    assert content == expected_crash_string, f"The content of {crash_path} is incorrect. Expected the minimal string '{expected_crash_string}', but got '{content}'."


def test_parser_handles_binary_and_malformed_input():
    module = load_extractor()

    assert module.parse_config_block(b'\xff\x00noiseC2CFG{0003}abc\xfe') == 'abc'
    assert module.parse_config_block(b'C2CFG{0004}a\x00bc') == 'a\x00bc'
    assert module.parse_config_block(b'\xffC2CFG{00\xfe3}payload') is None
    assert module.parse_config_block(b'no signature\xff\x00') is None


def test_parser_retains_corrupt_header_check_and_saved_input_is_minimal():
    module = load_extractor()
    crash = open(os.path.join(INVESTIGATION, 'minimal_crash.txt'), encoding='utf-8').read().strip()

    with pytest.raises(ValueError, match=r'^Corrupt Header$'):
        module.parse_config_block(crash.encode('ascii'))

    for index in range(len(crash)):
        candidate = (crash[:index] + crash[index + 1:]).encode('ascii')
        try:
            module.parse_config_block(candidate)
        except ValueError as exc:
            assert str(exc) != 'Corrupt Header', f'Deleting character {index} still triggers the same exception.'


def test_decoder_extracts_dump_payload_and_stops_at_valid_url():
    module = load_extractor()
    payload, expected = reference_payload_and_url()
    assert expected == EXPECTED_URL

    with open(MEMDUMP, 'rb') as f:
        parsed = module.parse_config_block(f.read())
    assert parsed == payload
    assert run_decode(parsed) == expected
    assert run_decode(EXPECTED_URL) == EXPECTED_URL


def test_decoder_enforces_ten_iteration_limit():
    current = EXPECTED_URL
    states = [current]
    for _ in range(12):
        current = base64.b64encode(current.encode()).decode()
        states.append(current)

    # Twelve nested layers require twelve decoding steps. A ten-iteration
    # implementation must return the value with two layers still remaining.
    assert run_decode(states[12]) == states[2]


def test_extractor_runs_on_the_supplied_dump():
    proc = subprocess.run(
        [sys.executable, EXTRACTOR],
        cwd=INVESTIGATION,
        text=True,
        capture_output=True,
        timeout=3,
    )
    assert proc.returncode == 0, proc.stderr
    _, expected = reference_payload_and_url()
    assert proc.stdout.strip() == expected

    with open(os.path.join(INVESTIGATION, 'c2.txt'), encoding='utf-8') as f:
        assert f.read().strip() == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
