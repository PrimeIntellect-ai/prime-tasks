#!/bin/bash
set -e
mkdir -p /logs/verifier

cat > /tmp/verify_task.py <<'PY'
import glob
import math
import os
import shutil
import subprocess
import sys

import h5py
import numpy as np

HOME = '/home/user'
NETWORKS = HOME + '/networks.txt'
OUTPUT = HOME + '/training_data.h5'
RUNS = 5000
P = 0.3


def find_project():
    preferred = HOME + '/gnn_data/Cargo.toml'
    manifests = [preferred] if os.path.isfile(preferred) else []
    manifests += [p for p in glob.glob(HOME + '/**/Cargo.toml', recursive=True)
                  if p != preferred and '/target/' not in p]
    assert manifests, 'No Cargo project was found under /home/user.'

    for manifest in manifests:
        project = os.path.dirname(manifest)
        rust_files = glob.glob(project + '/src/**/*.rs', recursive=True)
        if rust_files:
            source = '\n'.join(open(p, encoding='utf-8', errors='ignore').read()
                               for p in rust_files)
            if '5000' in source or '5_000' in source:
                return manifest
    raise AssertionError('No Rust Cargo project containing the required 5,000-run simulation was found.')


def run_program(manifest):
    env = os.environ.copy()
    env['HOME'] = HOME
    env.setdefault('CARGO_HOME', '/usr/local/cargo')
    env.setdefault('RUSTUP_HOME', '/usr/local/rustup')
    result = subprocess.run(
        ['cargo', 'run', '--release', '--quiet', '--manifest-path', manifest],
        cwd=os.path.dirname(manifest), env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300)
    assert result.returncode == 0, (
        'The submitted Rust application failed when executed.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}')
    assert os.path.isfile(OUTPUT), 'The executed Rust program did not create /home/user/training_data.h5.'


def read_output(expected_len):
    assert os.path.isfile(OUTPUT), '/home/user/training_data.h5 does not exist.'
    with h5py.File(OUTPUT, 'r') as f:
        assert list(f.keys()) == ['mean_times'], (
            'The HDF5 root must contain exactly one object named mean_times.')
        ds = f['mean_times']
        assert isinstance(ds, h5py.Dataset), '/mean_times is not a dataset.'
        assert ds.ndim == 1, '/mean_times must be one-dimensional.'
        assert ds.dtype.kind == 'f' and ds.dtype.itemsize == 8, (
            '/mean_times must contain 64-bit floating-point values.')
        data = ds[:]

    assert len(data) == expected_len, (
        f"Expected {expected_len} values in 'mean_times', got {len(data)}.")
    assert np.all(np.isfinite(data)), 'mean_times contains a non-finite value.'

    # Every run has an integer completion time, so a mean of exactly 5,000 runs
    # must be an integer multiple of 1/5,000 (up to floating-point roundoff).
    scaled = data * RUNS
    assert np.all(np.abs(scaled - np.rint(scaled)) < 1e-6), (
        'Values are not means of 5,000 integer-valued propagation times.')
    return data.astype(float)


def exact_moments(n, edges):
    neighbors = [set() for _ in range(n)]
    for a, b in edges:
        neighbors[a].add(b)
        neighbors[b].add(a)

    full = (1 << n) - 1
    means = {full: 0.0}
    seconds = {full: 0.0}

    # Infection only moves to strict supersets, so descending population count
    # gives an exact dynamic program over all reachable infection states.
    for count in range(n - 1, 0, -1):
        for mask in range(1 << n):
            if not (mask & 1) or mask.bit_count() != count:
                continue
            susceptible = [v for v in range(n) if not (mask >> v) & 1]
            qs = []
            for v in susceptible:
                k = sum((mask >> u) & 1 for u in neighbors[v])
                qs.append(1.0 - (1.0 - P) ** k)

            transitions = []
            for choice in range(1 << len(susceptible)):
                prob = 1.0
                nxt = mask
                for j, v in enumerate(susceptible):
                    if (choice >> j) & 1:
                        prob *= qs[j]
                        nxt |= 1 << v
                    else:
                        prob *= 1.0 - qs[j]
                if prob:
                    transitions.append((nxt, prob))

            stay = sum(prob for nxt, prob in transitions if nxt == mask)
            assert stay < 1.0 - 1e-14, 'Test graph is unreachable from node 0.'
            a = sum(prob * means[nxt] for nxt, prob in transitions if nxt != mask)
            mean = (1.0 + a) / (1.0 - stay)
            b = sum(prob * seconds[nxt] for nxt, prob in transitions if nxt != mask)
            second = (2.0 * mean - 1.0 + b) / (1.0 - stay)
            means[mask] = mean
            seconds[mask] = second

    variance = max(0.0, seconds[1] - means[1] ** 2)
    return means[1], variance


def parse_networks(text):
    graphs = []
    for line in text.strip().splitlines():
        parts = line.split(maxsplit=2)
        assert len(parts) == 3
        gid, n = int(parts[0]), int(parts[1])
        edges = []
        for item in parts[2].split(';'):
            a, b = item.split(',')
            edges.append((int(a), int(b)))
        graphs.append((gid, n, edges))
    return graphs


def check_statistics(values, graphs):
    assert len(values) == len(graphs)
    for value, (gid, n, edges) in zip(values, graphs):
        expected, variance = exact_moments(n, edges)
        tolerance = max(0.08, 8.0 * math.sqrt(variance / RUNS))
        assert abs(value - expected) <= tolerance, (
            f'Graph {gid} mean {value} is inconsistent with the specified model; '
            f'expected about {expected:.6f} (tolerance {tolerance:.6f}).')


def main():
    manifest = find_project()
    original = open(NETWORKS, 'rb').read()
    hidden = b'''1 5 0,1;0,2;1,2;1,3;2,4;3,4
2 7 0,1;0,2;1,3;1,4;2,4;2,5;3,6;4,6;5,6
3 4 0,1;0,2;0,3;1,2;1,3;2,3
4 6 0,1;1,2;2,3;3,4;4,5;0,5;1,4
5 6 0,1;0,2;1,3;2,3;3,4;3,5;4,5
'''

    try:
        with open(NETWORKS, 'wb') as f:
            f.write(hidden)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        run_program(manifest)
        hidden_graphs = parse_networks(hidden.decode())
        hidden_values = read_output(len(hidden_graphs))
        check_statistics(hidden_values, hidden_graphs)
    finally:
        with open(NETWORKS, 'wb') as f:
            f.write(original)

    # Execute again on the actual supplied input and leave that output intact.
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    run_program(manifest)
    original_graphs = parse_networks(original.decode())
    values = read_output(3)
    check_statistics(values, original_graphs)

    # Preserve the original verifier's range assertions.
    val_g2 = values[1]
    assert 5.5 <= val_g2 <= 6.5, (
        f'Graph 2 mean time {val_g2} is out of expected range [5.5, 6.5].')
    val_g3 = values[2]
    assert 15.5 <= val_g3 <= 17.5, (
        f'Graph 3 mean time {val_g3} is out of expected range [15.5, 17.5].')


if __name__ == '__main__':
    main()
PY

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
