#!/bin/bash
mkdir -p /logs/verifier
RESULT=0
SQLITE_BIN=/usr/bin/sqlite3
SQLITE_REAL=/tmp/verifier-sqlite3-real
SQLITE_LOG=/tmp/verifier-sqlite3.log

cleanup() {
    if [ -f "$SQLITE_REAL" ]; then
        cp "$SQLITE_REAL" "$SQLITE_BIN" 2>/dev/null || true
        chmod 755 "$SQLITE_BIN" 2>/dev/null || true
    fi
    echo "$RESULT" > /logs/verifier/reward.txt
}
trap cleanup EXIT

if ! cp "$SQLITE_BIN" "$SQLITE_REAL"; then
    exit 0
fi

cat > "$SQLITE_BIN" <<'WRAPPER_EOF'
#!/bin/bash
real=/tmp/verifier-sqlite3-real
log=/tmp/verifier-sqlite3.log
input=$(mktemp)
cat > "$input"
{
    echo '=== sqlite3 invocation ==='
    printf 'arg: %s\n' "$@"
    cat "$input"
} >> "$log"
"$real" "$@" < "$input"
status=$?
rm -f "$input"
exit $status
WRAPPER_EOF
chmod 755 "$SQLITE_BIN"

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess

SCRIPT = '/home/user/audit_graph.sh'
NODES = '/home/user/backup_data/nodes.csv'
EDGES = '/home/user/backup_data/edges.csv'
DANGLING = '/home/user/dangling_edges.csv'
VULNERABLE = '/home/user/vulnerable_dbs.csv'
SQLITE_LOG = '/tmp/verifier-sqlite3.log'


def write_fixture(nodes, edges):
    os.makedirs(os.path.dirname(NODES), exist_ok=True)
    with open(NODES, 'w', newline='') as f:
        for row in nodes:
            f.write(','.join(row) + '\n')
    with open(EDGES, 'w', newline='') as f:
        for row in edges:
            f.write(','.join(row) + '\n')


def derive_expected(nodes, edges):
    by_id = {row[0]: row for row in nodes}
    dangling = [','.join(edge) for edge in edges
                if edge[0] not in by_id or edge[1] not in by_id]

    manages = [(s, d) for s, d, rel in edges if rel == 'MANAGES']
    hosts = [(s, d) for s, d, rel in edges if rel == 'HOSTS']
    backed_up = {s for s, _d, rel in edges if rel == 'HAS_BACKUP'}
    vulnerable = []
    for engineer, cluster in manages:
        if (engineer not in by_id or cluster not in by_id or
                by_id[engineer][1] != 'Engineer' or
                by_id[cluster][1] != 'Cluster'):
            continue
        for host_cluster, database in hosts:
            if host_cluster != cluster or database not in by_id:
                continue
            if by_id[database][1] == 'Database' and database not in backed_up:
                vulnerable.append(','.join((by_id[engineer][2],
                                            by_id[cluster][2],
                                            by_id[database][2])))
    vulnerable.sort(key=lambda line: tuple(line.split(',')))
    return dangling, vulnerable


def read_nonempty_lines(path):
    assert os.path.isfile(path), f'The file {path} does not exist.'
    with open(path, newline='') as f:
        return [line.rstrip('\r\n') for line in f if line.rstrip('\r\n')]


def execute_and_check(nodes, edges):
    expected_dangling, expected_vulnerable = derive_expected(nodes, edges)
    write_fixture(nodes, edges)
    for path in (DANGLING, VULNERABLE, SQLITE_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    completed = subprocess.run(
        [SCRIPT], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert completed.returncode == 0, (
        f'audit_graph.sh exited with {completed.returncode}: {completed.stderr}'
    )
    assert read_nonempty_lines(DANGLING) == expected_dangling
    assert read_nonempty_lines(VULNERABLE) == expected_vulnerable

    assert os.path.isfile(SQLITE_LOG), 'audit_graph.sh did not execute sqlite3.'
    trace = open(SQLITE_LOG, errors='replace').read().lower()
    assert '=== sqlite3 invocation ===' in trace, 'sqlite3 was not executed.'
    assert re.search(r'\bselect\b', trace), 'No SQLite SELECT query was executed.'
    assert re.search(r'\bjoin\b', trace), 'No SQLite JOIN was executed.'
    assert ('not exists' in trace or
            re.search(r'\bnot\s+in\s*\(\s*select\b', trace)), (
        'No SQLite exclusion subquery was executed.'
    )


def test_audit_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f'The script {SCRIPT} does not exist.'
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f'The script {SCRIPT} is not executable.'


def test_declared_src_dst_rel_schema_and_original_scenario():
    nodes = [
        ('1','Engineer','Alice'), ('2','Engineer','Bob'),
        ('3','Cluster','ClusterAlpha'), ('4','Cluster','ClusterBeta'),
        ('5','Database','DB_Payments'), ('6','Database','DB_Analytics'),
        ('7','Database','DB_Users'), ('8','Storage','S3_Backup_Bucket'),
        ('9','Engineer','Charlie'), ('10','Cluster','ClusterGamma'),
        ('11','Database','DB_Logs')
    ]
    edges = [
        ('1','3','MANAGES'), ('2','4','MANAGES'), ('9','10','MANAGES'),
        ('3','5','HOSTS'), ('4','6','HOSTS'), ('4','7','HOSTS'),
        ('10','11','HOSTS'), ('5','8','HAS_BACKUP'),
        ('6','8','HAS_BACKUP'), ('99','3','MANAGES'),
        ('4','88','HOSTS'), ('10','8','HAS_BACKUP')
    ]
    execute_and_check(nodes, edges)


def test_fresh_fixture_is_actually_analyzed():
    tag = secrets.token_hex(5)
    nodes = [
        ('101','Engineer','EngZ_' + tag),
        ('102','Engineer','EngA_' + tag),
        ('201','Cluster','ClusterZ_' + tag),
        ('202','Cluster','ClusterA_' + tag),
        ('301','Database','DB_unbacked_' + tag),
        ('302','Database','DB_backed_' + tag),
        ('303','Database','DB_second_' + tag),
        ('401','Storage','Store_' + tag),
        ('501','Service','NotADatabase_' + tag),
    ]
    edges = [
        ('101','201','MANAGES'), ('102','202','MANAGES'),
        ('201','301','HOSTS'), ('201','302','HOSTS'),
        ('202','303','HOSTS'), ('202','501','HOSTS'),
        ('302','401','HAS_BACKUP'),
        ('9991','201','MANAGES'), ('202','9992','HOSTS'),
        ('301','201','MANAGES'), ('401','303','HAS_BACKUP')
    ]
    execute_and_check(nodes, edges)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short; then
    RESULT=1
fi
exit 0
