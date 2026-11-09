#!/bin/bash
set -e
mkdir -p /logs/verifier
mkdir -p /tmp/verifier_instrument

cat << 'INSTRUMENT_EOF' > /tmp/verifier_instrument/sitecustomize.py
import json
import os
import sqlite3

_LOG = os.environ.get("VERIFIER_ACTIVITY_LOG")

def _write(kind, value):
    if not _LOG:
        return
    try:
        with open(_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps({"kind": kind, "value": str(value)}) + "\n")
    except Exception:
        pass

_real_connect = sqlite3.connect

def _connect(*args, **kwargs):
    conn = _real_connect(*args, **kwargs)
    try:
        def trace(sql):
            normalized = " ".join(str(sql).lower().split())
            if "select" in normalized and "access_logs" in normalized:
                _write("database_query", sql)
        conn.set_trace_callback(trace)
    except Exception:
        pass
    return conn

sqlite3.connect = _connect

try:
    from jinja2.environment import Template

    _real_render = Template.render
    _real_generate = Template.generate

    def _render(self, *args, **kwargs):
        result = _real_render(self, *args, **kwargs)
        _write("jinja_output", result)
        return result

    def _generate(self, *args, **kwargs):
        parts = []
        for part in _real_generate(self, *args, **kwargs):
            parts.append(str(part))
            yield part
        _write("jinja_output", "".join(parts))

    Template.render = _render
    Template.generate = _generate
except Exception:
    pass
INSTRUMENT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import sqlite3
import math
import re
import json
import glob
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from html.parser import HTMLParser


def compute_ground_truth():
    log_path = '/home/user/raw_logs.csv'
    if not os.path.exists(log_path):
        return []

    users = {}
    with open(log_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            uid = row['user_id']
            if uid not in users:
                users[uid] = {'req': 0, 'ips': set(), 'bytes': []}
            users[uid]['req'] += 1
            users[uid]['ips'].add(row['source_ip'])
            users[uid]['bytes'].append(int(row['bytes_sent']))

    baseline = [50, 1, 2500]
    baseline_norm = math.sqrt(sum(x*x for x in baseline))

    results = []
    for uid, data in users.items():
        req = data['req']
        ips = len(data['ips'])
        avg_b = sum(data['bytes']) / req
        vec = [req, ips, avg_b]
        vec_norm = math.sqrt(sum(x*x for x in vec))
        dot = sum(a*b for a, b in zip(baseline, vec))
        sim = dot / (baseline_norm * vec_norm) if vec_norm > 0 else 0.0
        results.append({
            'user_id': uid,
            'total_requests': req,
            'unique_ips': ips,
            'avg_bytes': avg_b,
            'similarity_score': sim
        })

    results.sort(key=lambda x: x['similarity_score'])
    return results[:5]


class ListParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ul_stack = []
        self.lists = []
        self.current_li = None

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag == 'ul':
            current = []
            self.ul_stack.append(current)
            self.lists.append(current)
        elif tag == 'li' and self.ul_stack:
            self.current_li = []

    def handle_data(self, data):
        if self.current_li is not None:
            self.current_li.append(data)

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag == 'li' and self.current_li is not None and self.ul_stack:
            text = ' '.join(''.join(self.current_li).split())
            self.ul_stack[-1].append(text)
            self.current_li = None
        elif tag == 'ul' and self.ul_stack:
            self.ul_stack.pop()


def contains_expected_ul(content, expected_top5):
    parser = ListParser()
    parser.feed(content)
    expected_items = [
        f"User {row['user_id']} with score {round(row['similarity_score'], 4)}"
        for row in expected_top5
    ]
    return any(len(items) == 5 and Counter(items) == Counter(expected_items)
               for items in parser.lists)


def test_database_bulk_import():
    db_path = '/home/user/logs.db'
    assert os.path.exists(db_path), f"Database file {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='access_logs';")
    table_exists = cursor.fetchone()
    assert table_exists, "Table 'access_logs' does not exist in the database."

    cursor.execute("SELECT COUNT(*) FROM access_logs;")
    count = cursor.fetchone()[0]
    assert count > 0, "Table 'access_logs' is empty."

    with open('/home/user/raw_logs.csv', 'r', encoding='utf-8', newline='') as f:
        raw_rows = list(csv.DictReader(f))

    cursor.execute("PRAGMA table_info(access_logs)")
    db_columns = {row[1] for row in cursor.fetchall()}
    required = {'user_id', 'timestamp', 'source_ip', 'bytes_sent'}
    assert required.issubset(db_columns), \
        f"access_logs is missing required columns: {sorted(required - db_columns)}"

    cursor.execute("SELECT user_id, timestamp, source_ip, bytes_sent FROM access_logs")
    db_rows = [tuple('' if value is None else str(value) for value in row)
               for row in cursor.fetchall()]
    conn.close()

    expected_rows = [
        (row['user_id'], row['timestamp'], row['source_ip'], row['bytes_sent'])
        for row in raw_rows
    ]
    assert count == len(expected_rows), \
        f"access_logs has {count} rows, but raw_logs.csv has {len(expected_rows)} rows."
    assert Counter(db_rows) == Counter(expected_rows), \
        "access_logs does not contain exactly the rows imported from raw_logs.csv."


def test_top_anomalies_csv():
    csv_path = '/home/user/top_anomalies.csv'
    assert os.path.exists(csv_path), f"CSV file {csv_path} does not exist."

    expected_top5 = compute_ground_truth()
    assert len(expected_top5) == 5, "Could not compute ground truth."

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) == 5, f"Expected exactly 5 rows in {csv_path}, found {len(rows)}."

    expected_cols = {'user_id', 'total_requests', 'unique_ips', 'avg_bytes', 'similarity_score'}
    assert set(reader.fieldnames) == expected_cols, f"CSV columns do not match expected. Got {reader.fieldnames}"

    for i, (actual, expected) in enumerate(zip(rows, expected_top5)):
        assert actual['user_id'] == expected['user_id'], f"Row {i+1} user_id mismatch. Expected {expected['user_id']}, got {actual['user_id']}."
        assert int(actual['total_requests']) == expected['total_requests'], f"Row {i+1} total_requests mismatch."
        assert int(actual['unique_ips']) == expected['unique_ips'], f"Row {i+1} unique_ips mismatch."
        assert math.isclose(float(actual['avg_bytes']), expected['avg_bytes'], rel_tol=1e-5), f"Row {i+1} avg_bytes mismatch."
        assert math.isclose(float(actual['similarity_score']), expected['similarity_score'], abs_tol=1e-3), f"Row {i+1} similarity_score mismatch."


def test_anomaly_report_html():
    html_path = '/home/user/anomaly_report.html'
    assert os.path.exists(html_path), f"HTML report {html_path} does not exist."

    with open(html_path, 'r', encoding='utf-8') as f:
        content = f.read()

    expected_top5 = compute_ground_truth()

    for expected in expected_top5:
        uid = expected['user_id']
        sim = round(expected['similarity_score'], 4)

        # We allow some flexibility in whitespace, but the structure must match
        pattern = rf"<li>User\s+{uid}\s+with score\s+{sim}0*</li>"
        match = re.search(pattern, content)
        assert match, f"Could not find expected <li> tag for user {uid} with score ~{sim} in the HTML report."

    assert contains_expected_ul(content, expected_top5), \
        "The report must contain one <ul> with exactly the five required <li> items."


def test_python_workflow_queries_database_and_renders_jinja_template():
    scripts = [p for p in sorted(glob.glob('/home/user/*.py')) if os.path.isfile(p)]
    assert scripts, "No Python processing script was saved in /home/user."

    protected = [
        '/home/user/raw_logs.csv',
        '/home/user/logs.db',
        '/home/user/top_anomalies.csv',
        '/home/user/anomaly_report.html',
    ]
    expected_top5 = compute_ground_truth()
    saw_database_query = False
    rendered_outputs = []

    with tempfile.TemporaryDirectory() as backup_dir:
        for path in protected:
            assert os.path.exists(path), f"Required artifact disappeared before workflow verification: {path}"
            shutil.copy2(path, os.path.join(backup_dir, os.path.basename(path)))

        def restore():
            for path in protected:
                for suffix in ('', '-wal', '-shm'):
                    candidate = path + suffix
                    if os.path.exists(candidate):
                        os.remove(candidate)
                shutil.copy2(os.path.join(backup_dir, os.path.basename(path)), path)

        try:
            for index, script in enumerate(scripts):
                restore()
                activity_log = f'/tmp/verifier_activity_{index}.jsonl'
                if os.path.exists(activity_log):
                    os.remove(activity_log)
                env = os.environ.copy()
                env['PYTHONPATH'] = '/tmp/verifier_instrument' + (
                    os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else ''
                )
                env['VERIFIER_ACTIVITY_LOG'] = activity_log
                try:
                    result = subprocess.run(
                        [sys.executable, script],
                        cwd='/home/user',
                        env=env,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=30,
                    )
                except subprocess.TimeoutExpired:
                    continue

                if result.returncode != 0 or not os.path.exists(activity_log):
                    continue
                with open(activity_log, 'r', encoding='utf-8') as f:
                    for line in f:
                        try:
                            event = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        if event.get('kind') == 'database_query':
                            saw_database_query = True
                        elif event.get('kind') == 'jinja_output':
                            rendered_outputs.append(event.get('value', ''))
        finally:
            restore()

    assert saw_database_query, \
        "No successfully executable saved Python script queried the access_logs table."
    assert any(contains_expected_ul(output, expected_top5) for output in rendered_outputs), \
        "No successfully executable saved Python script used Jinja2 to render the required <ul> report."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
