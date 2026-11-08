#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import stat
import subprocess
import tempfile
import uuid


def test_pipeline_script_exists_and_executable():
    path = '/home/user/pipeline.sh'
    assert os.path.exists(path), f"{path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, 'rb') as f:
        first_line = f.readline()
    assert first_line.startswith(b'#!') and b'bash' in first_line, f"{path} is not a bash script."


def test_filter_executable_exists():
    path = '/home/user/filter'
    assert os.path.exists(path), f"Compiled binary {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{path} is not an ELF binary."


def test_cleaned_csv_content():
    path = '/home/user/cleaned.csv'
    assert os.path.exists(path), f"{path} is missing."

    expected_lines = [
        "id,sensor_val,timestamp",
        "1,45.1,1620000001",
        "2,46.2,1620000002",
        "4,44.9,1620000004",
        "6,47.8,1620000006",
        "7,45.5,1620000007",
        "9,37.5,1620000009",
        "10,48.0,1620000010"
    ]

    with open(path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Content of {path} does not match expected filtered output."


def test_checksum_txt_content():
    cleaned_path = '/home/user/cleaned.csv'
    checksum_path = '/home/user/checksum.txt'

    assert os.path.exists(cleaned_path), f"{cleaned_path} is missing."
    assert os.path.exists(checksum_path), f"{checksum_path} is missing."

    with open(cleaned_path, 'rb') as f:
        expected_md5 = hashlib.md5(f.read()).hexdigest()

    with open(checksum_path, 'r') as f:
        checksum_content = f.read().strip()

    assert expected_md5 in checksum_content, f"{checksum_path} does not contain the correct MD5 checksum of {cleaned_path}."


def test_benchmark_txt_content():
    path = '/home/user/benchmark.txt'
    assert os.path.exists(path), f"{path} is missing."

    with open(path, 'r') as f:
        content = f.read()

    assert "real" in content, f"'real' timing missing in {path}."
    assert "user" in content, f"'user' timing missing in {path}."
    assert "sys" in content, f"'sys' timing missing in {path}."


def _exercise_filter(executable):
    rng = random.SystemRandom()
    mean = rng.uniform(-30.0, 70.0)
    stddev = rng.uniform(1.1, 6.0)
    rows = ['id,sensor_val,timestamp']
    expected = [rows[0]]
    z_values = [-4.1, -2.7, -2.4, -1.3, -0.15, 0.2, 1.8, 2.4, 2.7, 4.3]
    rng.shuffle(z_values)
    for i in range(40):
        z = z_values[i % len(z_values)] + rng.uniform(-0.025, 0.025)
        value = mean + z * stddev
        line = f'{i + 1},{value:.7f},{1900000000 + i}'
        rows.append(line)
        rounded_value = float(f'{value:.7f}')
        if abs(rounded_value - mean) / stddev <= 2.5:
            expected.append(line)
    data = '\n'.join(rows) + '\n'
    result = subprocess.run(
        [executable, f'{mean:.9f}', f'{stddev:.9f}'],
        input=data,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == '\n'.join(expected) + '\n', 'Filter produced incorrect output on generated decimal-valued input.'


def test_filter_binary_and_source_on_generated_inputs():
    _exercise_filter('/home/user/filter')
    source = '/home/user/filter.c'
    assert os.path.isfile(source), f"{source} is missing."
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, 'filter')
        compile_result = subprocess.run(
            ['gcc', '-O3', source, '-o', rebuilt, '-lm'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, compile_result.stderr
        _exercise_filter(rebuilt)


def test_pipeline_executes_timed_filter_and_regenerates_outputs():
    home = '/home/user'
    data_path = os.path.join(home, 'sensor_data.csv')
    filter_path = os.path.join(home, 'filter')
    pipeline_path = os.path.join(home, 'pipeline.sh')
    cleaned_path = os.path.join(home, 'cleaned.csv')
    benchmark_path = os.path.join(home, 'benchmark.txt')
    checksum_path = os.path.join(home, 'checksum.txt')

    token = uuid.uuid4().hex
    saved_filter = f'/tmp/filter-real-{token}'
    marker = f'/tmp/filter-marker-{token}'
    original_data = open(data_path, 'rb').read()

    rng = random.SystemRandom()
    rows = ['id,sensor_val,timestamp']
    expected = [rows[0]]
    offsets = [-13.0, -8.7, -7.7, -3.25, -0.4, 2.2, 7.6, 8.3, 12.0]
    rng.shuffle(offsets)
    for i in range(31):
        value = 45.5 + offsets[i % len(offsets)] + rng.uniform(-0.04, 0.04)
        line = f'{5000 + i},{value:.6f},{2000000000 + i}'
        rows.append(line)
        if abs(float(f'{value:.6f}') - 45.5) / 3.2 <= 2.5:
            expected.append(line)
    generated_data = ('\n'.join(rows) + '\n').encode()

    os.replace(filter_path, saved_filter)
    wrapper = f'''#!/bin/bash
printf '%s\\n' "$@" >> {marker}
sleep 0.20
exec {saved_filter} "$@"
'''
    with open(filter_path, 'w') as f:
        f.write(wrapper)
    os.chmod(filter_path, 0o755)

    try:
        with open(data_path, 'wb') as f:
            f.write(generated_data)
        for path in (cleaned_path, benchmark_path, checksum_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        run = subprocess.run(
            [pipeline_path],
            cwd=home,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run.returncode == 0, f'pipeline.sh failed: {run.stderr}'
        assert os.path.exists(marker), 'pipeline.sh did not execute /home/user/filter.'
        args = open(marker).read().splitlines()
        assert len(args) >= 2 and float(args[0]) == 45.5 and float(args[1]) == 3.2, 'pipeline.sh used incorrect filter arguments.'

        with open(cleaned_path) as f:
            actual = f.read()
        assert actual == '\n'.join(expected) + '\n', 'pipeline.sh did not generate cleaned.csv through the filter.'

        benchmark = open(benchmark_path).read()
        for name in ('real', 'user', 'sys'):
            assert re.search(rf'^{name}\s+[0-9]+(?:\.[0-9]+)?\s*$', benchmark, re.MULTILINE), f'Missing valid {name} timing.'
        real_match = re.search(r'^real\s+([0-9]+(?:\.[0-9]+)?)\s*$', benchmark, re.MULTILINE)
        assert float(real_match.group(1)) >= 0.15, 'The filter invocation was not measured by /usr/bin/time.'

        expected_md5 = hashlib.md5(actual.encode()).hexdigest()
        checksum = open(checksum_path).read().strip()
        assert checksum.split()[0] == expected_md5, 'pipeline.sh generated an incorrect checksum.'
    finally:
        try:
            os.remove(filter_path)
        except FileNotFoundError:
            pass
        if os.path.exists(saved_filter):
            os.replace(saved_filter, filter_path)
        with open(data_path, 'wb') as f:
            f.write(original_data)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass
        subprocess.run([pipeline_path], cwd=home, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
