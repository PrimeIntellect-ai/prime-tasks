#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import subprocess
from pathlib import Path

PATIENTS = Path('/home/user/data/patients.csv')
MEASUREMENTS = Path('/home/user/data/measurements.csv')
OUTPUT = Path('/home/user/processed_data.csv')
HEADER = ['PatientID', 'Age', 'Condition', 'BiomarkerA', 'BiomarkerB', 'RiskScore']

ORIGINAL_PATIENTS = '''PatientID,Age,Condition
1,45,Healthy
2,60,AtRisk
3,30,Healthy
4,75,Critical
'''
ORIGINAL_MEASUREMENTS = '''PatientID,BiomarkerA,BiomarkerB
3,1.8,2.0
1,2.5,1.2
4,4.5,0.0
2,3.1,0.5
'''
ORIGINAL_EXPECTED = '''PatientID,Age,Condition,BiomarkerA,BiomarkerB,RiskScore
1,45,Healthy,2.50,1.20,93.75
2,60,AtRisk,3.10,0.50,372.00
3,30,Healthy,1.80,2.00,27.00
4,75,Critical,4.50,0.00,0.00'''


def normalized_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def find_go_programs():
    programs = []
    seen = set()
    roots = [Path('/home/user'), Path('/root'), Path('/tmp')]
    pruned_names = {'.cache', '.git', 'pkg', 'sumdb'}

    for root in roots:
        if not root.exists():
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in pruned_names]
            go_files = [f for f in files if f.endswith('.go') and not f.endswith('_test.go')]
            if not go_files:
                continue

            directory = Path(current)
            has_main = False
            package_main_files = []
            for name in go_files:
                path = directory / name
                try:
                    text = path.read_text(errors='ignore')
                except OSError:
                    continue
                if re.search(r'(?m)^\s*package\s+main\b', text):
                    package_main_files.append(path)
                    if re.search(r'\bfunc\s+main\s*\(', text):
                        has_main = True

            if has_main and package_main_files:
                key = str(directory.resolve())
                if key not in seen:
                    seen.add(key)
                    programs.append((directory, sorted(package_main_files)))

    assert programs, 'No executable Go source program was found.'
    return programs


def command_for_program(directory, files):
    current = directory.resolve()
    module_found = False
    while True:
        if (current / 'go.mod').is_file():
            module_found = True
            break
        if current.parent == current:
            break
        current = current.parent

    if module_found:
        return ['go', 'run', '.']
    return ['go', 'run'] + [str(path) for path in files]


def write_case(patient_rows, measurement_rows):
    PATIENTS.parent.mkdir(parents=True, exist_ok=True)
    with PATIENTS.open('w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['PatientID', 'Age', 'Condition'])
        writer.writerows(patient_rows)
    with MEASUREMENTS.open('w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['PatientID', 'BiomarkerA', 'BiomarkerB'])
        writer.writerows(measurement_rows)


def expected_for(patient_rows, measurement_rows):
    patients = {int(pid): (int(age), condition) for pid, age, condition in patient_rows}
    measurements = {int(pid): (float(a), float(b)) for pid, a, b in measurement_rows}
    rows = [HEADER]
    for pid in sorted(set(patients) & set(measurements)):
        age, condition = patients[pid]
        a, b = measurements[pid]
        risk = 0.0 if b == 0 else (age * a) / b
        rows.append([str(pid), str(age), condition, f'{a:.2f}', f'{b:.2f}', f'{risk:.2f}'])
    return '\n'.join(','.join(row) for row in rows)


def run_and_check(program, expected):
    directory, files = program
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        command_for_program(directory, files),
        cwd=directory,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f'Go program failed:\n{result.stdout}\n{result.stderr}'
    assert OUTPUT.is_file(), 'The executed Go program did not create /home/user/processed_data.csv.'
    actual = OUTPUT.read_text()
    assert normalized_lines(actual) == normalized_lines(expected), (
        f'Generated CSV is incorrect.\nExpected:\n{expected}\nActual:\n{actual}'
    )


def dynamic_cases():
    rng = random.SystemRandom()
    cases = []
    for count in (5, 7):
        ids = rng.sample(range(2, 900), count)
        patient_rows = []
        measurement_rows = []
        for index, pid in enumerate(ids):
            age = rng.randint(18, 90)
            biomarker_a = rng.randint(1, 12)
            biomarker_b = 0 if index == 0 else rng.choice([1, 2, 4])
            patient_rows.append([pid, age, f'Group{rng.randint(1, 9)}'])
            measurement_rows.append([pid, str(biomarker_a), str(biomarker_b)])
        rng.shuffle(patient_rows)
        rng.shuffle(measurement_rows)
        cases.append((patient_rows, measurement_rows))
    return cases


def test_processed_data_exists():
    assert OUTPUT.is_file(), 'File /home/user/processed_data.csv does not exist. The Go program must create it.'


def test_processed_data_content():
    content = OUTPUT.read_text().strip()
    assert normalized_lines(content) == normalized_lines(ORIGINAL_EXPECTED), (
        f'Content of /home/user/processed_data.csv is incorrect.\n'
        f'Expected:\n{ORIGINAL_EXPECTED}\nActual:\n{content}'
    )


def main():
    programs = find_go_programs()
    cases = dynamic_cases()
    failures = []

    for program in programs:
        try:
            for patient_rows, measurement_rows in cases:
                write_case(patient_rows, measurement_rows)
                run_and_check(program, expected_for(patient_rows, measurement_rows))

            PATIENTS.write_text(ORIGINAL_PATIENTS)
            MEASUREMENTS.write_text(ORIGINAL_MEASUREMENTS)
            run_and_check(program, ORIGINAL_EXPECTED)
            test_processed_data_exists()
            test_processed_data_content()
            return
        except Exception as exc:
            failures.append(f'{program[0]}: {exc}')

    raise AssertionError('No Go program passed all execution checks:\n' + '\n'.join(failures))


try:
    main()
finally:
    PATIENTS.write_text(ORIGINAL_PATIENTS)
    MEASUREMENTS.write_text(ORIGINAL_MEASUREMENTS)
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
