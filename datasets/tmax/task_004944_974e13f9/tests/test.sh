#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import secrets
import string
import subprocess

import pytest

MAKEFILE = "/app/cJSON-1.7.15/Makefile"
SOURCE = "/home/user/filter_pipelines.c"
BINARY = "/home/user/filter_pipelines"


def test_makefile_fixed():
    assert os.path.isfile(MAKEFILE), f"Makefile not found at {MAKEFILE}"
    with open(MAKEFILE, "r", errors="replace") as f:
        content = f.read()
    assert "broken-gcc" not in content, "The Makefile still contains 'broken-gcc'."


def test_cjson_library_was_built():
    candidates = []
    for pattern in ("**/libcjson.a", "**/libcjson.so", "**/libcjson.so.*"):
        candidates.extend(glob.glob(f"/app/cJSON-1.7.15/{pattern}", recursive=True))
    candidates = [p for p in candidates if os.path.isfile(p) and os.path.getsize(p) > 0]
    assert candidates, "No built cJSON library was found under /app/cJSON-1.7.15."


def test_c_source_exists_and_uses_cjson():
    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"
    with open(SOURCE, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"](?:[^>\"]*/)?cJSON\.h[>\"]", source), \
        "filter_pipelines.c does not include cJSON.h"
    assert re.search(r"\bcJSON_Parse(?:WithOpts|WithLength|WithLengthOpts)?\s*\(", source), \
        "filter_pipelines.c does not call a cJSON parsing function"


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"Compiled binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Binary at {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "filter_pipelines must be a compiled native executable"

    symbol_text = ""
    for command in (["nm", "-a", BINARY], ["readelf", "-Ws", BINARY]):
        result = subprocess.run(command, capture_output=True, text=True)
        symbol_text += result.stdout + result.stderr
    assert re.search(r"\bcJSON_Parse(?:WithOpts|WithLength|WithLengthOpts)?\b", symbol_text), \
        "The executable does not appear to be linked with and use cJSON"


def test_adversarial_corpus():
    clean_dir = "/home/user/corpora/clean"
    evil_dir = "/home/user/corpora/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_modified = []
    evil_bypassed = []

    for clean_file in clean_files:
        with open(clean_file, "rb") as f:
            input_data = f.read()
        result = subprocess.run([BINARY], input=input_data, capture_output=True, timeout=10)
        if result.returncode != 0 or result.stdout != input_data:
            clean_modified.append(os.path.basename(clean_file))

    for evil_file in evil_files:
        with open(evil_file, "rb") as f:
            input_data = f.read()
        result = subprocess.run([BINARY], input=input_data, capture_output=True, timeout=10)
        if result.returncode != 0 or result.stdout.strip() != b"":
            evil_bypassed.append(os.path.basename(evil_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def _token(prefix):
    return prefix + secrets.token_hex(10)


def _line(pipeline, prefix="q"):
    query_id = _token(prefix)
    collection = _token("collection_")
    if isinstance(pipeline, str):
        encoded = pipeline
    else:
        encoded = json.dumps(pipeline, separators=(",", ":"), ensure_ascii=True)
    return f"{query_id},{collection},{encoded}\n".encode()


def test_fresh_generated_mixed_inputs():
    # These IDs and rows are generated only when verification runs, so a filter
    # cannot pass by recognizing the corpora installed in the image.
    cases = []

    for _ in range(14):
        depth = secrets.randbelow(6)
        cases.append((_line([]), True))
        cases.append((_line([{"$match": {_token("field_"): _token("value_")}}]), True))
        cases.append((_line([
            {"$project": {_token("field_"): 1}},
            {"$graphLookup": {
                "from": _token("from_"),
                "startWith": "$parent",
                "connectFromField": "parent",
                "connectToField": "id",
                "as": _token("as_"),
                "maxDepth": depth,
            }},
        ]), True))

        cases.append((_line([{"$graphLookup": {"from": _token("from_")}}]), False))
        cases.append((_line([{"$graphLookup": {"maxDepth": 6 + secrets.randbelow(10000)}}]), False))
        cases.append((_line([{"$graphLookup": {"maxDepth": -(1 + secrets.randbelow(10000))}}]), False))
        cases.append((_line([{"$graphLookup": {"maxDepth": 1.5}}]), False))
        cases.append((_line([{"$graphLookup": {"maxDepth": str(depth)}}]), False))
        cases.append((_line([{"$graphLookup": {"maxDepth": None}}]), False))
        cases.append((_line([{"$graphLookup": {"maxDepth": True}}]), False))
        cases.append((_line([
            {"$graphLookup": {"maxDepth": depth}},
            {"$graphLookup": {"from": _token("second_")}},
        ]), False))
        cases.append((_line([{"$graphLookup": {"options": {"maxDepth": depth}}}]), False))

    # Syntactically malformed JSON must be rejected as well.
    malformed = [
        '[{"$graphLookup":{"maxDepth":3}}',
        '[{"$graphLookup":{"maxDepth":3}}] trailing',
        '[{"$graphLookup":{"maxDepth":}}]',
        '[{"$match":{"x":1}},]',
        'not-json-' + secrets.token_hex(8),
    ]
    for value in malformed:
        cases.append((_line(value, "malformed_"), False))

    random.SystemRandom().shuffle(cases)

    # Exercise multiple independently ordered streams and require exact,
    # unmodified output in original order.
    chunk_size = 23
    for start in range(0, len(cases), chunk_size):
        chunk = cases[start:start + chunk_size]
        input_data = b"".join(line for line, _ in chunk)
        expected = b"".join(line for line, valid in chunk if valid)
        result = subprocess.run([BINARY], input=input_data, capture_output=True, timeout=10)
        assert result.returncode == 0, f"filter exited with status {result.returncode}: {result.stderr!r}"
        assert result.stdout == expected, "filter produced incorrect output for freshly generated mixed rows"
        assert result.stderr == b"", "filter must silently drop invalid rows"


def test_preserves_valid_line_without_final_newline():
    pipeline = json.dumps([{"$graphLookup": {"from": _token("from_"), "maxDepth": secrets.randbelow(6)}}], separators=(",", ":"))
    row = f"{_token('q_')},{_token('collection_')},{pipeline}".encode()
    result = subprocess.run([BINARY], input=row, capture_output=True, timeout=10)
    assert result.returncode == 0
    assert result.stdout == row
    assert result.stderr == b""
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
