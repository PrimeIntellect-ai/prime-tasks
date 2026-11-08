#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import difflib
import json
import os
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/artifact_manager')
GRAPH = PROJECT / 'artifacts_graph.json'
OUTPUT = Path('/home/user/final_artifacts.json')
GROUND_TRUTH = (
    'Fixed the concurrent modification bug in the build cache and upgraded '
    'the networking library to version two point one.'
)

ORIGINAL_GRAPH = [
    {'id': 'base_lib', 'type': 'binary', 'dependencies': []},
    {'id': 'release_notes', 'type': 'audio_memo', 'dependencies': ['base_lib']},
]

SYNTHETIC_GRAPH = [
    {'id': 'release_notes', 'type': 'audio_memo', 'dependencies': ['application']},
    {'id': 'application', 'type': 'binary', 'dependencies': ['library_a', 'library_b']},
    {'id': 'library_b', 'type': 'binary', 'dependencies': ['core']},
    {'id': 'documentation', 'type': 'text', 'dependencies': []},
    {'id': 'library_a', 'type': 'binary', 'dependencies': ['core']},
    {'id': 'core', 'type': 'binary', 'dependencies': []},
]


def run_program():
    if OUTPUT.exists():
        OUTPUT.unlink()

    result = subprocess.run(
        ['cargo', 'run', '--quiet'],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        'Rust project did not compile and run successfully.\n'
        f'stdout:\n{result.stdout}\n'
        f'stderr:\n{result.stderr}'
    )
    assert OUTPUT.is_file(), f'Final output file missing: {OUTPUT}'

    try:
        with OUTPUT.open() as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'File is not valid JSON: {OUTPUT}: {exc}')


def validate_manifest(data, graph):
    assert isinstance(data, list), 'Output JSON must be an array of objects.'
    assert all(isinstance(item, dict) for item in data), 'Every array item must be an object.'

    expected_ids = [item['id'] for item in graph]
    actual_ids = [item.get('id') for item in data]
    assert len(actual_ids) == len(expected_ids), 'Output must contain every artifact exactly once.'
    assert len(set(actual_ids)) == len(actual_ids), 'Output contains duplicate artifact IDs.'
    assert set(actual_ids) == set(expected_ids), (
        f'Output artifact IDs differ from the input graph: {actual_ids}'
    )

    expected_types = {item['id']: item['type'] for item in graph}
    positions = {artifact_id: index for index, artifact_id in enumerate(actual_ids)}
    for item in data:
        artifact_id = item['id']
        assert item.get('type') == expected_types[artifact_id], (
            f'Wrong type for artifact {artifact_id!r}'
        )

    for node in graph:
        for dependency in node['dependencies']:
            assert positions[dependency] < positions[node['id']], (
                f'Dependency {dependency!r} must appear before {node["id"]!r}'
            )

    transcription = None
    for item in data:
        if item.get('id') == 'release_notes':
            transcription = item.get('transcription')
            break

    assert transcription is not None, (
        "Could not find 'release_notes' artifact with a 'transcription' field."
    )
    assert isinstance(transcription, str), "'transcription' field must be a string."

    t_norm = transcription.lower().strip()
    g_norm = GROUND_TRUTH.lower().strip()
    similarity = difflib.SequenceMatcher(None, t_norm, g_norm).ratio()
    assert similarity >= 0.85, (
        f'Transcription similarity {similarity:.3f} is below the 0.85 threshold.\n'
        f"Expected (normalized): '{g_norm}'\n"
        f"Got (normalized): '{t_norm}'"
    )


def test_compiled_program_generates_complete_topological_manifests():
    assert (PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml is missing.'
    assert (PROJECT / 'src' / 'main.rs').is_file(), 'Rust main source is missing.'

    original_bytes = GRAPH.read_bytes() if GRAPH.exists() else None
    try:
        GRAPH.write_text(json.dumps(ORIGINAL_GRAPH, indent=2) + '\n')
        validate_manifest(run_program(), ORIGINAL_GRAPH)

        # The deliberately non-topological input exercises branching,
        # transitive dependencies, and an independent root.
        GRAPH.write_text(json.dumps(SYNTHETIC_GRAPH, indent=2) + '\n')
        validate_manifest(run_program(), SYNTHETIC_GRAPH)
    finally:
        if original_bytes is None:
            GRAPH.unlink(missing_ok=True)
        else:
            GRAPH.write_bytes(original_bytes)

    # Leave the requested manifest generated from the provided graph.
    GRAPH.write_text(json.dumps(ORIGINAL_GRAPH, indent=2) + '\n')
    validate_manifest(run_program(), ORIGINAL_GRAPH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
