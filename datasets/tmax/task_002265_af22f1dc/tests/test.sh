#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST' > /tmp/test_final_state.py
import glob
import json
import os
import subprocess
import sys
import tempfile

HOME = '/home/user'
DATASET = os.path.join(HOME, 'dataset.nt')
COLLABS = os.path.join(HOME, 'alice_collaborators.txt')
PATHFILE = os.path.join(HOME, 'shortest_path.txt')
PLANFILE = os.path.join(HOME, 'query_plan.txt')


def read_text(path):
    assert os.path.exists(path), f'File {path} does not exist.'
    with open(path, 'r', encoding='utf-8') as f:
        return f.read().strip()


def test_original_outputs_and_executable_script():
    # Preserve the original verifier's assertions.
    content = read_text(COLLABS)
    assert content, f'File {COLLABS} is empty.'
    collabs = [x.strip() for x in content.split(',')]
    assert set(collabs) == {'Dr. Bob', 'Dr. Charlie'}, (
        f"Expected collaborators 'Dr. Bob' and 'Dr. Charlie', but got {collabs}"
    )

    path = read_text(PATHFILE)
    valid_paths = [
        'Dr. Alice,Dr. Bob,Dr. Delta,Dr. Zeta',
        'Dr. Alice,Dr. Charlie,Dr. Echo,Dr. Zeta',
    ]
    assert path in valid_paths, (
        f"Shortest path '{path}' is not one of the valid shortest paths: {valid_paths}"
    )

    plan = read_text(PLANFILE)
    assert len(plan) > 10, f'File {PLANFILE} content is too short to be a valid query plan.'
    assert 'BGP' in plan or 'Project' in plan, (
        f'File {PLANFILE} does not seem to contain a typical rdflib SPARQL algebra representation '
        "(missing 'BGP' or 'Project')."
    )

    candidates = sorted(
        p for p in glob.glob('/home/user/**/*.py', recursive=True)
        if os.path.isfile(p) and not os.path.islink(p)
    )
    assert candidates, 'No Python script was created under /home/user.'

    hidden_dataset = '''<http://example.org/h/a> <http://xmlns.com/foaf/0.1/name> "Dr. Alice" .
<http://example.org/h/n> <http://xmlns.com/foaf/0.1/name> "Dr. Nova" .
<http://example.org/h/q> <http://xmlns.com/foaf/0.1/name> "Dr. Quill" .
<http://example.org/h/t> <http://xmlns.com/foaf/0.1/name> "Dr. Tern" .
<http://example.org/h/r> <http://xmlns.com/foaf/0.1/name> "Dr. Rune" .
<http://example.org/h/s> <http://xmlns.com/foaf/0.1/name> "Dr. Sable" .
<http://example.org/h/z> <http://xmlns.com/foaf/0.1/name> "Dr. Zeta" .
<http://example.org/h/x> <http://xmlns.com/foaf/0.1/name> "Dr. Xeno" .
<http://example.org/h/n> <http://example.org/ontology/collaboratesWith> <http://example.org/h/a> .
<http://example.org/h/a> <http://example.org/ontology/collaboratesWith> <http://example.org/h/q> .
<http://example.org/h/q> <http://example.org/ontology/collaboratesWith> <http://example.org/h/t> .
<http://example.org/h/t> <http://example.org/ontology/collaboratesWith> <http://example.org/h/z> .
<http://example.org/h/n> <http://example.org/ontology/collaboratesWith> <http://example.org/h/r> .
<http://example.org/h/r> <http://example.org/ontology/collaboratesWith> <http://example.org/h/s> .
<http://example.org/h/s> <http://example.org/ontology/collaboratesWith> <http://example.org/h/z> .
<http://example.org/h/x> <http://example.org/ontology/collaboratesWith> <http://example.org/h/r> .
'''

    original_dataset = open(DATASET, 'rb').read()
    saved_outputs = {}
    for output in (COLLABS, PATHFILE, PLANFILE):
        saved_outputs[output] = open(output, 'rb').read() if os.path.exists(output) else None

    failures = []
    try:
        with open(DATASET, 'w', encoding='utf-8') as f:
            f.write(hidden_dataset)

        for candidate in candidates:
            for output in (COLLABS, PATHFILE, PLANFILE):
                try:
                    os.remove(output)
                except FileNotFoundError:
                    pass

            fd, report_path = tempfile.mkstemp(prefix='agent-report-', suffix='.json')
            os.close(fd)
            os.remove(report_path)
            try:
                proc = subprocess.run(
                    [sys.executable, '/tmp/run_agent_instrumented.py', candidate, report_path],
                    cwd=HOME,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=45,
                )
                if proc.returncode != 0 or not os.path.exists(report_path):
                    failures.append(f'{candidate}: execution failed: {proc.stderr[-500:]}')
                    continue

                with open(report_path, 'r', encoding='utf-8') as f:
                    report = json.load(f)
                if report.get('error'):
                    failures.append(f"{candidate}: {report['error']}")
                    continue

                dynamic_collabs = {x.strip() for x in read_text(COLLABS).split(',') if x.strip()}
                assert dynamic_collabs == {'Dr. Nova', 'Dr. Quill'}
                assert read_text(PATHFILE) == 'Dr. Alice,Dr. Quill,Dr. Tern,Dr. Zeta'

                dynamic_plan = read_text(PLANFILE)
                assert len(dynamic_plan) > 10
                assert 'BGP' in dynamic_plan or 'Project' in dynamic_plan
                assert dynamic_plan in report.get('query_algebras', []), (
                    'query_plan.txt was not the algebra of the parameterized query that was executed'
                )

                assert report.get('parsed_target_dataset'), (
                    'The script did not parse /home/user/dataset.nt with rdflib'
                )
                assert report.get('parameterized_alice_query'), (
                    'No rdflib query was executed with an initBindings value of Dr. Alice'
                )
                assert report.get('networkx_edges', 0) >= 8, (
                    'The RDF collaborations were not loaded into a networkx graph'
                )
                assert report.get('networkx_shortest_path'), (
                    'No networkx shortest-path routine was used for Dr. Alice to Dr. Zeta'
                )
                return
            except (AssertionError, OSError, ValueError, json.JSONDecodeError) as exc:
                failures.append(f'{candidate}: {exc}')
            finally:
                try:
                    os.remove(report_path)
                except FileNotFoundError:
                    pass

        raise AssertionError('No submitted Python script passed execution tests. ' + ' | '.join(failures))
    finally:
        with open(DATASET, 'wb') as f:
            f.write(original_dataset)
        for output, data in saved_outputs.items():
            if data is None:
                try:
                    os.remove(output)
                except FileNotFoundError:
                    pass
            else:
                with open(output, 'wb') as f:
                    f.write(data)
PYTEST

cat <<'RUNNER' > /tmp/run_agent_instrumented.py
import json
import os
import runpy
import sys
import traceback

import networkx as nx
import rdflib
import rdflib.plugins.sparql as sparql

candidate, report_path = sys.argv[1:3]
report = {
    'parsed_target_dataset': False,
    'parameterized_alice_query': False,
    'query_algebras': [],
    'networkx_edges': 0,
    'networkx_shortest_path': False,
    'error': None,
}

orig_parse = rdflib.Graph.parse
orig_query = rdflib.Graph.query
orig_prepare = sparql.prepareQuery
orig_add_edge = nx.Graph.add_edge


def wrapped_parse(self, source=None, *args, **kwargs):
    location = source if source is not None else kwargs.get('location')
    try:
        if location is not None and os.path.realpath(os.fspath(location)) == '/home/user/dataset.nt':
            report['parsed_target_dataset'] = True
    except TypeError:
        pass
    return orig_parse(self, source, *args, **kwargs)


def wrapped_query(self, query_object, *args, **kwargs):
    bindings = kwargs.get('initBindings') or {}
    if any(str(value) == 'Dr. Alice' for value in bindings.values()):
        report['parameterized_alice_query'] = True

    try:
        algebra = getattr(query_object, 'algebra', None)
        if algebra is None and isinstance(query_object, str):
            algebra = orig_prepare(query_object, initNs=kwargs.get('initNs')).algebra
        if algebra is not None:
            text = str(algebra).strip()
            if text not in report['query_algebras']:
                report['query_algebras'].append(text)
    except Exception:
        pass
    return orig_query(self, query_object, *args, **kwargs)


def wrapped_prepare(*args, **kwargs):
    prepared = orig_prepare(*args, **kwargs)
    try:
        text = str(prepared.algebra).strip()
        if text not in report['query_algebras']:
            report['query_algebras'].append(text)
    except Exception:
        pass
    return prepared


def wrapped_add_edge(self, u, v, *args, **kwargs):
    report['networkx_edges'] += 1
    return orig_add_edge(self, u, v, *args, **kwargs)

rdflib.Graph.parse = wrapped_parse
rdflib.Graph.query = wrapped_query
sparql.prepareQuery = wrapped_prepare
nx.Graph.add_edge = wrapped_add_edge

# Cover the standard NetworkX shortest-path entry points while preserving behavior.
for name in ('shortest_path', 'bidirectional_shortest_path', 'dijkstra_path', 'astar_path'):
    if not hasattr(nx, name):
        continue
    original = getattr(nx, name)
    def make_wrapper(fn):
        def wrapper(*args, **kwargs):
            source = kwargs.get('source', args[1] if len(args) > 1 else None)
            target = kwargs.get('target', args[2] if len(args) > 2 else None)
            if str(source) == 'Dr. Alice' and str(target) == 'Dr. Zeta':
                report['networkx_shortest_path'] = True
            return fn(*args, **kwargs)
        return wrapper
    setattr(nx, name, make_wrapper(original))

try:
    runpy.run_path(candidate, run_name='__main__')
except SystemExit as exc:
    if exc.code not in (None, 0):
        report['error'] = f'SystemExit({exc.code})'
except BaseException:
    report['error'] = traceback.format_exc()[-2000:]
finally:
    with open(report_path, 'w', encoding='utf-8') as f:
        json.dump(report, f)
RUNNER

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
