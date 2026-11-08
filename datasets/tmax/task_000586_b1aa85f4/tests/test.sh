#!/bin/bash
set -u
mkdir -p /logs/verifier

TMPDIR_VERIFY=$(mktemp -d)
JQ_MOVED=0
SPARQL_MOVED=0

cleanup() {
    if [ "$JQ_MOVED" -eq 1 ] && [ -e "$TMPDIR_VERIFY/jq.real" ]; then
        rm -f /usr/bin/jq
        mv "$TMPDIR_VERIFY/jq.real" /usr/bin/jq
    fi
    if [ "$SPARQL_MOVED" -eq 1 ] && [ -e "$TMPDIR_VERIFY/run_sparql.original.py" ]; then
        rm -f /home/user/run_sparql.py
        mv "$TMPDIR_VERIFY/run_sparql.original.py" /home/user/run_sparql.py
    fi
    if [ -e "$TMPDIR_VERIFY/graph_backup.nt" ]; then
        cp "$TMPDIR_VERIFY/graph_backup.nt" /home/user/graph_backup.nt
    fi
    rm -f /home/user/deps_VerifierProbe_*.json /home/user/deps_VerifierEmpty_*.json
    rm -rf "$TMPDIR_VERIFY"
}
trap cleanup EXIT

prepare() {
    command -v python3 >/dev/null 2>&1 || return 1
    [ -x /usr/bin/jq ] || return 1
    [ -f /home/user/run_sparql.py ] || return 1
    [ -f /home/user/graph_backup.nt ] || return 1

    cp /home/user/graph_backup.nt "$TMPDIR_VERIFY/graph_backup.nt" || return 1

    cat > "$TMPDIR_VERIFY/verifier_run_sparql.py" <<'PYEOF'
import argparse
import rdflib

parser = argparse.ArgumentParser()
parser.add_argument('--data', required=True)
parser.add_argument('--query', required=True)
args = parser.parse_args()
g = rdflib.Graph()
g.parse(args.data, format='nt')
with open(args.query, 'r') as f:
    query = f.read()
result = g.query(query)
print(result.serialize(format='json').decode('utf-8'))
PYEOF

    mv /home/user/run_sparql.py "$TMPDIR_VERIFY/run_sparql.original.py" || return 1
    SPARQL_MOVED=1
    cat > /home/user/run_sparql.py <<'PYEOF'
import json
import os
import shutil
import sys

log_dir = os.environ['VERIFIER_LOG_DIR']
with open(os.path.join(log_dir, 'sparql_invocations.jsonl'), 'a') as f:
    f.write(json.dumps(sys.argv[1:]) + '\n')
try:
    query_path = sys.argv[sys.argv.index('--query') + 1]
    target = os.path.join(log_dir, 'query_' + next(__import__('tempfile')._get_candidate_names()) + '.rq')
    shutil.copyfile(query_path, target)
except Exception:
    pass
os.execv(sys.executable, [sys.executable, os.environ['VERIFIER_SPARQL_RUNNER']] + sys.argv[1:])
PYEOF
    chmod 777 /home/user/run_sparql.py || return 1

    mv /usr/bin/jq "$TMPDIR_VERIFY/jq.real" || return 1
    JQ_MOVED=1
    cat > /usr/bin/jq <<'JQEOF'
#!/bin/bash
printf '%q ' "$@" >> "$VERIFIER_LOG_DIR/jq_invocations.log"
printf '\n' >> "$VERIFIER_LOG_DIR/jq_invocations.log"
infile=$(mktemp "$VERIFIER_LOG_DIR/jq_stdin_XXXXXX")
cat > "$infile"
exec "$VERIFIER_REAL_JQ" "$@" < "$infile"
JQEOF
    chmod 755 /usr/bin/jq || return 1

    export VERIFIER_LOG_DIR="$TMPDIR_VERIFY"
    export VERIFIER_REAL_JQ="$TMPDIR_VERIFY/jq.real"
    export VERIFIER_SPARQL_RUNNER="$TMPDIR_VERIFY/verifier_run_sparql.py"
    return 0
}

if ! prepare; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat > /tmp/test_final_state.py <<'TEST_EOF'
import json
import os
import re
import subprocess
import uuid
import pytest

HOME = '/home/user'
LOG_DIR = os.environ['VERIFIER_LOG_DIR']


def test_deps_appserver_json():
    path = '/home/user/deps_AppServer.json'
    assert os.path.exists(path), f"{path} is missing. The script did not generate the output for AppServer."

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} does not contain valid JSON.")

    assert 'server' in data, f"'server' key missing in {path}"
    assert data['server'] == 'AppServer', f"Expected server 'AppServer', got {data['server']}"
    assert 'dependsOn' in data, f"'dependsOn' key missing in {path}"
    assert isinstance(data['dependsOn'], list), f"'dependsOn' should be a list in {path}"

    expected_deps = ['DB_Primary', 'Redis_Cache']
    actual_deps = data['dependsOn']
    assert sorted(actual_deps) == expected_deps, f"Expected dependencies {expected_deps}, got {actual_deps}"
    assert actual_deps == sorted(actual_deps), f"Dependencies in {path} must be sorted alphabetically."


def test_deps_db_primary_json():
    path = '/home/user/deps_DB_Primary.json'
    assert os.path.exists(path), f"{path} is missing. The script did not generate the output for DB_Primary."

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} does not contain valid JSON.")

    assert 'server' in data, f"'server' key missing in {path}"
    assert data['server'] == 'DB_Primary', f"Expected server 'DB_Primary', got {data['server']}"
    assert 'dependsOn' in data, f"'dependsOn' key missing in {path}"
    assert isinstance(data['dependsOn'], list), f"'dependsOn' should be a list in {path}"

    expected_deps = ['AuthService', 'Storage_SAN']
    actual_deps = data['dependsOn']
    assert sorted(actual_deps) == expected_deps, f"Expected dependencies {expected_deps}, got {actual_deps}"
    assert actual_deps == sorted(actual_deps), f"Dependencies in {path} must be sorted alphabetically."


def test_query_index_csv():
    path = '/home/user/query_index.csv'
    assert os.path.exists(path), f"{path} is missing. The index file was not created."

    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_appserver = "AppServer,DB_Primary|Redis_Cache"
    expected_db_primary = "DB_Primary,AuthService|Storage_SAN"
    assert expected_appserver in lines, f"Expected '{expected_appserver}' in {path}"
    assert expected_db_primary in lines, f"Expected '{expected_db_primary}' in {path}"


def test_check_deps_script_exists():
    path = '/home/user/check_deps.sh'
    assert os.path.exists(path), f"{path} is missing. The bash script was not created."
    assert os.path.isfile(path), f"{path} is not a file."


def graph_dependencies(server):
    triple = re.compile(r'^<http://example[.]org/server/([^>]*)>\s+<http://example[.]org/vocab/dependsOn>\s+<http://example[.]org/server/([^>]*)>\s*[.]\s*$')
    result = []
    with open('/home/user/graph_backup.nt') as f:
        for line in f:
            match = triple.match(line.strip())
            if match and match.group(1) == server:
                result.append(match.group(2))
    return sorted(result)


def test_script_is_bash_and_executes_dynamic_sparql_pipeline():
    script = '/home/user/check_deps.sh'
    assert os.access(script, os.X_OK), f"{script} must be executable so it can be run as ./check_deps.sh"
    with open(script, 'rb') as f:
        first_line = f.readline().decode('utf-8', 'replace').strip()
    assert re.match(r'^#!\s*(?:/usr/bin/env\s+bash|/bin/bash|/usr/bin/bash)(?:\s|$)', first_line), 'check_deps.sh must be a Bash script'

    subprocess.run(['python3', '-c', 'import rdflib'], check=True, timeout=20)
    subprocess.run(['/usr/bin/jq', '--version'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)

    token = uuid.uuid4().hex
    server = 'VerifierProbe_' + token
    empty_server = 'VerifierEmpty_' + token
    deps = ['Zulu_' + token, 'Alpha_' + token, 'Middle_' + token]
    with open('/home/user/graph_backup.nt', 'a') as f:
        for dep in deps:
            f.write(f'<http://example.org/server/{server}> <http://example.org/vocab/dependsOn> <http://example.org/server/{dep}> .\n')

    expected = graph_dependencies(server)
    assert expected == sorted(deps)

    for name in (server, empty_server):
        output = f'/home/user/deps_{name}.json'
        if os.path.exists(output):
            os.unlink(output)
        subprocess.run([script, name], cwd=HOME, check=True, timeout=30)
        assert os.path.isfile(output), f'{script} did not generate {output}'
        with open(output) as f:
            data = json.load(f)
        wanted = graph_dependencies(name)
        assert data == {'server': name, 'dependsOn': wanted}
        assert data['dependsOn'] == sorted(data['dependsOn'])

        with open('/home/user/query_index.csv') as f:
            records = [line.rstrip('\n') for line in f]
        assert f"{name},{'|'.join(wanted)}" in records

    invocation_path = os.path.join(LOG_DIR, 'sparql_invocations.jsonl')
    assert os.path.isfile(invocation_path), 'The script never invoked /home/user/run_sparql.py'
    with open(invocation_path) as f:
        invocations = [json.loads(line) for line in f if line.strip()]
    assert len(invocations) >= 2
    for args in invocations[-2:]:
        assert '--data' in args and args[args.index('--data') + 1] == '/home/user/graph_backup.nt'
        assert '--query' in args, 'run_sparql.py must receive the generated query using --query'

    query_files = [os.path.join(LOG_DIR, n) for n in os.listdir(LOG_DIR) if n.startswith('query_') and n.endswith('.rq')]
    matching_queries = []
    for path in query_files:
        with open(path) as f:
            query = f.read()
        if f'<http://example.org/server/{server}>' in query:
            matching_queries.append(query)
    assert matching_queries, 'No generated SPARQL query targeted the dynamic server'
    query = matching_queries[-1]
    assert '<http://example.org/vocab/dependsOn>' in query
    select = re.search(r'\bSELECT\b(.*?){', query, re.I | re.S)
    assert select, 'Generated query is not a SPARQL SELECT query'
    assert re.findall(r'\?[A-Za-z_][A-Za-z0-9_]*', select.group(1)) == ['?dep'], 'The SELECT clause must select only ?dep'

    jq_log = os.path.join(LOG_DIR, 'jq_invocations.log')
    assert os.path.isfile(jq_log), 'The script never invoked jq'
    with open(jq_log) as f:
        assert len([line for line in f if line.strip()]) >= 2

    captured_json = False
    for name in os.listdir(LOG_DIR):
        if not name.startswith('jq_stdin_'):
            continue
        raw = open(os.path.join(LOG_DIR, name), 'rb').read()
        try:
            value = json.loads(raw)
        except Exception:
            continue
        if isinstance(value, dict) and 'results' in value and 'head' in value:
            captured_json = True
            break
    assert captured_json, 'jq was not given standard SPARQL JSON output to parse'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
