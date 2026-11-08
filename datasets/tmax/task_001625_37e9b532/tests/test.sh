#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import pathlib
import shutil
import subprocess

HOME = pathlib.Path('/home/user')
CPP = HOME / 'calc_ci.cpp'
OUT = HOME / 'ci_output.txt'
EXPERIMENTS = HOME / 'experiments.txt'
METRICS = HOME / 'metrics.txt'
BINARY = pathlib.Path('/tmp/calc_ci_test_bin')


def expected_line(values):
    n = len(values)
    mean = sum(values) / n
    variance = sum((x - mean) ** 2 for x in values) / (n - 1)
    margin = 1.96 * math.sqrt(variance) / math.sqrt(n)
    return f"Mean: {mean:.4f}, CI: [{mean - margin:.4f}, {mean + margin:.4f}]"


def selected_accuracies_from_inputs():
    with EXPERIMENTS.open() as f:
        exp_header = f.readline().split()
        exp_rows = [dict(zip(exp_header, line.split())) for line in f if line.strip()]
    with METRICS.open() as f:
        metric_header = f.readline().split()
        metric_rows = [dict(zip(metric_header, line.split())) for line in f if line.strip()]

    selected = {row['id'] for row in exp_rows if row['pca_components'] == '10'}
    by_id = {row['id']: float(row['accuracy']) for row in metric_rows}
    return [by_id[row['id']] for row in exp_rows if row['id'] in selected]


def test_calc_ci_cpp_exists():
    assert CPP.is_file(), f"C++ source file missing: {CPP}"


def test_ci_output_exists_and_correct():
    assert OUT.is_file(), f"Output file missing: {OUT}"

    # Preserve the original exact-output assertion.
    accuracies = [0.81, 0.83, 0.80, 0.82, 0.84]
    expected_output = expected_line(accuracies)
    content = OUT.read_text().strip()
    assert content == expected_output, (
        f"Output file content is incorrect. Expected '{expected_output}', got '{content}'"
    )

    # Also derive the answer from the supplied join inputs rather than trusting a list.
    derived_output = expected_line(selected_accuracies_from_inputs())
    assert content == derived_output


def rewrite_data_file(path, selected_values, selected_ids):
    """Preserve a candidate filtered file's shape while replacing its accuracies."""
    try:
        text = path.read_text()
    except (UnicodeDecodeError, OSError):
        return
    if not text.strip():
        return

    lines = text.splitlines()
    header = lines[0].split()
    has_header = any(not token.replace('.', '', 1).isdigit() for token in header)
    accuracy_index = None
    id_index = None
    if has_header:
        lowered = [token.lower() for token in header]
        if 'accuracy' in lowered:
            accuracy_index = lowered.index('accuracy')
        if 'id' in lowered:
            id_index = lowered.index('id')

    sequence = 0
    rewritten = []
    for line_no, line in enumerate(lines):
        fields = line.split()
        if not fields or (line_no == 0 and has_header):
            rewritten.append(line)
            continue

        idx = accuracy_index if accuracy_index is not None and accuracy_index < len(fields) else len(fields) - 1
        row_id = None
        candidate_id_index = id_index if id_index is not None else (0 if len(fields) >= 2 else None)
        if candidate_id_index is not None and candidate_id_index < len(fields):
            row_id = fields[candidate_id_index]

        if row_id in selected_ids:
            value = selected_values[selected_ids.index(row_id)]
        elif row_id is not None and row_id.isdigit() and row_id not in selected_ids:
            value = 0.9300
        else:
            value = selected_values[sequence % len(selected_values)]
            sequence += 1
        fields[idx] = f'{value:.4f}'
        rewritten.append(' '.join(fields))

    path.write_text('\n'.join(rewritten) + '\n')


def run_candidate(stdin_text, argv_file=None):
    if OUT.exists():
        OUT.unlink()
    cmd = [str(BINARY)]
    if argv_file is not None:
        cmd.append(str(argv_file))
    try:
        proc = subprocess.run(
            cmd,
            input=stdin_text,
            text=True,
            capture_output=True,
            cwd=str(HOME),
            timeout=5,
        )
    except (subprocess.TimeoutExpired, OSError):
        return []

    results = [proc.stdout.strip()]
    if OUT.is_file():
        results.append(OUT.read_text().strip())
    return results


def test_source_compiles_and_calculates_from_runtime_data():
    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', str(CPP), '-o', str(BINARY)],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"C++ compilation failed:\n{compile_result.stderr}"
    assert BINARY.is_file() and os.access(BINARY, os.X_OK)

    selected_ids = ['1', '3', '4', '6', '7']
    dynamic_values = [0.7100, 0.7700, 0.7400, 0.8000, 0.7600]
    expected = expected_line(dynamic_values)

    backups = {}
    candidates = []
    for path in HOME.rglob('*'):
        if not path.is_file() or path in (CPP, OUT):
            continue
        if path.suffix.lower() not in ('.txt', '.dat', '.csv'):
            continue
        try:
            backups[path] = path.read_bytes()
            candidates.append(path)
        except OSError:
            pass
    output_backup = OUT.read_bytes() if OUT.exists() else None

    try:
        # Make the original two join inputs a new coherent experiment and also
        # update any filtered-data artifact the solution created.
        EXPERIMENTS.write_text(
            'id pca_components\n1 10\n2 50\n3 10\n4 10\n5 50\n6 10\n7 10\n'
        )
        METRICS.write_text(
            'id accuracy\n'
            '1 0.7100\n2 0.9300\n3 0.7700\n4 0.7400\n'
            '5 0.9300\n6 0.8000\n7 0.7600\n'
        )
        for path in candidates:
            if path not in (EXPERIMENTS, METRICS):
                rewrite_data_file(path, dynamic_values, selected_ids)

        joined = '\n'.join(
            f'{i} 10 {v:.4f}' for i, v in zip(selected_ids, dynamic_values)
        ) + '\n'
        accuracy_only = '\n'.join(f'{v:.4f}' for v in dynamic_values) + '\n'
        id_accuracy = '\n'.join(
            f'{i} {v:.4f}' for i, v in zip(selected_ids, dynamic_values)
        ) + '\n'

        argv_files = []
        for number, content in enumerate((joined, accuracy_only, id_accuracy)):
            path = pathlib.Path(f'/tmp/runtime_filtered_{number}.txt')
            path.write_text(content)
            argv_files.append(path)

        observed = []
        for stdin_text in (joined, accuracy_only, id_accuracy):
            observed.extend(run_candidate(stdin_text))
            for argv_file in argv_files:
                observed.extend(run_candidate(stdin_text, argv_file))

        assert expected in observed, (
            'The compiled program did not calculate the confidence interval from '
            f'runtime filtered data. Expected runtime output: {expected!r}; '
            f'observed nonempty outputs: {[x for x in observed if x]!r}'
        )
    finally:
        for path, data in backups.items():
            try:
                path.write_bytes(data)
            except OSError:
                pass
        if output_backup is not None:
            OUT.write_bytes(output_backup)
        elif OUT.exists():
            OUT.unlink()

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
