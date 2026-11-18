#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import stat
import struct
import subprocess
from collections import defaultdict

import pytest

WORKSPACE = '/home/user/workspace'
SOURCE_PATH = os.path.join(WORKSPACE, 'analyze.go')
MODULE_PATH = os.path.join(WORKSPACE, 'go.mod')
RESULTS_PATH = os.path.join(WORKSPACE, 'results.json')
JSONL_PATH = '/home/user/data/papers.jsonl'
DB_PATH = '/home/user/data/authors.db'


def compute_expected_results():
    if not os.path.isfile(JSONL_PATH):
        pytest.fail(f"Missing input file: {JSONL_PATH}")

    papers = {}
    in_degree = defaultdict(int)

    with open(JSONL_PATH, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            data = json.loads(line)
            papers[data['paper_id']] = {
                'authors': set(data.get('authors', [])),
                'citations': set(data.get('citations', []))
            }
            if data['paper_id'] not in in_degree:
                in_degree[data['paper_id']] = 0

    for pid, pdata in papers.items():
        for cited in pdata['citations']:
            in_degree[cited] += 1

    max_degree = -1
    highest_papers = []
    for pid, degree in in_degree.items():
        if degree > max_degree:
            max_degree = degree
            highest_papers = [pid]
        elif degree == max_degree:
            highest_papers.append(pid)

    highest_centrality_paper = sorted(highest_papers)[0] if highest_papers else ""

    triads = []
    paper_ids = sorted(papers.keys())
    for a in paper_ids:
        for b in papers[a]['citations']:
            if b not in papers:
                continue
            for c in papers[b]['citations']:
                if c not in papers:
                    continue
                if a in papers[c]['citations'] and len({a, b, c}) == 3:
                    shared_authors = papers[a]['authors'].intersection(
                        papers[b]['authors'], papers[c]['authors']
                    )
                    for author in shared_authors:
                        triad_entry = {
                            "shared_author_id": author,
                            "papers": sorted([a, b, c])
                        }
                        if triad_entry not in triads:
                            triads.append(triad_entry)

    triads.sort(key=lambda x: (x["shared_author_id"], x["papers"]))
    return highest_centrality_paper, triads


def run_program_observing_database():
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    in_access = 0x00000001
    in_open = 0x00000020
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f"Unable to initialize database-access observation: errno {ctypes.get_errno()}"
    try:
        wd = libc.inotify_add_watch(fd, DB_PATH.encode(), in_access | in_open)
        assert wd >= 0, f"Unable to observe {DB_PATH}: errno {ctypes.get_errno()}"

        proc = subprocess.run(
            ['go', 'run', 'analyze.go'],
            cwd=WORKSPACE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120
        )

        observed = False
        while True:
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                break
            if not data:
                break
            offset = 0
            while offset + 16 <= len(data):
                event_wd, mask, cookie, name_len = struct.unpack_from('iIII', data, offset)
                if event_wd == wd and mask & (in_access | in_open):
                    observed = True
                offset += 16 + name_len

        return proc, observed
    finally:
        os.close(fd)


def assert_results_match_expected():
    assert os.path.isfile(RESULTS_PATH), f"The output file {RESULTS_PATH} is missing."
    with open(RESULTS_PATH, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("results.json is not a valid JSON file.")

    expected_highest, expected_triads = compute_expected_results()

    assert "highest_centrality_paper" in results, "Missing 'highest_centrality_paper' key in results.json"
    assert results["highest_centrality_paper"] == expected_highest, \
        f"Incorrect highest centrality paper. Expected {expected_highest}, got {results['highest_centrality_paper']}"

    assert "triad_patterns" in results, "Missing 'triad_patterns' key in results.json"
    actual_triads = results["triad_patterns"]
    assert isinstance(actual_triads, list), "'triad_patterns' must be a list"

    normalized_actual = []
    for t in actual_triads:
        assert "shared_author_id" in t, "Missing 'shared_author_id' in triad pattern"
        assert "papers" in t, "Missing 'papers' in triad pattern"
        assert isinstance(t["papers"], list), "'papers' must be a list"
        normalized_actual.append({
            "shared_author_id": t["shared_author_id"],
            "papers": sorted(t["papers"])
        })

    normalized_actual.sort(key=lambda x: (x["shared_author_id"], x["papers"]))
    assert len(normalized_actual) == len(expected_triads), \
        f"Incorrect number of triads. Expected {len(expected_triads)}, got {len(normalized_actual)}"

    for actual, expected in zip(normalized_actual, expected_triads):
        assert actual == expected, f"Triad mismatch. Expected {expected}, got {actual}"


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.exists(SOURCE_PATH), f"Missing required Go source: {SOURCE_PATH}"
    assert not os.path.islink(SOURCE_PATH) and stat.S_ISREG(os.stat(SOURCE_PATH).st_mode), \
        f"{SOURCE_PATH} must be a regular file"
    assert os.path.exists(MODULE_PATH), f"Missing required Go module file: {MODULE_PATH}"
    assert not os.path.islink(MODULE_PATH) and stat.S_ISREG(os.stat(MODULE_PATH).st_mode), \
        f"{MODULE_PATH} must be a regular file"

    module_check = subprocess.run(
        ['go', 'list', '-m'], cwd=WORKSPACE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert module_check.returncode == 0, f"Invalid Go module: {module_check.stderr}"

    if os.path.lexists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    proc, database_accessed = run_program_observing_database()
    assert proc.returncode == 0, \
        f"Go program failed with exit code {proc.returncode}:\n{proc.stderr}"
    assert database_accessed, f"The Go program did not access the required SQLite database {DB_PATH}"
    assert os.path.isfile(RESULTS_PATH), "The Go program did not generate results.json"


def test_results_json_exists():
    assert os.path.isfile(RESULTS_PATH), f"The output file {RESULTS_PATH} is missing."


def test_results_json_content():
    if not os.path.isfile(RESULTS_PATH):
        pytest.fail("results.json not found")
    assert_results_match_expected()


def test_program_recomputes_results_for_changed_input():
    with open(JSONL_PATH, 'rb') as f:
        original = f.read()

    changed_papers = [
        {"paper_id": "Q1", "title": "One", "authors": ["A2"], "citations": ["Q2"]},
        {"paper_id": "Q2", "title": "Two", "authors": ["A2"], "citations": ["Q3"]},
        {"paper_id": "Q3", "title": "Three", "authors": ["A2"], "citations": ["Q1"]},
        {"paper_id": "Q4", "title": "Four", "authors": ["A1"], "citations": ["Q2"]}
    ]

    try:
        with open(JSONL_PATH, 'w') as f:
            for paper in changed_papers:
                f.write(json.dumps(paper) + '\n')

        if os.path.lexists(RESULTS_PATH):
            os.remove(RESULTS_PATH)
        proc, database_accessed = run_program_observing_database()
        assert proc.returncode == 0, \
            f"Go program failed on changed input with exit code {proc.returncode}:\n{proc.stderr}"
        assert database_accessed, "The Go program did not access authors.db on changed input"
        assert_results_match_expected()
    finally:
        with open(JSONL_PATH, 'wb') as f:
            f.write(original)
        subprocess.run(
            ['go', 'run', 'analyze.go'], cwd=WORKSPACE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
