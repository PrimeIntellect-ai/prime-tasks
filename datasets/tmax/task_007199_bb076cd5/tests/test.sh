#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import pytest
import secrets
import shutil
import tempfile
from collections import defaultdict

SCRIPT_PATH = "/home/user/analyze_collaboration.sh"
AUTHORS_PATH = "/home/user/authors.csv"
COAUTHORS_PATH = "/home/user/coauthors.csv"

CANONICAL_AUTHORS = """1,Alice,Physics,2010
2,Bob,Physics,2012
3,Charlie,Math,2015
4,Diana,ComputerScience,2018
5,Eve,Math,2020
6,Frank,Biology,2011
7,Grace,ComputerScience,2019
8,Heidi,Physics,2021
9,Ivan,Chemistry,2017
10,Judy,Biology,2013
"""

CANONICAL_COAUTHORS = """1,2,5
2,3,2
3,4,1
4,5,3
2,6,1
6,7,4
1,8,2
7,9,1
6,10,3
10,3,1
"""


def replace_regular_file(path, content):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    fd, temporary = tempfile.mkstemp(prefix=".verifier-data-", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)


def install_dataset(authors_text, coauthors_text):
    replace_regular_file(AUTHORS_PATH, authors_text)
    replace_regular_file(COAUTHORS_PATH, coauthors_text)


def compute_expected_output(target_id, authors_text, coauthors_text):
    dept_map = {}
    for line in authors_text.splitlines():
        parts = line.strip().split(',')
        if len(parts) >= 3:
            dept_map[parts[0]] = parts[2]

    adj = defaultdict(set)
    for line in coauthors_text.splitlines():
        parts = line.strip().split(',')
        if len(parts) >= 2:
            u, v = parts[0], parts[1]
            adj[u].add(v)
            adj[v].add(u)

    target = str(target_id)
    first_degree = adj[target]
    second_degree = set()
    for neighbor in first_degree:
        second_degree.update(adj[neighbor])

    strict_second = second_degree - first_degree - {target}

    counts = defaultdict(int)
    for node in strict_second:
        if node in dept_map:
            counts[dept_map[node]] += 1

    return "\n".join(f"{dept}:{counts[dept]}" for dept in sorted(counts))


def invoke_and_check(author_id, authors_text, coauthors_text):
    # Reinstall trusted data immediately before every invocation, so changes made
    # before verification or by an earlier invocation cannot affect expectations.
    install_dataset(authors_text, coauthors_text)
    expected = compute_expected_output(author_id, authors_text, coauthors_text)

    result = subprocess.run(
        [SCRIPT_PATH, str(author_id)],
        capture_output=True,
        text=True,
        timeout=10
    )

    assert result.returncode == 0, (
        f"Script failed with non-zero exit code for AuthorID {author_id}. "
        f"Error: {result.stderr}"
    )
    assert result.stdout.strip() == expected.strip(), (
        f"Output mismatch for AuthorID {author_id}.\n"
        f"Expected:\n{expected.strip()}\n\nGot:\n{result.stdout.strip()}"
    )


def make_generated_dataset():
    rng = secrets.SystemRandom()
    ids = rng.sample(range(1000, 9000), 18)
    departments = [
        "Anthropology", "Astrophysics", "DataScience", "Ecology",
        "Linguistics", "Neuroscience", "Robotics"
    ]

    author_rows = []
    for index, author_id in enumerate(ids):
        department = rng.choice(departments)
        author_rows.append(
            f"{author_id},Researcher{index},{department},{1990 + rng.randrange(36)}"
        )
    rng.shuffle(author_rows)

    # A path guarantees meaningful two-hop relationships. Additional randomized
    # long-range edges, orientations, counts, and row order prevent fixed outputs.
    edges = set()
    for index in range(len(ids) - 1):
        edges.add((index, index + 1))
    for left in range(len(ids)):
        for right in range(left + 3, len(ids)):
            if rng.random() < 0.14:
                edges.add((left, right))

    edge_rows = []
    for left, right in edges:
        u, v = ids[left], ids[right]
        if rng.randrange(2):
            u, v = v, u
        edge_rows.append(f"{u},{v},{rng.randrange(1, 20)}")
    rng.shuffle(edge_rows)

    return "\n".join(author_rows) + "\n", "\n".join(edge_rows) + "\n", ids


GENERATED_AUTHORS, GENERATED_COAUTHORS, GENERATED_IDS = make_generated_dataset()


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable"


@pytest.mark.parametrize("author_id", [3, 1, 6, 2])
def test_script_logic(author_id):
    assert os.path.isfile(SCRIPT_PATH), "Script missing"
    invoke_and_check(author_id, CANONICAL_AUTHORS, CANONICAL_COAUTHORS)


def test_general_traversal_on_generated_graph():
    assert os.path.isfile(SCRIPT_PATH), "Script missing"
    for author_id in GENERATED_IDS:
        invoke_and_check(author_id, GENERATED_AUTHORS, GENERATED_COAUTHORS)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
