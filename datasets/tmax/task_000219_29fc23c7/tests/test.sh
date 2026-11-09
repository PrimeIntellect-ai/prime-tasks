#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import sqlite3
import subprocess
import tempfile


def get_script_path():
    candidates = [p for p in glob.glob('/home/user/validate_backup.*') if os.path.isfile(p)]
    assert candidates, 'Classifier /home/user/validate_backup.* not found.'
    executable = [p for p in candidates if os.access(p, os.X_OK)]
    return sorted(executable or candidates)[0]


def run_script(script_path, file_path):
    if not os.access(script_path, os.X_OK):
        if script_path.endswith('.py'):
            cmd = ['python3', script_path, file_path]
        elif script_path.endswith('.sh'):
            cmd = ['bash', script_path, file_path]
        elif script_path.endswith('.js'):
            cmd = ['node', script_path, file_path]
        else:
            raise AssertionError('Classifier is neither executable nor a supported script type')
    else:
        cmd = [script_path, file_path]
    try:
        return subprocess.run(cmd, capture_output=True, timeout=5)
    except subprocess.TimeoutExpired:
        raise AssertionError(f'Classifier timed out on {file_path}')


def classify(graph, basename):
    path = os.path.join('/tmp', basename)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(graph, f)
    return run_script(get_script_path(), path).returncode


def node(i, typ='document'):
    return {'id': i, 'type': typ}


def test_original_clean_corpus_accepted():
    script = get_script_path()
    files = glob.glob('/app/corpus/clean/*.json')
    assert files
    assert all(run_script(script, p).returncode == 0 for p in files)


def test_original_evil_corpus_rejected():
    script = get_script_path()
    files = glob.glob('/app/corpus/evil/*.json')
    assert files
    assert all(run_script(script, p).returncode != 0 for p in files)


def test_generated_graphs_independent_of_path():
    r = node('global_state_db', 'relational')
    valid = [
        {'nodes': [r], 'edges': []},
        {'nodes': [r, node('alpha'), node('beta')],
         'edges': [{'source':'alpha','target':'global_state_db'}, {'source':'beta','target':'alpha'}]},
        {'nodes': [r] + [node(x) for x in ['a','b','c','d','side']],
         'edges': [{'source':'a','target':'global_state_db'}, {'source':'b','target':'a'},
                   {'source':'c','target':'b'}, {'source':'d','target':'c'},
                   {'source':'side','target':'a'}]},
        {'nodes': [r, node('x'), node('y'), node('z')],
         'edges': [{'source':'x','target':'global_state_db'}, {'source':'y','target':'global_state_db'},
                   {'source':'z','target':'x'}, {'source':'z','target':'y'}]},
    ]
    invalid = [
        # Cycle while a correctly named root is also present.
        {'nodes':[r,node('cycle_a'),node('cycle_b')],
         'edges':[{'source':'cycle_a','target':'cycle_b'}, {'source':'cycle_b','target':'cycle_a'}]},
        # Wrong sole root.
        {'nodes':[node('root_x'),node('leaf')], 'edges':[{'source':'leaf','target':'root_x'}]},
        # Five hops from the root.
        {'nodes':[r]+[node(f'd{i}') for i in range(1,6)],
         'edges':[{'source':'d1','target':'global_state_db'}]+[
             {'source':f'd{i}','target':f'd{i-1}'} for i in range(2,6)]},
        # Extra root/disconnected component.
        {'nodes':[r,node('connected'),node('orphan')],
         'edges':[{'source':'connected','target':'global_state_db'}]},
        # Two sinks despite both being connected through a common dependent.
        {'nodes':[r,node('other_root'),node('fan')],
         'edges':[{'source':'fan','target':'global_state_db'}, {'source':'fan','target':'other_root'}]},
    ]
    # Neutral, misleading names ensure behavior cannot key off clean/evil paths.
    for i, graph in enumerate(valid):
        assert classify(graph, f'probe_{i}_evil_named.json') == 0, f'valid generated graph {i} rejected'
    for i, graph in enumerate(invalid):
        assert classify(graph, f'probe_{i}_clean_named.json') != 0, f'invalid generated graph {i} accepted'


def test_schema_is_executable_and_models_indexed_edges():
    path = '/home/user/backup_schema.sql'
    assert os.path.isfile(path), f'Schema file {path} is missing.'
    sql = open(path, encoding='utf-8').read()
    assert 'create table' in sql.lower(), 'No CREATE TABLE statement found in the schema file.'
    assert 'index' in sql.lower(), 'No INDEX statement found in the schema file to optimize querying.'

    db = sqlite3.connect(':memory:')
    try:
        db.executescript(sql)
    except sqlite3.Error as e:
        raise AssertionError(f'Schema is not executable SQLite SQL: {e}')

    tables = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
    assert tables, 'Schema creates no usable tables.'
    columns = {}
    for table in tables:
        safe = table.replace("'", "''")
        columns[table] = {r[1].lower() for r in db.execute(f"PRAGMA table_info('{safe}')")}

    edge_tables = [t for t, cols in columns.items()
                   if any(c in cols for c in ('source','source_id','from_node','from_id','dependent_id'))
                   and any(c in cols for c in ('target','target_id','to_node','to_id','dependency_id'))]
    assert edge_tables, 'Schema must store graph edges with source and target/dependency columns.'

    indexes = list(db.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND sql IS NOT NULL"))
    assert indexes, 'Schema creates no explicit usable index.'
    indexed_cols = set()
    for name, table in indexes:
        safe = name.replace("'", "''")
        indexed_cols.update((table, r[2].lower()) for r in db.execute(f"PRAGMA index_info('{safe}')"))
    target_names = {'target','target_id','to_node','to_id','dependency_id'}
    assert any(table in edge_tables and col in target_names for table, col in indexed_cols), \
        'An edge target/dependency column must be indexed for traversal toward the root.'
    db.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
