#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

CPP_PATH = '/home/user/etl_pipeline.cpp'
SCRIPT_PATH = '/home/user/run_pipeline.sh'
EXE_PATH = '/home/user/etl.out'
SUMMARY_PATH = '/home/user/summary.csv'
RAW_PATH = '/home/user/raw_data.csv'
VERIFIER_EXE = '/tmp/verifier_etl.out'


def run(command):
    return subprocess.run(command, cwd='/home/user', capture_output=True, text=True, timeout=20)


def read_summary():
    with open(SUMMARY_PATH, 'r') as f:
        return [line.strip() for line in f.read().strip().splitlines() if line.strip()]


def make_dynamic_case():
    rng = secrets.SystemRandom()
    numbers = set()
    while len(numbers) < 4:
        numbers.add(rng.randrange(10000, 99999999))
    ids = [f'S-{n}' for n in numbers]
    a, b, c, d = ids
    base = rng.randrange(100000000, 1900000000)

    values = {
        a: [10.25, 20.25],
        b: [-50.0, 50.0],
        c: [-10.0, 5.0, 20.0],
        d: [10.0],
    }

    rows = []
    timestamp = base
    for sensor_id, temperatures in values.items():
        for temperature in temperatures:
            rows.append(f'{timestamp},{sensor_id},{temperature},OK')
            timestamp += 1

    # Valid ERR records must be ignored.
    rows.extend([
        f'{timestamp},{a},49.0,ERR',
        f'{timestamp + 1},{d},-49.0,ERR',
    ])
    timestamp += 2

    # Every row below violates at least one schema rule and must be discarded.
    rows.extend([
        f'0,{a},40.0,OK',
        f'-1,{a},40.0,OK',
        f'{timestamp}x,{a},40.0,OK',
        f'invalid,{a},40.0,OK',
        f'{timestamp + 1},S-,22.0,OK',
        f'{timestamp + 2},S-12x,22.0,OK',
        f'{timestamp + 3},X-123,22.0,OK',
        f'{timestamp + 4},{a},50.0001,OK',
        f'{timestamp + 5},{a},-50.0001,OK',
        f'{timestamp + 6},{a},12x,OK',
        f'{timestamp + 7},{a},nan,OK',
        f'{timestamp + 8},{a},inf,OK',
        f'{timestamp + 9},{a},12.0,ok',
        f'{timestamp + 10},{a},12.0,OK ',
        f'{timestamp + 11},{a},12.0,ERRx',
        f'{timestamp + 12},{a},12.0,OK,extra',
        f'{timestamp + 13},{a},OK',
        f'{timestamp + 14},,12.0,OK',
        f'{timestamp + 15},{a},,OK',
    ])
    rng.shuffle(rows)

    expected = [
        f'{sensor_id},{sum(temperatures) / len(temperatures):.2f}'
        for sensor_id, temperatures in sorted(values.items())
    ]
    return '\n'.join(rows) + '\n', expected


def install_case(data):
    with open(RAW_PATH, 'w') as f:
        f.write(data)
    if os.path.exists(SUMMARY_PATH):
        os.remove(SUMMARY_PATH)


def assert_case(executable, data, expected):
    install_case(data)
    result = run([executable])
    assert result.returncode == 0, (
        f'Execution of {executable} failed.\n'
        f'Stdout: {result.stdout}\nStderr: {result.stderr}'
    )
    assert os.path.isfile(SUMMARY_PATH), f'{SUMMARY_PATH} was not generated.'
    assert read_summary() == expected, (
        f'Incorrect output for a verifier-generated input.\n'
        f'Expected: {expected}\nGot: {read_summary()}'
    )


def test_cpp_file_exists():
    assert os.path.isfile(CPP_PATH), f'{CPP_PATH} does not exist.'


def test_bash_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} does not exist.'
    assert os.access(SCRIPT_PATH, os.X_OK), f'{SCRIPT_PATH} is not executable.'


def test_pipeline_execution_and_output():
    # Independently compile the submitted source before allowing the pipeline
    # script to run, so the dynamic tests exercise the requested C++ artifact.
    compile_result = run(['g++', '-std=c++17', CPP_PATH, '-o', VERIFIER_EXE])
    assert compile_result.returncode == 0, (
        f'Compiling {CPP_PATH} with g++ -std=c++17 failed.\n'
        f'Stdout: {compile_result.stdout}\nStderr: {compile_result.stderr}'
    )

    # Execute the pipeline script against the original fixture.
    result = run([SCRIPT_PATH])
    assert result.returncode == 0, f'Execution of {SCRIPT_PATH} failed.\nStdout: {result.stdout}\nStderr: {result.stderr}'

    # Check if executable was created.
    assert os.path.isfile(EXE_PATH), f'{EXE_PATH} was not created by the bash script.'
    assert os.access(EXE_PATH, os.X_OK), f'{EXE_PATH} is not executable.'
    with open(EXE_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{EXE_PATH} is not a compiled ELF executable.'

    # Check if summary.csv was created.
    assert os.path.isfile(SUMMARY_PATH), f'{SUMMARY_PATH} was not generated.'

    expected_output = [
        'S-001,26.50',
        'S-002,11.00',
        'S-004,49.90',
        'S-005,-13.33'
    ]

    actual_output = read_summary()
    assert actual_output == expected_output, (
        f'The content of {SUMMARY_PATH} is incorrect.\n'
        f'Expected:\n{expected_output}\n'
        f'Got:\n{actual_output}'
    )

    # Exercise the executable produced by run_pipeline.sh on an unpredictable
    # input, preventing the script from merely writing the fixed fixture answer.
    data, expected = make_dynamic_case()
    assert_case(EXE_PATH, data, expected)

    # Exercise the independently compiled original source on another fresh case,
    # ensuring parsing, validation, aggregation, sorting, and formatting are in C++.
    data, expected = make_dynamic_case()
    assert_case(VERIFIER_EXE, data, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
