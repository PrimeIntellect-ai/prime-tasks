#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import stat
import subprocess

SCRIPT = '/home/user/analyze.sh'
DATASET = '/home/user/metrics.csv'
OUTPUTS = {
    'zero': '/home/user/zero_variance_cols.txt',
    'correlation': '/home/user/correlation.txt',
    'ci': '/home/user/ci.txt',
}

ORIGINAL = '''ID,CPU,Memory,Response_Time,Const1,Const2,Status
1,50.5,60.2,120,42,10,OK
2,55.0,65.0,135,42,10,OK
3,NaN,70.1,140,42,10,OK
4,60.2,70.5,150,42,10,ERROR
5,45.1,55.1,110,42,10,OK
6,48.0,58.0,115,42,10,OK
7,62.5,72.3,160,42,10,OK
8,58.9,68.9,145,42,10,OK
9,40.5,50.5,100,42,10,OK
10,65.2,75.1,170,42,10,OK
'''


def inspect_script():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} is not a regular file."
    assert os.path.getsize(SCRIPT) > 0, f"{SCRIPT} is empty."
    subprocess.run(['/bin/bash', '-n', SCRIPT], check=True, timeout=10)
    with open(SCRIPT, 'r', errors='replace') as f:
        source = f.read()
    assert re.search(r'(?m)^\s*LC_NUMERIC\s*=\s*["\']?C["\']?', source), \
        'analyze.sh must set LC_NUMERIC=C.'
    assert re.search(r'(?m)^\s*export(?:\s+[^\n;]*)?\bLC_NUMERIC\b', source), \
        'analyze.sh must export LC_NUMERIC.'


def run_case(csv_text):
    inspect_script()
    with open(DATASET, 'w') as f:
        f.write(csv_text)
    for path in OUTPUTS.values():
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                raise AssertionError(f'{path} must be an output file, not a directory.')
            os.remove(path)
    subprocess.run(['/bin/bash', SCRIPT], cwd='/home/user', check=True, timeout=20)
    result = {}
    for name, path in OUTPUTS.items():
        assert os.path.isfile(path), f"File {path} is missing after running analyze.sh."
        with open(path, 'r') as f:
            result[name] = f.read().strip()
    return result


def expected_for(valid_rows):
    # Status is necessarily constant after filtering, so dimensionality reduction
    # is evaluated over the six data columns, consistent with the required result.
    zero = []
    for column in range(6):
        if all(row[column] == valid_rows[0][column] for row in valid_rows):
            zero.append(str(column + 1))

    cpu = [float(row[1]) for row in valid_rows]
    memory = [float(row[2]) for row in valid_rows]
    response = [float(row[3]) for row in valid_rows]
    n = len(valid_rows)

    cpu_mean = sum(cpu) / n
    memory_mean = sum(memory) / n
    numerator = sum((x - cpu_mean) * (y - memory_mean) for x, y in zip(cpu, memory))
    denominator = math.sqrt(
        sum((x - cpu_mean) ** 2 for x in cpu) *
        sum((y - memory_mean) ** 2 for y in memory)
    )
    correlation = numerator / denominator

    mean = sum(response) / n
    sample_sd = math.sqrt(sum((x - mean) ** 2 for x in response) / (n - 1))
    margin = 1.96 * sample_sd / math.sqrt(n)
    return {
        'zero': ','.join(zero),
        'correlation': f'{correlation:.3f}',
        'ci': f'{mean:.3f},{mean - margin:.3f},{mean + margin:.3f}',
    }


def make_dynamic_case(constant_column):
    salt = secrets.randbelow(5000) + 1000
    cpu_values = [11, 18, 23, 31, 44, 52]
    memory_values = [17, 29, 21, 42, 38, 61]
    response_values = [73, 91, 86, 118, 127, 149]
    valid = []
    for i in range(6):
        const1 = 700 + salt if constant_column == 5 else 700 + salt + i
        const2 = 900 + salt if constant_column == 6 else 900 + salt + 2 * i
        valid.append([
            str(salt + i),
            str(cpu_values[i] + salt / 100.0),
            str(memory_values[i] + salt / 200.0),
            str(response_values[i] + salt % 37),
            str(const1),
            str(const2),
            'OK',
        ])

    lines = ['ID,CPU,Memory,Response_Time,Const1,Const2,Status']
    lines.extend(','.join(row) for row in valid[:3])
    lines.extend([
        f'{salt+50},NaN,88,111,1,2,OK',
        f'{salt+51},20,30,120,,2,OK',
        f'{salt+52},20,30,120,1,2,ERROR',
        f'{salt+53},20,30,120,1,OK',
        f'NaN,20,30,120,1,2,OK',
    ])
    lines.extend(','.join(row) for row in valid[3:])
    return '\n'.join(lines) + '\n', valid


def test_zero_variance_cols():
    """Test that zero_variance_cols.txt contains the correct zero variance columns."""
    result = run_case(ORIGINAL)
    file_path = '/home/user/zero_variance_cols.txt'
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    content = result['zero']
    assert content == "5,6", f"Expected '5,6' in {file_path}, but got '{content}'."


def test_correlation():
    """Test that correlation.txt contains the correct Pearson correlation coefficient."""
    result = run_case(ORIGINAL)
    file_path = '/home/user/correlation.txt'
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    content = result['correlation']
    assert content == "0.999", f"Expected '0.999' in {file_path}, but got '{content}'."


def test_ci():
    """Test that ci.txt contains the correct mean and confidence interval."""
    result = run_case(ORIGINAL)
    file_path = '/home/user/ci.txt'
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    content = result['ci']
    assert content == "131.875,114.607,149.143", f"Expected '131.875,114.607,149.143' in {file_path}, but got '{content}'."


def test_script_exists():
    """Test that the analyze.sh script was created."""
    file_path = '/home/user/analyze.sh'
    assert os.path.isfile(file_path), f"Script {file_path} is missing."
    inspect_script()


def test_script_processes_unseen_inputs():
    for constant_column in (5, 6):
        csv_text, valid_rows = make_dynamic_case(constant_column)
        actual = run_case(csv_text)
        expected = expected_for(valid_rows)
        assert actual == expected, f'Incorrect results for generated dataset: expected {expected}, got {actual}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
