#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/bio_graph')
READS = Path('/home/user/reads.txt')
RESULT = Path('/home/user/result.json')
ORIGINAL_READS = """AAAAAAAAAAAAAAAAAAAAAAAGATTACA
GATTACACCCCCCCCCCCCCCCCCCCCCCC
GATTACAGGGGGGGGGGGGGGGGGGGGGGG
GATTACATTTTTTTTTTTTTTTTTTTTTTT
NNNNNNNNNNNNNNNNNNNNNNNNNNNNNN
"""


def expected_result(reads):
    n = len(reads)
    outgoing = [[] for _ in reads]
    undirected = [set() for _ in reads]
    for i, a in enumerate(reads):
        for j, b in enumerate(reads):
            if i != j and len(a) >= 7 and len(b) >= 7 and a[-7:] == b[:7]:
                outgoing[i].append(j)
                undirected[i].add(j)
                undirected[j].add(i)

    components = []
    seen = set()
    for start in range(n):
        if start in seen:
            continue
        stack = [start]
        seen.add(start)
        component = []
        while stack:
            node = stack.pop()
            component.append(node)
            for neighbor in undirected[node]:
                if neighbor not in seen:
                    seen.add(neighbor)
                    stack.append(neighbor)
        components.append(component)

    largest = max(components, key=len)
    target = min(largest, key=lambda i: (-len(outgoing[i]), i))
    return {
        'largest_component_size': len(largest),
        'target_primer': reads[target][:20],
        'stability_score': 0.5,
    }


def validate_result(expected, require_original_assertions=False):
    assert RESULT.is_file(), f'Output file {RESULT} is missing after execution.'
    try:
        with RESULT.open() as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {RESULT} does not contain valid JSON: {exc}')

    assert 'largest_component_size' in data, "Key 'largest_component_size' is missing in JSON."
    assert 'target_primer' in data, "Key 'target_primer' is missing in JSON."
    assert 'stability_score' in data, "Key 'stability_score' is missing in JSON."
    assert set(data) == {'largest_component_size', 'target_primer', 'stability_score'}, 'result.json must contain exactly the required keys.'

    if require_original_assertions:
        assert data['largest_component_size'] == 4, f"Expected largest_component_size to be 4, got {data['largest_component_size']}."
        assert data['target_primer'] == 'AAAAAAAAAAAAAAAAAAAA', f"Expected target_primer to be 'AAAAAAAAAAAAAAAAAAAA', got '{data['target_primer']}'."
    else:
        assert data['largest_component_size'] == expected['largest_component_size'], (
            f"Expected largest_component_size {expected['largest_component_size']}, got {data['largest_component_size']}."
        )
        assert data['target_primer'] == expected['target_primer'], (
            f"Expected target_primer {expected['target_primer']!r}, got {data['target_primer']!r}."
        )

    score = data['stability_score']
    assert isinstance(score, (int, float)) and not isinstance(score, bool), f'Expected stability_score to be a number, got {type(score)}.'
    assert math.isfinite(score), 'stability_score must be finite.'
    assert math.isclose(score, 0.5, abs_tol=1e-4), f'Expected stability_score to be approximately 0.5 (numerically stable), got {score}.'


def unique_tokens(count):
    alphabet = 'ACGT'
    tokens = set()
    while len(tokens) < count:
        tokens.add(''.join(secrets.choice(alphabet) for _ in range(7)))
    return list(tokens)


def make_sequence(prefix, suffix):
    middle = ''.join(secrets.choice('ACGT') for _ in range(13))
    return prefix + middle + suffix


def run_binary(executable, reads):
    READS.write_text('\n'.join(reads) + '\n')
    if RESULT.exists():
        RESULT.unlink()
    proc = subprocess.run(
        [str(executable)], cwd=str(PROJECT), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert proc.returncode == 0, f'Application exited with {proc.returncode}. stderr:\n{proc.stderr[-4000:]}'
    validate_result(expected_result(reads))


def test_project_build_and_behavior():
    assert PROJECT.is_dir(), 'The /home/user/bio_graph Rust project is missing.'
    manifest = PROJECT / 'Cargo.toml'
    assert manifest.is_file(), 'Cargo.toml is missing from the bio_graph project.'

    env = os.environ.copy()
    env['HOME'] = '/home/user'
    metadata_proc = subprocess.run(
        ['cargo', 'metadata', '--format-version', '1', '--no-deps'], cwd=str(PROJECT), env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert metadata_proc.returncode == 0, f'cargo metadata failed:\n{metadata_proc.stderr[-4000:]}'
    metadata = json.loads(metadata_proc.stdout)
    manifest_resolved = manifest.resolve()
    packages = [p for p in metadata['packages'] if Path(p['manifest_path']).resolve() == manifest_resolved]
    assert len(packages) == 1, 'Could not identify the bio_graph package in Cargo metadata.'
    package = packages[0]
    assert package['name'] == 'bio_graph', f"Expected package name bio_graph, got {package['name']!r}."

    normal_deps = {d['name']: d for d in package['dependencies'] if d.get('kind') in (None, 'normal')}
    assert 'rayon' in normal_deps, 'rayon must be a normal dependency of the application.'
    assert 'petgraph' in normal_deps, 'petgraph must be a normal dependency of the application.'

    rust_files = [p for p in PROJECT.rglob('*.rs') if 'target' not in p.parts]
    assert rust_files, 'No Rust source files were found.'
    source = '\n'.join(p.read_text(errors='replace') for p in rust_files)
    source_without_comments = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    rayon_name = normal_deps['rayon'].get('rename') or 'rayon'
    petgraph_name = normal_deps['petgraph'].get('rename') or 'petgraph'
    assert re.search(rf'\b{re.escape(rayon_name)}\b', source_without_comments), 'Rust source does not use the rayon dependency.'
    assert re.search(r'par_iter|into_par_iter|par_bridge|par_chunks|rayon\s*::\s*(?:join|scope)|ThreadPool', source_without_comments), 'No Rayon parallel operation was found in the Rust source.'
    assert re.search(rf'\b{re.escape(petgraph_name)}\b', source_without_comments), 'Rust source does not use the petgraph dependency.'
    assert re.search(r'\b(?:Graph|DiGraph|StableGraph|StableDiGraph|GraphMap|DiGraphMap)\b', source_without_comments), 'No petgraph graph type was found in the Rust source.'

    build = subprocess.run(
        ['cargo', 'build', '--release', '--offline'], cwd=str(PROJECT), env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert build.returncode == 0, f'Release build failed:\n{build.stderr[-6000:]}'

    target_dir = Path(metadata['target_directory'])
    executable = target_dir / 'release' / 'bio_graph'
    assert executable.is_file(), f'Release executable {executable} is missing.'
    assert executable.read_bytes()[:4] == b'\x7fELF', 'The release artifact is not an ELF executable.'

    old_reads = READS.read_bytes() if READS.exists() else None
    try:
        # Preserve and exercise all assertions from the original verifier, but only
        # after running the compiled application on the original input.
        READS.write_text(ORIGINAL_READS)
        if RESULT.exists():
            RESULT.unlink()
        proc = subprocess.run(
            [str(executable)], cwd=str(PROJECT), text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert proc.returncode == 0, f'Application failed on the original reads:\n{proc.stderr[-4000:]}'
        validate_result(expected_result(ORIGINAL_READS.strip().splitlines()), require_original_assertions=True)

        # Randomized inputs prevent a hardcoded result.json from passing and test
        # weak components, overlap direction, out-degree, indexing, and tie-breaking.
        p, x, y, z, w, q, r = unique_tokens(7)
        case_one = [
            make_sequence(p, x),
            make_sequence(x, y),
            make_sequence(x, z),
            make_sequence(y, w),
            make_sequence(q, r),
        ]
        run_binary(executable, case_one)

        d0, d1, p, x, y, a, b, c = unique_tokens(8)
        case_two = [
            make_sequence(d0, d1),
            make_sequence(p, x),
            make_sequence(x, y),
            make_sequence(x, a),
            make_sequence(y, b),
            make_sequence(y, c),
        ]
        run_binary(executable, case_two)
    finally:
        if old_reads is None:
            READS.unlink(missing_ok=True)
        else:
            READS.write_bytes(old_reads)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
