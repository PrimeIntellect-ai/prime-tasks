#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest

PROCESS_SCRIPT = '/home/user/process_graph.py'
CYPHER_SCRIPT = '/home/user/graph_init.cypher'
AUDIO_FILE = '/app/interview_tape.wav'

EDGE_PATTERN = r'\{name:\s*["\']([^"\']+)["\']\}\)\-\[\:([A-Z_]+)\]\-\>\([a-zA-Z]+\:[a-zA-Z]+\s*\{(?:name|title):\s*["\']([^"\']+)["\']\}\)'

GROUND_TRUTH = {
    ('Alice', 'MANAGES', 'Bob'),
    ('Bob', 'WORKS_ON', 'Project Apollo'),
    ('Charlie', 'MANAGES', 'David'),
    ('David', 'WORKS_ON', 'Project Apollo'),
    ('Alice', 'MANAGES', 'Charlie'),
    ('Eve', 'WORKS_ON', 'Project Zeus'),
    ('Alice', 'MANAGES', 'Eve')
}


def run_process_graph():
    if os.path.exists(CYPHER_SCRIPT):
        os.remove(CYPHER_SCRIPT)
    result = subprocess.run(
        ['python3', PROCESS_SCRIPT],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=300,
    )
    assert result.returncode == 0, (
        f'process_graph.py failed with exit code {result.returncode}. '
        f'Stdout: {result.stdout}\nStderr: {result.stderr}'
    )
    assert os.path.isfile(CYPHER_SCRIPT), \
        'process_graph.py did not generate /home/user/graph_init.cypher.'


def read_cypher():
    with open(CYPHER_SCRIPT, 'r') as f:
        return f.read()


def extract_edges(cypher_text):
    return {
        (src.strip(), rel.strip(), tgt.strip())
        for src, rel, tgt in re.findall(EDGE_PATTERN, cypher_text)
    }


def assert_indexes(cypher_text):
    assert re.search(r'(?i)CREATE\s+(?:INDEX|INDEX\s+IF\s+NOT\s+EXISTS)\s+(?:FOR\s+\([a-zA-Z0-9_]+\s*:\s*Employee\)\s+ON\s+\([a-zA-Z0-9_]+\.name\)|ON\s+:Employee\(name\))', cypher_text), \
        "Missing index creation for Employee on 'name' property."
    assert re.search(r'(?i)CREATE\s+(?:INDEX|INDEX\s+IF\s+NOT\s+EXISTS)\s+(?:FOR\s+\([a-zA-Z0-9_]+\s*:\s*Project\)\s+ON\s+\([a-zA-Z0-9_]+\.title\)|ON\s+:Project\(title\))', cypher_text), \
        "Missing index creation for Project on 'title' property."


@pytest.fixture(scope='session', autouse=True)
def execute_required_workflow():
    assert os.path.isfile(PROCESS_SCRIPT), \
        'The file /home/user/process_graph.py does not exist or is not a regular file.'
    run_process_graph()


def test_cypher_script_exists():
    assert os.path.exists(CYPHER_SCRIPT), \
        'The file /home/user/graph_init.cypher does not exist.'


def test_cypher_indexes():
    assert_indexes(read_cypher())


def test_extracted_edges_f1_score():
    try:
        cypher_text = read_cypher()
    except FileNotFoundError:
        pytest.fail('The file /home/user/graph_init.cypher does not exist.')

    extracted_edges = extract_edges(cypher_text)
    true_positives = len(extracted_edges.intersection(GROUND_TRUTH))
    false_positives = len(extracted_edges - GROUND_TRUTH)
    false_negatives = len(GROUND_TRUTH - extracted_edges)

    if true_positives == 0:
        f1 = 0.0
    else:
        precision = true_positives / (true_positives + false_positives)
        recall = true_positives / (true_positives + false_negatives)
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.85, \
        f'F1 score of extracted edges is {f1:.2f}, which is below the threshold of 0.85. Extracted: {extracted_edges}'
    assert extracted_edges == GROUND_TRUTH, \
        f'Not all relationships dictated in the audio were generated exactly. Extracted: {extracted_edges}'


def test_z_processes_changed_audio_instead_of_hardcoding_output():
    original_audio = open(AUDIO_FILE, 'rb').read()
    rng = secrets.SystemRandom()
    people = rng.sample(['Frank', 'Grace', 'Helen', 'Jack', 'Kevin', 'Laura'], 4)
    projects = rng.sample(['Orion', 'Phoenix', 'Atlas'], 2)

    expected = {
        (people[0], 'MANAGES', people[1]),
        (people[1], 'WORKS_ON', 'Project ' + projects[0]),
        (people[2], 'MANAGES', people[3]),
        (people[0], 'WORKS_ON', 'Project ' + projects[1]),
    }
    spoken_text = (
        f'{people[0]} manages {people[1]}. '
        f'{people[1]} works on Project {projects[0]}. '
        f'{people[2]} manages {people[3]}. '
        f'{people[0]} works on Project {projects[1]}.'
    )

    dynamic_result = None
    dynamic_cypher = None
    restore_result = None
    try:
        subprocess.run(['espeak', '-w', AUDIO_FILE, spoken_text], check=True, timeout=30)
        if os.path.exists(CYPHER_SCRIPT):
            os.remove(CYPHER_SCRIPT)
        dynamic_result = subprocess.run(
            ['python3', PROCESS_SCRIPT], cwd='/home/user', text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300
        )
        if os.path.isfile(CYPHER_SCRIPT):
            dynamic_cypher = read_cypher()
    finally:
        with open(AUDIO_FILE, 'wb') as f:
            f.write(original_audio)
        if os.path.exists(CYPHER_SCRIPT):
            os.remove(CYPHER_SCRIPT)
        restore_result = subprocess.run(
            ['python3', PROCESS_SCRIPT], cwd='/home/user', text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300
        )

    assert dynamic_result is not None and dynamic_result.returncode == 0, (
        'process_graph.py failed on a changed interview audio. '
        f'Stdout: {getattr(dynamic_result, "stdout", "")}\n'
        f'Stderr: {getattr(dynamic_result, "stderr", "")}'
    )
    assert dynamic_cypher is not None, \
        'process_graph.py did not generate graph_init.cypher from changed audio.'
    assert_indexes(dynamic_cypher)
    assert extract_edges(dynamic_cypher) == expected, (
        'process_graph.py did not transcribe and parse the changed audio. '
        f'Expected: {expected}; extracted: {extract_edges(dynamic_cypher)}'
    )
    assert restore_result.returncode == 0 and os.path.isfile(CYPHER_SCRIPT), \
        'process_graph.py failed to regenerate graph_init.cypher after restoring the original audio.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
