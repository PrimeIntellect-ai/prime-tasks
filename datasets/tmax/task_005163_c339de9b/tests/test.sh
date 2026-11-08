#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import secrets
import subprocess
import tempfile
from collections import defaultdict


def expected_projection(input_path):
    paper_to_authors = defaultdict(list)
    with open(input_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            if len(parts) == 2:
                a, p = parts
                paper_to_authors[p].append(a)

    coauthors = defaultdict(int)
    for auths in paper_to_authors.values():
        auths = list(set(auths))
        for i in range(len(auths)):
            for j in range(i + 1, len(auths)):
                a1, a2 = auths[i], auths[j]
                if a1 > a2:
                    a1, a2 = a2, a1
                coauthors[(a1, a2)] += 1

    return "\n".join(
        f"{a1},{a2},{coauthors[(a1, a2)]}"
        for a1, a2 in sorted(coauthors)
    )


def test_c_source_exists():
    """Test that the C source code was created."""
    assert os.path.isfile('/home/user/project_graph.c'), "The C source file /home/user/project_graph.c is missing."


def test_c_executable_exists():
    """Test that the C program was compiled."""
    assert os.path.isfile('/home/user/project_graph'), "The compiled executable /home/user/project_graph is missing."
    assert os.access('/home/user/project_graph', os.X_OK), "The file /home/user/project_graph is not executable."


def test_coauthors_csv_correctness():
    """Test that the output coauthors.csv matches the expected graph projection."""
    input_path = '/home/user/wrote.csv'
    output_path = '/home/user/coauthors.csv'

    assert os.path.isfile(input_path), f"Input file {input_path} is missing."
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    expected_output = expected_projection(input_path)

    with open(output_path, 'r') as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, "The contents of /home/user/coauthors.csv do not match the expected graph projection."


def run_and_check(input_text):
    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, 'input.csv')
        output_path = os.path.join(td, 'output.csv')
        with open(input_path, 'w') as f:
            f.write(input_text)

        result = subprocess.run(
            ['/home/user/project_graph', input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Program failed: {result.stderr}"
        assert os.path.isfile(output_path), "Program did not create its requested output file."
        with open(output_path, 'r') as f:
            actual = f.read().strip()
        assert actual == expected_projection(input_path), "Program produced an incorrect projection on a verifier-supplied input."


def test_source_compiles_and_program_executes_on_unseen_inputs():
    """Compile the submitted C source and exercise the resulting tool."""
    result = subprocess.run(
        ['gcc', '-O3', '/home/user/project_graph.c', '-o', '/home/user/project_graph'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"C source did not compile successfully: {result.stderr}"
    assert os.path.isfile('/home/user/project_graph')
    assert os.access('/home/user/project_graph', os.X_OK)

    run_and_check(
        'z9,P1\n'
        'A10,P1\n'
        'a1,P1\n'
        'A10,P2\n'
        'B2,P2\n'
        'z9,P2\n'
        'B2,P3\n'
        'A10,P3\n'
        'solo,P4\n'
    )

    rng = random.SystemRandom()
    prefixes = ['A', 'Z', 'a', 'z', '0', '9']
    authors = [f"{prefixes[i % len(prefixes)]}{i:03d}{secrets.token_hex(2)}" for i in range(80)]
    papers = [f"Q{i:04d}{secrets.token_hex(2)}" for i in range(180)]
    edges = []
    for paper in papers:
        for author in rng.sample(authors, rng.randint(1, 6)):
            edges.append((author, paper))
    rng.shuffle(edges)
    run_and_check(''.join(f'{author},{paper}\n' for author, paper in edges))

    with tempfile.TemporaryDirectory() as td:
        output_path = os.path.join(td, 'from_original.csv')
        result = subprocess.run(
            ['/home/user/project_graph', '/home/user/wrote.csv', output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Program failed on /home/user/wrote.csv: {result.stderr}"
        assert os.path.isfile(output_path)
        with open(output_path, 'r') as f:
            actual = f.read().strip()
        assert actual == expected_projection('/home/user/wrote.csv')
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
