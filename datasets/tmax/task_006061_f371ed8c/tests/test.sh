#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import json
import os
import secrets
import subprocess
import pytest

GRAPH_PATH = '/home/user/knowledge_graph.json'
RESULT_PATH = '/home/user/processed_results.json'
EXPECTED_ORIGINAL = {
    'pattern_matches': [
        ['Dr. Alice', 'Dr. Bob'],
        ['Dr. Alice', 'Dr. Diana'],
        ['Dr. Bob', 'Dr. Diana']
    ],
    'shortest_path_length': 4
}


def read_result():
    with open(RESULT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {RESULT_PATH} is not valid JSON.')


def test_processed_results_exists():
    assert os.path.exists(RESULT_PATH), f'The file {RESULT_PATH} is missing.'
    assert os.path.isfile(RESULT_PATH), f'The path {RESULT_PATH} is not a file.'


def test_processed_results_content():
    data = read_result()
    assert 'pattern_matches' in data, "The 'pattern_matches' key is missing from the JSON data."
    assert 'shortest_path_length' in data, "The 'shortest_path_length' key is missing from the JSON data."

    actual_matches = data['pattern_matches']
    assert isinstance(actual_matches, list), "'pattern_matches' should be a list."
    assert actual_matches == EXPECTED_ORIGINAL['pattern_matches'], (
        f"Pattern matches do not match expected output.\n"
        f"Expected: {EXPECTED_ORIGINAL['pattern_matches']}\nActual: {actual_matches}"
    )

    actual_path_length = data['shortest_path_length']
    assert isinstance(actual_path_length, int), "'shortest_path_length' should be an integer."
    assert actual_path_length == EXPECTED_ORIGINAL['shortest_path_length'], (
        f"Shortest path length does not match expected output.\n"
        f"Expected: {EXPECTED_ORIGINAL['shortest_path_length']}\nActual: {actual_path_length}"
    )


def oracle(graph):
    nodes = {node['id']: node for node in graph['nodes']}
    paper_authors = collections.defaultdict(set)
    paper_concepts = collections.defaultdict(set)
    adjacency = collections.defaultdict(set)

    for edge in graph['edges']:
        source, target = edge['source'], edge['target']
        adjacency[source].add(target)
        adjacency[target].add(source)
        if edge['relation'] == 'authored':
            paper_authors[target].add(source)
        elif edge['relation'] == 'covers':
            paper_concepts[source].add(target)

    concept_papers = collections.defaultdict(set)
    for paper, concepts in paper_concepts.items():
        for concept in concepts:
            concept_papers[concept].add(paper)

    pairs = set()
    for papers in concept_papers.values():
        papers = sorted(papers)
        for i, first in enumerate(papers):
            for second in papers[i + 1:]:
                for author1 in paper_authors[first]:
                    for author2 in paper_authors[second]:
                        if author1 != author2:
                            pairs.add(tuple(sorted((nodes[author1]['name'], nodes[author2]['name']))))

    alice = next(n['id'] for n in graph['nodes'] if n.get('type') == 'author' and n.get('name') == 'Dr. Alice')
    bob = next(n['id'] for n in graph['nodes'] if n.get('type') == 'author' and n.get('name') == 'Dr. Bob')
    queue = collections.deque([(alice, 0)])
    seen = {alice}
    distance = None
    while queue:
        node, depth = queue.popleft()
        if node == bob:
            distance = depth
            break
        for neighbor in adjacency[node]:
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append((neighbor, depth + 1))
    assert distance is not None
    return {'pattern_matches': [list(pair) for pair in sorted(pairs)], 'shortest_path_length': distance}


def randomized_graph():
    token = secrets.token_hex(6)
    authors = [
        {'id': f'a_{token}_{i}', 'type': 'author',
         'name': name}
        for i, name in enumerate([
            'Dr. Alice', 'Dr. Bob', f'Prof. {token} A', f'Prof. {token} B',
            f'Prof. {token} C', f'Prof. {token} D', f'Prof. {token} E'
        ])
    ]
    papers = [{'id': f'p_{token}_{i}', 'type': 'paper'} for i in range(11)]
    concepts = [
        {'id': f'c_{token}_{i}', 'type': 'concept', 'name': f'Concept {token} {i}'}
        for i in range(5)
    ]
    edges = []

    # Guaranteed Alice-to-Bob connection through different papers and one concept.
    edges.extend([
        {'source': authors[0]['id'], 'target': papers[0]['id'], 'relation': 'authored'},
        {'source': papers[0]['id'], 'target': concepts[0]['id'], 'relation': 'covers'},
        {'source': authors[1]['id'], 'target': papers[1]['id'], 'relation': 'authored'},
        {'source': papers[1]['id'], 'target': concepts[0]['id'], 'relation': 'covers'}
    ])

    # A same-paper coauthor case, which must not alone create a pattern match.
    edges.extend([
        {'source': authors[2]['id'], 'target': papers[2]['id'], 'relation': 'authored'},
        {'source': authors[3]['id'], 'target': papers[2]['id'], 'relation': 'authored'},
        {'source': papers[2]['id'], 'target': concepts[1]['id'], 'relation': 'covers'}
    ])

    rng = secrets.SystemRandom()
    for paper in papers[3:]:
        for author in rng.sample(authors, rng.randint(1, 3)):
            edges.append({'source': author['id'], 'target': paper['id'], 'relation': 'authored'})
        for concept in rng.sample(concepts, rng.randint(1, 2)):
            edges.append({'source': paper['id'], 'target': concept['id'], 'relation': 'covers'})

    rng.shuffle(edges)
    nodes = authors + papers + concepts
    rng.shuffle(nodes)
    return {'nodes': nodes, 'edges': edges}


def candidate_scripts():
    candidates = []
    for path in glob.glob('/home/user/**/*.py', recursive=True):
        rel = os.path.relpath(path, '/home/user')
        if any(part.startswith('.') or part == '__pycache__' for part in rel.split(os.sep)):
            continue
        if os.path.isfile(path):
            candidates.append(path)
    preferred = '/home/user/process_graph.py'
    return sorted(set(candidates), key=lambda p: (p != preferred, p))


def run_candidate(script, graph, expected):
    with open(GRAPH_PATH, 'w') as f:
        json.dump(graph, f)
    try:
        os.remove(RESULT_PATH)
    except FileNotFoundError:
        pass

    completed = subprocess.run(
        ['python3', script], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    if completed.returncode != 0:
        return False, f'exited {completed.returncode}: {completed.stderr[-500:]}'
    if not os.path.isfile(RESULT_PATH):
        return False, 'did not create processed_results.json'
    try:
        with open(RESULT_PATH) as f:
            actual = json.load(f)
    except Exception as exc:
        return False, f'created invalid JSON: {exc}'
    if actual != expected:
        return False, f'wrong output: expected {expected!r}, got {actual!r}'
    return True, ''


def test_processing_script_executes_and_generalizes():
    scripts = candidate_scripts()
    assert scripts, 'No Python processing script was found under /home/user.'

    with open(GRAPH_PATH, 'rb') as f:
        original_bytes = f.read()
    original_graph = json.loads(original_bytes)
    dynamic_graphs = [randomized_graph(), randomized_graph()]
    cases = [(graph, oracle(graph)) for graph in dynamic_graphs]
    cases.append((original_graph, EXPECTED_ORIGINAL))

    failures = []
    successful = None
    try:
        for script in scripts:
            passed = True
            for graph, expected in cases:
                ok, reason = run_candidate(script, graph, expected)
                if not ok:
                    failures.append(f'{script}: {reason}')
                    passed = False
                    break
            if passed:
                successful = script
                break
    finally:
        with open(GRAPH_PATH, 'wb') as f:
            f.write(original_bytes)

    assert successful is not None, 'No submitted Python script correctly processed varied graphs. ' + ' | '.join(failures)
    # Leave the required output corresponding to the original supplied dataset.
    ok, reason = run_candidate(successful, original_graph, EXPECTED_ORIGINAL)
    assert ok, reason
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
