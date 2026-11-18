#!/bin/bash
set +e
mkdir -p /logs/verifier

CSV_BACKUP=/tmp/flights.csv.verifier_backup
PAGE_BACKUP=/tmp/page2.json.verifier_backup
GRAPH_BACKUP=/tmp/graph_edges.csv.verifier_backup
cp /home/user/flights.csv "$CSV_BACKUP"
PAGE_EXISTED=0
GRAPH_EXISTED=0
if [ -f /home/user/page2.json ]; then cp /home/user/page2.json "$PAGE_BACKUP"; PAGE_EXISTED=1; fi
if [ -f /home/user/graph_edges.csv ]; then cp /home/user/graph_edges.csv "$GRAPH_BACKUP"; GRAPH_EXISTED=1; fi

cleanup() {
    cp "$CSV_BACKUP" /home/user/flights.csv 2>/dev/null || true
    if [ "$PAGE_EXISTED" -eq 1 ]; then cp "$PAGE_BACKUP" /home/user/page2.json 2>/dev/null || true; else rm -f /home/user/page2.json; fi
    if [ "$GRAPH_EXISTED" -eq 1 ]; then cp "$GRAPH_BACKUP" /home/user/graph_edges.csv 2>/dev/null || true; else rm -f /home/user/graph_edges.csv; fi
}
trap cleanup EXIT

(
set -e

test -f /home/user/process_flights.c
test -s /home/user/process_flights.c
gcc /home/user/process_flights.c -o /home/user/process_flights -lsqlite3
test -x /home/user/process_flights
ldd /home/user/process_flights | grep -q 'libsqlite3'

cat > /tmp/sqlite_trace.c <<'TRACE_EOF'
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

typedef int (*open_fn)(const char *, sqlite3 **);
typedef int (*open16_fn)(const void *, sqlite3 **);
typedef int (*open_v2_fn)(const char *, sqlite3 **, int, const char *);
typedef int (*trace_fn)(sqlite3 *, unsigned, int (*)(unsigned, void *, void *, void *), void *);
typedef const char *(*sql_fn)(sqlite3_stmt *);

static int trace_callback(unsigned kind, void *ctx, void *stmt_ptr, void *unused) {
    (void)ctx; (void)unused;
    sql_fn get_sql = (sql_fn)dlsym(RTLD_NEXT, "sqlite3_sql");
    const char *sql = get_sql ? get_sql((sqlite3_stmt *)stmt_ptr) : NULL;
    if (!sql) return 0;
    int fd = open("/tmp/process_flights_sql.log", O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
        const char *prefix = (kind == SQLITE_TRACE_PROFILE) ? "PROFILE: " : "STMT: ";
        write(fd, prefix, strlen(prefix));
        write(fd, sql, strlen(sql));
        write(fd, "\n", 1);
        close(fd);
    }
    return 0;
}

static void install_trace(sqlite3 *db) {
    trace_fn set_trace = (trace_fn)dlsym(RTLD_NEXT, "sqlite3_trace_v2");
    if (db && set_trace)
        set_trace(db, SQLITE_TRACE_STMT | SQLITE_TRACE_PROFILE, trace_callback, NULL);
}

int sqlite3_open(const char *name, sqlite3 **db) {
    open_fn real_open = (open_fn)dlsym(RTLD_NEXT, "sqlite3_open");
    int rc = real_open(name, db);
    if (rc == SQLITE_OK) install_trace(*db);
    return rc;
}

int sqlite3_open_v2(const char *name, sqlite3 **db, int flags, const char *vfs) {
    open_v2_fn real_open = (open_v2_fn)dlsym(RTLD_NEXT, "sqlite3_open_v2");
    int rc = real_open(name, db, flags, vfs);
    if (rc == SQLITE_OK) install_trace(*db);
    return rc;
}

int sqlite3_open16(const void *name, sqlite3 **db) {
    open16_fn real_open = (open16_fn)dlsym(RTLD_NEXT, "sqlite3_open16");
    int rc = real_open(name, db);
    if (rc == SQLITE_OK) install_trace(*db);
    return rc;
}
TRACE_EOF

gcc -shared -fPIC /tmp/sqlite_trace.c -o /tmp/sqlite_trace.so -ldl -lsqlite3

cat > /tmp/check_sql_trace.py <<'TRACE_CHECK_EOF'
import re

with open('/tmp/process_flights_sql.log', encoding='utf-8', errors='replace') as f:
    trace = f.read().lower()

# Remove common identifier quoting solely for robust matching.
clean = re.sub(r'["`\[\]]', '', trace)
profiles = '\n'.join(line for line in clean.splitlines() if line.startswith('profile:'))
assert profiles, 'No successfully executed SQLite statements were observed'
assert re.search(r'\bcreate\s+(?:unique\s+)?index\s+(?:if\s+not\s+exists\s+)?idx_airline_delay\s+on\s+[^\s(]+\s*\(', profiles), \
       'The required idx_airline_delay index was not created through SQLite'
match = re.search(r'\bcreate\s+(?:unique\s+)?index\s+(?:if\s+not\s+exists\s+)?idx_airline_delay\s+on\s+[^\s(]+\s*\(([^)]*)\)', profiles)
columns = []
for item in match.group(1).split(','):
    token = item.strip().split()[0] if item.strip() else ''
    columns.append(token.split('.')[-1])
assert columns[:2] == ['airline', 'delay'], 'idx_airline_delay must index airline followed by delay'
assert re.search(r'\binsert\s+into\b', profiles), 'No SQLite INSERT statements were executed'
assert re.search(r'\bselect\b', profiles), 'No SQLite SELECT query was executed'
TRACE_CHECK_EOF

# First exercise the program on the original task data and retain the original
# verifier's exact output assertions.
cat > /home/user/flights.csv <<'CSV_EOF'
id,source,dest,airline,delay
1,JFK,LAX,SkyCorp,15
2,JFK,SFO,SkyCorp,0
3,ORD,ATL,Delta,10
4,LAX,ORD,SkyCorp,45
5,SFO,JFK,SkyCorp,120
6,ATL,JFK,SkyCorp,5
7,JFK,MIA,SkyCorp,25
8,MIA,LAX,SkyCorp,60
9,ORD,JFK,SkyCorp,35
10,LAX,JFK,SkyCorp,50
11,SFO,LAX,SkyCorp,80
12,ATL,ORD,SkyCorp,90
13,JFK,ATL,SkyCorp,10
CSV_EOF
rm -f /home/user/page2.json /home/user/graph_edges.csv /tmp/process_flights_sql.log
timeout 20s env LD_PRELOAD=/tmp/sqlite_trace.so /home/user/process_flights
python3 /tmp/check_sql_trace.py

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

def test_page2_json_exists_and_content():
    """Test that page2.json exists and contains the correct paginated data."""
    file_path = '/home/user/page2.json'
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did the C program run successfully?"

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    expected_data = [
        {"id": 8, "source": "MIA", "dest": "LAX", "delay": 60},
        {"id": 10, "source": "LAX", "dest": "JFK", "delay": 50},
        {"id": 4, "source": "LAX", "dest": "ORD", "delay": 45}
    ]

    assert isinstance(data, list), f"{file_path} must contain a JSON array."
    assert len(data) == len(expected_data), f"{file_path} should contain exactly {len(expected_data)} records."

    for i, expected_record in enumerate(expected_data):
        assert data[i] == expected_record, f"Record at index {i} in {file_path} does not match expected output."

def test_graph_edges_csv_exists_and_content():
    """Test that graph_edges.csv exists and contains the correct delayed SkyCorp flights."""
    file_path = '/home/user/graph_edges.csv'
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did the C program run successfully?"

    expected_lines = [
        "source,dest,weight",
        "SFO,JFK,120",
        "ATL,ORD,90",
        "SFO,LAX,80",
        "MIA,LAX,60",
        "LAX,JFK,50",
        "LAX,ORD,45",
        "ORD,JFK,35",
        "JFK,MIA,25",
        "JFK,LAX,15",
        "JFK,ATL,10",
        "ATL,JFK,5"
    ]

    with open(file_path, 'r') as f:
        content = f.read().strip().splitlines()

    assert len(content) == len(expected_lines), f"{file_path} should have exactly {len(expected_lines)} lines."

    for i, expected_line in enumerate(expected_lines):
        assert content[i].strip() == expected_line, f"Line {i+1} in {file_path} does not match expected output."
TEST_EOF
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

# Generate a fresh fixture after the agent has finished so hardcoded outputs do
# not pass. Expected results are derived independently from that fixture.
python3 <<'DYNAMIC_EOF'
import csv, json, random, secrets
rng = random.Random(secrets.randbits(128))
airports = ['BOS', 'SEA', 'DFW', 'PHX', 'DEN', 'IAD', 'SAN', 'MSP']
delays = rng.sample(range(7, 240), 10)
ids = rng.sample(range(1000, 9000), 14)
rows = []
for i, delay in enumerate(delays):
    src, dst = rng.sample(airports, 2)
    rows.append({'id': ids[i], 'source': src, 'dest': dst, 'airline': 'SkyCorp', 'delay': delay})
rows.extend([
    {'id': ids[10], 'source': 'BOS', 'dest': 'SEA', 'airline': 'SkyCorp', 'delay': 0},
    {'id': ids[11], 'source': 'SEA', 'dest': 'DEN', 'airline': 'SkyCorp', 'delay': -4},
    {'id': ids[12], 'source': 'DFW', 'dest': 'SAN', 'airline': 'OtherAir', 'delay': 250},
    {'id': ids[13], 'source': 'PHX', 'dest': 'IAD', 'airline': 'Delta', 'delay': 33},
])
rng.shuffle(rows)
with open('/home/user/flights.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['id','source','dest','airline','delay'])
    w.writeheader(); w.writerows(rows)
selected = sorted((r for r in rows if r['airline'] == 'SkyCorp' and r['delay'] > 0), key=lambda r: r['delay'], reverse=True)
page = [{'id': r['id'], 'source': r['source'], 'dest': r['dest'], 'delay': r['delay']} for r in selected[3:6]]
edges = [{'source': r['source'], 'dest': r['dest'], 'weight': r['delay']} for r in selected]
with open('/tmp/dynamic_expected.json', 'w') as f:
    json.dump({'page': page, 'edges': edges}, f)
DYNAMIC_EOF

rm -f /home/user/page2.json /home/user/graph_edges.csv /tmp/process_flights_sql.log
timeout 20s env LD_PRELOAD=/tmp/sqlite_trace.so /home/user/process_flights
python3 /tmp/check_sql_trace.py

python3 <<'DYNAMIC_CHECK_EOF'
import csv, json, os
with open('/tmp/dynamic_expected.json') as f:
    expected = json.load(f)
assert os.path.isfile('/home/user/page2.json')
with open('/home/user/page2.json') as f:
    actual_page = json.load(f)
assert actual_page == expected['page'], f'Incorrect dynamically tested Page 2: {actual_page!r}'
assert os.path.isfile('/home/user/graph_edges.csv')
with open('/home/user/graph_edges.csv', newline='') as f:
    reader = csv.DictReader(f)
    assert reader.fieldnames == ['source', 'dest', 'weight']
    actual_edges = []
    for row in reader:
        actual_edges.append({'source': row['source'], 'dest': row['dest'], 'weight': int(row['weight'])})
assert actual_edges == expected['edges'], f'Incorrect dynamically tested graph edges: {actual_edges!r}'
DYNAMIC_CHECK_EOF
) 
status=$?

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
