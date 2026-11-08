#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import uuid
from pathlib import Path

import pytest

PROJECT = Path("/home/user/citation_query")
OUTPUT = Path("/home/user/top_articles.json")
DATASET = Path("/home/user/research_data.ttl")


def test_top_articles_json_exists_and_correct():
    output_path = "/home/user/top_articles.json"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} is not valid JSON.")

    assert isinstance(data, list), f"The JSON data should be a list, but got {type(data).__name__}."

    expected_data = [
        {
            "title": "Advances in Graph Databases",
            "year": 2019,
            "authors": "Dr. Alpha, Dr. Bravo",
            "citations": 4
        },
        {
            "title": "Machine Learning for RDF",
            "year": 2020,
            "authors": "Dr. Charlie",
            "citations": 3
        },
        {
            "title": "SPARQL Optimization Techniques",
            "year": 2019,
            "authors": "Dr. Alpha, Dr. Delta",
            "citations": 2
        }
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items, but got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."

        for key in ["title", "year", "authors", "citations"]:
            assert key in actual, f"Item at index {i} is missing the '{key}' key."
            assert actual[key] == expected[key], f"Item at index {i} has incorrect '{key}'. Expected {expected[key]}, got {actual[key]}."


def test_rust_project_executes_sparql_against_changed_graph():
    manifest = PROJECT / "Cargo.toml"
    main_rs = PROJECT / "src" / "main.rs"
    assert PROJECT.is_dir(), "The required /home/user/citation_query project does not exist."
    assert manifest.is_file(), "The Rust project is missing Cargo.toml."
    assert main_rs.is_file(), "The Rust application is missing src/main.rs."

    project_text = []
    rust_text = []
    for path in PROJECT.rglob("*"):
        if not path.is_file() or "target" in path.parts or ".git" in path.parts:
            continue
        if path.suffix.lower() not in {".rs", ".rq", ".sparql", ".toml"}:
            continue
        try:
            text = path.read_text(errors="ignore")
        except OSError:
            continue
        project_text.append(text)
        if path.suffix.lower() == ".rs":
            rust_text.append(text)

    all_project_text = "\n".join(project_text)
    all_rust_text = "\n".join(rust_text)
    assert re.search(r"\bSELECT\b", all_project_text, re.IGNORECASE), "No SPARQL SELECT query was found in the project."
    assert re.search(r"\bWHERE\b", all_project_text, re.IGNORECASE), "No SPARQL WHERE clause was found in the project."
    assert re.search(r"(?:\.|\b)(?:query|query_opt)\s*\(", all_rust_text, re.IGNORECASE), "The Rust source does not appear to execute a SPARQL query."

    token = uuid.uuid4().hex[:10]
    authors = {
        "a0": f"Zulu {token}",
        "a1": f"Able {token}",
        "a2": f"Mike {token}",
        "a3": f"Echo {token}",
        "a4": f"Bravo {token}",
        "a5": f"Old Author {token}",
        "a6": f"Zero Author {token}",
    }
    papers = {
        "p0": {"title": f"Zeta Study {token}", "year": 2022, "authors": ["a0", "a1"]},
        "p1": {"title": f"Alpha Study {token}", "year": 2020, "authors": ["a2"]},
        "p2": {"title": f"Beta Study {token}", "year": 2021, "authors": ["a3", "a4"]},
        "p3": {"title": f"Gamma Study {token}", "year": 2019, "authors": ["a1"]},
        "p4": {"title": f"Old Study {token}", "year": 2018, "authors": ["a5"]},
        "p5": {"title": f"Zero Study {token}", "year": 2024, "authors": ["a6"]},
        "p6": {"title": f"Citing Study {token}", "year": 2017, "authors": ["a2"]},
    }
    edges = {
        ("p1", "p0"), ("p2", "p0"), ("p3", "p0"), ("p4", "p0"), ("p5", "p0"),
        ("p0", "p1"), ("p2", "p1"), ("p3", "p1"),
        ("p0", "p2"), ("p1", "p2"), ("p5", "p2"),
        ("p0", "p3"),
        ("p0", "p4"), ("p1", "p4"), ("p2", "p4"), ("p3", "p4"), ("p5", "p4"), ("p6", "p4"),
    }

    incoming = {paper_id: 0 for paper_id in papers}
    for _, target in edges:
        incoming[target] += 1

    expected = []
    for paper_id, paper in papers.items():
        count = incoming[paper_id]
        if paper["year"] > 2018 and count > 0:
            expected.append({
                "title": paper["title"],
                "year": paper["year"],
                "authors": ", ".join(sorted(authors[a] for a in paper["authors"])),
                "citations": count,
            })
    expected.sort(key=lambda item: (-item["citations"], item["title"]))
    expected = expected[:3]

    ttl = [
        "@prefix ex: <http://example.org/> .",
        "@prefix dc: <http://purl.org/dc/elements/1.1/> .",
        "@prefix foaf: <http://xmlns.com/foaf/0.1/> .",
        "",
    ]
    for author_id, name in authors.items():
        ttl.append(f"ex:{author_id} a foaf:Person ; foaf:name {json.dumps(name)} .")
    ttl.append("")
    for paper_id, paper in papers.items():
        author_refs = ", ".join(f"ex:{a}" for a in paper["authors"])
        ttl.append(
            f"ex:{paper_id} a ex:Article ; dc:title {json.dumps(paper['title'])} ; "
            f"dc:date {paper['year']} ; ex:hasAuthor {author_refs} ."
        )
    ttl.append("")
    for source, target in sorted(edges):
        ttl.append(f"ex:{source} ex:cites ex:{target} .")
    fixture = "\n".join(ttl) + "\n"

    original_dataset = DATASET.read_bytes()
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None
    try:
        DATASET.write_text(fixture)
        if OUTPUT.exists():
            OUTPUT.unlink()

        env = os.environ.copy()
        env["RUSTUP_HOME"] = "/opt/rustup"
        env["CARGO_HOME"] = "/opt/cargo"
        env["PATH"] = "/opt/cargo/bin:" + env.get("PATH", "")
        result = subprocess.run(
            ["/opt/cargo/bin/cargo", "run", "--quiet"],
            cwd=PROJECT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=300,
        )
        assert result.returncode == 0, f"The Rust application failed on a changed RDF graph:\n{result.stdout}\n{result.stderr}"
        assert OUTPUT.is_file(), "Running the Rust application did not generate /home/user/top_articles.json."
        try:
            actual = json.loads(OUTPUT.read_text())
        except json.JSONDecodeError as exc:
            pytest.fail(f"The Rust application generated invalid JSON: {exc}")
        assert actual == expected, f"The application did not compute the expected results from the changed RDF graph. Expected {expected}, got {actual}."
    finally:
        DATASET.write_bytes(original_dataset)
        if original_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
