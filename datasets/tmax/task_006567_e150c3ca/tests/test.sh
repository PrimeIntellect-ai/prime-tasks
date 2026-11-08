#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
import tempfile
import pytest

SOURCE = "/home/user/query_engine.cpp"
EXECUTABLE = "/home/user/query_engine"
DATA_DIR = "/home/user/data"


def test_source_file_exists():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {EXECUTABLE} is not a compiled executable."


def test_result_json():
    result_file = "/home/user/result.json"
    assert os.path.isfile(result_file), f"Output file {result_file} does not exist."

    with open(result_file, "r") as f:
        content = f.read().strip()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"File {result_file} does not contain valid JSON.")

    expected_data = [
        {"author_id": 1, "name": "Alice", "domain_citations": 230, "coauthor_degree": 3},
        {"author_id": 2, "name": "Bob", "domain_citations": 110, "coauthor_degree": 2}
    ]

    assert data == expected_data, f"JSON content does not match expected output. Got: {data}"


def calculate_expected(domain, top):
    with open(os.path.join(DATA_DIR, "authors.csv"), newline="") as f:
        names = {int(row["author_id"]): row["name"] for row in csv.DictReader(f)}

    with open(os.path.join(DATA_DIR, "papers.csv"), newline="") as f:
        papers = {
            int(row["paper_id"]): (row["domain"], int(row["citation_count"]))
            for row in csv.DictReader(f)
        }

    paper_authors = {}
    with open(os.path.join(DATA_DIR, "authors_papers.csv"), newline="") as f:
        for row in csv.DictReader(f):
            paper_authors.setdefault(int(row["paper_id"]), set()).add(int(row["author_id"]))

    citations = {}
    coauthors = {}
    for paper_id, (paper_domain, count) in papers.items():
        if paper_domain != domain:
            continue
        authors = paper_authors.get(paper_id, set())
        for author_id in authors:
            citations[author_id] = citations.get(author_id, 0) + count
            coauthors.setdefault(author_id, set()).update(authors - {author_id})

    ranked = sorted(citations, key=lambda author_id: (-citations[author_id], author_id))[:top]
    return [
        {
            "author_id": author_id,
            "name": names[author_id],
            "domain_citations": citations[author_id],
            "coauthor_degree": len(coauthors.get(author_id, set())),
        }
        for author_id in ranked
    ]


def run_and_check(binary, domain, top):
    fd, output_path = tempfile.mkstemp(prefix="query-output-", suffix=".json")
    os.close(fd)
    os.unlink(output_path)
    try:
        completed = subprocess.run(
            [binary, "--domain", domain, "--top", str(top), "--out", output_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert completed.returncode == 0, (
            f"{binary} exited with {completed.returncode}. stderr: {completed.stderr}"
        )
        assert os.path.isfile(output_path), f"{binary} did not create the requested output file."
        with open(output_path, "r") as f:
            raw = f.read()

        expected = calculate_expected(domain, top)
        expected_text = json.dumps(expected, ensure_ascii=False, separators=(",", ":"))
        assert raw in (expected_text, expected_text + "\n"), (
            f"Incorrect or non-strict JSON for domain={domain!r}, top={top}. Got: {raw!r}"
        )
    finally:
        if os.path.exists(output_path):
            os.unlink(output_path)


def write_generated_dataset():
    token = secrets.token_hex(5)
    domain_a = "DomainA_" + token
    domain_b = "DomainB_" + token
    base_author = 1000 + secrets.randbelow(50000)
    base_paper = 70000 + secrets.randbelow(50000)
    author_ids = [base_author + n * 7 for n in range(7)]
    paper_ids = [base_paper + n * 11 for n in range(7)]
    counts = [13 + secrets.randbelow(80) for _ in range(7)]

    with open(os.path.join(DATA_DIR, "authors.csv"), "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["author_id", "name"])
        for index, author_id in enumerate(author_ids):
            writer.writerow([author_id, f"Researcher{index}_{token}"])

    with open(os.path.join(DATA_DIR, "papers.csv"), "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["paper_id", "title", "domain", "citation_count"])
        rows = [
            (paper_ids[0], "Study0", domain_a, counts[0]),
            (paper_ids[1], "Study1", domain_a, counts[1]),
            (paper_ids[2], "Study2", domain_a, counts[2]),
            (paper_ids[3], "Study3", domain_a, counts[3]),
            (paper_ids[4], "Study4", domain_b, counts[4]),
            (paper_ids[5], "Study5", domain_b, counts[5]),
            (paper_ids[6], "Study6", "Unused_" + token, counts[6]),
        ]
        writer.writerows(rows)

    links = [
        (author_ids[0], paper_ids[0]), (author_ids[1], paper_ids[0]), (author_ids[2], paper_ids[0]),
        (author_ids[0], paper_ids[1]), (author_ids[3], paper_ids[1]),
        (author_ids[1], paper_ids[2]), (author_ids[3], paper_ids[2]),
        (author_ids[4], paper_ids[3]),
        (author_ids[2], paper_ids[4]), (author_ids[5], paper_ids[4]),
        (author_ids[5], paper_ids[5]), (author_ids[6], paper_ids[5]),
        (author_ids[0], paper_ids[6]),
    ]
    with open(os.path.join(DATA_DIR, "authors_papers.csv"), "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["author_id", "paper_id"])
        writer.writerows(links)

    return domain_a, domain_b, "Missing_" + token


def test_query_engine_behavior_and_source():
    compiled = "/tmp/query_engine_from_source"
    build = subprocess.run(
        ["g++", "-O3", "-std=c++17", SOURCE, "-o", compiled],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"Source failed to compile: {build.stderr}"

    # Execute the submitted artifact against the original required query.
    run_and_check(EXECUTABLE, "AI", 2)

    paths = [os.path.join(DATA_DIR, name) for name in
             ("authors.csv", "papers.csv", "authors_papers.csv")]
    backups = {path: open(path, "rb").read() for path in paths}
    try:
        domain_a, domain_b, missing = write_generated_dataset()
        for binary in (EXECUTABLE, compiled):
            run_and_check(binary, domain_a, 1)
            run_and_check(binary, domain_a, 4)
            run_and_check(binary, domain_b, 10)
            run_and_check(binary, missing, 3)
    finally:
        for path, content in backups.items():
            with open(path, "wb") as f:
                f.write(content)
        if os.path.exists(compiled):
            os.unlink(compiled)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
