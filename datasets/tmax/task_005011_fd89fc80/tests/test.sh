#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import sqlite3
import subprocess
import pytest

SCRIPT = '/home/user/get_network.py'
DB = '/home/user/research.db'


def run_script(author_id):
    assert os.path.isfile(SCRIPT), f"Expected script {SCRIPT} does not exist."
    assert not os.path.islink(SCRIPT), f"Expected {SCRIPT} to be a regular file, not a symlink."
    result = subprocess.run(
        ['python3', SCRIPT, str(author_id)],
        cwd='/home/user', text=True, capture_output=True, timeout=15
    )
    assert result.returncode == 0, (
        f"Script failed for author_id {author_id}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_json(author_id):
    path = f'/home/user/network_{author_id}.json'
    assert os.path.isfile(path), f"Expected JSON file {path} does not exist."
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {path} is not valid JSON.")


def expected_from_database(target):
    con = sqlite3.connect(DB)
    try:
        rows = con.execute('SELECT author_id, paper_id FROM author_paper').fetchall()
        authors = {
            row[0]: (row[1], row[2])
            for row in con.execute('SELECT id, name, wikidata_q FROM authors')
        }
    finally:
        con.close()

    by_paper = {}
    for author_id, paper_id in rows:
        by_paper.setdefault(paper_id, set()).add(author_id)

    adjacency = {author_id: set() for author_id in authors}
    for participants in by_paper.values():
        for author_id in participants:
            adjacency.setdefault(author_id, set()).update(participants - {author_id})

    distance_one = adjacency.get(target, set()) - {target}
    distance_two = set()
    for author_id in distance_one:
        distance_two.update(adjacency.get(author_id, set()))
    distance_two -= distance_one | {target}

    result = []
    for distance, ids in ((1, distance_one), (2, distance_two)):
        for author_id in ids:
            name, wikidata_q = authors[author_id]
            result.append({
                'author_id': author_id,
                'name': name,
                'distance': distance,
                'wikidata_q': wikidata_q,
            })
    return sorted(result, key=lambda item: (item['distance'], item['author_id']))


def assert_strict_json(data, target, expected):
    assert type(data) is dict, 'Top-level JSON value must be an object.'
    assert set(data) == {'target_author', 'network'}, 'JSON has missing or extra top-level keys.'
    assert type(data['target_author']) is int, 'target_author must be an integer.'
    assert data['target_author'] == target
    assert type(data['network']) is list, 'network should be a list.'
    for item in data['network']:
        assert type(item) is dict, 'Each network entry must be an object.'
        assert set(item) == {'author_id', 'name', 'distance', 'wikidata_q'}, (
            'Network entry has missing or extra keys.'
        )
        assert type(item['author_id']) is int
        assert type(item['name']) is str
        assert type(item['distance']) is int
        assert type(item['wikidata_q']) is str
    assert data['network'] == expected


def strip_sparql_comments(text):
    output = []
    in_angle = False
    quote = None
    escaped = False
    i = 0
    while i < len(text):
        char = text[i]
        if escaped:
            output.append(char)
            escaped = False
        elif quote:
            output.append(char)
            if char == '\\':
                escaped = True
            elif char == quote:
                quote = None
        elif char in ('\"', "'"):
            quote = char
            output.append(char)
        elif char == '<':
            in_angle = True
            output.append(char)
        elif char == '>':
            in_angle = False
            output.append(char)
        elif char == '#' and not in_angle:
            while i < len(text) and text[i] != '\n':
                i += 1
            output.append('\n')
        else:
            output.append(char)
        i += 1
    return ''.join(output)


def assert_valid_sparql(author_id, expected_qids, preserve_original_checks=False):
    path = f'/home/user/wikidata_{author_id}.rq'
    assert os.path.isfile(path), f"Expected SPARQL file {path} does not exist."
    with open(path, 'r') as f:
        content = f.read()

    if preserve_original_checks:
        assert 'VALUES' in content.upper(), 'SPARQL query missing VALUES clause.'
        for q_id in ['wd:Q222', 'wd:Q333', 'wd:Q555']:
            assert q_id in content, f'SPARQL query missing expected Wikidata ID {q_id}.'
        for var in ['?author', '?dob', '?employer']:
            assert var in content, f'SPARQL query missing expected variable {var}.'
        for prop in ['wdt:P569', 'wdt:P108']:
            assert prop in content, f'SPARQL query missing expected property {prop}.'

    query = strip_sparql_comments(content).strip()
    prefixes = {}
    prefix_re = re.compile(
        r'^\s*PREFIX\s+([A-Za-z][\w-]*):\s*<([^>]+)>', re.IGNORECASE
    )
    while True:
        match = prefix_re.match(query)
        if not match:
            break
        prefixes[match.group(1).lower()] = match.group(2)
        query = query[match.end():]

    assert prefixes.get('wd') in {
        'http://www.wikidata.org/entity/', 'https://www.wikidata.org/entity/'
    }, 'SPARQL query must declare the wd: Wikidata entity prefix.'
    assert prefixes.get('wdt') in {
        'http://www.wikidata.org/prop/direct/',
        'https://www.wikidata.org/prop/direct/'
    }, 'SPARQL query must declare the wdt: Wikidata direct-property prefix.'

    outer = re.fullmatch(
        r'\s*SELECT\s+(.*?)\s+(?:WHERE\s*)?\{(.*)\}\s*',
        query, flags=re.IGNORECASE | re.DOTALL
    )
    assert outer, 'SPARQL file is not a complete SELECT query.'
    projection, body = outer.groups()
    projection_tokens = re.findall(r'\?[A-Za-z_]\w*|DISTINCT|REDUCED', projection, re.I)
    assert re.fullmatch(
        r'(?:\s*(?:\?[A-Za-z_]\w*|DISTINCT|REDUCED)\s*)+', projection, re.I
    ), 'SELECT projection contains invalid text.'
    assert {'?author', '?dob', '?employer'}.issubset(set(projection_tokens)), (
        'SELECT must project ?author, ?dob, and ?employer.'
    )

    depth = 0
    for char in body:
        if char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
            assert depth >= 0, 'SPARQL query has unbalanced braces.'
    assert depth == 0, 'SPARQL query has unbalanced braces.'

    values_re = re.compile(r'VALUES\s+\?author\s*\{([^{}]*)\}', re.I | re.S)
    values_matches = list(values_re.finditer(body))
    assert len(values_matches) == 1, 'SPARQL query must contain one VALUES ?author clause.'
    values_text = values_matches[0].group(1)
    assert re.fullmatch(r'(?:\s*wd:Q\d+\s*)*', values_text), (
        'VALUES ?author must contain only wd:Q identifiers.'
    )
    actual_qids = re.findall(r'wd:Q\d+', values_text)
    assert len(actual_qids) == len(set(actual_qids)), 'VALUES contains duplicate IDs.'
    assert set(actual_qids) == set(expected_qids), (
        f'VALUES IDs {actual_qids} do not match network IDs {expected_qids}.'
    )

    work = values_re.sub(' ', body)
    combined_1 = re.compile(
        r'\?author\s+wdt:P569\s+\?dob\s*;\s*wdt:P108\s+\?employer\s*\.?', re.I
    )
    combined_2 = re.compile(
        r'\?author\s+wdt:P108\s+\?employer\s*;\s*wdt:P569\s+\?dob\s*\.?', re.I
    )
    if combined_1.search(work) or combined_2.search(work):
        work = combined_1.sub(' ', work)
        work = combined_2.sub(' ', work)
        has_dob = has_employer = True
    else:
        dob_re = re.compile(r'\?author\s+wdt:P569\s+\?dob\s*\.?', re.I)
        employer_re = re.compile(r'\?author\s+wdt:P108\s+\?employer\s*\.?', re.I)
        has_dob = bool(dob_re.search(work))
        has_employer = bool(employer_re.search(work))
        work = dob_re.sub(' ', work)
        work = employer_re.sub(' ', work)

    assert has_dob, 'SPARQL query is missing the ?author wdt:P569 ?dob triple.'
    assert has_employer, 'SPARQL query is missing the ?author wdt:P108 ?employer triple.'
    work = re.sub(r'\bOPTIONAL\b', ' ', work, flags=re.I)
    assert re.fullmatch(r'[\s{}.]*', work), 'SPARQL graph pattern contains invalid extra text.'


def test_network_json_output():
    for path in ('/home/user/network_1.json', '/home/user/wikidata_1.rq'):
        if os.path.lexists(path):
            os.remove(path)
    run_script(1)

    data = load_json(1)
    assert 'target_author' in data, "JSON missing 'target_author' key."
    assert data['target_author'] == 1, f"Expected target_author to be 1, got {data['target_author']}."
    assert 'network' in data, "JSON missing 'network' key."
    network = data['network']
    assert isinstance(network, list), "'network' should be a list."

    expected_network = [
        {'author_id': 2, 'name': 'Bob', 'distance': 1, 'wikidata_q': 'Q222'},
        {'author_id': 5, 'name': 'Eve', 'distance': 1, 'wikidata_q': 'Q555'},
        {'author_id': 3, 'name': 'Charlie', 'distance': 2, 'wikidata_q': 'Q333'}
    ]
    assert len(network) == len(expected_network), (
        f'Expected {len(expected_network)} authors in network, got {len(network)}.'
    )
    for i, expected_author in enumerate(expected_network):
        actual_author = network[i]
        assert actual_author.get('author_id') == expected_author['author_id']
        assert actual_author.get('name') == expected_author['name']
        assert actual_author.get('distance') == expected_author['distance']
        assert actual_author.get('wikidata_q') == expected_author['wikidata_q']

    assert_strict_json(data, 1, expected_network)


def test_wikidata_rq_output():
    assert_valid_sparql(1, ['wd:Q222', 'wd:Q333', 'wd:Q555'], True)


def test_script_queries_database_for_unseen_author_id():
    con = sqlite3.connect(DB)
    while True:
        base = 1_000_000 + secrets.randbelow(800_000_000)
        ids = [base + offset for offset in range(5)]
        paper_ids = [base + 900_000_000 + offset for offset in range(4)]
        occupied = con.execute(
            f"SELECT COUNT(*) FROM authors WHERE id IN ({','.join('?' for _ in ids)})", ids
        ).fetchone()[0]
        if not occupied:
            break

    target, direct_a, direct_b, distance_two, distance_three = ids
    token = secrets.token_hex(6)
    authors = [
        (target, f'Target-{token}', f'Q{target}'),
        (direct_a, f'Direct-A-{token}', f'Q{direct_a}'),
        (direct_b, f'Direct-B-{token}', f'Q{direct_b}'),
        (distance_two, f'Distance-Two-{token}', f'Q{distance_two}'),
        (distance_three, f'Distance-Three-{token}', f'Q{distance_three}'),
    ]
    papers = [(paper_id, f'Verifier Paper {token}-{i}') for i, paper_id in enumerate(paper_ids)]
    links = [
        (target, paper_ids[0]), (direct_a, paper_ids[0]),
        (target, paper_ids[1]), (direct_b, paper_ids[1]),
        (direct_a, paper_ids[2]), (distance_two, paper_ids[2]),
        (distance_two, paper_ids[3]), (distance_three, paper_ids[3]),
    ]
    con.executemany('INSERT INTO authors VALUES (?, ?, ?)', authors)
    con.executemany('INSERT INTO papers VALUES (?, ?)', papers)
    con.executemany('INSERT INTO author_paper VALUES (?, ?)', links)
    con.commit()
    con.close()

    json_path = f'/home/user/network_{target}.json'
    rq_path = f'/home/user/wikidata_{target}.rq'
    for path in (json_path, rq_path):
        if os.path.lexists(path):
            os.remove(path)

    try:
        expected = expected_from_database(target)
        run_script(target)
        assert_strict_json(load_json(target), target, expected)
        expected_qids = [f"wd:{item['wikidata_q']}" for item in expected]
        assert_valid_sparql(target, expected_qids)
    finally:
        con = sqlite3.connect(DB)
        con.executemany('DELETE FROM author_paper WHERE author_id = ?', [(i,) for i in ids])
        con.executemany('DELETE FROM author_paper WHERE paper_id = ?', [(i,) for i in paper_ids])
        con.executemany('DELETE FROM papers WHERE id = ?', [(i,) for i in paper_ids])
        con.executemany('DELETE FROM authors WHERE id = ?', [(i,) for i in ids])
        con.commit()
        con.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
