#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path

INPUT_PATH = Path('/home/user/sensor_data.csv')
OUTPUT_PATH = Path('/home/user/etl_output.json')


def compute_expected_output(csv_path):
    valid_data = {}
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            temp = float(row['temperature'])
            hum = float(row['humidity'])
            sensor_id = row['sensor_id']
            timestamp = row['timestamp']

            if -20.0 <= temp <= 50.0 and 0.0 <= hum <= 100.0:
                if sensor_id not in valid_data:
                    valid_data[sensor_id] = []
                valid_data[sensor_id].append({'time': timestamp, 'temp': temp, 'hum': hum})

    # Ensure chronological processing
    for sensor_id in valid_data:
        valid_data[sensor_id].sort(key=lambda x: x['time'])

    rolling_temp_sma = {}
    max_humidity = {}

    for sensor_id, records in valid_data.items():
        if not records:
            continue

        # Summary Aggregation: Max Humidity
        max_humidity[sensor_id] = round(max(r['hum'] for r in records), 1)

        # Rolling Aggregation: SMA of valid temperatures
        sma = []
        temps = [r['temp'] for r in records]
        for i in range(len(temps) - 2):
            window = temps[i:i+3]
            avg = sum(window) / 3.0
            sma.append(round(avg, 1))
        rolling_temp_sma[sensor_id] = sma

    return {
        'rolling_temp_sma': rolling_temp_sma,
        'max_humidity': max_humidity
    }


def load_json(path):
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        assert False, f'The file {path} does not contain valid JSON.'


def test_etl_output_exists():
    assert os.path.exists(OUTPUT_PATH), f'The expected output file {OUTPUT_PATH} does not exist.'
    assert os.path.isfile(OUTPUT_PATH), f'{OUTPUT_PATH} is not a valid file.'


def test_etl_output_correctness():
    assert os.path.exists(INPUT_PATH), f'The input file {INPUT_PATH} is missing.'
    assert os.path.exists(OUTPUT_PATH), f'The output file {OUTPUT_PATH} is missing.'

    expected_result = compute_expected_output(INPUT_PATH)
    actual_result = load_json(OUTPUT_PATH)

    assert 'rolling_temp_sma' in actual_result, "Missing 'rolling_temp_sma' key in the output JSON."
    assert 'max_humidity' in actual_result, "Missing 'max_humidity' key in the output JSON."

    expected_max_hum = expected_result['max_humidity']
    actual_max_hum = actual_result['max_humidity']
    for sensor_id, expected_val in expected_max_hum.items():
        assert sensor_id in actual_max_hum, f"Missing sensor_id '{sensor_id}' in 'max_humidity'."
        assert actual_max_hum[sensor_id] == expected_val, (
            f"Incorrect max_humidity for sensor '{sensor_id}'. "
            f'Expected {expected_val}, got {actual_max_hum[sensor_id]}.'
        )

    expected_sma = expected_result['rolling_temp_sma']
    actual_sma = actual_result['rolling_temp_sma']
    for sensor_id, expected_val in expected_sma.items():
        assert sensor_id in actual_sma, f"Missing sensor_id '{sensor_id}' in 'rolling_temp_sma'."
        assert actual_sma[sensor_id] == expected_val, (
            f"Incorrect rolling_temp_sma for sensor '{sensor_id}'. "
            f'Expected {expected_val}, got {actual_sma[sensor_id]}.'
        )


def invocation_commands(path):
    suffix_commands = {
        '.py': ['python3'],
        '.sh': ['bash'],
        '.bash': ['bash'],
        '.pl': ['perl'],
        '.rb': ['ruby'],
        '.js': ['node'],
        '.php': ['php'],
        '.lua': ['lua'],
        '.r': ['Rscript'],
        '.awk': ['awk', '-f'],
    }
    commands = []
    base = suffix_commands.get(path.suffix.lower())
    if base and shutil.which(base[0]):
        commands.append(base + [str(path)])

    try:
        first_line = path.open('r', errors='ignore').readline().strip()
        if first_line.startswith('#!'):
            shebang = shlex.split(first_line[2:].strip())
            if shebang:
                commands.append(shebang + [str(path)])
    except (OSError, UnicodeError):
        pass

    if os.access(path, os.X_OK):
        commands.append([str(path)])

    unique = []
    seen = set()
    for command in commands:
        key = tuple(command)
        if key not in seen:
            seen.add(key)
            unique.append(command)
    return unique


def find_script_candidates():
    excluded = {
        INPUT_PATH.resolve(),
        OUTPUT_PATH.resolve(),
        Path('/home/user/.bash_logout').resolve(),
        Path('/home/user/.bashrc').resolve(),
        Path('/home/user/.profile').resolve(),
    }
    candidates = []
    for path in Path('/home/user').rglob('*'):
        try:
            if path.is_file() and path.resolve() not in excluded and invocation_commands(path):
                candidates.append(path)
        except OSError:
            continue
    return candidates


def test_submitted_script_processes_new_input():
    challenge = '''timestamp,sensor_id,temperature,humidity
2024-05-01T00:03:00Z,X,6.0,30.0
2024-05-01T00:02:00Z,A,5.0,50.0
2024-05-01T00:00:00Z,X,0.0,10.0
2024-05-01T00:00:00Z,A,50.0,0.0
2024-05-01T00:04:00Z,X,9.0,101.0
2024-05-01T00:01:00Z,X,3.0,20.0
2024-05-01T00:01:00Z,A,-20.0,100.0
2024-05-01T00:02:00Z,X,99.0,25.0
2024-05-01T00:05:00Z,X,-3.0,100.0
2024-05-01T00:00:00Z,B,1.0,25.0
2024-05-01T00:01:00Z,B,2.0,35.0
2024-05-01T00:03:00Z,A,4.0,-1.0
'''
    candidates = find_script_candidates()
    assert candidates, 'No runnable ETL processing script was found under /home/user.'

    original_input = INPUT_PATH.read_bytes()
    original_output = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() else None
    success = False
    errors = []

    try:
        INPUT_PATH.write_text(challenge)
        expected = compute_expected_output(INPUT_PATH)

        for candidate in candidates:
            for command in invocation_commands(candidate):
                INPUT_PATH.write_text(challenge)
                if OUTPUT_PATH.exists():
                    OUTPUT_PATH.unlink()
                try:
                    result = subprocess.run(
                        command,
                        cwd='/home/user',
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=15,
                    )
                except (OSError, subprocess.TimeoutExpired) as exc:
                    errors.append(f'{candidate}: {exc}')
                    continue

                if result.returncode != 0:
                    errors.append(f'{candidate}: exited with status {result.returncode}')
                    continue
                if not OUTPUT_PATH.is_file():
                    errors.append(f'{candidate}: did not create {OUTPUT_PATH}')
                    continue
                try:
                    actual = load_json(OUTPUT_PATH)
                except AssertionError as exc:
                    errors.append(f'{candidate}: {exc}')
                    continue
                if actual == expected:
                    success = True
                    break
                errors.append(f'{candidate}: output was incorrect for the verification input')
            if success:
                break
    finally:
        INPUT_PATH.write_bytes(original_input)
        if original_output is None:
            if OUTPUT_PATH.exists():
                OUTPUT_PATH.unlink()
        else:
            OUTPUT_PATH.write_bytes(original_output)

    assert success, 'No submitted script generated the correct output when executed on new input. ' + '; '.join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
