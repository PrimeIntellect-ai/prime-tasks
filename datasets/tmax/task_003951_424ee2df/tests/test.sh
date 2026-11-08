#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess
import pandas as pd

FASTA_PATH = '/home/user/data/targets.fasta'
OUTPUT_CSV = '/home/user/output/primer_scores.csv'


def compute_reference(fasta_path):
    alpha = 0.62
    beta = 1.15
    gamma = 0.04

    sequences = {}
    current_id = None
    with open(fasta_path, 'r') as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith('>'):
                current_id = line[1:].strip()
                assert current_id, 'Encountered an empty FASTA sequence ID.'
                assert current_id not in sequences, f"Duplicate FASTA sequence ID: {current_id}"
                sequences[current_id] = ''
            else:
                assert current_id is not None, 'FASTA sequence data appeared before a header.'
                sequences[current_id] += line

    results = {}
    for sid, sequence in sequences.items():
        primer = sequence[:20]
        if len(primer) < 20:
            continue

        g_c_count = primer.count('G') + primer.count('C')
        a_t_count = primer.count('A') + primer.count('T')
        gc_content = g_c_count / 20.0
        tm = 4 * g_c_count + 2 * a_t_count

        max_homo = 1
        current_homo = 1
        for i in range(1, 20):
            if primer[i] == primer[i - 1]:
                current_homo += 1
                max_homo = max(max_homo, current_homo)
            else:
                current_homo = 1

        score = (alpha * gc_content) + (beta * (tm / 100.0)) - (gamma * max_homo)
        results[sid] = (primer, score)
    return results


def validate_csv(output_csv, fasta_path):
    assert os.path.exists(output_csv), f"Output file not found at {output_csv}"

    try:
        with open(output_csv, newline='') as f:
            rows = list(csv.reader(f))
    except Exception as e:
        assert False, f"Failed to parse CSV at {output_csv}: {e}"

    assert rows, 'Output CSV is empty.'
    assert rows[0] == ['SequenceID', 'Primer20', 'Score'], \
        f"Expected exact header SequenceID,Primer20,Score, but found: {rows[0]}"
    for line_number, row in enumerate(rows[1:], start=2):
        assert len(row) == 3, f"CSV row {line_number} has {len(row)} fields instead of 3."
        assert re.fullmatch(r'[+-]?(?:\d+\.\d{6})', row[2]), \
            f"Score on CSV row {line_number} is not printed to exactly 6 decimal places: {row[2]!r}"

    try:
        df = pd.read_csv(output_csv, dtype={'SequenceID': str, 'Primer20': str})
    except Exception as e:
        assert False, f"Failed to parse CSV at {output_csv}: {e}"

    expected_columns = ['SequenceID', 'Primer20', 'Score']
    for col in expected_columns:
        assert col in df.columns, f"Missing column '{col}' in output CSV. Found columns: {list(df.columns)}"
    assert list(df.columns) == expected_columns, \
        f"Expected exactly columns {expected_columns}, but found {list(df.columns)}"

    ref = compute_reference(fasta_path)
    assert len(df) == len(ref), f"Expected {len(ref)} rows, but got {len(df)}."

    ids = [str(x) for x in df['SequenceID'].tolist()]
    assert len(ids) == len(set(ids)), 'Each SequenceID must appear exactly once; duplicate IDs were found.'
    assert set(ids) == set(ref), \
        f"Output SequenceIDs do not exactly match FASTA IDs. Missing: {sorted(set(ref) - set(ids))}; extra: {sorted(set(ids) - set(ref))}"

    mse = 0.0
    for _, row in df.iterrows():
        sid = str(row['SequenceID'])
        assert sid in ref, f"Sequence ID '{sid}' not found in reference."
        expected_primer, expected_score = ref[sid]
        primer = str(row['Primer20'])
        assert primer == expected_primer, \
            f"Primer20 for '{sid}' is {primer!r}, expected {expected_primer!r}."
        try:
            val = float(row['Score'])
        except Exception as e:
            assert False, f"Score for '{sid}' is not numeric: {e}"
        assert math.isfinite(val), f"Score for '{sid}' is not finite."
        mse += (val - expected_score) ** 2

    mse /= len(df)
    threshold = 1e-8
    assert mse <= threshold, f"MSE {mse} exceeds threshold {threshold}. The calculated scores do not match the expected formula."


def find_cpp_sources():
    excluded_at_root = {
        'proc', 'sys', 'dev', 'usr', 'var', 'opt', 'run', 'etc', 'lib', 'lib64',
        'bin', 'sbin', 'boot', 'media', 'mnt', 'tests', 'logs'
    }
    found = []
    for root, dirs, files in os.walk('/', topdown=True, followlinks=False):
        if root == '/':
            dirs[:] = [d for d in dirs if d not in excluded_at_root]
        dirs[:] = [d for d in dirs if d not in {'__pycache__', '.git'}]
        for name in files:
            if name.endswith(('.cpp', '.cc', '.cxx')):
                path = os.path.join(root, name)
                if os.path.isfile(path) and not os.path.islink(path):
                    found.append(path)
    return sorted(found)


def write_challenge_fasta(path):
    records = [
        ('verify_a', 'ACGTACGTACGTACGTACGTGATTACAGATTACA'),
        ('verify_b', 'GGGGGGGGGGCCCCCCCCCCATATATATATAT'),
        ('verify_c', 'AAAAAAAAAAAAAAAAAAAATGCGCGCGCGCG'),
        ('verify_d', 'TGCATGCATGCATGCATGCACCCCCAAAAAG'),
        ('verify_e', 'ATATATATATATATATATATGGGGTTTTCCCC'),
        ('verify_f', 'CGCGCGCGCGCGCGCGCGCGAAAATTTT'),
        ('verify_g', 'AAACCCGGGTTTAAACCCGGTTGCAACGT'),
    ]
    with open(path, 'w') as f:
        for sid, sequence in records:
            f.write(f'>{sid}\n')
            # Deliberately wrap sequences: a FASTA parser must concatenate lines.
            f.write(sequence[:11] + '\n')
            f.write(sequence[11:23] + '\n')
            f.write(sequence[23:] + '\n')


def test_final_state():
    # Preserve and strengthen all checks on the originally submitted artifact.
    validate_csv(OUTPUT_CSV, FASTA_PATH)

    sources = find_cpp_sources()
    assert sources, 'No C++ source file was found; the requested C++ program was not written.'

    with open(FASTA_PATH, 'rb') as f:
        original_fasta = f.read()
    with open(OUTPUT_CSV, 'rb') as f:
        original_output = f.read()

    successful_source = None
    build_messages = []
    try:
        for index, source in enumerate(sources):
            executable = f'/tmp/primer_pipeline_candidate_{index}'
            try:
                build = subprocess.run(
                    ['g++', '-std=c++17', '-O2', source, '-o', executable],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
                if build.returncode != 0:
                    build_messages.append(f'{source}: compilation failed')
                    continue

                write_challenge_fasta(FASTA_PATH)
                if os.path.exists(OUTPUT_CSV):
                    os.remove(OUTPUT_CSV)

                run = subprocess.run(
                    [executable],
                    cwd=os.path.dirname(source) or '/',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=20,
                )
                if run.returncode != 0:
                    build_messages.append(f'{source}: exited with status {run.returncode}')
                    continue

                try:
                    validate_csv(OUTPUT_CSV, FASTA_PATH)
                except AssertionError as e:
                    build_messages.append(f'{source}: generated invalid challenge output ({e})')
                    continue

                successful_source = source
                break
            except (subprocess.TimeoutExpired, OSError) as e:
                build_messages.append(f'{source}: could not be compiled/run ({e})')
            finally:
                try:
                    os.remove(executable)
                except FileNotFoundError:
                    pass

        assert successful_source is not None, \
            'No submitted C++ source could be compiled and run to correctly process verifier-controlled FASTA input. ' + '; '.join(build_messages[-5:])
    finally:
        with open(FASTA_PATH, 'wb') as f:
            f.write(original_fasta)
        with open(OUTPUT_CSV, 'wb') as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
