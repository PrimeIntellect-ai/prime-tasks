#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess

APP_DIR = "/home/user/app"
FIXTURE_DIR = os.path.join(APP_DIR, "fixtures")
FIXTURE_FILE = os.path.join(FIXTURE_DIR, "schema_v1.json")
PATCH_FILE = "/home/user/router.patch"
TEST_SCRIPT = os.path.join(APP_DIR, "test.sh")
ROUTER = os.path.join(APP_DIR, "router.sh")

EXPECTED_TEST_SCRIPT = b'''#!/bin/bash

for i in {1..50}; do
    TARGET=$RANDOM
    PREFIX_PARAM="dummy=$RANDOM"
    SUFFIX_PARAM="foo=bar"

    ORDER=$((RANDOM % 3))
    if [ $ORDER -eq 0 ]; then
        QUERY="target=${TARGET}&${PREFIX_PARAM}&${SUFFIX_PARAM}"
    elif [ $ORDER -eq 1 ]; then
        QUERY="${PREFIX_PARAM}&target=${TARGET}&${SUFFIX_PARAM}"
    else
        QUERY="${PREFIX_PARAM}&${SUFFIX_PARAM}&target=${TARGET}"
    fi

    OUTPUT=$(./router.sh "/api/migrate?$QUERY")
    if [[ "$OUTPUT" != "Migrating to schema $TARGET" ]]; then
        echo "Test failed for query: $QUERY"
        echo "Got: $OUTPUT"
        exit 1
    fi
done
echo "All tests passed."
'''

ORIGINAL_ROUTER = b'''#!/bin/bash
URI="$1"
PATH_PART="${URI%%\\?*}"
QUERY_STRING="${URI#*\\?}"

if [ "$PATH_PART" = "/api/migrate" ]; then
    # BROKEN PR CODE: only works if 'target' is the first parameter
    TARGET=$(echo "$QUERY_STRING" | cut -d'&' -f1 | cut -d'=' -f2)

    if [[ ! "$QUERY_STRING" =~ "target=" ]]; then
        echo "Error: target missing"
        exit 1
    fi

    if [ ! -f "fixtures/schema_v1.json" ]; then
        echo "Error: Base fixture missing"
        exit 1
    fi

    echo "Migrating to schema $TARGET"
else
    echo "404 Not Found"
fi
'''


def test_fixture_exists_and_correct():
    assert os.path.isdir(FIXTURE_DIR), f"Directory {FIXTURE_DIR} was not created."
    assert os.path.isfile(FIXTURE_FILE), f"File {FIXTURE_FILE} was not created."

    with open(FIXTURE_FILE, "r") as f:
        content = f.read().strip()

    try:
        data = json.loads(content)
        assert data == {"version": 1}, f"Fixture content is incorrect. Expected {{'version': 1}}, got {data}"
    except json.JSONDecodeError:
        assert content == '{"version": 1}', f"Fixture content is incorrect. Expected '{{\"version\": 1}}', got '{content}'"


def apply_unified_diff(original, patch_text):
    lines = patch_text.splitlines(keepends=True)
    assert len(lines) >= 3, "Patch is too short."
    assert lines[0].startswith("--- ") and lines[1].startswith("+++ "), "Patch must begin with unified-diff headers."

    old_name = lines[0][4:].rstrip("\n").split("\t", 1)[0]
    new_name = lines[1][4:].rstrip("\n").split("\t", 1)[0]
    assert "router.sh" in old_name and "router.sh" in new_name, "Patch headers must identify router.sh."

    source = original.splitlines(keepends=True)
    output = []
    source_pos = 0
    i = 2
    saw_hunk = False
    hunk_re = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")

    while i < len(lines):
        match = hunk_re.match(lines[i])
        assert match, f"Unexpected non-hunk content in patch: {lines[i]!r}"
        saw_hunk = True
        old_start = int(match.group(1))
        old_count = int(match.group(2) or "1")
        new_count = int(match.group(4) or "1")
        expected_pos = old_start - 1 if old_start else 0
        assert expected_pos >= source_pos, "Patch hunks overlap or are out of order."
        output.extend(source[source_pos:expected_pos])
        source_pos = expected_pos
        i += 1
        consumed_old = 0
        produced_new = 0

        while i < len(lines) and not lines[i].startswith("@@ "):
            line = lines[i]
            assert line and line[0] in " +-", f"Invalid unified-diff line: {line!r}"
            marker, payload = line[0], line[1:]
            if marker == " ":
                assert source_pos < len(source) and source[source_pos] == payload, "Patch context does not match the original router.sh."
                output.append(payload)
                source_pos += 1
                consumed_old += 1
                produced_new += 1
            elif marker == "-":
                assert source_pos < len(source) and source[source_pos] == payload, "Patch deletion does not match the original router.sh."
                source_pos += 1
                consumed_old += 1
            else:
                output.append(payload)
                produced_new += 1
            i += 1

        assert consumed_old == old_count, "Patch hunk has an incorrect old-line count."
        assert produced_new == new_count, "Patch hunk has an incorrect new-line count."

    assert saw_hunk, "Patch contains no changes."
    output.extend(source[source_pos:])
    return b"".join(part.encode() for part in output)


def test_patch_file_exists_and_valid():
    assert os.path.isfile(PATCH_FILE), f"Patch file {PATCH_FILE} was not created."

    with open(PATCH_FILE, "r") as f:
        content = f.read()

    assert "---" in content and "+++" in content, f"Patch file {PATCH_FILE} does not look like a valid unified diff."
    assert "router.sh" in content, f"Patch file {PATCH_FILE} does not seem to contain changes for router.sh."
    assert os.path.isfile(ROUTER), f"Router {ROUTER} is missing."
    with open(ROUTER, "rb") as f:
        current_router = f.read()
    patched = apply_unified_diff(ORIGINAL_ROUTER, content)
    assert patched == current_router, "router.patch does not transform the original broken router.sh into the submitted router.sh."


def test_test_script_is_unmodified_and_passes():
    assert os.path.isfile(TEST_SCRIPT), f"Test script {TEST_SCRIPT} is missing."
    with open(TEST_SCRIPT, "rb") as f:
        actual = f.read()
    assert actual == EXPECTED_TEST_SCRIPT, "test.sh was modified; the instruction explicitly forbids this."

    result = subprocess.run(
        [TEST_SCRIPT],
        cwd=APP_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    assert result.returncode == 0, f"test.sh failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert "All tests passed." in result.stdout, f"test.sh did not print 'All tests passed.'.\nOutput: {result.stdout}"


def test_router_extracts_target_in_every_position():
    assert os.path.isfile(ROUTER), f"Router {ROUTER} is missing."
    assert os.access(ROUTER, os.X_OK), f"Router {ROUTER} is not executable."

    for _ in range(20):
        target = str(secrets.randbelow(900000000) + 100000000)
        nonce = secrets.token_hex(8)
        cases = [
            f"target={target}&dummy={nonce}&foo=bar",
            f"dummy={nonce}&target={target}&foo=bar",
            f"dummy={nonce}&foo=bar&target={target}",
        ]
        for query in cases:
            result = subprocess.run(
                [ROUTER, f"/api/migrate?{query}"],
                cwd=APP_DIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5,
            )
            assert result.returncode == 0, f"router.sh failed for query {query!r}: {result.stderr}"
            assert result.stdout.strip() == f"Migrating to schema {target}", (
                f"router.sh extracted the wrong target for {query!r}. Got: {result.stdout!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
