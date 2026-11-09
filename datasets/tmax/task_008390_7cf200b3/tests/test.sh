#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

from rdflib import Graph, Namespace, RDF

SCRIPT = Path('/home/user/find_cycles.py')
DATA = Path('/home/user/company_data.ttl')
OUTPUT = Path('/home/user/cross_dependencies.csv')
MARKER = Path('/tmp/find_cycles_sparql_marker')


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def install_query_instrumentation(directory):
    code = r'''
import os
from rdflib.graph import Graph

_original_query = Graph.query

def _tracked_query(self, *args, **kwargs):
    result = _original_query(self, *args, **kwargs)
    marker = os.environ.get("FIND_CYCLES_QUERY_MARKER")
    if marker:
        with open(marker, "a", encoding="utf-8") as f:
            f.write("query-succeeded\n")
    return result

Graph.query = _tracked_query
'''
    Path(directory, 'sitecustomize.py').write_text(code, encoding='utf-8')


def run_submission(instrument_dir):
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    if MARKER.exists():
        MARKER.unlink()

    env = os.environ.copy()
    old_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = instrument_dir + (os.pathsep + old_pythonpath if old_pythonpath else '')
    env['FIND_CYCLES_QUERY_MARKER'] = str(MARKER)

    completed = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd='/home/user',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    require(
        completed.returncode == 0,
        'find_cycles.py failed when executed. stdout=%r stderr=%r'
        % (completed.stdout, completed.stderr),
    )
    require(MARKER.is_file() and MARKER.read_text(encoding='utf-8').strip(),
            'find_cycles.py did not successfully execute an rdflib Graph.query SPARQL query.')
    require(OUTPUT.exists(),
            'The output file /home/user/cross_dependencies.csv does not exist. Did your script run and generate it?')
    require(OUTPUT.is_file(),
            'The path /home/user/cross_dependencies.csv is not a valid file.')


def nonempty_stripped_lines():
    with OUTPUT.open('r', encoding='utf-8') as f:
        return [line.strip() for line in f if line.strip()]


def check_original_output():
    lines = nonempty_stripped_lines()
    expected_lines = [
        'http://example.org/Alice,http://example.org/Bob',
        'http://example.org/Charlie,http://example.org/Diana',
    ]
    require(len(lines) == len(expected_lines),
            f'Expected {len(expected_lines)} lines in CSV, but found {len(lines)}.')
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        require(actual == expected,
                f"Line {i + 1} mismatch. Expected '{expected}', got '{actual}'.")


def make_challenge_graph():
    token = uuid.uuid4().hex
    ex = Namespace('http://example.org/')
    inst = Namespace(f'http://challenge.example/{token}/')
    graph = Graph()

    def employee(name, department, project):
        graph.add((inst[name], RDF.type, ex.Employee))
        graph.add((inst[name], ex.worksIn, inst[department]))
        graph.add((inst[name], ex.assignedTo, inst[project]))

    def manages(department, project):
        graph.add((inst[department], RDF.type, ex.Department))
        graph.add((inst[department], ex.managesProject, inst[project]))

    # Two valid cycles.
    employee('WorkerZeta', 'DivisionZeta', 'ProjectBeta')
    employee('WorkerBeta', 'DivisionBeta', 'ProjectZeta')
    manages('DivisionZeta', 'ProjectZeta')
    manages('DivisionBeta', 'ProjectBeta')

    employee('WorkerMu', 'DivisionMu', 'ProjectNu')
    employee('WorkerNu', 'DivisionNu', 'ProjectMu')
    manages('DivisionMu', 'ProjectMu')
    manages('DivisionNu', 'ProjectNu')

    # A mutual dependency in one department, which must be excluded.
    employee('WorkerSameOne', 'DivisionShared', 'ProjectSameTwo')
    employee('WorkerSameTwo', 'DivisionShared', 'ProjectSameOne')
    manages('DivisionShared', 'ProjectSameOne')
    manages('DivisionShared', 'ProjectSameTwo')

    # A one-way dependency, which must be excluded.
    employee('WorkerOneWayA', 'DivisionOneWayA', 'ProjectOneWayB')
    employee('WorkerOneWayB', 'DivisionOneWayB', 'ProjectOneWayA')
    manages('DivisionOneWayA', 'ProjectOneWayA')
    manages('DivisionOneWayB', 'UnrelatedProject')

    return graph, ex


def derive_expected(graph, ex):
    employees = set(graph.subjects(RDF.type, ex.Employee))
    pairs = set()
    for a in employees:
        for b in employees:
            if a == b:
                continue
            valid = False
            for dept_a in graph.objects(a, ex.worksIn):
                for dept_b in graph.objects(b, ex.worksIn):
                    if dept_a == dept_b:
                        continue
                    projects_a = set(graph.objects(a, ex.assignedTo))
                    projects_b = set(graph.objects(b, ex.assignedTo))
                    if (any((dept_a, ex.managesProject, p) in graph for p in projects_b)
                            and any((dept_b, ex.managesProject, p) in graph for p in projects_a)):
                        valid = True
            if valid:
                left, right = sorted((str(a), str(b)))
                pairs.add((left, right))
    return sorted(pairs)


def check_challenge_output(expected):
    raw_lines = OUTPUT.read_text(encoding='utf-8').splitlines()
    require(all(line.strip() for line in raw_lines), 'The CSV contains a blank row.')

    actual = []
    for number, line in enumerate(raw_lines, 1):
        require(line == line.strip(), f'CSV line {number} contains surrounding whitespace.')
        columns = line.split(',')
        require(len(columns) == 2, f'CSV line {number} does not contain exactly two columns.')
        require(columns[0] < columns[1],
                f'CSV line {number} does not put the lexicographically smaller URI first.')
        actual.append(tuple(columns))

    require(actual == sorted(actual), 'The CSV rows are not sorted by the first and second columns.')
    require(actual == expected,
            'The CSV did not contain the cross-dependencies derived from the challenge RDF graph. '
            f'Expected {expected!r}, got {actual!r}.')


def main():
    require(SCRIPT.exists(), 'The script /home/user/find_cycles.py does not exist.')
    require(SCRIPT.is_file(), 'The path /home/user/find_cycles.py is not a valid file.')
    require(DATA.is_file(), 'The input RDF dataset is missing.')

    original_data = DATA.read_bytes()
    saved_original_output = None

    with tempfile.TemporaryDirectory(prefix='query_instrument_') as instrument_dir:
        install_query_instrumentation(instrument_dir)
        try:
            # Preserve the original exact output assertions, but generate that output by
            # actually executing the submitted artifact first.
            run_submission(instrument_dir)
            check_original_output()
            saved_original_output = OUTPUT.read_bytes()

            # Replace the input with an unpredictable graph and derive its answers from
            # the RDF triples so hardcoded original rows cannot pass.
            challenge, ex = make_challenge_graph()
            expected = derive_expected(challenge, ex)
            challenge.serialize(destination=str(DATA), format='turtle')
            run_submission(instrument_dir)
            check_challenge_output(expected)
        finally:
            DATA.write_bytes(original_data)
            if saved_original_output is not None:
                OUTPUT.write_bytes(saved_original_output)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
