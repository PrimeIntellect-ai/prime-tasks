#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import shutil
import signal
import sqlite3
import subprocess
import time
from pathlib import Path

import pytest
import requests

BUILD = Path('/home/user/build_graph.sh')
SERVE = Path('/home/user/serve_api.sh')
DB = Path('/home/user/intrusion.db')
VIDEO = Path('/app/surveillance.mp4')
LOGS = Path('/app/network_logs.csv')
URL = 'http://127.0.0.1:8080/api/v1/threats'


def assert_bash_script(path, required_pattern=None):
    assert path.is_file(), f'{path} does not exist or is not a regular file'
    text = path.read_text(errors='replace')
    first = text.splitlines()[0] if text.splitlines() else ''
    assert first.startswith('#!') and 'bash' in first, f'{path} is not a Bash script'
    result = subprocess.run(['bash', '-n', str(path)], capture_output=True, text=True)
    assert result.returncode == 0, f'{path} has invalid Bash syntax: {result.stderr}'
    if required_pattern:
        import re
        assert re.search(required_pattern, text, re.I | re.S), f'{path} is missing required implementation elements'
    return text


def kill_port_8080():
    inodes = set()
    for procnet in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(procnet).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            parts = line.split()
            if len(parts) > 9 and parts[1].split(':')[-1].upper() == '1F90' and parts[3] == '0A':
                inodes.add(parts[9])
    victims = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    victims.add(int(proc.name))
        except (OSError, PermissionError):
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.3)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def run_build():
    DB.unlink(missing_ok=True)
    result = subprocess.run(['bash', str(BUILD)], capture_output=True, text=True, timeout=90)
    assert result.returncode == 0, f'build_graph.sh failed:\nstdout={result.stdout}\nstderr={result.stderr}'
    assert DB.is_file() and DB.stat().st_size > 0, 'build_graph.sh did not create a nonempty intrusion.db'


def start_server():
    kill_port_8080()
    proc = subprocess.Popen(
        ['bash', str(SERVE)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    for _ in range(30):
        try:
            response = requests.get(URL, timeout=2)
            return proc, response
        except requests.exceptions.RequestException:
            time.sleep(0.2)
    pytest.fail(f'Failed to connect to the API server at {URL}')


def flag_is_true(value):
    if isinstance(value, (int, float)):
        return value != 0
    return str(value).strip().lower() in {'1', 'true', 'yes', 'malicious'}


def quote_identifier(value):
    return '"' + value.replace('"', '""') + '"'


def inspect_database(expected_rows, malicious_timestamps):
    try:
        con = sqlite3.connect(str(DB))
        tables = [r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
        assert tables, 'intrusion.db contains no relational tables'

        selected = None
        for table in tables:
            cols = [r[1] for r in con.execute(f'PRAGMA table_info({quote_identifier(table)})')]
            lower = {c.lower(): c for c in cols}
            mal = next((c for c in cols if 'malicious' in c.lower()), None)
            if {'timestamp', 'src_ip', 'dst_ip', 'bytes'} <= set(lower) and mal:
                selected = (table, lower['timestamp'], lower['src_ip'], lower['dst_ip'], lower['bytes'], mal)
                break
        assert selected, 'No connection table contains timestamp, src_ip, dst_ip, bytes, and a malicious flag'
        table, ts_col, src_col, dst_col, bytes_col, mal_col = selected
        qtable = quote_identifier(table)
        cols = ','.join(map(quote_identifier, (ts_col, src_col, dst_col, bytes_col, mal_col)))
        actual = list(con.execute(f'SELECT {cols} FROM {qtable}'))
        assert len(actual) == len(expected_rows), f'Expected {len(expected_rows)} loaded log rows, found {len(actual)}'

        expected = {(round(float(r['timestamp']), 4), r['src_ip'], r['dst_ip'], int(r['bytes'])) for r in expected_rows}
        found = {(round(float(r[0]), 4), str(r[1]), str(r[2]), int(r[3])) for r in actual}
        assert found == expected, f'Database rows do not match network_logs.csv: {found}'
        expected_malicious = {round(float(v), 4) for v in malicious_timestamps}
        found_malicious = {round(float(r[0]), 4) for r in actual if flag_is_true(r[4])}
        assert found_malicious == expected_malicious, f'Incorrect malicious flags: {found_malicious}'

        indexed_columns = set()
        for index_row in con.execute(f'PRAGMA index_list({qtable})'):
            index_name = index_row[1]
            for info in con.execute(f'PRAGMA index_info({quote_identifier(index_name)})'):
                if info[2]:
                    indexed_columns.add(str(info[2]).lower())
        assert {ts_col.lower(), src_col.lower(), dst_col.lower()} <= indexed_columns, \
            f'Missing indexes for timestamp/src_ip/dst_ip; indexed columns are {indexed_columns}'

        qt, qs, qd, qm = map(quote_identifier, (ts_col, src_col, dst_col, mal_col))
        query = f'''SELECT DISTINCT b.{qd}
                    FROM {qtable} a JOIN {qtable} b
                      ON b.{qs} IN (a.{qs}, a.{qd})
                     AND b.{qt} > a.{qt} AND b.{qt} <= a.{qt} + 10
                    WHERE lower(CAST(a.{qm} AS TEXT)) IN ('1','true','yes','malicious')'''
        started = time.perf_counter()
        con.execute(query).fetchall()
        elapsed = time.perf_counter() - started
        assert elapsed < 0.050, f'Representative indexed graph query took {elapsed * 1000:.2f}ms'
    finally:
        if 'con' in locals():
            con.close()


def read_csv():
    with LOGS.open(newline='') as f:
        return list(csv.DictReader(f))


def assert_api(response, expected_edges, expected_nodes, preserve_original_assertions=False):
    assert response.status_code == 200, f'Expected HTTP 200 OK, got {response.status_code}. Response text: {response.text}'
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f'Response body is not valid JSON. Response text: {response.text}')

    assert set(data) == {'status', 'primary_malicious_edges', 'secondary_compromised_nodes'}, \
        f'JSON schema has incorrect keys: {set(data)}'
    assert data.get('status') == 'success', f"Expected 'status' to be 'success', got {data.get('status')}"
    primary_edges = data.get('primary_malicious_edges', [])
    assert isinstance(primary_edges, list)
    for edge in primary_edges:
        assert isinstance(edge, dict) and set(edge) == {'src', 'dst', 'timestamp'}, f'Invalid edge schema: {edge}'
        assert isinstance(edge['timestamp'], (int, float)) and not isinstance(edge['timestamp'], bool)

    if preserve_original_assertions:
        assert len(primary_edges) == 2, f'Expected 2 primary malicious edges, got {len(primary_edges)}'
        for edge in expected_edges:
            assert edge in primary_edges, f'Expected edge {edge} not found in primary_malicious_edges. Actual edges: {primary_edges}'
        secondary_nodes = data.get('secondary_compromised_nodes', [])
        assert len(secondary_nodes) == 1, f'Expected 1 secondary compromised node, got {len(secondary_nodes)}'
        assert '10.0.0.4' in secondary_nodes, f"Expected '10.0.0.4' in secondary_compromised_nodes. Actual nodes: {secondary_nodes}"
    else:
        normalized_actual = sorted((e['src'], e['dst'], round(float(e['timestamp']), 4)) for e in primary_edges)
        normalized_expected = sorted((e['src'], e['dst'], round(float(e['timestamp']), 4)) for e in expected_edges)
        assert normalized_actual == normalized_expected, f'Incorrect primary edges: {primary_edges}'
        nodes = data.get('secondary_compromised_nodes')
        assert isinstance(nodes, list), 'secondary_compromised_nodes must be a JSON array'
        assert len(nodes) == len(expected_nodes) and set(nodes) == set(expected_nodes), f'Incorrect secondary nodes: {nodes}'


def make_random_case():
    rng = random.SystemRandom()
    t0 = round(rng.uniform(5.0, 7.0), 1)
    t1 = round(rng.uniform(16.5, 18.5), 1)
    octets = rng.sample(range(20, 230), 8)
    ips = [f'10.{octets[0]}.{octets[i]}.{octets[i+1]}' for i in range(1, 7)]
    src1, dst1, secondary1, src2, dst2, secondary2 = ips
    rows = [
        {'timestamp': f'{t0 - 3:.1f}', 'src_ip': '198.51.100.10', 'dst_ip': '198.51.100.11', 'bytes': '101'},
        {'timestamp': f'{t0 + 0.2:.1f}', 'src_ip': src1, 'dst_ip': dst1, 'bytes': '901'},
        {'timestamp': f'{t0 + 3.0:.1f}', 'src_ip': dst1, 'dst_ip': secondary1, 'bytes': '302'},
        {'timestamp': f'{t0 + 11.0:.1f}', 'src_ip': dst1, 'dst_ip': '203.0.113.250', 'bytes': '303'},
        {'timestamp': f'{t1 - 0.3:.1f}', 'src_ip': src2, 'dst_ip': dst2, 'bytes': '902'},
        {'timestamp': f'{t1 + 2.0:.1f}', 'src_ip': dst2, 'dst_ip': secondary2, 'bytes': '304'},
    ]
    with LOGS.open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['timestamp', 'src_ip', 'dst_ip', 'bytes'])
        writer.writeheader()
        writer.writerows(rows)
    vf = (f"drawbox=x=0:y=0:w=320:h=240:color=white:t=fill:"
          f"enable='between(t,{t0},{t0 + 0.2})+between(t,{t1},{t1 + 0.2})'")
    result = subprocess.run([
        'ffmpeg', '-loglevel', 'error', '-f', 'lavfi', '-i', 'color=c=black:s=320x240:r=25:d=22',
        '-vf', vf, '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-y', str(VIDEO)
    ], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, f'Failed to generate verifier video: {result.stderr}'
    edges = [
        {'src': src1, 'dst': dst1, 'timestamp': round(t0 + 0.2, 1)},
        {'src': src2, 'dst': dst2, 'timestamp': round(t1 - 0.3, 1)},
    ]
    return rows, edges, [secondary1, secondary2]


def test_complete_pipeline():
    build_text = assert_bash_script(BUILD, r'\bffmpeg\b.*\bsqlite3\b|\bsqlite3\b.*\bffmpeg\b')
    import re
    assert re.search(r'\b(JOIN|WITH)\b', build_text, re.I), 'build_graph.sh does not implement graph SQL using a JOIN or CTE'
    assert re.search(r'\bCREATE\s+(?:UNIQUE\s+)?INDEX\b', build_text, re.I), 'build_graph.sh does not create SQL indexes'
    assert_bash_script(SERVE, r'\b(socat|nc|netcat)\b')

    video_backup = Path('/tmp/verifier-surveillance.mp4')
    logs_backup = Path('/tmp/verifier-network_logs.csv')
    shutil.copy2(VIDEO, video_backup)
    shutil.copy2(LOGS, logs_backup)
    try:
        # Execute and verify the complete pipeline on the supplied incident data.
        run_build()
        original_rows = read_csv()
        inspect_database(original_rows, [12.2, 25.4])
        proc, response = start_server()
        expected_edges = [
            {'src': '10.0.0.2', 'dst': '10.0.0.3', 'timestamp': 12.2},
            {'src': '192.168.1.10', 'dst': '10.0.0.5', 'timestamp': 25.4},
        ]
        assert_api(response, expected_edges, ['10.0.0.4'], preserve_original_assertions=True)
        kill_port_8080()

        # Replace both inputs with an unpredictable incident and require the scripts to recompute it.
        rows, dynamic_edges, dynamic_nodes = make_random_case()
        run_build()
        inspect_database(rows, [e['timestamp'] for e in dynamic_edges])
        proc, response = start_server()
        assert_api(response, dynamic_edges, dynamic_nodes)
    finally:
        kill_port_8080()
        shutil.copy2(video_backup, VIDEO)
        shutil.copy2(logs_backup, LOGS)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
