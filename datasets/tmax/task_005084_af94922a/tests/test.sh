#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import secrets
import stat
import subprocess
from pathlib import Path

import numpy as np
from scipy.optimize import curve_fit

SCRIPT = Path('/home/user/analyze_primers.py')
OUTPUT = Path('/home/user/valid_primers_tm.csv')
REFERENCE = Path('/home/user/reference.fasta')
PRIMERS = Path('/home/user/primers.fasta')
MELTING = Path('/home/user/melting_data.csv')


def logistic(t, L, k, Tm, b):
    return L / (1 + np.exp(-k * (t - Tm))) + b


def reverse_complement(seq):
    table = str.maketrans('ACGTacgt', 'TGCAtgca')
    return seq.translate(table)[::-1]


def occurrences(haystack, needle):
    count = 0
    start = 0
    while True:
        pos = haystack.find(needle, start)
        if pos < 0:
            return count
        count += 1
        start = pos + 1


def match_count(reference, primer):
    return occurrences(reference, primer) + occurrences(reference, reverse_complement(primer))


def assert_script_and_multiprocessing():
    assert SCRIPT.exists(), f'Required script {SCRIPT} does not exist.'
    mode = SCRIPT.lstat().st_mode
    assert stat.S_ISREG(mode) and not SCRIPT.is_symlink(), f'{SCRIPT} must be a regular Python file.'

    source = SCRIPT.read_text()
    try:
        tree = ast.parse(source, filename=str(SCRIPT))
    except SyntaxError as exc:
        raise AssertionError(f'{SCRIPT} is not valid Python: {exc}')

    multiprocessing_imported = False
    module_aliases = set()
    pool_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                if item.name == 'multiprocessing' or item.name.startswith('multiprocessing.'):
                    multiprocessing_imported = True
                    module_aliases.add(item.asname or item.name.split('.')[0])
        elif isinstance(node, ast.ImportFrom) and node.module and (
            node.module == 'multiprocessing' or node.module.startswith('multiprocessing.')
        ):
            multiprocessing_imported = True
            for item in node.names:
                if item.name == 'Pool':
                    pool_aliases.add(item.asname or item.name)

    pool_called = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in pool_aliases:
            pool_called = True
        elif isinstance(node.func, ast.Attribute) and node.func.attr == 'Pool':
            # Covers multiprocessing.Pool(), mp.Pool(), and get_context().Pool().
            if multiprocessing_imported:
                pool_called = True

    assert multiprocessing_imported, 'The script must import Python multiprocessing.'
    assert pool_called, 'The script must construct and use a multiprocessing Pool for curve fitting.'


def run_script():
    completed = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f'{SCRIPT} failed with exit code {completed.returncode}.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    assert OUTPUT.is_file(), f'Output file {OUTPUT} does not exist after executing the script.'


def read_output():
    with OUTPUT.open(newline='') as f:
        return list(csv.reader(f))


def assert_original_output():
    rows = read_output()
    assert len(rows) > 0, 'Output CSV is empty.'
    header = rows[0]
    assert header == ['primer_id', 'Tm'], f"Header is incorrect. Expected ['primer_id', 'Tm'], got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 2, f'Expected exactly 2 data rows for valid unique primers, got {len(data_rows)}.'

    primer_ids = [row[0] for row in data_rows]
    assert primer_ids == ['P1', 'P4'], f"Expected primer_ids to be ['P1', 'P4'] (sorted alphabetically), got {primer_ids}."

    try:
        p1_tm = float(data_rows[0][1])
        p4_tm = float(data_rows[1][1])
    except (ValueError, IndexError):
        raise AssertionError('Tm values in the CSV must be numeric.')

    assert abs(p1_tm - 65.20) <= 0.05, f'P1 Tm value {p1_tm} is outside the acceptable range (65.20 +/- 0.05).'
    assert abs(p4_tm - 68.45) <= 0.05, f'P4 Tm value {p4_tm} is outside the acceptable range (68.45 +/- 0.05).'

    p1_str = data_rows[0][1].strip()
    p4_str = data_rows[1][1].strip()
    assert '.' in p1_str and len(p1_str.split('.')[1]) == 2, f"P1 Tm '{p1_str}' is not rounded to exactly 2 decimal places."
    assert '.' in p4_str and len(p4_str.split('.')[1]) == 2, f"P4 Tm '{p4_str}' is not rounded to exactly 2 decimal places."


def make_hidden_case():
    rng = np.random.default_rng(secrets.randbits(64))
    alphabet = np.array(list('ACGT'))
    reference = ''.join(rng.choice(alphabet, size=750)) + 'ACGTA' + 'GGCCGGCC' + 'ACGTA'

    selected = []
    for pos in rng.permutation(len(reference) - 18):
        fragment = reference[int(pos):int(pos) + 17]
        if fragment != reverse_complement(fragment) and match_count(reference, fragment) == 1:
            selected.append(fragment)
        if len(selected) == 3:
            break
    assert len(selected) == 3, 'Could not construct hidden unique-primer case.'

    zero = None
    for _ in range(1000):
        candidate = ''.join(rng.choice(alphabet, size=17))
        if match_count(reference, candidate) == 0:
            zero = candidate
            break
    assert zero is not None

    primers = {
        'Zeta_hidden': selected[0],
        'Alpha_hidden': reverse_complement(selected[1]),
        'Mu_hidden': selected[2],
        'Repeat_hidden': 'ACGTA',
        'Absent_hidden': zero,
    }

    valid_ids = sorted(pid for pid, seq in primers.items() if match_count(reference, seq) == 1)
    assert valid_ids == ['Alpha_hidden', 'Mu_hidden', 'Zeta_hidden']

    temperatures = np.linspace(43.0, 89.0, 57)
    fitted = {}
    records = []
    for index, pid in enumerate(primers):
        true_tm = float(rng.uniform(54.0, 78.0))
        L = float(rng.uniform(70.0, 135.0))
        k = float(rng.uniform(0.28, 0.75))
        b = float(rng.uniform(3.0, 18.0))
        fluorescence = logistic(temperatures, L, k, true_tm, b)
        fluorescence += rng.normal(0.0, 0.025, size=len(temperatures))
        for t, fl in zip(temperatures, fluorescence):
            records.append((pid, float(t), float(fl)))

        params, _ = curve_fit(
            logistic,
            temperatures,
            fluorescence,
            p0=[float(np.ptp(fluorescence)), 0.5, float(np.median(temperatures)), float(np.min(fluorescence))],
            maxfev=50000,
        )
        fitted[pid] = float(params[2])

    return reference, primers, records, valid_ids, fitted


def write_hidden_case(reference, primers, records):
    REFERENCE.write_text('>hidden_reference\n' + reference + '\n')
    with PRIMERS.open('w') as f:
        for pid, sequence in primers.items():
            f.write(f'>{pid}\n{sequence}\n')
    with MELTING.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['primer_id', 'temperature', 'fluorescence'])
        writer.writerows(records)


def assert_hidden_output(valid_ids, fitted):
    rows = read_output()
    assert rows and rows[0] == ['primer_id', 'Tm'], "Hidden-case output must have exactly the header ['primer_id', 'Tm']."
    data_rows = rows[1:]
    assert all(len(row) == 2 for row in data_rows), 'Every output row must contain exactly two columns.'
    assert [row[0] for row in data_rows] == valid_ids, (
        'The script did not derive the sorted uniquely matching primers from the hidden FASTA inputs.'
    )
    assert len(data_rows) == len(valid_ids)

    for row in data_rows:
        pid, text = row
        assert '.' in text and len(text.split('.', 1)[1]) == 2, f"Tm '{text}' for {pid} is not formatted to exactly 2 decimal places."
        try:
            actual = float(text)
        except ValueError:
            raise AssertionError(f'Tm for {pid} is not numeric: {text!r}')
        expected_text = f'{fitted[pid]:.2f}'
        assert text == expected_text, f'Incorrect fitted Tm for {pid}: expected {expected_text}, got {text}.'


def test_valid_primers_tm_output():
    assert_script_and_multiprocessing()

    paths = [REFERENCE, PRIMERS, MELTING, OUTPUT]
    backups = {path: path.read_bytes() if path.exists() else None for path in paths}
    try:
        # Preserve and strengthen all original final-output assertions by first
        # executing the submitted artifact against the supplied inputs.
        run_script()
        assert_original_output()

        # Then replace the inputs with an unpredictable case and derive the
        # expected alignment and fitted results directly from those inputs.
        reference, primers, records, valid_ids, fitted = make_hidden_case()
        write_hidden_case(reference, primers, records)
        if OUTPUT.exists():
            OUTPUT.unlink()
        run_script()
        assert_hidden_output(valid_ids, fitted)
    finally:
        for path, content in backups.items():
            if content is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
