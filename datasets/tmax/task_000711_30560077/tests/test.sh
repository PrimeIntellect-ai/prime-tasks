#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import string
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

VERIFIER_PATH = "/home/user/verifier"
SOURCE_PATH = "/home/user/verifier.c"
CJSON_DIR = "/app/cJSON-1.7.17"
LIBRARY_PATH = os.path.join(CJSON_DIR, "libcjson.a")
MAKEFILE_PATH = os.path.join(CJSON_DIR, "Makefile")
EVIL_CORPUS_DIR = "/home/user/corpus/evil"
CLEAN_CORPUS_DIR = "/home/user/corpus/clean"


def test_verifier_exists_and_executable():
    assert os.path.isfile(VERIFIER_PATH), f"Verifier executable not found at {VERIFIER_PATH}"
    assert os.access(VERIFIER_PATH, os.X_OK), f"Verifier at {VERIFIER_PATH} is not executable"
    with open(VERIFIER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Verifier must be a compiled native executable"


def test_verifier_adversarial_corpus():
    if not os.path.isfile(VERIFIER_PATH) or not os.access(VERIFIER_PATH, os.X_OK):
        pytest.fail("Verifier executable is missing or not executable.")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    for evil_file in evil_files:
        file_path = os.path.join(EVIL_CORPUS_DIR, evil_file)
        result = subprocess.run([VERIFIER_PATH, file_path], capture_output=True, text=True)

        stdout = result.stdout.strip()
        if result.returncode != 1 or stdout != "REJECT":
            evil_bypassed.append((evil_file, result.returncode, stdout))

    clean_rejected = []
    for clean_file in clean_files:
        file_path = os.path.join(CLEAN_CORPUS_DIR, clean_file)
        result = subprocess.run([VERIFIER_PATH, file_path], capture_output=True, text=True)

        stdout = result.stdout.strip()
        if result.returncode != 0 or stdout != "ACCEPT":
            clean_rejected.append((clean_file, result.returncode, stdout))

    error_messages = []
    if evil_bypassed:
        bypassed_names = [x[0] for x in evil_bypassed]
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {bypassed_names}")

    if clean_rejected:
        rejected_names = [x[0] for x in clean_rejected]
        error_messages.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified/rejected: {rejected_names}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


@pytest.fixture(scope="session")
def rebuilt_verifier():
    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    assert os.path.isfile(MAKEFILE_PATH), "Vendored Makefile is missing"
    assert os.path.isfile(LIBRARY_PATH), "libcjson.a was not built"

    source = Path(SOURCE_PATH).read_text(errors="replace")
    makefile = Path(MAKEFILE_PATH).read_text(errors="replace")
    assert "broken-gcc-compiler" not in makefile, "The deliberate Makefile perturbation remains"
    assert re.search(r"\bcJSON_Parse\s*\(", source), "verifier.c does not call cJSON_Parse"
    assert re.search(r"\bfopen\s*\(", source), "verifier.c does not use standard C file I/O"

    archive = subprocess.run(
        ["ar", "t", LIBRARY_PATH], capture_output=True, text=True, timeout=15
    )
    assert archive.returncode == 0, f"libcjson.a is not a valid archive: {archive.stderr}"
    assert any("cJSON" in member for member in archive.stdout.splitlines()), "libcjson.a lacks cJSON objects"

    build = subprocess.run(
        ["make", "-B", "libcjson.a"], cwd=CJSON_DIR,
        capture_output=True, text=True, timeout=60
    )
    assert build.returncode == 0, f"The repaired Makefile cannot build libcjson.a:\n{build.stdout}\n{build.stderr}"

    output = os.path.join(tempfile.mkdtemp(prefix="rebuilt_cfgcheck_"), "program")
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-I", CJSON_DIR, SOURCE_PATH, LIBRARY_PATH, "-lm", "-o", output],
        capture_output=True, text=True, timeout=60
    )
    assert compile_result.returncode == 0, (
        "verifier.c cannot be linked against the built libcjson.a:\n"
        + compile_result.stdout + compile_result.stderr
    )

    symbols = subprocess.run(["nm", output], capture_output=True, text=True, timeout=15)
    assert symbols.returncode == 0
    assert re.search(r"\b[Tt]\s+cJSON_Parse$", symbols.stdout, re.MULTILINE), (
        "The rebuilt verifier does not contain the statically linked cJSON_Parse implementation"
    )
    return output


def test_source_makefile_and_static_library(rebuilt_verifier):
    assert os.path.isfile(rebuilt_verifier)
    assert os.access(rebuilt_verifier, os.X_OK)


def contains_forbidden(value):
    if isinstance(value, dict):
        return "exec_cmd" in value or any(contains_forbidden(v) for v in value.values())
    if isinstance(value, list):
        return any(contains_forbidden(v) for v in value)
    return False


def random_clean_value(rng, depth=0):
    if depth >= 5:
        return rng.choice([None, True, False, rng.randint(-100000, 100000), "text-" + secrets.token_hex(4)])
    kind = rng.randrange(6)
    if kind == 0:
        return None
    if kind == 1:
        return rng.choice([True, False])
    if kind == 2:
        return rng.randint(-1000000, 1000000)
    if kind == 3:
        return "value-" + ''.join(rng.choice(string.ascii_letters) for _ in range(12))
    if kind == 4:
        return [random_clean_value(rng, depth + 1) for _ in range(rng.randrange(5))]
    return {
        "key_" + secrets.token_hex(4): random_clean_value(rng, depth + 1)
        for _ in range(rng.randrange(5))
    }


def run_case(executable, path, expected_code, expected_stdout):
    result = subprocess.run(
        [executable, path], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == expected_code, (
        f"{executable} returned {result.returncode} for {path}; expected {expected_code}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_stdout, (
        f"{executable} printed {result.stdout!r} for {path}; expected {expected_stdout!r}"
    )


def test_runtime_generated_hidden_corpus(rebuilt_verifier):
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    root = tempfile.mkdtemp(prefix="cfg_inputs_" + secrets.token_hex(8) + "_")
    cases = []

    # Valid files whose expected answer is derived from their parsed JSON tree.
    values = [
        None, True, False, 0, "exec_cmd", [], {},
        {"Exec_cmd": 1, "exec_cmd_suffix": 2, "nested": {"safe": "exec_cmd"}},
        {"level": [{"deeper": [{"still_safe": True}]}]},
        {"exec_cmd": None},
        {"outer": {"middle": {"exec_cmd": "run"}}},
        [{"safe": 1}, [{"exec_cmd": {"anything": True}}]],
    ]
    for _ in range(45):
        values.append(random_clean_value(rng))
    for i in range(35):
        depth = rng.randrange(1, 18)
        node = {"exec_cmd": "payload-" + secrets.token_hex(5)}
        for level in range(depth):
            node = ([node, {"safe": level}] if rng.choice([True, False])
                    else {"layer_" + secrets.token_hex(3): node})
        values.append(node)

    for value in values:
        path = os.path.join(root, uuid.uuid4().hex + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(value, f, ensure_ascii=True, separators=(",", ":"))
        with open(path, encoding="utf-8") as f:
            parsed = json.load(f)
        reject = contains_forbidden(parsed)
        cases.append((path, 1 if reject else 0, "REJECT" if reject else "ACCEPT"))

    malformed_payloads = [
        "", "{", "[1,}", '{"a":}', '{"a":"unterminated}',
        '{"a":"bad\\xescape"}', "tru", '{"nested":[1,2,3}',
    ]
    for payload in malformed_payloads:
        path = os.path.join(root, uuid.uuid4().hex + ".json")
        Path(path).write_text(payload)
        cases.append((path, 1, "REJECT"))

    rng.shuffle(cases)
    for executable in (VERIFIER_PATH, rebuilt_verifier):
        for path, code, output in cases:
            run_case(executable, os.path.abspath(path), code, output)

        missing = os.path.join(root, uuid.uuid4().hex + ".json")
        run_case(executable, os.path.abspath(missing), 1, "REJECT")


def test_exactly_one_argument(rebuilt_verifier):
    for executable in (VERIFIER_PATH, rebuilt_verifier):
        no_args = subprocess.run([executable], capture_output=True, text=True, timeout=5)
        assert no_args.returncode != 0, "Verifier accepted a call with no path argument"
        extra_args = subprocess.run(
            [executable, "/definitely/missing/one.json", "/definitely/missing/two.json"],
            capture_output=True, text=True, timeout=5
        )
        assert extra_args.returncode != 0, "Verifier accepted more than one path argument"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
