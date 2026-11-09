#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_final_state.py
import math
import os
import re
import shlex
import subprocess
from pathlib import Path

HOME = Path('/home/user')
RAW = HOME / 'sensor_data.csv'
CLEAN = HOME / 'clean_data.csv'
CORR = HOME / 'correlation.txt'

EXPECTED_ORIGINAL = """timestamp,sensor_A,sensor_B
t1,10.0,20.0
t2,12.0,25.0
t4,9.0,19.0
t5,15.0,31.0
t6,14.0,27.0
t7,16.0,33.0
t9,8.0,16.0
t11,11.0,22.0"""

FIXTURES = [
    """timestamp,sensor_A,sensor_B
A1,1,2
B2,2.5,8
C3,-1.0,4.5
bad_stamp,3,4
D4,4.0,-2
E5,.,3
F6,6,7,extra
G7,7x,8
H8,0,1
""",
    """timestamp,sensor_A,sensor_B
x1,10,100
x2,20,80
x3,30,70
x4,40,20
bad-5,50,0
x6,-5.5,120.25
x7,12,NaN
x8,9
x9,6.25,91.5
""",
]

number_re = re.compile(r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$')
timestamp_re = re.compile(r'^[A-Za-z0-9]+$')
forbidden_re = re.compile(r'^(?:python(?:[0-9]+(?:\.[0-9]+)*)?|perl|ruby)$', re.I)


def expected_for(raw):
    lines = raw.splitlines()
    valid = []
    for line in lines[1:]:
        fields = line.split(',')
        if (len(fields) == 3 and timestamp_re.fullmatch(fields[0]) and
                number_re.fullmatch(fields[1]) and number_re.fullmatch(fields[2])):
            valid.append(line)

    xs = [float(line.split(',')[1]) for line in valid]
    ys = [float(line.split(',')[2]) for line in valid]
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    numerator = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    denominator = math.sqrt(sum((x - mx) ** 2 for x in xs) *
                            sum((y - my) ** 2 for y in ys))
    return 'timestamp,sensor_A,sensor_B\n' + '\n'.join(valid), f'{numerator / denominator:.4f}'


def candidate_scripts():
    result = []
    excluded = {RAW.resolve(), CLEAN.resolve(), CORR.resolve()}
    for path in HOME.rglob('*'):
        try:
            if not path.is_file() or path.resolve() in excluded or path.stat().st_size > 1024 * 1024:
                continue
            data = path.read_bytes()
        except (OSError, UnicodeError):
            continue
        first = data.splitlines()[0] if data.splitlines() else b''
        shell_shebang = re.match(br'^#!.*(?:/|\b)(?:ba|da|k|z)?sh(?:\s|$)', first) is not None
        if path.suffix == '.sh' or shell_shebang or os.access(path, os.X_OK):
            result.append(path)
    return result


def has_forbidden_language(script, trace=''):
    try:
        text = script.read_text(errors='replace')
    except OSError:
        return True
    for line in text.splitlines():
        if line.lstrip().startswith('#'):
            continue
        try:
            tokens = shlex.split(line, comments=True)
        except ValueError:
            tokens = line.split()
        if any(forbidden_re.fullmatch(os.path.basename(token)) for token in tokens):
            return True
    for line in trace.splitlines():
        if not line.startswith('+'):
            continue
        try:
            tokens = shlex.split(line.lstrip('+ '))
        except ValueError:
            tokens = line.split()
        if any(forbidden_re.fullmatch(os.path.basename(token)) for token in tokens):
            return True
    return False


def run_candidate(script):
    if has_forbidden_language(script):
        return False
    for fixture in FIXTURES:
        RAW.write_text(fixture)
        for output in (CLEAN, CORR):
            try:
                output.unlink()
            except FileNotFoundError:
                pass
        try:
            proc = subprocess.run(
                ['/bin/bash', '-x', str(script)], cwd=str(HOME),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=10, env=os.environ.copy())
        except (OSError, subprocess.TimeoutExpired):
            return False
        if proc.returncode != 0 or has_forbidden_language(script, proc.stderr):
            return False
        if not CLEAN.is_file() or not CORR.is_file():
            return False
        expected_clean, expected_corr = expected_for(fixture)
        if CLEAN.read_text().strip() != expected_clean:
            return False
        if CORR.read_text().strip() != expected_corr:
            return False
    return True


def test_original_outputs_and_pipeline():
    # Preserve the original verifier's assertions for the supplied fixture.
    assert CLEAN.exists(), f'The file {CLEAN} does not exist.'
    assert CLEAN.is_file(), f'The path {CLEAN} is not a file.'
    assert CLEAN.read_text().strip() == EXPECTED_ORIGINAL, \
        f'The content of {CLEAN} does not match the expected cleaned data.'

    assert CORR.exists(), f'The file {CORR} does not exist.'
    assert CORR.is_file(), f'The path {CORR} is not a file.'
    correlation = CORR.read_text().strip()
    assert correlation == '0.9960', \
        f"The correlation value in {CORR} is expected to be '0.9960', but got '{correlation}'."

    scripts = candidate_scripts()
    assert scripts, 'No Bash pipeline script was found under /home/user.'

    saved = {path: path.read_bytes() for path in (RAW, CLEAN, CORR)}
    try:
        assert any(run_candidate(script) for script in scripts), \
            'No Bash-only pipeline correctly handled the additional sensor-data fixtures.'
    finally:
        for path, data in saved.items():
            path.write_bytes(data)
PY

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
