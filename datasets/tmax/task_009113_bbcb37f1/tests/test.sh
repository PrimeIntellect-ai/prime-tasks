#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import uuid

import pytest

EXECUTABLE = "/home/user/graph_query"
SOURCE = "/home/user/graph_query.cpp"
RESULTS = "/home/user/query_results.txt"
ORIGINAL_TSV = "/home/user/knowledge_base.tsv"


def read_results():
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} is missing."
    with open(RESULTS, "r", encoding="utf-8") as f:
        return [line.strip() for line in f.read().strip().splitlines() if line.strip()]


def expected_result(triples, person_a, topic_b):
    authors = {}
    topics = {}
    for subject, predicate, obj in triples:
        if predicate == "authored_by":
            authors.setdefault(subject, set()).add(obj)
        elif predicate == "covers_topic":
            topics.setdefault(subject, set()).add(obj)

    coauthors = set()
    for publication, people in authors.items():
        if person_a in people:
            coauthors.update(people)

    topical_authors = set()
    for publication, publication_topics in topics.items():
        if topic_b in publication_topics:
            topical_authors.update(authors.get(publication, set()))

    return sorted((coauthors & topical_authors) - {person_a})


def run_query(tsv_path, person_a, topic_b):
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        [EXECUTABLE, str(tsv_path), person_a, topic_b],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"graph_query exited with {completed.returncode}.\n"
        f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
    )
    return read_results()


def test_executable_exists():
    """Test that the compiled C++ program exists and is executable."""
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "graph_query is not a compiled native executable."
    assert os.path.isfile(SOURCE), f"C++ source file {SOURCE} is missing."


def test_results_file_exists():
    """Test that the query results file exists."""
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} is missing."


def test_results_content():
    """Test that the requested initial query results are correct."""
    content = read_results()
    expected = ["Person_2", "Person_4"]
    assert content == expected, (
        f"Query results do not match expected output.\n"
        f"Expected: {expected}\nActual: {content}"
    )


def test_parameterized_graph_query(tmp_path):
    """Execute the submitted tool against unpredictable graph/query combinations."""
    rng = random.SystemRandom()

    try:
        for trial in range(5):
            tag = uuid.uuid4().hex
            person_a = f"Person_A_{tag}"
            yes_separate = f"Person_QualifiesSeparate_{tag}"
            yes_same = f"Person_QualifiesSame_{tag}"
            coauthor_only = f"Person_CoauthOnly_{tag}"
            topic_only = f"Person_TopicOnly_{tag}"
            unrelated = f"Person_Unrelated_{tag}"
            topic_b = f"Topic_Target_{tag}"
            other_topic = f"Topic_Other_{tag}"

            def pub(name):
                return f"Publication_{name}_{tag}"

            triples = [
                (pub("shared1"), "authored_by", person_a),
                (pub("shared1"), "authored_by", yes_separate),
                (pub("shared1"), "authored_by", coauthor_only),
                (pub("shared2"), "authored_by", person_a),
                (pub("shared2"), "authored_by", yes_same),
                (pub("shared2"), "covers_topic", topic_b),
                (pub("topical1"), "authored_by", yes_separate),
                (pub("topical1"), "authored_by", yes_separate),
                (pub("topical1"), "covers_topic", topic_b),
                (pub("topical2"), "authored_by", topic_only),
                (pub("topical2"), "covers_topic", topic_b),
                (pub("irrelevant"), "authored_by", unrelated),
                (pub("irrelevant"), "covers_topic", other_topic),
                (person_a, "affiliated_with", f"Institute_{tag}"),
            ]

            people = [person_a, yes_separate, yes_same, coauthor_only,
                      topic_only, unrelated]
            for index in range(20):
                noise_pub = pub(f"noise{index}")
                for author in rng.sample(people, rng.randint(1, 3)):
                    triples.append((noise_pub, "authored_by", author))
                if rng.choice([True, False]):
                    triples.append((noise_pub, "covers_topic",
                                    rng.choice([topic_b, other_topic])))

            rng.shuffle(triples)
            graph_path = tmp_path / f"graph_{trial}_{tag}.tsv"
            with open(graph_path, "w", encoding="utf-8") as f:
                for subject, predicate, obj in triples:
                    f.write(f"{subject}\t{predicate}\t{obj}\n")

            expected = expected_result(triples, person_a, topic_b)
            actual = run_query(graph_path, person_a, topic_b)
            assert actual == expected, (
                f"Incorrect result for generated query {trial}.\n"
                f"Expected: {expected}\nActual: {actual}"
            )
    finally:
        # Restore and validate the final output required by the instruction.
        restored = run_query(ORIGINAL_TSV, "Person_1", "Topic_X")
        assert restored == ["Person_2", "Person_4"]
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
