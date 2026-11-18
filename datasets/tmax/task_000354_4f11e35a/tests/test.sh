#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import uuid
from pathlib import Path

PROJECT = Path("/home/user/schema_extractor")
DATASET = Path("/home/user/dataset.nt")
OUTPUT = Path("/home/user/schema_output.json")
TYPE_PREDICATE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

CANONICAL_DATASET = '''<http://example.org/paper/1> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/Paper> .
<http://example.org/paper/1> <http://example.org/title> "Graph Processing in Rust" .
<http://example.org/paper/1> <http://example.org/author> <http://example.org/person/A> .
<http://example.org/person/A> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/Researcher> .
<http://example.org/person/A> <http://example.org/name> "Alice" .
<http://example.org/person/A> <http://example.org/worksAt> <http://example.org/org/1> .
<http://example.org/org/1> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/Institution> .
<http://example.org/org/1> <http://example.org/orgName> "University of Graph" .
<http://example.org/paper/2> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/Paper> .
<http://example.org/paper/2> <http://example.org/year> "2023"^^<http://www.w3.org/2001/XMLSchema#integer> .
<http://example.org/paper/2> <http://example.org/author> <http://example.org/person/B> .
<http://example.org/person/B> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://example.org/Researcher> .
<http://example.org/person/B> <http://example.org/name> "Bob" .
'''


def run_application():
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    env = os.environ.copy()
    env["CARGO_TERM_COLOR"] = "never"
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", str(PROJECT / "Cargo.toml")],
        cwd=str(PROJECT),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Rust application failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert OUTPUT.exists(), "Running the Rust application did not create schema_output.json"
    assert OUTPUT.is_file(), "schema_output.json is not a file"
    try:
        with OUTPUT.open("r") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        assert False, f"Rust application produced invalid JSON: {e}"


def make_challenge():
    token = uuid.uuid4().hex
    base = f"http://verifier.invalid/{token}"
    type_a = f"{base}/TypeZ"
    type_b = f"{base}/TypeA"
    subject_a1 = f"{base}/subject/a1"
    subject_a2 = f"{base}/subject/a2"
    subject_b = f"{base}/subject/b"
    untyped = f"{base}/subject/untyped"

    triples = [
        (subject_a1, f"{base}/zeta", '"value with spaces"'),
        (subject_a2, f"{base}/alpha", f"<{subject_b}>"),
        (subject_b, f"{base}/middle", '"a literal"'),
        (subject_a1, TYPE_PREDICATE, f"<{type_a}>"),
        (subject_a2, TYPE_PREDICATE, f"<{type_a}>"),
        (subject_b, TYPE_PREDICATE, f"<{type_b}>"),
        (subject_a1, f"{base}/alpha", '"duplicate property across subjects"'),
        (subject_a1, f"{base}/zeta", '"duplicate predicate"'),
        (untyped, f"{base}/ignored", '"must not create a type"'),
    ]
    random.SystemRandom().shuffle(triples)

    subject_types = {}
    subject_predicates = {}
    for subject, predicate, obj in triples:
        subject_predicates.setdefault(subject, set()).add(predicate)
        if predicate == TYPE_PREDICATE and obj.startswith("<") and obj.endswith(">"):
            subject_types.setdefault(subject, set()).add(obj[1:-1])

    schema = {}
    for subject, types in subject_types.items():
        for type_uri in types:
            schema.setdefault(type_uri, set()).update(subject_predicates.get(subject, set()))
    expected = {type_uri: sorted(predicates) for type_uri, predicates in schema.items()}

    lines = [f"<{s}> <{p}> {o} ." for s, p, o in triples]
    return "\n".join(lines) + "\n", expected


def test_rust_project_executes_and_processes_unseen_datasets():
    assert PROJECT.exists(), f"The Rust project directory {PROJECT} does not exist."
    assert PROJECT.is_dir(), f"The path {PROJECT} is not a directory."
    manifest = PROJECT / "Cargo.toml"
    assert manifest.is_file(), f"The Cargo manifest {manifest} does not exist."
    rust_sources = [p for p in PROJECT.rglob("*.rs") if p.is_file()]
    assert rust_sources, f"No Rust source files were found under {PROJECT}."
    assert any(p.read_text(errors="ignore").strip() for p in rust_sources), "Rust source files are empty."

    try:
        for _ in range(2):
            dataset_text, expected = make_challenge()
            DATASET.write_text(dataset_text)
            actual = run_application()
            assert isinstance(actual, dict), "The generated JSON must be an object."
            for key, value in actual.items():
                assert isinstance(value, list), f"The predicates for {key} must be an array."
                assert value == sorted(value), f"The list of predicates for {key} is not alphabetically sorted."
                assert len(value) == len(set(value)), f"The list of predicates for {key} contains duplicates."
            assert actual == expected, f"Application failed an unseen dataset. Expected: {expected}, Actual: {actual}"
    finally:
        DATASET.write_text(CANONICAL_DATASET)
        run_application()


def test_schema_output_exists():
    output_path = "/home/user/schema_output.json"
    assert os.path.exists(output_path), f"The output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"The path {output_path} is not a file."


def test_schema_output_content():
    output_path = "/home/user/schema_output.json"

    with open(output_path, 'r') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError as e:
            assert False, f"Failed to parse {output_path} as JSON: {e}"

    expected = {
        "http://example.org/Institution": [
            "http://example.org/orgName",
            "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
        ],
        "http://example.org/Paper": [
            "http://example.org/author",
            "http://example.org/title",
            "http://example.org/year",
            "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
        ],
        "http://example.org/Researcher": [
            "http://example.org/name",
            "http://example.org/worksAt",
            "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
        ]
    }

    # Sort the lists in the expected and actual to ensure order doesn't fail the test if they are out of order,
    # although the requirements say they should be sorted.
    for key in expected:
        expected[key] = sorted(expected[key])

    for key in actual:
        if isinstance(actual[key], list):
            # Check if the list is actually sorted as per requirements
            assert actual[key] == sorted(actual[key]), f"The list of predicates for {key} is not alphabetically sorted."

    assert actual == expected, f"The content of {output_path} does not match the expected schema. Expected: {expected}, Actual: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
