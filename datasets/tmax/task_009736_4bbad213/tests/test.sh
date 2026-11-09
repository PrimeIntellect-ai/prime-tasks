#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
from pathlib import Path

SCRIPT = Path('/home/user/analyze_network.py')
DATASET = Path('/home/user/citation_graph.nt')
OUTPUT = Path('/home/user/path_analysis.json')
TELEMETRY = Path('/tmp/network_analysis_telemetry.jsonl')

EXPECTED_NT = '''<http://example.org/paper/P1> <http://example.org/ontology/cites> <http://example.org/paper/P2> .
<http://example.org/paper/P1> <http://example.org/ontology/cites> <http://example.org/paper/P3> .
<http://example.org/paper/P2> <http://example.org/ontology/cites> <http://example.org/paper/P4> .
<http://example.org/paper/P3> <http://example.org/ontology/cites> <http://example.org/paper/P6> .
<http://example.org/paper/P4> <http://example.org/ontology/cites> <http://example.org/paper/P5> .
<http://example.org/paper/P6> <http://example.org/ontology/cites> <http://example.org/paper/P8> .
<http://example.org/paper/P5> <http://example.org/ontology/cites> <http://example.org/paper/P8> .
<http://example.org/paper/P8> <http://example.org/ontology/cites> <http://example.org/paper/P9> .

<http://example.org/paper/P1> <http://example.org/ontology/authoredBy> <http://example.org/author/A1> .
<http://example.org/paper/P2> <http://example.org/ontology/authoredBy> <http://example.org/author/A1> .

<http://example.org/paper/P3> <http://example.org/ontology/authoredBy> <http://example.org/author/A2> .

<http://example.org/paper/P4> <http://example.org/ontology/authoredBy> <http://example.org/author/A3> .
<http://example.org/paper/P5> <http://example.org/ontology/authoredBy> <http://example.org/author/A3> .
<http://example.org/paper/P6> <http://example.org/ontology/authoredBy> <http://example.org/author/A3> .
<http://example.org/paper/P7> <http://example.org/ontology/authoredBy> <http://example.org/author/A3> .

<http://example.org/paper/P8> <http://example.org/ontology/authoredBy> <http://example.org/author/A4> .
<http://example.org/paper/P9> <http://example.org/ontology/authoredBy> <http://example.org/author/A4> .
<http://example.org/paper/P10> <http://example.org/ontology/authoredBy> <http://example.org/author/A4> .
'''

EXPECTED_ORIGINAL = [
    {'paper': 'http://example.org/paper/P1', 'author_total_papers': 2},
    {'paper': 'http://example.org/paper/P3', 'author_total_papers': 1},
    {'paper': 'http://example.org/paper/P6', 'author_total_papers': 4},
    {'paper': 'http://example.org/paper/P8', 'author_total_papers': 3},
]

DYNAMIC_NT = '''<http://example.org/paper/P1> <http://example.org/ontology/cites> <http://example.org/paper/P4> .
<http://example.org/paper/P4> <http://example.org/ontology/cites> <http://example.org/paper/P8> .
<http://example.org/paper/P1> <http://example.org/ontology/cites> <http://example.org/paper/P3> .
<http://example.org/paper/P3> <http://example.org/ontology/cites> <http://example.org/paper/P6> .
<http://example.org/paper/P6> <http://example.org/ontology/cites> <http://example.org/paper/P8> .
<http://example.org/paper/P1> <http://example.org/ontology/authoredBy> <http://example.org/author/Z1> .
<http://example.org/paper/P2> <http://example.org/ontology/authoredBy> <http://example.org/author/Z1> .
<http://example.org/paper/P4> <http://example.org/ontology/authoredBy> <http://example.org/author/Z2> .
<http://example.org/paper/P5> <http://example.org/ontology/authoredBy> <http://example.org/author/Z2> .
<http://example.org/paper/P7> <http://example.org/ontology/authoredBy> <http://example.org/author/Z2> .
<http://example.org/paper/P8> <http://example.org/ontology/authoredBy> <http://example.org/author/Z3> .
'''

EXPECTED_DYNAMIC = [
    {'paper': 'http://example.org/paper/P1', 'author_total_papers': 2},
    {'paper': 'http://example.org/paper/P4', 'author_total_papers': 3},
    {'paper': 'http://example.org/paper/P8', 'author_total_papers': 1},
]


def install_instrumentation():
    instrument_dir = Path('/tmp/network_analysis_instrumentation')
    instrument_dir.mkdir(exist_ok=True)
    (instrument_dir / 'sitecustomize.py').write_text(r'''import json
import os
import rdflib
import networkx

_LOG = os.environ.get('NETWORK_ANALYSIS_TELEMETRY')

def _record(event):
    if _LOG:
        with open(_LOG, 'a') as f:
            f.write(json.dumps({'event': event}) + '\n')

_original_parse = rdflib.Graph.parse
_original_query = rdflib.Graph.query
_original_shortest_path = networkx.shortest_path

def _parse(self, *args, **kwargs):
    _record('rdflib.parse')
    return _original_parse(self, *args, **kwargs)

def _query(self, *args, **kwargs):
    _record('rdflib.query')
    return _original_query(self, *args, **kwargs)

def _shortest_path(*args, **kwargs):
    _record('networkx.shortest_path')
    return _original_shortest_path(*args, **kwargs)

rdflib.Graph.parse = _parse
rdflib.Graph.query = _query
networkx.shortest_path = _shortest_path
''')
    return instrument_dir


def run_script(expected):
    if OUTPUT.exists():
        OUTPUT.unlink()
    if TELEMETRY.exists():
        TELEMETRY.unlink()

    instrument_dir = install_instrumentation()
    env = os.environ.copy()
    env['PYTHONPATH'] = str(instrument_dir) + os.pathsep + env.get('PYTHONPATH', '')
    env['NETWORK_ANALYSIS_TELEMETRY'] = str(TELEMETRY)

    result = subprocess.run(
        ['python3', str(SCRIPT)], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, f'Script failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    assert OUTPUT.is_file(), f'The script did not create {OUTPUT}.'
    try:
        data = json.loads(OUTPUT.read_text())
    except json.JSONDecodeError as exc:
        assert False, f'The file {OUTPUT} contains invalid JSON: {exc}'
    assert data == expected, f'Content of {OUTPUT} is incorrect. Expected {expected}, got {data}'

    assert TELEMETRY.is_file(), 'No library-use telemetry was produced.'
    events = [json.loads(line)['event'] for line in TELEMETRY.read_text().splitlines() if line.strip()]
    assert 'rdflib.parse' in events, 'The script did not parse the RDF data using rdflib.'
    assert 'networkx.shortest_path' in events, 'The script did not use NetworkX shortest-path traversal.'
    assert events.count('rdflib.query') >= len(expected), 'The script did not perform a SPARQL query for every paper in the path.'


def test_original_file_unmodified():
    nt_file_path = '/home/user/citation_graph.nt'
    assert os.path.isfile(nt_file_path), f'The original dataset file {nt_file_path} is missing.'
    content = Path(nt_file_path).read_text()

    expected_lines = [
        '<http://example.org/paper/P1> <http://example.org/ontology/cites> <http://example.org/paper/P2> .',
        '<http://example.org/paper/P1> <http://example.org/ontology/cites> <http://example.org/paper/P3> .',
        '<http://example.org/paper/P8> <http://example.org/ontology/cites> <http://example.org/paper/P9> .',
        '<http://example.org/paper/P1> <http://example.org/ontology/authoredBy> <http://example.org/author/A1> .',
        '<http://example.org/paper/P10> <http://example.org/ontology/authoredBy> <http://example.org/author/A4> .',
    ]
    for line in expected_lines:
        assert line in content, f"Original file {nt_file_path} was modified. Missing line: '{line}'"
    assert content == EXPECTED_NT, f'The original dataset file {nt_file_path} was modified.'


def test_script_executes_and_produces_original_result():
    assert SCRIPT.is_file(), f'The required script {SCRIPT} does not exist.'
    run_script(EXPECTED_ORIGINAL)


def test_path_analysis_json():
    json_path = '/home/user/path_analysis.json'
    assert os.path.isfile(json_path), f'The file {json_path} does not exist.'
    try:
        data = json.loads(Path(json_path).read_text())
    except json.JSONDecodeError:
        assert False, f'The file {json_path} contains invalid JSON.'
    assert data == EXPECTED_ORIGINAL, f'Content of {json_path} is incorrect. Expected {EXPECTED_ORIGINAL}, got {data}'


def test_script_generalizes_to_changed_graph():
    original_dataset = DATASET.read_bytes()
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None
    try:
        DATASET.write_text(DYNAMIC_NT)
        run_script(EXPECTED_DYNAMIC)
    finally:
        DATASET.write_bytes(original_dataset)
        if original_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(original_output)
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
