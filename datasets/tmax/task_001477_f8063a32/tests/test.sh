#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
from pathlib import Path

PARSER = Path('/home/user/parser.c')
EDGES = Path('/home/user/edges.csv')
DB = Path('/home/user/schema.db')
RESULTS = Path('/home/user/2hop_results.txt')


def parse_statements(text):
    return [
        (a.lower(), b.lower())
        for a, b in re.findall(
            r'([A-Za-z_][A-Za-z0-9_]*)\s+joins\s+with\s+([A-Za-z_][A-Za-z0-9_]*)',
            text,
            flags=re.IGNORECASE,
        )
    ]


def read_csv_edges(path):
    with open(path, newline='', encoding='utf-8') as f:
        rows = [tuple(cell.strip().lower() for cell in row) for row in csv.reader(f) if any(cell.strip() for cell in row)]
    if rows and rows[0] == ('source_table', 'target_table'):
        rows = rows[1:]
    assert all(len(row) == 2 and row[0] and row[1] for row in rows), f'Invalid edge CSV rows in {path}: {rows}'
    return rows


def oracle_transcript_and_edges():
    with tempfile.TemporaryDirectory() as td:
        subprocess.run(
            ['whisper', '/app/dataset_dictation.wav'],
            cwd=td,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        transcript = Path(td, 'dataset_dictation.txt').read_text(encoding='utf-8')
    edges = parse_statements(transcript)
    assert edges, 'The supplied audio transcription did not contain any join statements.'
    return transcript, edges


def test_2hop_results_iou():
    """Test that the 2-hop results match the ground truth with IoU >= 0.85."""
    results_path = "/home/user/2hop_results.txt"
    assert os.path.exists(results_path), f"Output file {results_path} does not exist."

    truth = {"billing_info", "preferences", "telemetry"}

    with open(results_path, "r") as f:
        predictions = {line.strip().lower() for line in f if line.strip()}

    intersection = truth.intersection(predictions)
    union = truth.union(predictions)
    iou = len(intersection) / len(union) if union else 0.0

    assert iou >= 0.85, f"IoU {iou:.2f} is below threshold 0.85. Expected {truth}, got {predictions}"


def test_intermediate_files_exist():
    """Test that the intermediate files from the task steps exist."""
    assert os.path.exists("/home/user/parser.c"), "C parser source file /home/user/parser.c is missing."
    assert os.path.exists("/home/user/edges.csv"), "CSV edges file /home/user/edges.csv is missing."
    assert os.path.exists("/home/user/schema.db"), "SQLite database /home/user/schema.db is missing."


def test_transcription_csv_database_and_cte_are_consistent():
    oracle_text, expected_edges = oracle_transcript_and_edges()
    expected_set = set(expected_edges)

    transcript_found = False
    for root in ('/home/user', '/app'):
        for path in Path(root).rglob('*.txt'):
            if path == RESULTS:
                continue
            try:
                text = path.read_text(encoding='utf-8')
            except (OSError, UnicodeError):
                continue
            if set(parse_statements(text)) == expected_set and oracle_text.strip().lower() in text.strip().lower():
                transcript_found = True
                break
        if transcript_found:
            break
    assert transcript_found, 'No retained text transcription of /app/dataset_dictation.wav was found.'

    csv_edges = read_csv_edges(EDGES)
    assert set(csv_edges) == expected_set and len(csv_edges) == len(expected_edges), (
        f'edges.csv does not contain exactly the joins parsed from the audio transcription: {csv_edges}'
    )

    con = sqlite3.connect(str(DB))
    try:
        table = con.execute("SELECT name FROM sqlite_master WHERE type='table' AND lower(name)='edges'").fetchone()
        assert table is not None, "schema.db does not contain an edges table."
        columns = [row[1].lower() for row in con.execute('PRAGMA table_info(edges)')]
        assert 'source_table' in columns and 'target_table' in columns, (
            f'edges table must have source_table and target_table columns; found {columns}'
        )
        db_edges = [
            (str(a).strip().lower(), str(b).strip().lower())
            for a, b in con.execute('SELECT source_table, target_table FROM edges')
        ]
        assert set(db_edges) == expected_set and len(db_edges) == len(expected_edges), (
            f'edges table was not loaded with exactly the CSV relationships: {db_edges}'
        )

        cte_query = '''
            WITH two_hop(target_table) AS (
                SELECT e2.target_table
                FROM edges AS e1
                JOIN edges AS e2 ON lower(e1.target_table) = lower(e2.source_table)
                WHERE lower(e1.source_table) = 'user_logs'
            )
            SELECT DISTINCT lower(target_table)
            FROM two_hop
            ORDER BY lower(target_table)
        '''
        derived = [row[0] for row in con.execute(cte_query)]
    finally:
        con.close()

    output_lines = [line.strip().lower() for line in RESULTS.read_text(encoding='utf-8').splitlines() if line.strip()]
    assert output_lines == derived, f'2hop_results.txt must be the sorted CTE result. Expected {derived}, got {output_lines}'


def test_c_parser_compiles_and_parses_unseen_input():
    synthetic = (
        'Unrelated introduction. red_alpha joins with blue_beta. '
        'blue_beta joins with green_gamma. orange_delta joins with violet_epsilon.\n'
    )
    expected = {
        ('red_alpha', 'blue_beta'),
        ('blue_beta', 'green_gamma'),
        ('orange_delta', 'violet_epsilon'),
    }

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        executable = td / 'parser'
        compile_result = subprocess.run(
            ['gcc', '-std=c11', '-O2', str(PARSER), '-o', str(executable)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, f'parser.c does not compile with gcc:\n{compile_result.stderr}'

        absolute_inputs = [Path('/home/user/transcription.txt'), Path('/home/user/dataset_dictation.txt'), Path('/app/dataset_dictation.txt')]
        absolute_output = Path('/home/user/edges.csv')
        touched = absolute_inputs + [absolute_output]
        backups = {}
        for path in touched:
            backups[path] = path.read_bytes() if path.exists() else None

        try:
            for path in absolute_inputs:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(synthetic, encoding='utf-8')
            (td / 'dataset_dictation.txt').write_text(synthetic, encoding='utf-8')
            (td / 'transcription.txt').write_text(synthetic, encoding='utf-8')
            explicit_input = td / 'unseen_transcription.txt'
            explicit_output = td / 'explicit_edges.csv'
            explicit_input.write_text(synthetic, encoding='utf-8')

            invocations = [
                [str(executable), str(explicit_input), str(explicit_output)],
                [str(executable), str(explicit_input)],
                [str(executable)],
            ]
            success = False
            diagnostics = []
            for command in invocations:
                for candidate in (explicit_output, td / 'edges.csv', absolute_output):
                    if candidate.exists() and candidate not in absolute_inputs:
                        candidate.unlink()
                run = subprocess.run(
                    command,
                    cwd=td,
                    input=synthetic,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
                diagnostics.append(f"{' '.join(command)} exited {run.returncode}: {run.stderr}")
                for candidate in (explicit_output, td / 'edges.csv', absolute_output):
                    if candidate.exists():
                        try:
                            rows = read_csv_edges(candidate)
                        except Exception:
                            continue
                        if set(rows) == expected and len(rows) == len(expected):
                            success = True
                            break
                if success:
                    break

            assert success, (
                'The compiled C program did not parse unseen join statements into CSV when run using '
                'standard argument, fixed-file, or stdin conventions.\n' + '\n'.join(diagnostics)
            )
        finally:
            for path, data in backups.items():
                if data is None:
                    try:
                        path.unlink()
                    except FileNotFoundError:
                        pass
                else:
                    path.write_bytes(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
