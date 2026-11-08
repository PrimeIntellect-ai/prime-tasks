#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import subprocess
from collections import Counter
import pytest


def read_fasta(filepath):
    seqs = []
    with open(filepath, 'r') as f:
        seq = []
        for line in f:
            line = line.strip()
            if line.startswith('>'):
                if seq:
                    seqs.append(''.join(seq))
                    seq = []
            else:
                seq.append(line)
        if seq:
            seqs.append(''.join(seq))
    return seqs


def compute_ground_truth(seqs):
    n_seqs = len(seqs)
    out_degrees = [0] * n_seqs
    total_edges = 0

    for i in range(n_seqs):
        for j in range(n_seqs):
            if i == j:
                continue
            s1 = seqs[i]
            s2 = seqs[j]
            max_len = min(len(s1), len(s2))
            for length in range(max_len, 9, -1):
                if s1[-length:] == s2[:length]:
                    out_degrees[i] += 1
                    total_edges += 1
                    break

    freqs = Counter(out_degrees)
    x_vals = []
    y_vals = []
    for x, y in freqs.items():
        if y > 0:
            x_vals.append(x)
            y_vals.append(y)

    n = len(x_vals)
    sum_x = sum(x_vals)
    sum_lny = sum(math.log(y) for y in y_vals)
    sum_x_lny = sum(x * math.log(y) for x, y in zip(x_vals, y_vals))
    sum_x2 = sum(x**2 for x in x_vals)

    m = (n * sum_x_lny - sum_x * sum_lny) / (n * sum_x2 - sum_x**2)
    c = (sum_lny - m * sum_x) / n
    A = math.exp(c)
    b = -m
    return n_seqs, total_edges, A, b


def build_rust_binary(project_path):
    manifest = os.path.join(project_path, 'Cargo.toml')
    assert os.path.isdir(project_path), f'Cargo project {project_path} is missing.'
    assert os.path.isfile(manifest), f'Cargo manifest {manifest} is missing.'

    metadata_proc = subprocess.run(
        ['cargo', 'metadata', '--format-version', '1', '--no-deps', '--manifest-path', manifest],
        cwd=project_path, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=60
    )
    assert metadata_proc.returncode == 0, f'Cargo metadata failed: {metadata_proc.stderr}'
    metadata = json.loads(metadata_proc.stdout)

    project_real = os.path.realpath(project_path)
    candidates = []
    for package in metadata.get('packages', []):
        for target in package.get('targets', []):
            if 'bin' not in target.get('kind', []):
                continue
            src = os.path.realpath(target.get('src_path', ''))
            try:
                inside = os.path.commonpath([project_real, src]) == project_real
            except ValueError:
                inside = False
            if inside and src.endswith('.rs'):
                candidates.append((package, target, src))

    assert candidates, 'The Cargo project has no Rust binary target.'
    preferred = [c for c in candidates if c[1].get('name') == 'sequence_graph']
    if len(preferred) == 1:
        package, target, source = preferred[0]
    else:
        assert len(candidates) == 1, 'Cargo project has multiple ambiguous binary targets.'
        package, target, source = candidates[0]

    assert os.path.isfile(source), f'Rust source file {source} is missing.'
    assert os.path.getsize(source) > 0, f'Rust source file {source} is empty.'

    build_proc = subprocess.run(
        ['cargo', 'build', '--manifest-path', manifest, '--package', package['name'],
         '--bin', target['name'], '--message-format=json-render-diagnostics'],
        cwd=project_path, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=180
    )
    assert build_proc.returncode == 0, f'Cargo build failed: {build_proc.stderr}\n{build_proc.stdout}'

    executables = []
    for line in build_proc.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        executable = message.get('executable')
        message_target = message.get('target', {})
        if executable and message_target.get('name') == target['name']:
            executables.append(executable)

    assert executables, 'Cargo did not produce an executable Rust binary.'
    executable = executables[-1]
    assert os.path.isfile(executable), f'Built executable {executable} is missing.'
    assert os.access(executable, os.X_OK), f'Built artifact {executable} is not executable.'
    with open(executable, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'Built artifact is not a native Linux executable.'
    return executable


def test_final_state():
    fasta_path = '/home/user/sequences.fasta'
    results_path = '/home/user/analysis_results.json'
    project_path = '/home/user/sequence_graph'

    assert os.path.exists(fasta_path), f'FASTA file {fasta_path} is missing.'
    assert os.path.exists(results_path), f'Results JSON file {results_path} is missing.'

    executable = build_rust_binary(project_path)

    # A prewritten JSON file is not sufficient: the compiled Rust artifact must
    # recreate it when executed.
    os.remove(results_path)
    run_proc = subprocess.run(
        [executable], cwd=project_path, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert run_proc.returncode == 0, f'Rust program failed: {run_proc.stderr}'
    assert os.path.exists(results_path), 'Rust program did not create analysis_results.json.'

    seqs = read_fasta(fasta_path)
    expected_nodes, expected_edges, expected_A, expected_b = compute_ground_truth(seqs)

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'Could not parse {results_path} as JSON.')

    assert 'total_nodes' in results, "Missing 'total_nodes' in JSON output."
    assert 'total_edges' in results, "Missing 'total_edges' in JSON output."
    assert 'A' in results, "Missing 'A' in JSON output."
    assert 'b' in results, "Missing 'b' in JSON output."

    assert results['total_nodes'] == expected_nodes, f"Expected total_nodes={expected_nodes}, got {results['total_nodes']}"
    assert results['total_edges'] == expected_edges, f"Expected total_edges={expected_edges}, got {results['total_edges']}"
    assert math.isclose(results['A'], expected_A, rel_tol=1e-3, abs_tol=1e-3), f"Expected A={expected_A}, got {results['A']}"
    assert math.isclose(results['b'], expected_b, rel_tol=1e-3, abs_tol=1e-3), f"Expected b={expected_b}, got {results['b']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
