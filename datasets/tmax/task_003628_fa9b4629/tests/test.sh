#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier
mkdir -p /tmp/empty_path

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import stat
import subprocess
import time

import pytest
import requests

MAKEFILE = '/app/extractor/Makefile'
EXTRACTOR = '/app/extractor/extractor'
FIXTURE = '/app/fixture.wav'
COMMANDS = '/home/user/commands.txt'
INTERPRETER = '/home/user/interpreter.sh'
SERVER = '/home/user/server.sh'
URL = 'http://127.0.0.1:9090/state'


def run_checked(argv, **kwargs):
    result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=10, **kwargs)
    assert result.returncode == 0, (
        f"Command {argv!r} failed with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    return result


def test_makefile_fixed_and_clean_build_works():
    assert os.path.isfile(MAKEFILE), f"The file {MAKEFILE} is missing."
    with open(MAKEFILE, 'r') as f:
        content = f.read()
    assert '-lm' in content, "The Makefile does not contain the '-lm' flag required for linking math functions."

    run_checked(['make', 'clean'], cwd='/app/extractor')
    run_checked(['make'], cwd='/app/extractor')


def test_extractor_compiled_and_runs():
    assert os.path.isfile(EXTRACTOR), f"The binary {EXTRACTOR} was not compiled."
    assert os.access(EXTRACTOR, os.X_OK), f"The file {EXTRACTOR} is not executable."
    with open(EXTRACTOR, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'The extractor is not a compiled ELF executable.'

    result = run_checked([EXTRACTOR, FIXTURE])
    expected = b'LOAD 100\nADD 50\nDIV 3\nSUB 8\nMUL 2\n'
    assert result.stdout == expected, f"Extractor produced unexpected data: {result.stdout!r}"


def test_commands_extracted_from_extractor():
    assert os.path.isfile(COMMANDS), f"The file {COMMANDS} is missing."
    with open(COMMANDS, 'rb') as f:
        content = f.read()
    assert b'LOAD 100' in content, 'The extracted commands do not seem correct.'
    extracted = run_checked([EXTRACTOR, FIXTURE]).stdout
    assert content == extracted, 'commands.txt does not exactly match the extractor output.'


def test_interpreter_exists_is_bash_and_has_valid_syntax():
    assert os.path.isfile(INTERPRETER), f"The file {INTERPRETER} is missing."
    result = subprocess.run(['/bin/bash', '-n', INTERPRETER], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=5)
    assert result.returncode == 0, f"interpreter.sh is not valid Bash: {result.stderr!r}"


def test_server_script_exists_and_is_valid_bash_server_script():
    assert os.path.isfile(SERVER), f"The file {SERVER} is missing."
    result = subprocess.run(['/bin/bash', '-n', SERVER], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=5)
    assert result.returncode == 0, f"server.sh is not valid Bash: {result.stderr!r}"
    with open(SERVER, 'r', errors='replace') as f:
        content = f.read()
    assert re.search(r'(^|[^A-Za-z0-9_])(nc|netcat|socat)([^A-Za-z0-9_]|$)', content), \
        'server.sh does not use nc/netcat or socat as required.'


def http_state(expected):
    try:
        response = requests.get(URL, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"HTTP request failed: {exc}. Is the server running and handling multiple requests?")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert 'application/json' in response.headers.get('Content-Type', ''), \
        'Expected Content-Type application/json'
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text!r}")
    expected_data = {'accumulator': expected}
    assert data == expected_data, f"Expected {expected_data}, got {data}"
    assert response.text.strip() == f'{{"accumulator": {expected}}}', \
        f"Unexpected JSON body formatting: {response.text!r}"


def evaluate(command_text):
    accumulator = 0
    for line in command_text.splitlines():
        if not line.strip():
            continue
        op, raw_value = line.split()
        value = int(raw_value)
        if op == 'LOAD':
            accumulator = value
        elif op == 'ADD':
            accumulator += value
        elif op == 'SUB':
            accumulator -= value
        elif op == 'MUL':
            accumulator *= value
        elif op == 'DIV':
            assert value != 0
            quotient = abs(accumulator) // abs(value)
            accumulator = quotient if (accumulator >= 0) == (value >= 0) else -quotient
        else:
            raise AssertionError(f'Unknown test operation: {op}')
    return accumulator


def atomic_write(path, data, mode):
    temporary = path + '.verifier_tmp'
    with open(temporary, 'wb') as f:
        f.write(data)
    os.chmod(temporary, stat.S_IMODE(mode))
    os.replace(temporary, path)


def run_interpreter(expected):
    env = os.environ.copy()
    env['PATH'] = '/tmp/empty_path'
    env.pop('BASH_ENV', None)
    result = subprocess.run(['/bin/bash', '--restricted', INTERPRETER],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env, timeout=5)
    assert result.returncode == 0, (
        f"Interpreter failed under pure-Bash execution: status={result.returncode}, "
        f"stderr={result.stderr!r}"
    )
    output = result.stdout.decode('ascii', errors='strict')
    assert re.fullmatch(r'-?[0-9]+\n?', output), \
        f"Interpreter must output only the final integer, got {output!r}"
    assert int(output) == expected, f"Interpreter expected {expected}, got {output!r}"


def test_http_service_responses_and_dynamic_interpreter():
    # Retain the original repeated-response assertion for the extracted fixture.
    for _ in range(3):
        http_state(84)
        time.sleep(0.1)

    with open(COMMANDS, 'rb') as f:
        original_commands = f.read()
    commands_mode = os.stat(COMMANDS).st_mode
    with open(INTERPRETER, 'rb') as f:
        original_interpreter = f.read()
    interpreter_mode = os.stat(INTERPRETER).st_mode

    rng = secrets.SystemRandom()
    a, b, c, d = [rng.randint(2, 30) for _ in range(4)]
    cases = [
        f'ADD {a}\nMUL {b}\nSUB {c}\nDIV {d}\n',
        f'LOAD -{a}\nADD {b}\nMUL {c}\nDIV {d}\n',
        f'LOAD {a}\nSUB {b}\nMUL -{c}\nADD {d}\n',
        f'LOAD {a * b}\nDIV {b}\nADD {c}\nMUL {d}\nSUB {a}\n',
    ]

    try:
        for command_text in cases:
            expected = evaluate(command_text)
            atomic_write(COMMANDS, command_text.encode(), commands_mode)
            run_interpreter(expected)
            http_state(expected)

        # Replace the interpreter briefly with a random sentinel. This verifies
        # that the live HTTP service actually executes interpreter.sh rather
        # than independently returning or caching command results.
        sentinel = rng.randint(1000000, 9000000)
        sentinel_script = f'#!/bin/bash\nprintf "%s\\n" {sentinel}\n'.encode()
        atomic_write(INTERPRETER, sentinel_script, interpreter_mode)
        http_state(sentinel)
    finally:
        atomic_write(INTERPRETER, original_interpreter, interpreter_mode)
        atomic_write(COMMANDS, original_commands, commands_mode)

    # Confirm that restoration and another sequential request both work.
    run_interpreter(84)
    http_state(84)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
