#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
from collections import Counter

import pytest

DATA_DIR = "/home/user/data"
INDEX_DIR = "/home/user/indexes"
OUTPUT_DIR = "/home/user/output"
RESULTS_FILE = os.path.join(OUTPUT_DIR, "results.json")


def nonempty_lines(path):
    with open(path, "r", newline="") as f:
        return [line.strip() for line in f if line.strip()]


def csv_rows(path):
    with open(path, "r", newline="") as f:
        return list(csv.reader(f))


def assert_same_records(index_path, source_path):
    indexed = nonempty_lines(index_path)
    source = nonempty_lines(source_path)
    assert Counter(indexed) == Counter(source), (
        f"{index_path} does not contain exactly the records from {source_path}."
    )


def expected_names_from_sources():
    users = csv_rows(os.path.join(DATA_DIR, "users.csv"))
    follows = csv_rows(os.path.join(DATA_DIR, "follows.csv"))
    posts = csv_rows(os.path.join(DATA_DIR, "posts.csv"))

    user_names = {}
    for row in users:
        assert len(row) >= 2, f"Invalid users.csv row: {row}"
        user_names.setdefault(row[0], []).append(row[1])

    matching_authors = set()
    for row in posts:
        assert len(row) >= 3, f"Invalid posts.csv row: {row}"
        if "BASH_ROCKS" in ",".join(row[2:]):
            matching_authors.add(row[1])

    follower_ids = set()
    for row in follows:
        assert len(row) >= 2, f"Invalid follows.csv row: {row}"
        if row[1] in matching_authors:
            follower_ids.add(row[0])

    return sorted({name for uid in follower_ids for name in user_names.get(uid, [])})


def test_directories_created():
    assert os.path.isdir(INDEX_DIR), f"Directory {INDEX_DIR} does not exist."
    assert os.path.isdir(OUTPUT_DIR), f"Directory {OUTPUT_DIR} does not exist."


def test_users_sorted_file():
    filepath = os.path.join(INDEX_DIR, "users_sorted.csv")
    assert os.path.isfile(filepath), f"File {filepath} does not exist."

    lines = nonempty_lines(filepath)
    user_ids = []
    for line in lines:
        parts = line.split(',')
        assert len(parts) >= 2, f"Invalid line format in {filepath}: {line}"
        user_ids.append(int(parts[0]))

    assert user_ids == sorted(user_ids), f"{filepath} is not sorted numerically by user_id."
    assert len(user_ids) == 6, f"Expected 6 users in {filepath}, found {len(user_ids)}."
    assert_same_records(filepath, os.path.join(DATA_DIR, "users.csv"))


def test_follows_by_followee_file():
    filepath = os.path.join(INDEX_DIR, "follows_by_followee.csv")
    assert os.path.isfile(filepath), f"File {filepath} does not exist."

    lines = nonempty_lines(filepath)
    followee_ids = []
    for line in lines:
        parts = line.split(',')
        assert len(parts) >= 2, f"Invalid line format in {filepath}: {line}"
        followee_ids.append(int(parts[1]))

    assert followee_ids == sorted(followee_ids), f"{filepath} is not sorted numerically by followee_id."
    assert len(followee_ids) == 5, f"Expected 5 follows in {filepath}, found {len(followee_ids)}."
    assert_same_records(filepath, os.path.join(DATA_DIR, "follows.csv"))


def test_posts_by_user_file():
    filepath = os.path.join(INDEX_DIR, "posts_by_user.csv")
    assert os.path.isfile(filepath), f"File {filepath} does not exist."

    lines = nonempty_lines(filepath)
    user_ids = []
    for line in lines:
        parts = line.split(',')
        assert len(parts) >= 3, f"Invalid line format in {filepath}: {line}"
        user_ids.append(int(parts[1]))

    assert user_ids == sorted(user_ids), f"{filepath} is not sorted numerically by user_id."
    assert len(user_ids) == 4, f"Expected 4 posts in {filepath}, found {len(user_ids)}."
    assert_same_records(filepath, os.path.join(DATA_DIR, "posts.csv"))


def test_results_json():
    assert os.path.isfile(RESULTS_FILE), f"File {RESULTS_FILE} does not exist."

    with open(RESULTS_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_FILE} does not contain valid JSON.")

    expected = expected_names_from_sources()
    assert isinstance(data, list), f"Expected JSON array in {RESULTS_FILE}, got {type(data)}."
    assert data == expected, f"Expected {expected}, got {data}."


def test_results_json_formatting():
    with open(RESULTS_FILE, 'r') as f:
        content = f.read()

    expected_format = json.dumps(expected_names_from_sources(), indent=2, ensure_ascii=False)
    assert content.strip() == expected_format, (
        "JSON formatting does not match expected 2-space indentation.\n"
        f"Expected:\n{expected_format}\nGot:\n{content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
