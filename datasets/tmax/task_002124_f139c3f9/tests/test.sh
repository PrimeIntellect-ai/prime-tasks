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
import tempfile
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import pytest

FILTER_SCRIPT = "/home/user/api_filter.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def test_filter_script_exists_and_executable():
    assert os.path.exists(FILTER_SCRIPT), f"Missing filter script at {FILTER_SCRIPT}"
    assert os.path.isfile(FILTER_SCRIPT), f"{FILTER_SCRIPT} is not a file"
    assert os.access(FILTER_SCRIPT, os.X_OK), f"Filter script at {FILTER_SCRIPT} is not executable"


def run_filter(file_path: str) -> list[str]:
    result = subprocess.run(
        [FILTER_SCRIPT, file_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Script failed on {file_path} with stderr: {result.stderr}"
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def test_clean_corpus_accepted():
    clean_files = list(Path(CLEAN_CORPUS_DIR).glob("*.txt"))
    assert len(clean_files) > 0, f"No clean corpus files found in {CLEAN_CORPUS_DIR}"

    bypassed = []
    total_clean = 0

    for clean_file in clean_files:
        with open(clean_file, "r") as f:
            lines = [line.strip() for line in f if line.strip()]

        total_clean += len(lines)
        output_lines = run_filter(str(clean_file))
        assert len(output_lines) == len(lines), f"Output line count mismatch for {clean_file.name}"

        for url, out in zip(lines, output_lines):
            if not out.startswith("ACCEPT:"):
                bypassed.append(url)
            assert out == f"ACCEPT: {url}", f"Output must echo the exact URL: {out!r}"

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {total_clean} clean modified/rejected. Offending URLs: {bypassed[:5]}")


def test_evil_corpus_rejected():
    evil_files = list(Path(EVIL_CORPUS_DIR).glob("*.txt"))
    assert len(evil_files) > 0, f"No evil corpus files found in {EVIL_CORPUS_DIR}"

    bypassed = []
    total_evil = 0

    for evil_file in evil_files:
        with open(evil_file, "r") as f:
            lines = [line.strip() for line in f if line.strip()]

        total_evil += len(lines)
        output_lines = run_filter(str(evil_file))
        assert len(output_lines) == len(lines), f"Output line count mismatch for {evil_file.name}"

        for url, out in zip(lines, output_lines):
            if not out.startswith("REJECT:"):
                bypassed.append(url)
            assert out == f"REJECT: {url}", f"Output must echo the exact URL: {out!r}"

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {total_evil} evil bypassed. Offending URLs: {bypassed[:5]}")


def structured_depth(value):
    if isinstance(value, dict):
        return 1 + max((structured_depth(v) for v in value.values()), default=0)
    if isinstance(value, list):
        return 1 + max((structured_depth(v) for v in value), default=0)
    return 0


def expected_decision(url: str) -> str:
    try:
        params = parse_qs(urlsplit(url).query, keep_blank_values=True)
        if set(params) != {"id", "config"}:
            return "REJECT"
        if len(params["id"]) != 1 or len(params["config"]) != 1:
            return "REJECT"
        if re.fullmatch(r"[0-9a-fA-F]{16}", params["id"][0]) is None:
            return "REJECT"
        data = json.loads(params["config"][0])
        if structured_depth(data) > 3:
            return "REJECT"
        return "ACCEPT"
    except (ValueError, TypeError, json.JSONDecodeError):
        return "REJECT"


def test_randomized_mixed_file_is_parsed_and_exactly_echoed():
    candidates = []
    for _ in range(10):
        ident = secrets.token_hex(8)
        n = secrets.randbelow(900) + 1
        candidates.append(f"/api/v1/data?id={ident}&config={{\"timeout\":{n}}}")
        candidates.append(
            f"/api/v1/auth?config={{\"nested\":{{\"level1\":{{\"level2\":\"ok{n}\"}}}}}}&id={ident}"
        )
        candidates.append(f"/api/v1/data?id={ident[:-1]}z&config={{\"timeout\":{n}}}")
        candidates.append(f"/api/v1/data?id={ident[:-1]}&config={{\"timeout\":{n}}}")
        candidates.append(
            f"/api/v1/data?id={ident}&config={{\"a\":{{\"b\":{{\"c\":{{\"d\":{n}}}}}}}}"
        )
        candidates.append(f"/api/v1/data?id={ident}&config={{\"timeout\":{n}")
        candidates.append(f"/api/v1/data?id={ident}&id={secrets.token_hex(8)}&config={{\"timeout\":{n}}}")
        candidates.append(
            f"/api/v1/data?id={ident}&config={{\"timeout\":{n}}}&config={{\"timeout\":{n + 1}}}"
        )

    random.SystemRandom().shuffle(candidates)
    expected = [f"{expected_decision(url)}: {url}" for url in candidates]
    assert any(line.startswith("ACCEPT: ") for line in expected)
    assert any(line.startswith("REJECT: ") for line in expected)

    fd, input_path = tempfile.mkstemp(prefix="routing_requests_", suffix=".data")
    try:
        with os.fdopen(fd, "w") as f:
            for url in candidates:
                f.write(url + "\n")

        result = subprocess.run(
            [FILTER_SCRIPT, input_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"Script failed with stderr: {result.stderr}"
        assert result.stderr == "", f"Unexpected stderr: {result.stderr!r}"
        assert result.stdout.splitlines() == expected
    finally:
        os.unlink(input_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
