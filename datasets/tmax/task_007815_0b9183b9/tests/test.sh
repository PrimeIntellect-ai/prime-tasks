#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import importlib.util
import os
import random
import re
import string
import subprocess
import sys

import pytest

VALIDATOR_PATH = '/home/user/validator.py'
TEST_VALIDATOR_PATH = '/home/user/test_validator.py'
TEST_OUTPUT_PATH = '/home/user/test_output.txt'


def expected_hash(data):
    if isinstance(data, str):
        data = data.encode('utf-8')
    value = 5381
    for byte in data:
        # tokenhash.c uses plain char, which is signed in this image.
        c_value = byte if byte < 128 else byte - 256
        value = ((value << 5) + value + c_value) & 0xFFFFFFFF
    return value


def load_validator():
    spec = importlib.util.spec_from_file_location('validator_under_test', VALIDATOR_PATH)
    assert spec is not None and spec.loader is not None, 'Could not load validator.py'
    validator = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(validator)
    except Exception as exc:
        pytest.fail(f'Failed to execute {VALIDATOR_PATH}. Is it valid Python 3 code? Error: {exc}')
    return validator


def test_validator_py_exists():
    assert os.path.isfile(VALIDATOR_PATH), f'The file {VALIDATOR_PATH} does not exist.'


def test_test_validator_py_exists():
    assert os.path.isfile(TEST_VALIDATOR_PATH), f'The file {TEST_VALIDATOR_PATH} does not exist.'


def test_test_output_txt_exists_and_passed():
    assert os.path.isfile(TEST_OUTPUT_PATH), f'The file {TEST_OUTPUT_PATH} does not exist.'
    with open(TEST_OUTPUT_PATH, 'r', encoding='utf-8') as handle:
        content = handle.read()
    assert re.search(r'\d+ passed', content), \
        "The test output does not indicate successful test passes (e.g., '3 passed')."

    # Execute the submitted suite rather than trusting a fabricated output file.
    env = os.environ.copy()
    env['PYTEST_DISABLE_PLUGIN_AUTOLOAD'] = '1'
    result = subprocess.run(
        [sys.executable, '-m', 'pytest', TEST_VALIDATOR_PATH, '-v',
         '-c', '/dev/null', '--confcutdir=/tmp', '-o', 'addopts='],
        cwd='/tmp', env=env, text=True, capture_output=True, timeout=60
    )
    combined = result.stdout + result.stderr
    assert result.returncode == 0, f'Submitted pytest suite failed when executed:\n{combined}'
    for name in ('test_valid_token', 'test_invalid_format', 'test_invalid_checksum'):
        assert re.search(rf'::{name}(?:\s|\[).*?PASSED', combined), \
            f'{name} was not successfully executed by pytest. Output:\n{combined}'


def test_test_validator_contains_required_functions():
    with open(TEST_VALIDATOR_PATH, 'r', encoding='utf-8') as handle:
        tree = ast.parse(handle.read(), filename=TEST_VALIDATOR_PATH)

    functions = {node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)}
    required_functions = {'test_valid_token', 'test_invalid_format', 'test_invalid_checksum'}
    missing = required_functions - functions
    assert not missing, f'The test suite is missing the following required functions: {missing}'


def test_validator_py_logic_and_ctypes():
    validator = load_validator()

    # Preserve the original ABI assertions.
    assert hasattr(validator, 'lib'), "validator.py does not define 'lib'"
    compute_hash = validator.lib.compute_hash
    assert compute_hash.argtypes == [ctypes.c_char_p, ctypes.c_int], \
        'lib.compute_hash.argtypes is not correctly set.'
    assert compute_hash.restype == ctypes.c_uint32, \
        'lib.compute_hash.restype is not correctly set.'

    try:
        checksum = validator.get_checksum('admin123')
    except ctypes.ArgumentError:
        pytest.fail('get_checksum raised ctypes.ArgumentError. Did you forget to encode the string to bytes?')
    except Exception as exc:
        pytest.fail(f'get_checksum failed with an unexpected error: {exc}')

    admin_hash = expected_hash('admin123')
    assert checksum == admin_hash, f'get_checksum returned {checksum}, expected {admin_hash}.'

    tv = validator.TokenValidator()
    valid_token = f'SECadmin123#{admin_hash:08x}'
    assert tv.validate(valid_token) is True, 'TokenValidator failed to validate a correct token.'
    assert tv.validate('SECadmin123#00000000') is False, \
        'TokenValidator incorrectly validated a token with a bad checksum.'

    with pytest.raises(ValueError):
        tv.parse_token('BADadmin123#00000000')
    with pytest.raises(ValueError):
        tv.parse_token('SECadmin123')


def test_generalized_checksum_and_parser_behavior():
    validator = load_validator()
    tv = validator.TokenValidator()
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + '_-.~:@/'

    # Runtime-generated cases prevent implementations that special-case the
    # handful of examples visible in the task and old verifier.
    for _ in range(40):
        data = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 80)))
        wanted = expected_hash(data)

        assert validator.get_checksum(data) == wanted
        assert validator.get_checksum(data.encode('utf-8')) == wanted

        checksum_text = f'{wanted:08x}'
        if rng.choice((True, False)):
            checksum_text = checksum_text.upper()
        token = f'SEC{data}#{checksum_text}'
        parsed_data, parsed_checksum = tv.parse_token(token)
        assert parsed_data == data
        assert parsed_checksum == wanted
        assert tv.validate(token) is True

        delta = rng.randrange(1, 2**32)
        wrong = (wanted + delta) & 0xFFFFFFFF
        assert tv.validate(f'SEC{data}#{wrong:08x}') is False

    # UTF-8 must use encoded byte length and preserve the parsed string data.
    for data in ('café', 'naïve-user', '雪だるま', 'ключ42', 'emoji-🔐'):
        wanted = expected_hash(data)
        assert validator.get_checksum(data) == wanted
        assert validator.get_checksum(data.encode('utf-8')) == wanted
        token = f'SEC{data}#{wanted:08x}'
        assert tv.parse_token(token) == (data, wanted)
        assert tv.validate(token) is True


def test_generalized_malformed_tokens():
    validator = load_validator()
    tv = validator.TokenValidator()
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + '_-.'

    for _ in range(20):
        data = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 50)))
        checksum = expected_hash(data)
        malformed = [
            f'SE{data}#{checksum:08x}',
            f'sec{data}#{checksum:08x}',
            f'XSEC{data}#{checksum:08x}',
            f'SEC{data}',
            f'SEC{data}#',
            f'SEC{data}#not_hex',
            f'SEC{data}#{checksum:08x}#extra',
        ]
        for token in malformed:
            with pytest.raises(ValueError):
                tv.parse_token(token)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
