#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import re
import sqlite3

DB_PATH = '/home/user/network.db'
SUMMARY_PATH = '/home/user/summary.json'
PLAN_PATH = '/home/user/query_plan.txt'


def derive_expected_result():
    assert os.path.isfile(DB_PATH), f"{DB_PATH} is not a regular file."
    conn = sqlite3.connect(DB_PATH)
    try:
        tables = {
            row[0] for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        assert {'authors', 'papers', 'paper_authors'} <= tables, (
            "The database is missing one or more required tables."
        )

        authors = dict(conn.execute('SELECT id, name FROM authors'))
        ids_by_name = {name: author_id for author_id, name in authors.items()}
        assert 'Alice Smith' in ids_by_name
        assert 'Bob Jones' in ids_by_name

        authors_by_paper = collections.defaultdict(set)
        for paper_id, author_id in conn.execute(
            'SELECT paper_id, author_id FROM paper_authors'
        ):
            authors_by_paper[paper_id].add(author_id)

        graph = {author_id: set() for author_id in authors}
        for paper_authors in authors_by_paper.values():
            for author_id in paper_authors:
                graph.setdefault(author_id, set()).update(paper_authors - {author_id})

        start = ids_by_name['Alice Smith']
        target = ids_by_name['Bob Jones']
        distance = {start: 0}
        path_count = {start: 1}
        predecessor = {}
        queue = collections.deque([start])

        while queue:
            current = queue.popleft()
            for neighbor in sorted(graph.get(current, ())):
                candidate_distance = distance[current] + 1
                if neighbor not in distance:
                    distance[neighbor] = candidate_distance
                    path_count[neighbor] = path_count[current]
                    predecessor[neighbor] = current
                    queue.append(neighbor)
                elif distance[neighbor] == candidate_distance:
                    path_count[neighbor] += path_count[current]

        assert target in distance, 'Alice Smith and Bob Jones are not connected.'
        assert path_count[target] == 1, 'The database does not have one unique shortest path.'

        path_ids = []
        current = target
        while True:
            path_ids.append(current)
            if current == start:
                break
            current = predecessor[current]
        path_ids.reverse()

        placeholders = ','.join('?' for _ in path_ids)
        total_unique_papers = conn.execute(
            f'SELECT COUNT(DISTINCT paper_id) FROM paper_authors '
            f'WHERE author_id IN ({placeholders})',
            path_ids,
        ).fetchone()[0]

        return {
            'shortest_path': [authors[author_id] for author_id in path_ids],
            'total_unique_papers': total_unique_papers,
        }
    finally:
        conn.close()


def test_summary_json_exists_and_correct():
    assert os.path.exists(SUMMARY_PATH), f"File {SUMMARY_PATH} does not exist."
    assert os.path.isfile(SUMMARY_PATH), f"{SUMMARY_PATH} is not a regular file."

    with open(SUMMARY_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)

    assert set(data) == {'shortest_path', 'total_unique_papers'}, (
        'summary.json must contain exactly the required two keys.'
    )

    expected = derive_expected_result()
    expected_path = ['Alice Smith', 'Charlie Brown', 'David Lee', 'Bob Jones']
    assert expected['shortest_path'] == expected_path
    assert expected['total_unique_papers'] == 6

    assert data['shortest_path'] == expected_path, (
        f"Expected shortest_path to be {expected_path}, got {data['shortest_path']}."
    )
    assert data['total_unique_papers'] == 6, (
        f"Expected total_unique_papers to be 6, got {data['total_unique_papers']}."
    )
    assert data == expected, 'summary.json was not derived correctly from network.db.'


def test_query_plan_exists_and_valid():
    assert os.path.exists(PLAN_PATH), f"File {PLAN_PATH} does not exist."
    assert os.path.isfile(PLAN_PATH), f"{PLAN_PATH} is not a regular file."

    with open(PLAN_PATH, 'r', encoding='utf-8') as f:
        content = f.read()
    upper_content = content.upper()

    # Preserve the original assertion, then require complete, structured plan rows.
    assert 'SCAN' in upper_content or 'SEARCH' in upper_content, (
        f"{PLAN_PATH} does not seem to contain a valid SQLite execution plan "
        "(expected to find 'SCAN' or 'SEARCH' in the output)."
    )

    operation_re = re.compile(
        r'\b(SCAN|SEARCH)\s+(?:TABLE\s+)?([A-Za-z_][A-Za-z0-9_$]*)',
        re.IGNORECASE,
    )
    operations = []
    has_query_plan_header = 'QUERY PLAN' in upper_content

    for line in content.splitlines():
        match = operation_re.search(line)
        if not match:
            continue

        prefix = line[:match.start()]
        is_cli_tree_row = has_query_plan_header and '--' in prefix
        is_pipe_row = bool(re.match(r'^\s*\d+\s*\|\s*\d+\s*\|\s*\d+\s*\|', line))
        is_tuple_row = bool(re.match(r'^\s*\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*,', line))
        is_column_row = bool(re.match(r'^\s*\d+\s+\d+\s+\d+\s+', line))

        assert is_cli_tree_row or is_pipe_row or is_tuple_row or is_column_row, (
            f"Unstructured SCAN/SEARCH text is not a SQLite EXPLAIN QUERY PLAN row: {line!r}"
        )
        operations.append((match.group(1).upper(), match.group(2)))

    assert len(operations) >= 2, (
        'query_plan.txt must contain the structured plan operations for joining '
        'authorship records, not just a SCAN or SEARCH keyword.'
    )
    targets = {
        target.lower() for _, target in operations
        if target.upper() not in {'CONSTANT', 'SUBQUERY'}
    }
    assert len(targets) >= 2, (
        'The execution plan does not show access to both sides of a co-authorship connection.'
    )

    # Independently execute EXPLAIN QUERY PLAN against the submitted database to ensure
    # SQLite can produce a real plan for the required co-authorship connection query.
    conn = sqlite3.connect(DB_PATH)
    try:
        actual_plan = list(conn.execute(
            'EXPLAIN QUERY PLAN '
            'SELECT DISTINCT pa1.author_id, pa2.author_id '
            'FROM paper_authors AS pa1 '
            'JOIN paper_authors AS pa2 ON pa1.paper_id = pa2.paper_id '
            'WHERE pa1.author_id <> pa2.author_id'
        ))
    finally:
        conn.close()
    assert len(actual_plan) >= 2
    assert all(len(row) == 4 and isinstance(row[3], str) for row in actual_plan)


if __name__ == '__main__':
    test_summary_json_exists_and_correct()
    test_query_plan_exists_and_valid()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
