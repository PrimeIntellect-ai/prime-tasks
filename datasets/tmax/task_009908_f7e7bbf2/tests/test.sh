#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import stat
import string
import subprocess


def exercise_library(inputs, prefix):
    script = r'''
import ctypes
import json
import sys

lib = ctypes.CDLL('/home/user/libtransform.so')
fn = lib.transform_string
fn.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
fn.restype = ctypes.c_int
results = []
for value in json.loads(sys.argv[1]):
    encoded = value.encode('ascii')
    output = ctypes.create_string_buffer(len(encoded) + 256)
    length = fn(encoded, output)
    results.append([length, output.value.decode('ascii')])
print(json.dumps(results))
'''
    res = subprocess.run(
        ['python3', '-c', script, json.dumps(inputs)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert res.returncode == 0, f"Library invocation failed: {res.stderr}"
    actual = json.loads(res.stdout)
    expected = [[len(prefix + value[::-1]), prefix + value[::-1]] for value in inputs]
    assert actual == expected, f"Expected {expected}, got {actual}"


def random_inputs():
    alphabet = string.ascii_letters + string.digits
    return [
        '',
        'a',
        'pipeline',
        'AbleWasI',
        ''.join(secrets.choice(alphabet) for _ in range(37)),
        ''.join(secrets.choice(alphabet) for _ in range(91)),
    ]


def test_files_exist():
    assert os.path.isfile('/home/user/transform.c'), "transform.c is missing."
    assert os.path.isfile('/home/user/build.sh'), "build.sh is missing."
    assert os.path.isfile('/home/user/libtransform.so'), "libtransform.so is missing."
    assert os.path.isfile('/home/user/result.log'), "result.log is missing."


def test_build_sh_executable():
    st = os.stat('/home/user/build.sh')
    assert bool(st.st_mode & stat.S_IXUSR), "build.sh is not executable."


def test_initial_result_log():
    with open('/home/user/result.log', 'r') as f:
        content = f.read().strip()
    assert content == "13,PROD_reenigne", f"Expected '13,PROD_reenigne' in result.log, got '{content}'"


def test_initial_prod_library():
    res = subprocess.run(['python3', '/home/user/verify.py'], capture_output=True, text=True)
    assert res.returncode == 0, f"verify.py failed: {res.stderr}"
    with open('/home/user/result.log', 'r') as f:
        content = f.read().strip()
    assert content == "13,PROD_reenigne", f"Expected '13,PROD_reenigne' in result.log, got '{content}'"


def test_build_ci_env():
    res = subprocess.run(['/home/user/build.sh', 'CI'], capture_output=True, text=True)
    assert res.returncode == 0, f"build.sh failed with CI argument: {res.stderr}"

    res = subprocess.run(['python3', '/home/user/verify.py'], capture_output=True, text=True)
    assert res.returncode == 0, f"verify.py failed: {res.stderr}"

    with open('/home/user/result.log', 'r') as f:
        content = f.read().strip()
    assert content == "11,CI_reenigne", f"Expected '11,CI_reenigne' in result.log, got '{content}'"


def test_build_default_env():
    res = subprocess.run([
        'gcc', '-shared', '-fPIC', '-o', '/home/user/libtransform.so', '/home/user/transform.c'
    ], capture_output=True, text=True)
    assert res.returncode == 0, f"Manual compilation failed: {res.stderr}"

    res = subprocess.run(['python3', '/home/user/verify.py'], capture_output=True, text=True)
    assert res.returncode == 0, f"verify.py failed: {res.stderr}"

    with open('/home/user/result.log', 'r') as f:
        content = f.read().strip()
    assert content == "16,DEFAULT_reenigne", f"Expected '16,DEFAULT_reenigne' in result.log, got '{content}'"


def test_build_sh_requires_exactly_one_argument():
    no_args = subprocess.run(
        ['/home/user/build.sh'], capture_output=True, text=True, timeout=10
    )
    assert no_args.returncode != 0, "build.sh must reject zero arguments."

    two_args = subprocess.run(
        ['/home/user/build.sh', 'CI', 'EXTRA'], capture_output=True, text=True, timeout=10
    )
    assert two_args.returncode != 0, "build.sh must reject more than one argument."


def test_transform_on_derived_inputs_and_arbitrary_env():
    env_name = 'ENV' + secrets.token_hex(8).upper()
    res = subprocess.run(
        ['/home/user/build.sh', env_name], capture_output=True, text=True, timeout=20
    )
    assert res.returncode == 0, f"build.sh failed with {env_name} argument: {res.stderr}"
    assert os.path.isfile('/home/user/libtransform.so'), "build.sh did not create libtransform.so."
    exercise_library(random_inputs(), env_name + '_')


def test_default_transform_on_derived_inputs():
    res = subprocess.run([
        'gcc', '-shared', '-fPIC', '-o', '/home/user/libtransform.so', '/home/user/transform.c'
    ], capture_output=True, text=True, timeout=20)
    assert res.returncode == 0, f"Manual compilation failed: {res.stderr}"
    exercise_library(random_inputs(), 'DEFAULT_')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
