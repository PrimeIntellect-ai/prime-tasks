#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
from pathlib import Path

HOME = Path('/home/user')
TABLES = HOME / 'backup_data/tables.txt'
FKS = HOME / 'backup_data/fks.txt'
SOURCE = HOME / 'graph_mapper.c'
BINARY = HOME / 'graph_mapper'
MAPPED = HOME / 'mapped_graph.txt'
SUMMARY = HOME / 'backup_summary.csv'


def nonempty_lines(data):
    if isinstance(data, bytes):
        data = data.decode('utf-8', errors='replace')
    return [line.strip() for line in data.splitlines() if line.strip()]


def run_checked(command, timeout=10, input_text=None):
    return subprocess.run(
        command,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
        cwd=str(HOME),
    )


def find_aggregation_scripts():
    excluded = {
        SOURCE.resolve(), BINARY.resolve(), MAPPED.resolve(), SUMMARY.resolve(),
        TABLES.resolve(), FKS.resolve(),
    }
    candidates = []
    for root, dirs, files in os.walk(HOME):
        rel_depth = len(Path(root).relative_to(HOME).parts)
        if rel_depth >= 3:
            dirs[:] = []
        dirs[:] = [d for d in dirs if not d.startswith('.') and d != 'backup_data']
        for name in files:
            if name.startswith('.'):
                continue
            path = Path(root) / name
            try:
                resolved = path.resolve()
                mode = path.stat().st_mode
                size = path.stat().st_size
            except OSError:
                continue
            if resolved in excluded or not path.is_file() or size > 1024 * 1024:
                continue
            if path.suffix.lower() in {'.sh', '.py', '.awk'} or os.access(path, os.X_OK):
                candidates.append(path)
                continue
            try:
                first = path.open('rb').read(128)
            except OSError:
                continue
            if first.startswith(b'#!'):
                candidates.append(path)
    return candidates


def script_commands(path):
    p = str(path)
    mapped = str(MAPPED)
    suffix = path.suffix.lower()
    if suffix == '.py':
        bases = [['python3', p]]
    elif suffix == '.awk':
        bases = [['awk', '-f', p]]
    elif suffix == '.sh':
        bases = [['bash', p]]
    else:
        bases = [[p], ['bash', p], ['python3', p], ['awk', '-f', p]]
    commands = []
    for base in bases:
        commands.append(base)
        commands.append(base + [mapped])
    return commands


def test_complete_solution():
    # Preserve the original source assertion.
    assert SOURCE.is_file(), f'{SOURCE} is missing'
    content = SOURCE.read_text()
    assert 'if' in content and 'source_id' in content and 'id' in content, \
        'The C program does not appear to contain a conditional check linking source_id and table id.'

    # Preserve the original fixed-fixture output assertions.
    assert MAPPED.is_file(), f'{MAPPED} is missing'
    original_graph_lines = nonempty_lines(MAPPED.read_text())
    expected_original_graph = [
        '(Backup_100)-[:HAS]->(orders)-[:REFERENCES]->(Table_1)',
        '(Backup_100)-[:HAS]->(orders)-[:REFERENCES]->(Table_3)',
        '(Backup_101)-[:HAS]->(orders)-[:REFERENCES]->(Table_4)',
        '(Backup_101)-[:HAS]->(orders)-[:REFERENCES]->(Table_6)',
        '(Backup_101)-[:HAS]->(reviews)-[:REFERENCES]->(Table_4)',
        '(Backup_101)-[:HAS]->(reviews)-[:REFERENCES]->(Table_6)',
        '(Backup_102)-[:HAS]->(orders)-[:REFERENCES]->(Table_8)',
    ]
    assert sorted(expected_original_graph) == expected_original_graph, 'Expected lines are not sorted.'
    assert original_graph_lines == expected_original_graph, \
        f'{MAPPED} does not match the expected output or is not sorted properly.'

    assert SUMMARY.is_file(), f'{SUMMARY} is missing'
    expected_original_summary = [
        'backup_id,fk_count',
        '100,2',
        '101,4',
        '102,1',
    ]
    assert nonempty_lines(SUMMARY.read_text()) == expected_original_summary, \
        f'{SUMMARY} does not contain the expected summary statistics or is not sorted correctly.'

    # The requested named executable must exist and be an executable binary.
    assert BINARY.is_file(), f'{BINARY} is missing'
    assert os.access(BINARY, os.X_OK), f'{BINARY} is not executable'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', f'{BINARY} is not a compiled ELF executable'

    saved = {p: p.read_bytes() for p in (TABLES, FKS, MAPPED, SUMMARY)}
    rebuilt = Path('/tmp/graph_mapper_rebuilt')
    try:
        # Use unpredictable IDs/order so fixed output files or fixture-specific logic cannot pass.
        base = secrets.randbelow(50000) + 10000
        table_rows = [
            (base + 41, 901, 'zeta'),
            (base + 7, 17, 'alpha'),
            (base + 83, 250, 'gamma'),
            (base + 12, 901, 'beta'),
            (base + 65, 17, 'omega'),
            (base + 29, 250, 'delta'),
        ]
        fk_rows = [
            (base + 41, base + 7),
            (base + 41, base + 83),
            (base + 7, base + 12),
            (base + 65, base + 29),
            (base + 65, base + 83),
            (base + 29, base + 41),
        ]
        secrets.SystemRandom().shuffle(table_rows)
        secrets.SystemRandom().shuffle(fk_rows)
        TABLES.write_text(''.join(f'{i},{backup},{name}\n' for i, backup, name in table_rows))
        FKS.write_text(''.join(f'{source},{target}\n' for source, target in fk_rows))

        by_id = {i: (backup, name) for i, backup, name in table_rows}
        expected_graph = sorted(
            f'(Backup_{by_id[source][0]})-[:HAS]->({by_id[source][1]})-[:REFERENCES]->(Table_{target})'
            for source, target in fk_rows
            if source in by_id
        )

        # Execute the submitted named artifact on the changed inputs.
        submitted = run_checked([str(BINARY)])
        assert submitted.returncode == 0, f'graph_mapper failed: {submitted.stderr}'
        assert sorted(nonempty_lines(submitted.stdout)) == expected_graph, \
            'The submitted graph_mapper executable does not implement the source_id == table id join.'

        # Compile the submitted source independently and exercise that build too.
        compile_result = run_checked(['gcc', '-std=c11', '-Wall', '-Wextra', str(SOURCE), '-o', str(rebuilt)])
        assert compile_result.returncode == 0, f'graph_mapper.c does not compile: {compile_result.stderr}'
        rebuilt_result = run_checked([str(rebuilt)])
        assert rebuilt_result.returncode == 0, f'Rebuilt graph_mapper failed: {rebuilt_result.stderr}'
        assert sorted(nonempty_lines(rebuilt_result.stdout)) == expected_graph, \
            'graph_mapper.c does not implement the source_id == table id join on changed inputs.'

        # Supply sorted mapper output to the aggregation artifact, as required by the task.
        MAPPED.write_text(''.join(line + '\n' for line in expected_graph))
        counts = {}
        for source, _ in fk_rows:
            if source in by_id:
                backup = by_id[source][0]
                counts[backup] = counts.get(backup, 0) + 1
        expected_summary = ['backup_id,fk_count'] + [
            f'{backup},{counts[backup]}' for backup in sorted(counts)
        ]

        scripts = find_aggregation_scripts()
        assert scripts, 'No bash, awk, or Python aggregation script was found.'
        matched = False
        diagnostics = []
        mapped_input = MAPPED.read_text()
        for script in scripts:
            for command in script_commands(script):
                MAPPED.write_text(mapped_input)
                try:
                    SUMMARY.unlink(missing_ok=True)
                    result = run_checked(command, timeout=8, input_text=mapped_input)
                except (OSError, subprocess.TimeoutExpired) as exc:
                    diagnostics.append(f'{script}: {exc}')
                    continue
                file_lines = nonempty_lines(SUMMARY.read_text()) if SUMMARY.is_file() else []
                stdout_lines = nonempty_lines(result.stdout)
                if result.returncode == 0 and (file_lines == expected_summary or stdout_lines == expected_summary):
                    matched = True
                    break
            if matched:
                break
        assert matched, \
            'No submitted aggregation script produced the correct summary for changed mapper output. ' + '; '.join(diagnostics[-3:])
    finally:
        for path, data in saved.items():
            path.write_bytes(data)
        rebuilt.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
