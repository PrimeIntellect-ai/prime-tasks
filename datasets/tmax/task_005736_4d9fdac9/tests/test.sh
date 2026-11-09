#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_drag.py
import csv
import os
import re
import secrets
import subprocess
import sys
import tempfile

HOME = '/home/user'
DATA = os.path.join(HOME, 'trajectory_data.csv')
OUTPUT = os.path.join(HOME, 'optimal_c.txt')


def assert_original_output():
    assert os.path.exists(OUTPUT), f"Verification failed: {OUTPUT} not found."
    assert os.path.isfile(OUTPUT), f"Verification failed: {OUTPUT} is not a file."
    with open(OUTPUT, 'r') as f:
        content = f.read().strip()
    assert content == '0.45', f"Verification failed: Expected '0.45', got '{content}'"


def generate_dataset(path, c):
    m = 10.0
    g = 9.81
    dt = 0.01
    y = 1000.0
    v = 0.0
    rows = []
    for steps in range(1001):
        t = steps * dt
        if steps % 100 == 0:
            rows.append((round(t, 2), round(y, 4)))
        a = -g - (c / m) * v * abs(v)
        y_new = y + v * dt
        v_new = v + a * dt
        y, v = y_new, v_new
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['time', 'height'])
        writer.writerows(rows)


def run_program(executable):
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run([executable], cwd=HOME, check=True, timeout=45,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert os.path.exists(OUTPUT), 'The compiled C++ program did not create optimal_c.txt.'
    assert os.path.isfile(OUTPUT), 'optimal_c.txt is not a regular file.'
    with open(OUTPUT, 'r') as f:
        value = f.read().strip()
    assert re.fullmatch(r'(?:0|1)\.\d{2}', value), \
        f"Program output is not a single value formatted to two decimals: {value!r}"
    return value


# Preserve the original verifier's existence and exact-value assertions.
assert_original_output()

with open(DATA, 'rb') as f:
    original_data = f.read()

sources = []
for root, dirs, files in os.walk(HOME):
    for name in files:
        if name.endswith('.cpp'):
            path = os.path.join(root, name)
            if os.path.isfile(path) and not os.path.islink(path):
                sources.append(path)
assert sources, 'No C++ source file was found under /home/user.'
sources.sort(key=lambda p: (os.path.basename(p) != 'optimize_drag.cpp', p))

# Use unpredictable coefficients so a program that merely writes 0.45 cannot pass.
choices = [i for i in range(10, 101) if i != 45]
trial_cs = [secrets.choice(choices) / 100.0]
remaining = [i for i in choices if i != int(round(trial_cs[0] * 100))]
trial_cs.append(secrets.choice(remaining) / 100.0)

errors = []
passed = False
try:
    with tempfile.TemporaryDirectory(prefix='drag_verify_') as build_dir:
        for index, source in enumerate(sources):
            executable = os.path.join(build_dir, f'candidate_{index}')
            try:
                subprocess.run(['g++', '-std=c++17', '-O2', source, '-o', executable],
                               check=True, timeout=45,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)

                # Execute the submitted program against the task's original data.
                with open(DATA, 'wb') as f:
                    f.write(original_data)
                run_program(executable)
                assert_original_output()

                # Exercise the same program on independently generated Euler data.
                for expected_c in trial_cs:
                    generate_dataset(DATA, expected_c)
                    value = run_program(executable)
                    actual_c = float(value)
                    assert abs(actual_c - expected_c) < 0.005, \
                        f'For generated c={expected_c:.2f}, program returned {value}.'

                # Restore and verify the required final result once more.
                with open(DATA, 'wb') as f:
                    f.write(original_data)
                run_program(executable)
                assert_original_output()
                passed = True
                break
            except Exception as exc:
                errors.append(f'{source}: {exc}')

    assert passed, 'No submitted C++ program compiled and passed execution tests. ' + ' | '.join(errors)
finally:
    with open(DATA, 'wb') as f:
        f.write(original_data)

sys.exit(0)
PY_EOF

if python3 /tmp/verify_drag.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
