#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import math
import os
import sqlite3

import jsonschema

DB_PATH = "/home/user/papers.db"
OUTPUT_PATH = "/home/user/top_authors.json"
SCHEMA_PATH = "/home/user/output_schema.json"

EXPECTED_PAPERS = [
    (1, "A", 1992), (2, "B", 1995), (3, "C", 1998),
    (4, "D", 2001), (5, "E", 2005), (6, "F", 2009),
    (7, "G", 2011), (8, "H", 2015), (9, "I", 2019),
    (10, "J", 2020),
]
EXPECTED_AUTHORS = [
    (1, "Alice"), (2, "Bob"), (3, "Charlie"), (4, "Diana"), (5, "Eve")
]
EXPECTED_PAPER_AUTHORS = [
    (1, 1), (1, 2), (2, 1), (3, 1), (4, 2), (5, 2), (6, 2),
    (7, 3), (8, 3), (8, 4), (9, 4), (10, 4), (10, 5),
]
EXPECTED_CITATIONS = [
    (2, 1), (3, 1), (4, 1), (5, 2), (6, 2),
    (7, 4), (8, 4), (9, 7), (10, 8),
]
EXPECTED_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "array",
    "items": {
        "type": "object",
        "properties": {
            "author_id": {"type": "integer"},
            "author_name": {"type": "string"},
            "peak_decade": {"type": "integer"},
            "author_score": {"type": "number"},
            "decade_rank": {"type": "integer", "minimum": 1, "maximum": 3},
            "max_coauthor_weight": {"type": "integer"},
        },
        "required": [
            "author_id", "author_name", "peak_decade", "author_score",
            "decade_rank", "max_coauthor_weight"
        ],
    },
}
REQUIRED_KEYS = set(EXPECTED_SCHEMA["items"]["required"])


def pagerank(nodes, edges, alpha=0.85):
    nodes = list(nodes)
    n = len(nodes)
    assert n > 0
    outgoing = {node: set() for node in nodes}
    for source, target in edges:
        assert source in outgoing and target in outgoing
        outgoing[source].add(target)

    rank = {node: 1.0 / n for node in nodes}
    for _ in range(10000):
        dangling = sum(rank[node] for node in nodes if not outgoing[node])
        updated = {
            node: (1.0 - alpha) / n + alpha * dangling / n
            for node in nodes
        }
        for source in nodes:
            if outgoing[source]:
                share = alpha * rank[source] / len(outgoing[source])
                for target in outgoing[source]:
                    updated[target] += share
        error = sum(abs(updated[node] - rank[node]) for node in nodes)
        rank = updated
        if error < n * 1e-14:
            break
    else:
        raise AssertionError("Reference PageRank calculation did not converge")
    return rank


def derive_expected(conn):
    papers = conn.execute("SELECT id, title, year FROM papers ORDER BY id").fetchall()
    authors = conn.execute("SELECT id, name FROM authors ORDER BY id").fetchall()
    paper_authors = conn.execute(
        "SELECT paper_id, author_id FROM paper_authors ORDER BY paper_id, author_id"
    ).fetchall()
    citations = conn.execute(
        "SELECT source_paper_id, target_paper_id FROM citations "
        "ORDER BY source_paper_id, target_paper_id"
    ).fetchall()

    # Ensure the verifier is calculating against the supplied dataset, not an
    # agent-modified substitute.
    assert papers == EXPECTED_PAPERS, "The papers table was modified."
    assert authors == EXPECTED_AUTHORS, "The authors table was modified."
    assert paper_authors == EXPECTED_PAPER_AUTHORS, "The paper_authors table was modified."
    assert citations == EXPECTED_CITATIONS, "The citations table was modified."

    paper_year = {paper_id: year for paper_id, _, year in papers}
    author_name = dict(authors)
    papers_by_author = collections.defaultdict(set)
    authors_by_paper = collections.defaultdict(set)
    for paper_id, author_id in paper_authors:
        papers_by_author[author_id].add(paper_id)
        authors_by_paper[paper_id].add(author_id)

    ranks = pagerank([paper_id for paper_id, _, _ in papers], citations, alpha=0.85)
    author_scores = {
        author_id: sum(ranks[paper_id] for paper_id in papers_by_author[author_id])
        for author_id in author_name
        if papers_by_author[author_id]
    }

    peak_decades = {}
    for author_id, authored_papers in papers_by_author.items():
        counts = collections.Counter((paper_year[p] // 10) * 10 for p in authored_papers)
        highest_count = max(counts.values())
        peak_decades[author_id] = min(
            decade for decade, count in counts.items() if count == highest_count
        )

    pair_weights = collections.Counter()
    for paper_id in paper_year:
        paper_author_ids = sorted(authors_by_paper[paper_id])
        for index, left in enumerate(paper_author_ids):
            for right in paper_author_ids[index + 1:]:
                pair_weights[(left, right)] += 1

    max_coauthor = {}
    for author_id in author_scores:
        weights = [
            weight for pair, weight in pair_weights.items() if author_id in pair
        ]
        max_coauthor[author_id] = max(weights, default=0)

    grouped = collections.defaultdict(list)
    for author_id, decade in peak_decades.items():
        grouped[decade].append(author_id)

    expected = {}
    for decade, author_ids in grouped.items():
        ordered = sorted(author_ids, key=lambda aid: (-author_scores[aid], aid))
        for decade_rank, author_id in enumerate(ordered[:3], start=1):
            expected[author_id] = {
                "author_id": author_id,
                "author_name": author_name[author_id],
                "peak_decade": decade,
                "author_score": author_scores[author_id],
                "decade_rank": decade_rank,
                "max_coauthor_weight": max_coauthor[author_id],
            }
    return expected


def test_final_output_exists_and_valid():
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    assert os.path.isfile(OUTPUT_PATH), f"Output path {OUTPUT_PATH} is not a file."

    with open(SCHEMA_PATH, "r", encoding="utf-8") as handle:
        schema = json.load(handle)
    assert schema == EXPECTED_SCHEMA, "The provided output schema was modified."
    jsonschema.Draft7Validator.check_schema(schema)

    with open(OUTPUT_PATH, "r", encoding="utf-8") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError as exc:
            raise AssertionError("Output is not valid JSON.") from exc

    assert isinstance(data, list), "Output must be a JSON array."
    jsonschema.validate(instance=data, schema=schema)

    with sqlite3.connect(DB_PATH) as conn:
        expected = derive_expected(conn)

    assert len(data) == len(expected), (
        f"Expected exactly {len(expected)} output rows, got {len(data)}."
    )

    seen_ids = set()
    seen_names = set()
    for item in data:
        assert isinstance(item, dict), "Each item in the array must be a JSON object."
        missing_keys = REQUIRED_KEYS - set(item.keys())
        assert not missing_keys, f"Missing keys in output object: {missing_keys}"

        author_id = item["author_id"]
        name = item["author_name"]
        assert author_id not in seen_ids, f"Duplicate author_id in output: {author_id}"
        assert name not in seen_names, f"Duplicate author_name in output: {name}"
        seen_ids.add(author_id)
        seen_names.add(name)

        assert author_id in expected, f"Unexpected author_id found: {author_id}"
        wanted = expected[author_id]
        assert name == wanted["author_name"], f"Wrong author_name for author_id {author_id}."
        assert item["peak_decade"] == wanted["peak_decade"], (
            f"Wrong peak decade for {name}. Expected {wanted['peak_decade']}, "
            f"got {item['peak_decade']}."
        )
        assert item["max_coauthor_weight"] == wanted["max_coauthor_weight"], (
            f"Wrong max coauthor weight for {name}. Expected "
            f"{wanted['max_coauthor_weight']}, got {item['max_coauthor_weight']}."
        )
        assert isinstance(item["author_score"], (int, float)), (
            f"author_score for {name} must be a number."
        )
        assert math.isfinite(item["author_score"]), f"author_score for {name} must be finite."
        assert math.isclose(
            item["author_score"], wanted["author_score"], rel_tol=1e-5, abs_tol=1e-5
        ), (
            f"Wrong author_score for {name}. Expected approximately "
            f"{wanted['author_score']}, got {item['author_score']}."
        )
        assert isinstance(item["decade_rank"], int), (
            f"decade_rank for {name} must be an integer."
        )
        assert 1 <= item["decade_rank"] <= 3, (
            f"decade_rank for {name} must be between 1 and 3."
        )
        assert item["decade_rank"] == wanted["decade_rank"], (
            f"Wrong decade_rank for {name}. Expected {wanted['decade_rank']}, "
            f"got {item['decade_rank']}."
        )

    assert seen_ids == set(expected), "The output does not contain exactly the expected authors."
    assert seen_names == {row["author_name"] for row in expected.values()}, (
        "The output does not contain exactly the expected author names."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
