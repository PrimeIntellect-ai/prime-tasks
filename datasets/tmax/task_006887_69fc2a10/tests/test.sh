#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import tempfile

SCRIPT = '/home/user/pipeline/run_etl.sh'
EDGES = '/home/user/raw_data/edges.tsv'
RESULTS = '/home/user/pipeline/results.jsonl'


def read_results():
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} does not exist."
    objects = []
    with open(RESULTS, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                assert False, f"Line {line_num} in {RESULTS} is not valid JSON."
            assert isinstance(obj, dict), f"Line {line_num} is not a JSON object."
            assert set(obj) == {'user', 'repo', 'file', 'library'}, \
                f"Line {line_num} does not contain exactly the required four keys."
            for key in ('user', 'repo', 'file', 'library'):
                assert isinstance(obj[key], str) and obj[key], \
                    f"Line {line_num} has an invalid value for {key}."
            objects.append(obj)
    return objects


def sort_key(obj):
    return (obj['user'], obj['repo'], obj['file'], obj['library'])


def expected_from_tsv(text):
    edges = []
    for line in text.splitlines():
        if not line:
            continue
        fields = line.split('\t')
        assert len(fields) == 3
        edges.append(tuple(fields))

    follows = [(s, o) for s, r, o in edges if r == 'follows']
    contains = [(s, o) for s, r, o in edges if r == 'contains']
    imports = [(s, o) for s, r, o in edges if r == 'imports']
    return [
        {'user': user, 'repo': repo, 'file': file_name, 'library': library}
        for user, repo in follows
        for parent_repo, file_name in contains if parent_repo == repo
        for parent_file, library in imports if parent_file == file_name
    ]


def run_script(env=None):
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        [SCRIPT], env=env, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )
    assert completed.returncode == 0, (
        f"ETL script exited with {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS), "The script did not create results.jsonl."
    return read_results()


def make_fixture(tag):
    token = secrets.token_hex(8)
    u1, u2, u3 = (f'{tag}_user_{token}_{i}' for i in range(3))
    r1, r2, unused = (f'{tag}_repo_{token}_{i}' for i in range(3))
    f1, f2, f3 = (f'{tag}_file_{token}_{i}.src' for i in range(3))
    l1, l2, l3 = (f'{tag}_lib_{token}_{i}' for i in range(3))
    rows = [
        (u1, 'follows', r1), (u2, 'follows', r2), (u3, 'follows', r1),
        (r1, 'contains', f1), (r1, 'contains', f2), (r2, 'contains', f3),
        (f1, 'imports', l1), (f1, 'imports', l2), (f2, 'imports', l3),
        (u1, 'knows', u2), (unused, 'contains', f'{tag}_orphan_{token}'),
        (f'{tag}_noise_{token}', 'imports', f'{tag}_noise_lib_{token}'),
        (r2, 'forked_from', r1),
    ]
    return ''.join('\t'.join(row) + '\n' for row in rows)


def test_complete_etl_pipeline():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    with open(SCRIPT, 'r', encoding='utf-8', errors='replace') as f:
        source = f.read()
    assert re.search(r'(^|[\s;/|&])(?:/[^\s]+/)?jq(?:[\s;&|]|$)', source, re.M), \
        "run_etl.sh must invoke jq for schema validation."
    assert 'results.jsonl' in source, "The script must validate the generated results.jsonl."

    with open(EDGES, 'r', encoding='utf-8') as f:
        original_edges = f.read()

    expected_objects = [
        {'user':'alice','repo':'repoA','file':'main.py','library':'requests'},
        {'user':'alice','repo':'repoA','file':'main.py','library':'sys'},
        {'user':'alice','repo':'repoA','file':'utils.py','library':'os'},
        {'user':'alice','repo':'repoC','file':'index.ts','library':'lodash'},
        {'user':'bob','repo':'repoB','file':'app.js','library':'express'},
        {'user':'charlie','repo':'repoC','file':'index.ts','library':'lodash'}
    ]

    try:
        # Preserve the original exact correctness assertion, but require the script
        # itself to freshly generate the file.
        actual_objects = run_script()
        assert len(actual_objects) == len(expected_objects), \
            f"Expected {len(expected_objects)} lines, got {len(actual_objects)}."
        assert sorted(actual_objects, key=sort_key) == sorted(expected_objects, key=sort_key), \
            "The extracted graph patterns do not match the expected output."

        # Log actual jq invocations while exercising an unpredictable graph.
        with tempfile.TemporaryDirectory() as td:
            jq_log = os.path.join(td, 'jq_calls.jsonl')
            wrapper = os.path.join(td, 'jq')
            with open(wrapper, 'w', encoding='utf-8') as f:
                f.write("#!/usr/bin/python3\n")
                f.write("import json, os, sys\n")
                f.write(f"with open({jq_log!r}, 'a') as out: out.write(json.dumps(sys.argv[1:]) + '\\n')\n")
                f.write("os.execv('/usr/bin/jq', ['/usr/bin/jq'] + sys.argv[1:])\n")
            os.chmod(wrapper, 0o755)

            fixture = make_fixture('dynamic')
            with open(EDGES, 'w', encoding='utf-8') as f:
                f.write(fixture)
            env = os.environ.copy()
            env['PATH'] = td + os.pathsep + env.get('PATH', '')
            actual = run_script(env)
            expected = expected_from_tsv(fixture)
            assert sorted(actual, key=sort_key) == sorted(expected, key=sort_key), \
                "The script did not compute the graph matches for a new input."

            assert os.path.isfile(jq_log), "jq was not executed by the ETL script."
            with open(jq_log, 'r', encoding='utf-8') as f:
                calls = [json.loads(line) for line in f if line.strip()]
            joined = '\n'.join(' '.join(call) for call in calls)
            for key in ('user', 'repo', 'file', 'library'):
                assert key in joined, f"jq validation does not check the {key!r} field."
            assert ('keys' in joined or ('has(' in joined and 'length' in joined)), \
                "jq validation does not enforce the exact object keys."
            assert ('string' in joined or 'strings' in joined), \
                "jq validation does not check that values are strings."
            assert ('length' in joined or '!= \"\"' in joined or "!= ''" in joined), \
                "jq validation does not check that values are non-empty."
            assert any('-e' in call or '--exit-status' in call or
                       any('error' in arg or 'halt_error' in arg for arg in call)
                       for call in calls), \
                "jq validation is not configured to fail the script on invalid schema."

        # A second independently generated fixture prevents fixed alternate output.
        fixture = make_fixture('second')
        with open(EDGES, 'w', encoding='utf-8') as f:
            f.write(fixture)
        actual = run_script()
        assert sorted(actual, key=sort_key) == sorted(expected_from_tsv(fixture), key=sort_key), \
            "The script appears to return fixed results rather than processing edges.tsv."
    finally:
        with open(EDGES, 'w', encoding='utf-8') as f:
            f.write(original_edges)

    # Leave the required final output corresponding to the supplied dataset.
    final_objects = run_script()
    assert sorted(final_objects, key=sort_key) == sorted(expected_objects, key=sort_key)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
