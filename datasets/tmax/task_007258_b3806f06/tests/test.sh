#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

DB_PATH = '/home/user/publications.db'
JSON_PATH = '/home/user/top_papers.json'

def calculate_pagerank(nodes, edges, alpha=0.85, max_iter=100, tol=1e-06):
    """Simple PageRank implementation matching networkx defaults."""
    N = len(nodes)
    if N == 0:
        return {}

    pr = {n: 1.0 / N for n in nodes}
    out_degree = {n: 0 for n in nodes}
    for u, v in edges:
        out_degree[u] += 1

    dangling_nodes = [n for n in nodes if out_degree[n] == 0]

    for _ in range(max_iter):
        prev_pr = pr.copy()
        dangling_sum = sum(prev_pr[n] for n in dangling_nodes)

        for n in nodes:
            pr[n] = (1.0 - alpha) / N + alpha * dangling_sum / N

        for u, v in edges:
            pr[v] += alpha * prev_pr[u] / out_degree[u]

        err = sum(abs(pr[n] - prev_pr[n]) for n in nodes)
        if err < tol:
            break

    return pr

def get_expected_top_papers():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # 1. Deduplicate papers
    c.execute("""
        SELECT p1.paper_id, p1.title
        FROM papers p1
        JOIN (
            SELECT paper_id, MAX(updated_at) as max_updated_at
            FROM papers
            GROUP BY paper_id
        ) p2 ON p1.paper_id = p2.paper_id AND p1.updated_at = p2.max_updated_at
    """)
    papers = {row[0]: row[1] for row in c.fetchall()}

    # 2. Deduplicate citations
    c.execute("""
        SELECT c1.source_paper_id, c1.target_paper_id, c1.is_active
        FROM citations c1
        JOIN (
            SELECT source_paper_id, target_paper_id, MAX(updated_at) as max_updated_at
            FROM citations
            GROUP BY source_paper_id, target_paper_id
        ) c2 ON c1.source_paper_id = c2.source_paper_id 
            AND c1.target_paper_id = c2.target_paper_id 
            AND c1.updated_at = c2.max_updated_at
    """)
    edges = []
    for src, tgt, is_active in c.fetchall():
        if is_active == 1 and src in papers and tgt in papers:
            edges.append((src, tgt))

    # 3. Get authors for each paper
    c.execute("""
        SELECT pa.paper_id, a.name
        FROM paper_authors pa
        JOIN authors a ON pa.author_id = a.author_id
    """)
    paper_authors = {pid: [] for pid in papers}
    for pid, author in c.fetchall():
        if pid in paper_authors:
            paper_authors[pid].append(author)

    for pid in paper_authors:
        paper_authors[pid].sort()

    conn.close()

    # 4. Calculate PageRank
    nodes = list(papers.keys())
    pr = calculate_pagerank(nodes, edges)

    # 5. Sort and get top 3
    sorted_papers = sorted(pr.items(), key=lambda x: (-x[1], x[0]))
    top_3 = sorted_papers[:3]

    expected_output = []
    for pid, score in top_3:
        expected_output.append({
            "paper_id": pid,
            "title": papers[pid],
            "pagerank": round(score, 4),
            "authors": paper_authors[pid]
        })

    return expected_output

def test_output_file_exists():
    assert os.path.exists(JSON_PATH), f"Output file {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"Path {JSON_PATH} is not a file."

def test_output_content_matches():
    expected_data = get_expected_top_papers()

    with open(JSON_PATH, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert isinstance(actual_data, list), "Output JSON must be a list of objects."
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} papers in output, found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual.get("paper_id") == expected["paper_id"], f"Mismatch in paper_id at index {i}. Expected {expected['paper_id']}, got {actual.get('paper_id')}."
        assert actual.get("title") == expected["title"], f"Mismatch in title at index {i}. Expected {expected['title']}, got {actual.get('title')}."
        assert actual.get("authors") == expected["authors"], f"Mismatch in authors at index {i}. Expected {expected['authors']}, got {actual.get('authors')}."

        # Check pagerank with a small tolerance for rounding differences if any, though it should match exactly to 4 decimals
        actual_pr = actual.get("pagerank")
        expected_pr = expected["pagerank"]
        assert actual_pr is not None, f"Missing pagerank at index {i}."
        assert abs(actual_pr - expected_pr) <= 0.0001, f"Mismatch in pagerank at index {i}. Expected {expected_pr}, got {actual_pr}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
