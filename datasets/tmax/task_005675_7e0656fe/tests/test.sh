#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess

import pytest

ETL_DIR = "/home/user/etl"
RAW_JSON_PATH = os.path.join(ETL_DIR, "raw_graph_results.json")
PROCESS_GO_PATH = os.path.join(ETL_DIR, "process.go")
PAGE_3_JSON_PATH = os.path.join(ETL_DIR, "page_3.json")
BOTTLENECK_TXT_PATH = os.path.join(ETL_DIR, "bottleneck.txt")
QUERY_CYPHER_PATH = os.path.join(ETL_DIR, "query.cypher")
QUERY_PLAN_PATH = os.path.join(ETL_DIR, "query_plan.txt")


def expected_page(data):
    filtered = [a for a in data if a.get("trust_score", 0) >= 0.6]
    filtered.sort(key=lambda x: (-x.get("pagerank", 0), x.get("author_id", "")))
    return filtered[10:15]


def run_processor():
    if os.path.exists(PAGE_3_JSON_PATH):
        os.remove(PAGE_3_JSON_PATH)
    result = subprocess.run(
        ["go", "run", PROCESS_GO_PATH],
        cwd=ETL_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process.go failed to compile or run. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(PAGE_3_JSON_PATH), (
        f"Running process.go did not create {PAGE_3_JSON_PATH}."
    )


def read_and_check_page(expected):
    with open(PAGE_3_JSON_PATH, "r", encoding="utf-8") as f:
        text = f.read()
    try:
        actual = json.loads(text)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {PAGE_3_JSON_PATH} does not contain valid JSON: {exc}")

    assert isinstance(actual, list), "Output should be a JSON array."
    assert actual == expected, f"Expected complete page data {expected!r}, got {actual!r}."

    # The requested output must be pretty-printed rather than compact JSON, using
    # two spaces for each array/object indentation level.
    assert "\n" in text, "page_3.json must be formatted JSON, not compact JSON."
    lines = text.splitlines()
    object_lines = [line for line in lines if line.strip() == "{"]
    field_lines = [line for line in lines if re.match(r'^\s*"author_id"\s*:', line)]
    if expected:
        assert object_lines and all(line.startswith("  {") for line in object_lines)
        assert field_lines and all(line.startswith("    \"author_id\"") for line in field_lines)
    return actual


@pytest.fixture(scope="module", autouse=True)
def restore_inputs_and_output():
    with open(RAW_JSON_PATH, "rb") as f:
        original_raw = f.read()
    original_page = None
    if os.path.exists(PAGE_3_JSON_PATH):
        with open(PAGE_3_JSON_PATH, "rb") as f:
            original_page = f.read()
    yield
    with open(RAW_JSON_PATH, "wb") as f:
        f.write(original_raw)
    # Leave the requested output corresponding to the supplied input whenever
    # the submitted program remains runnable.
    try:
        run_processor()
    except Exception:
        if original_page is not None:
            with open(PAGE_3_JSON_PATH, "wb") as f:
                f.write(original_page)


def test_process_go_exists():
    assert os.path.isfile(PROCESS_GO_PATH), f"Go script {PROCESS_GO_PATH} does not exist."
    assert os.path.getsize(PROCESS_GO_PATH) > 0, f"Go script {PROCESS_GO_PATH} is empty."


def test_page_3_json_output():
    with open(RAW_JSON_PATH, "r", encoding="utf-8") as f:
        raw_data = json.load(f)

    # Execute the submitted artifact, rather than accepting a pre-created output.
    run_processor()
    assert os.path.isfile(PAGE_3_JSON_PATH), f"Output file {PAGE_3_JSON_PATH} does not exist."
    actual_page_3 = read_and_check_page(expected_page(raw_data))
    expected_page_3 = expected_page(raw_data)

    # Preserve the original per-entry assertion in addition to exact object checks.
    assert len(actual_page_3) == len(expected_page_3), (
        f"Expected {len(expected_page_3)} items in page 3, got {len(actual_page_3)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_page_3, expected_page_3)):
        assert actual.get("author_id") == expected.get("author_id"), (
            f"Mismatch at index {i}: expected author_id {expected.get('author_id')}, "
            f"got {actual.get('author_id')}."
        )


def test_process_go_on_unseen_input():
    rng = random.Random(secrets.randbits(128))
    data = []
    ranks = [0.25, 1.0, 1.0, 2.5, 3.75, 5.0]
    trusts = [0.5999, 0.6, 0.61, 0.82]
    for i in range(24):
        token = secrets.token_hex(5)
        data.append({
            "author_id": f"U{token}_{23-i:02d}",
            "name": f"Generated Author {token}",
            "pagerank": ranks[rng.randrange(len(ranks))],
            "trust_score": trusts[i % len(trusts)],
        })
    rng.shuffle(data)

    with open(RAW_JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f)
    run_processor()
    read_and_check_page(expected_page(data))


def test_bottleneck_txt():
    assert os.path.isfile(BOTTLENECK_TXT_PATH), f"File {BOTTLENECK_TXT_PATH} does not exist."
    with open(BOTTLENECK_TXT_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()

    # Preserve the original assertion.
    assert "CartesianProduct" in content, (
        f"Expected 'CartesianProduct' in {BOTTLENECK_TXT_PATH}, got {content!r}."
    )

    rows = []
    with open(QUERY_PLAN_PATH, "r", encoding="utf-8") as f:
        for line in f:
            match = re.match(r"^\|\s*(.*?)\s*\|\s*([0-9]+)\s*\|", line)
            if not match or match.group(1) == "Operator":
                continue
            operator = re.sub(r"^[|\s+]+", "", match.group(1)).strip()
            rows.append((int(match.group(2)), operator))
    assert rows, "Could not parse any operators from query_plan.txt."
    expected = max(rows, key=lambda item: item[0])[1]
    assert content == expected, (
        f"bottleneck.txt must contain only the exact highest-EstimatedRows operator "
        f"{expected!r}, got {content!r}."
    )


def strip_cypher_comments(text):
    out = []
    i = 0
    quote = None
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if quote:
            out.append(ch)
            if ch == quote:
                if i + 1 < len(text) and text[i + 1] == quote and quote in "'\"`":
                    out.append(text[i + 1])
                    i += 2
                    continue
                quote = None
            elif ch == "\\" and quote in "'\"" and i + 1 < len(text):
                out.append(text[i + 1])
                i += 2
                continue
            i += 1
            continue
        if ch in "'\"`":
            quote = ch
            out.append(ch)
            i += 1
        elif ch == "/" and nxt == "/":
            i += 2
            while i < len(text) and text[i] not in "\r\n":
                i += 1
            out.append(" ")
        elif ch == "/" and nxt == "*":
            end = text.find("*/", i + 2)
            assert end != -1, "Unterminated block comment in query.cypher."
            out.append(" ")
            i = end + 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def test_query_cypher():
    assert os.path.isfile(QUERY_CYPHER_PATH), f"File {QUERY_CYPHER_PATH} does not exist."
    with open(QUERY_CYPHER_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content, f"File {QUERY_CYPHER_PATH} is empty."

    # Preserve the original checks.
    upper_content = content.upper()
    assert "MATCH" in upper_content, "Query must contain MATCH statement."
    assert "RETURN" in upper_content, "Query must contain RETURN statement."
    assert re.search(r'\(\s*\w*\s*:\s*Person\s*\)', content), "Query must match a Person node."
    assert re.search(r'\(\s*\w*\s*:\s*Article\s*\)', content), "Query must match an Article node."
    assert re.search(r'\[\s*\w*\s*:\s*WROTE\s*\]', content), "Query must match a WROTE relationship."
    assert ">" in content and "2023" in content, "Query must filter for publish_year > 2023."
    assert "publish_year" in content, "Query must check the publish_year property."
    assert "author_id" in content, "Query must alias id as author_id."
    assert "name" in content, "Query must return name."
    assert "pagerank" in content, "Query must return pagerank."
    assert "trust_score" in content, "Query must return trust_score."

    # Validate the executable query after removing comments, tying the relationship,
    # predicate, and returned properties to the same Person/Article variables.
    query = strip_cypher_comments(content).strip()
    clause = re.fullmatch(
        r"(?is)\s*MATCH\s+(.+?)\s+WHERE\s+(.+?)\s+RETURN\s+(.+?)\s*;?\s*",
        query,
    )
    assert clause, "query.cypher must be a single MATCH ... WHERE ... RETURN query."
    match_body, where_body, return_body = clause.groups()

    connection = re.fullmatch(
        r"(?is)\s*\(\s*([A-Za-z_]\w*)\s*:\s*(Person|Article)\s*\)\s*"
        r"(?:<-\s*|-\s*)\[\s*(?:[A-Za-z_]\w*\s*)?:\s*WROTE\s*\]\s*"
        r"(?:->|-)\s*\(\s*([A-Za-z_]\w*)\s*:\s*(Person|Article)\s*\)\s*",
        match_body,
    )
    assert connection, "MATCH must directly connect Person and Article with a WROTE relationship."
    left_var, left_label, right_var, right_label = connection.groups()
    assert {left_label.lower(), right_label.lower()} == {"person", "article"}
    person_var = left_var if left_label.lower() == "person" else right_var
    article_var = left_var if left_label.lower() == "article" else right_var

    predicate = re.fullmatch(
        rf"(?is)\s*\(?\s*{re.escape(article_var)}\s*\.\s*publish_year\s*>\s*2023\s*\)?\s*",
        where_body,
    )
    assert predicate, "WHERE must filter the matched Article variable with publish_year > 2023."

    fields = [part.strip() for part in return_body.split(",")]
    assert len(fields) == 4, "RETURN must contain exactly the four requested Person properties."
    seen = set()
    for field in fields:
        item = re.fullmatch(
            rf"(?is){re.escape(person_var)}\s*\.\s*(id|name|pagerank|trust_score)"
            r"(?:\s+AS\s+([A-Za-z_]\w*))?",
            field,
        )
        assert item, f"Invalid RETURN expression: {field!r}."
        prop, alias = item.groups()
        prop = prop.lower()
        if prop == "id":
            assert alias is not None and alias.lower() == "author_id", (
                "Person.id must be aliased as author_id."
            )
        elif alias is not None:
            assert alias.lower() == prop, f"Unexpected alias for {prop}: {alias}."
        assert prop not in seen, f"Duplicate returned property: {prop}."
        seen.add(prop)
    assert seen == {"id", "name", "pagerank", "trust_score"}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
