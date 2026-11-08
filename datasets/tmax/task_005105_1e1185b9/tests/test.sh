#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import shlex
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

CSV_PATH = Path('/home/user/data/combined.csv')
FASTA_PATH = Path('/home/user/data/sequence.fasta')
PDB_PATH = Path('/home/user/data/structure.pdb')
RESULTS_PATH = Path('/home/user/output/model_results.txt')
EXACT_RESULT_RE = re.compile(
    r'alpha: ([+-]?(?:\d+\.\d{4}))\nbeta: ([+-]?(?:\d+\.\d{4}))(?:\n)?\Z'
)


def test_combined_csv_exists_and_correct():
    csv_path = str(CSV_PATH)
    assert os.path.isfile(csv_path), f"Expected CSV file {csv_path} does not exist."

    expected_rows = [
        {"index": "1", "fasta_char": "A", "pdb_res_name": "ALA", "b_factor": "20.50"},
        {"index": "2", "fasta_char": "R", "pdb_res_name": "ARG", "b_factor": "23.50"},
        {"index": "3", "fasta_char": "N", "pdb_res_name": "ASN", "b_factor": "26.50"},
        {"index": "4", "fasta_char": "D", "pdb_res_name": "ASP", "b_factor": "29.50"},
        {"index": "5", "fasta_char": "C", "pdb_res_name": "CYS", "b_factor": "32.50"},
    ]

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None, "CSV must have a header."

        expected_fields = ["index", "fasta_char", "pdb_res_name", "b_factor"]
        for field in expected_fields:
            assert field in reader.fieldnames, f"CSV header missing expected column: {field}"
        assert reader.fieldnames == expected_fields, f"CSV header must be exactly {','.join(expected_fields)}"

        rows = list(reader)
        assert len(rows) == len(expected_rows), f"CSV should have exactly {len(expected_rows)} data rows, found {len(rows)}."

        for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
            assert actual["index"].strip() == expected["index"], f"Row {i+1} index mismatch."
            assert actual["fasta_char"].strip() == expected["fasta_char"], f"Row {i+1} fasta_char mismatch."
            assert actual["pdb_res_name"].strip() == expected["pdb_res_name"], f"Row {i+1} pdb_res_name mismatch."
            actual_b = float(actual["b_factor"].strip())
            expected_b = float(expected["b_factor"])
            assert abs(actual_b - expected_b) < 1e-4, f"Row {i+1} b_factor mismatch: expected {expected_b}, got {actual_b}."


def test_model_results_exist_and_correct():
    results_path = str(RESULTS_PATH)
    assert os.path.isfile(results_path), f"Expected output file {results_path} does not exist."

    with open(results_path, 'r') as f:
        content = f.read()

    alpha_match = re.search(r"alpha:\s*([+-]?\d*\.\d+)", content)
    beta_match = re.search(r"beta:\s*([+-]?\d*\.\d+)", content)

    assert alpha_match is not None, "Could not find 'alpha: <value>' in model_results.txt"
    assert beta_match is not None, "Could not find 'beta: <value>' in model_results.txt"

    alpha_val = float(alpha_match.group(1))
    beta_val = float(beta_match.group(1))
    assert abs(alpha_val - 17.5) < 0.1, f"Alpha value {alpha_val} is not close enough to expected 17.5000"
    assert abs(beta_val - 3.0) < 0.1, f"Beta value {beta_val} is not close enough to expected 3.0000"
    assert EXACT_RESULT_RE.fullmatch(content), "model_results.txt must contain exactly two lines with values rounded to 4 decimal places"


def pdb_line(serial, atom, residue, index, b_factor):
    line = [' '] * 80
    line[0:6] = 'ATOM  '
    line[6:11] = f'{serial:5d}'
    line[12:16] = f'{atom:^4s}'
    line[17:20] = f'{residue:>3s}'
    line[21] = 'A'
    line[22:26] = f'{index:4d}'
    line[30:38] = f'{10.0 + serial:8.3f}'
    line[38:46] = f'{5.0 + serial:8.3f}'
    line[46:54] = f'{-2.0 - serial:8.3f}'
    line[54:60] = f'{1.0:6.2f}'
    line[60:66] = f'{b_factor:6.2f}'
    line[76:78] = ' C'
    return ''.join(line) + '\n'


def script_commands(path):
    suffix = path.suffix.lower()
    base = None
    if suffix == '.py':
        base = ['python3', str(path)]
    elif suffix == '.sh':
        base = ['bash', str(path)]
    elif suffix == '.pl':
        base = ['perl', str(path)]
    elif suffix == '.rb':
        base = ['ruby', str(path)]
    else:
        try:
            first = path.open('r', errors='ignore').readline().strip()
        except (OSError, UnicodeError):
            return []
        if first.startswith('#!'):
            base = shlex.split(first[2:]) + [str(path)]
        elif os.access(path, os.X_OK):
            base = [str(path)]
    if base is None:
        return []
    return [
        base,
        base + [str(FASTA_PATH), str(PDB_PATH), str(CSV_PATH)],
        base + [str(PDB_PATH), str(FASTA_PATH), str(CSV_PATH)],
    ]


def find_parser_scripts():
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'target', '.cargo', '.rustup', 'output'}]
        for name in files:
            path = Path(root) / name
            if path in {FASTA_PATH, PDB_PATH, CSV_PATH, Path('/home/user/fitter/src/main.rs')}:
                continue
            if path.suffix.lower() in {'.py', '.sh', '.pl', '.rb'}:
                candidates.append(path)
                continue
            try:
                if path.stat().st_size <= 1024 * 1024 and path.open('rb').read(2) == b'#!':
                    candidates.append(path)
            except OSError:
                pass
    return candidates


def dynamic_csv_is_correct():
    expected = [
        ('2', 'K', 'LYS', 11.25),
        ('4', 'W', 'TRP', 37.75),
        ('7', 'A', 'ALA', 6.50),
    ]
    try:
        with CSV_PATH.open(newline='') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames != ['index', 'fasta_char', 'pdb_res_name', 'b_factor']:
                return False
            rows = list(reader)
        if len(rows) != len(expected):
            return False
        for row, exp in zip(rows, expected):
            if row['index'].strip() != exp[0] or row['fasta_char'].strip() != exp[1] or row['pdb_res_name'].strip() != exp[2]:
                return False
            if abs(float(row['b_factor']) - exp[3]) >= 1e-4:
                return False
        return True
    except Exception:
        return False


def test_parser_regenerates_csv_from_changed_inputs():
    scripts = find_parser_scripts()
    assert scripts, "No parser script was found under /home/user"

    originals = {p: p.read_bytes() if p.exists() else None for p in (FASTA_PATH, PDB_PATH, CSV_PATH)}
    try:
        FASTA_PATH.write_text('>dynamic_sequence\nMKTWYVAQ\n')
        PDB_PATH.write_text(
            pdb_line(1, 'N', 'LYS', 2, 99.0)
            + pdb_line(2, 'CA', 'LYS', 2, 11.25)
            + pdb_line(3, 'C', 'LYS', 2, 88.0)
            + pdb_line(4, 'CA', 'TRP', 4, 37.75)
            + pdb_line(5, 'O', 'TRP', 4, 77.0)
            + pdb_line(6, 'CA', 'ALA', 7, 6.50)
        )

        for script in scripts:
            for command in script_commands(script):
                try:
                    if CSV_PATH.exists():
                        CSV_PATH.unlink()
                    subprocess.run(
                        command,
                        cwd='/home/user',
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=20,
                        check=False,
                    )
                    if dynamic_csv_is_correct():
                        return
                except (OSError, subprocess.TimeoutExpired):
                    continue
        pytest.fail("No submitted parser script regenerated combined.csv correctly from changed FASTA/PDB inputs")
    finally:
        for path, data in originals.items():
            if data is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_bytes(data)


def parse_exact_results(content):
    match = EXACT_RESULT_RE.fullmatch(content)
    assert match, "The executed fitter must emit exactly alpha and beta on two lines, each with 4 decimal places"
    alpha, beta = map(float, match.groups())
    assert math.isfinite(alpha) and math.isfinite(beta), "Fitted values must be finite"
    return alpha, beta


def test_rust_fitter_compiles_and_fits_unseen_data():
    project = Path('/home/user/fitter')
    source = project / 'src/main.rs'
    manifest = project / 'Cargo.toml'
    assert source.is_file(), "Missing /home/user/fitter/src/main.rs"
    assert manifest.is_file(), "Missing /home/user/fitter/Cargo.toml"

    subprocess.run(
        ['cargo', 'build', '--quiet'],
        cwd=project,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
        check=True,
    )
    executable = project / 'target/debug/fitter'
    assert executable.is_file(), "Cargo build did not produce the fitter executable"

    with tempfile.TemporaryDirectory() as tmpdir:
        dynamic_csv = Path(tmpdir) / 'unseen.csv'
        # These values differ from the shipped data. Expected coefficients are
        # derived from the generated observations rather than trusted artifacts.
        observations = [(1, 8.73), (2, 10.14), (3, 11.62), (4, 12.91), (5, 14.48)]
        with dynamic_csv.open('w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['index', 'fasta_char', 'pdb_res_name', 'b_factor'])
            for i, y in observations:
                writer.writerow([i, 'A', 'ALA', f'{y:.4f}'])

        xs = [float(x) for x, _ in observations]
        ys = [float(y) for _, y in observations]
        xbar = sum(xs) / len(xs)
        ybar = sum(ys) / len(ys)
        expected_beta = sum((x - xbar) * (y - ybar) for x, y in zip(xs, ys)) / sum((x - xbar) ** 2 for x in xs)
        expected_alpha = ybar - expected_beta * xbar

        old_results = RESULTS_PATH.read_bytes() if RESULTS_PATH.exists() else None
        try:
            if RESULTS_PATH.exists():
                RESULTS_PATH.unlink()
            run = subprocess.run(
                [str(executable), str(dynamic_csv)],
                cwd=project,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
                check=True,
            )
            emitted = run.stdout
            if not EXACT_RESULT_RE.fullmatch(emitted) and RESULTS_PATH.exists():
                emitted = RESULTS_PATH.read_text()
            alpha, beta = parse_exact_results(emitted)
            assert abs(alpha - expected_alpha) < 0.08, f"Executed fitter alpha {alpha} differs from derived OLS value {expected_alpha}"
            assert abs(beta - expected_beta) < 0.03, f"Executed fitter beta {beta} differs from derived OLS value {expected_beta}"
        finally:
            if old_results is None:
                if RESULTS_PATH.exists():
                    RESULTS_PATH.unlink()
            else:
                RESULTS_PATH.parent.mkdir(parents=True, exist_ok=True)
                RESULTS_PATH.write_bytes(old_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
