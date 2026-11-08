#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import shlex
import shutil
import subprocess
from pathlib import Path

BASE = Path('/home/user/sensor_sim')
LIB = BASE / 'libsensor.so'
INPUT = BASE / 'requests.jsonl'
OUTPUT = BASE / 'processed_outputs.jsonl'

REQUESTS = [
    {'id': 'a', 'status': 'active', 'value': 4.5},
    {'id': 'b', 'status': 'inactive', 'value': 10.0},
    {'id': 'c', 'status': 'active', 'value': -2.0},
    {'id': 'd', 'status': 'active', 'value': 0},
    {'id': 'e', 'status': 'active', 'value': 1.23},
    {'id': 91, 'status': 'active', 'value': 0.01},
    {'id': 92, 'status': 'active', 'value': '5'},
    {'id': 93, 'value': 7.0},
]


def write_requests():
    with INPUT.open('w') as f:
        for obj in REQUESTS:
            f.write(json.dumps(obj, separators=(',', ':')) + '\n')


def expected_outputs(checksum_func):
    result = []
    for obj in REQUESTS:
        value = obj.get('value')
        valid = (obj.get('status') == 'active' and
                 isinstance(value, (int, float)) and
                 not isinstance(value, bool) and value > 0)
        if valid:
            result.append({'id': obj['id'], 'checksum': checksum_func(value)})
        else:
            result.append({'id': obj['id'], 'error': 'invalid_request'})
    return result


def read_outputs():
    assert OUTPUT.is_file(), f'Output file {OUTPUT} does not exist.'
    with OUTPUT.open() as f:
        lines = [line.strip() for line in f if line.strip()]
    return [json.loads(line) for line in lines]


def real_checksum(value):
    return int(math.pow(value * 100.0, 1.5)) % 997


def command_for(path):
    if os.access(path, os.X_OK):
        return [str(path)]
    suffix_commands = {
        '.py': ['python3'],
        '.sh': ['bash'],
        '.rb': ['ruby'],
        '.pl': ['perl'],
        '.js': ['node'],
    }
    if path.suffix.lower() in suffix_commands:
        command = suffix_commands[path.suffix.lower()]
        if shutil.which(command[0]):
            return command + [str(path)]
    try:
        first = path.open(errors='ignore').readline().strip()
    except (OSError, UnicodeError):
        return None
    if first.startswith('#!'):
        command = shlex.split(first[2:].strip())
        if command:
            return command + [str(path)]
    return None


def candidate_scripts():
    excluded = {
        'sensor_calc.c', 'Makefile', 'requests.jsonl',
        'processed_outputs.jsonl', 'libsensor.so'
    }
    files = [p for p in BASE.iterdir() if p.is_file() and p.name not in excluded
             and not p.name.endswith('.o')]
    priority = {'process.sh': 0, 'process.py': 1, 'process.rb': 2,
                'process.pl': 3, 'process.js': 4}
    return sorted(files, key=lambda p: (priority.get(p.name, 100), p.name))


def run_command(command):
    write_requests()
    if OUTPUT.exists():
        OUTPUT.unlink()
    subprocess.run(command, cwd=str(BASE), check=True, timeout=30)
    assert INPUT.is_file(), 'The processing script removed requests.jsonl.'
    with INPUT.open() as f:
        current = [json.loads(line) for line in f if line.strip()]
    assert current == REQUESTS, 'The processing script modified requests.jsonl.'


def find_and_run_processing_script():
    wanted = expected_outputs(real_checksum)
    attempted = []
    for path in candidate_scripts():
        command = command_for(path)
        if command is None:
            continue
        attempted.append(path.name)
        try:
            run_command(command)
            if read_outputs() == wanted:
                return command
        except (AssertionError, OSError, subprocess.SubprocessError,
                json.JSONDecodeError):
            continue
    raise AssertionError(
        'No created processing script could be executed successfully. '
        f'Attempted: {attempted}'
    )


# Exercise the submitted Makefile from a missing-library state.
dry_run = subprocess.check_output(
    ['make', '-Bn'], cwd=str(BASE), stderr=subprocess.STDOUT, text=True
)
assert '-fPIC' in dry_run, 'The Makefile compilation must use -fPIC.'
assert '-shared' in dry_run, 'The Makefile must link a shared library with -shared.'
assert '-lm' in dry_run, 'The Makefile must link the math library with -lm.'
if LIB.exists():
    LIB.unlink()
subprocess.run(['make'], cwd=str(BASE), check=True, timeout=30)

# Execute the agent-created processing artifact on verifier-controlled requests.
PROCESS_COMMAND = find_and_run_processing_script()


def test_libsensor_so_exists():
    path = '/home/user/sensor_sim/libsensor.so'
    assert os.path.isfile(path), f'Shared library {path} does not exist. Did you run make?'


def test_libsensor_so_is_valid_elf():
    path = '/home/user/sensor_sim/libsensor.so'
    try:
        output = subprocess.check_output(['file', path]).decode('utf-8')
        assert 'shared object' in output, f'{path} is not a valid shared object. Output: {output}'
    except FileNotFoundError:
        pass


def test_compute_sensor_checksum_symbol_and_behavior():
    library = ctypes.CDLL(str(LIB))
    function = library.compute_sensor_checksum
    function.argtypes = [ctypes.c_double]
    function.restype = ctypes.c_int
    for value in [0.01, 0.5, 1.23, 4.5, 17.75, 83.125]:
        assert function(value) == real_checksum(value), (
            f'compute_sensor_checksum({value}) returned {function(value)}, '
            f'expected {real_checksum(value)}'
        )


def test_processed_outputs_exists():
    path = '/home/user/sensor_sim/processed_outputs.jsonl'
    assert os.path.isfile(path), f'Output file {path} does not exist.'


def test_processed_outputs_content():
    input_path = '/home/user/sensor_sim/requests.jsonl'
    output_path = '/home/user/sensor_sim/processed_outputs.jsonl'
    assert os.path.isfile(input_path), f'Input file {input_path} is missing.'
    assert os.path.isfile(output_path), f'Output file {output_path} is missing.'

    with open(input_path, 'r') as f:
        inputs = [json.loads(line.strip()) for line in f if line.strip()]
    with open(output_path, 'r') as f:
        outputs = [json.loads(line.strip()) for line in f if line.strip()]

    assert inputs == REQUESTS, 'requests.jsonl was altered during processing.'
    assert len(outputs) == len(inputs), f'Expected {len(inputs)} lines in output, got {len(outputs)}.'

    for in_obj, out_obj in zip(inputs, outputs):
        assert 'id' in out_obj, f"Output object missing 'id': {out_obj}"
        assert out_obj['id'] == in_obj['id'], f"Expected id {in_obj['id']}, got {out_obj.get('id')}"
        value = in_obj.get('value', 0)
        is_valid = (in_obj.get('status') == 'active' and
                    isinstance(value, (int, float)) and
                    not isinstance(value, bool) and value > 0)
        if is_valid:
            assert 'checksum' in out_obj, f"Expected valid request to have 'checksum', got: {out_obj}"
            assert 'error' not in out_obj, f"Valid request should not have 'error', got: {out_obj}"
            expected_checksum = real_checksum(value)
            assert out_obj['checksum'] == expected_checksum, (
                f"For id {in_obj['id']} (value={value}), expected checksum "
                f"{expected_checksum}, got {out_obj['checksum']}"
            )
            assert set(out_obj) == {'id', 'checksum'}, f'Unexpected output fields: {out_obj}'
        else:
            assert 'error' in out_obj, f"Expected invalid request to have 'error', got: {out_obj}"
            assert 'checksum' not in out_obj, f"Invalid request should not have 'checksum', got: {out_obj}"
            assert out_obj['error'] == 'invalid_request', (
                f"For id {in_obj['id']}, expected error 'invalid_request', got '{out_obj['error']}'"
            )
            assert set(out_obj) == {'id', 'error'}, f'Unexpected output fields: {out_obj}'


def test_processing_script_uses_libsensor_ffi():
    probe_source = Path('/tmp/sensor_probe.c')
    probe_library = Path('/tmp/libsensor_probe.so')
    saved_library = Path('/tmp/libsensor_saved.so')
    probe_source.write_text(
        'int compute_sensor_checksum(double value) { (void)value; return 424242; }\n'
    )
    subprocess.run(
        ['gcc', '-fPIC', '-shared', '-o', str(probe_library), str(probe_source)],
        check=True, timeout=30
    )
    shutil.copy2(LIB, saved_library)
    try:
        shutil.copy2(probe_library, LIB)
        run_command(PROCESS_COMMAND)
        assert read_outputs() == expected_outputs(lambda value: 424242), (
            'Processing results did not follow the substituted libsensor.so; '
            'the script must call compute_sensor_checksum through FFI.'
        )
    finally:
        shutil.copy2(saved_library, LIB)
        run_command(PROCESS_COMMAND)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
