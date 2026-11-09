#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import string
import subprocess
import tempfile

import pytest

FILTER_SOURCE = "/home/user/json_filter.cpp"
FILTER_BINARY = "/home/user/json_filter"
JSON11_CPP = "/app/vendor/json11/json11.cpp"
JSON11_INCLUDE = "/app/vendor/json11"


def run_filter(binary, path):
    return subprocess.run([binary, path], capture_output=True, timeout=5).returncode


def compile_filter(output):
    attempts = [
        ["g++", "-std=c++11", "-O2", FILTER_SOURCE, "-o", output],
        ["g++", "-std=c++11", "-O2", "-I" + JSON11_INCLUDE,
         FILTER_SOURCE, JSON11_CPP, "-o", output],
    ]
    errors = []
    for command in attempts:
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode == 0:
            return
        errors.append(result.stderr)
    pytest.fail("json_filter.cpp did not compile as C++:\n" + "\n".join(errors))


def test_json_filter_adversarial_corpus():
    # Preserve the original corpus assertions.
    assert os.path.isfile(FILTER_BINARY), f"Executable {FILTER_BINARY} not found."
    assert os.access(FILTER_BINARY, os.X_OK), f"{FILTER_BINARY} is not executable."
    assert os.path.isfile(FILTER_SOURCE), f"C++ source {FILTER_SOURCE} not found."

    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".json")]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".json")]
    assert evil_files, f"No JSON files found in {evil_dir}"
    assert clean_files, f"No JSON files found in {clean_dir}"

    for path in evil_files:
        assert run_filter(FILTER_BINARY, path) == 1, f"Evil payload was accepted: {path}"
    for path in clean_files:
        assert run_filter(FILTER_BINARY, path) == 0, f"Clean payload was rejected: {path}"

    # Compile the submitted source and exercise both that build and the installed artifact
    # on randomized paths and payload contents.
    token = "".join(random.SystemRandom().choices(string.ascii_letters + string.digits, k=24))
    evil_payloads = [
        f'[{random.randint(1000, 999999)}, "{token}",]',
        f'[true, null, {{"tag":"{token}"}},   ]',
        f'{{"outer": [{{"id":"{token}"}},], "enabled": true}}',
        f'[[1, 2,], ["{token}"], 7]',
        f'["comma and bracket inside a string: ,] {token}", 3,\n\t]',
    ]
    clean_payloads = [
        json.dumps({"tag": token, "values": [1, 2, 3], "enabled": True}),
        json.dumps(["literal ,] is harmless " + token, {"nested": [False, None, 4.5]}]),
        "  [ ]  ",
        json.dumps({"outer": [{"id": token}], "tail": token[::-1]}),
        json.dumps([random.randint(1, 1000000), token, [1, 2, 3]]),
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "json_filter_rebuilt")
        compile_filter(rebuilt)
        cases = []
        for expected, payloads in ((1, evil_payloads), (0, clean_payloads)):
            for index, payload in enumerate(payloads):
                path = os.path.join(tmpdir, f"{token}_{random.randrange(1 << 30)}_{index}.json")
                with open(path, "w") as handle:
                    handle.write(payload)
                cases.append((path, expected))

        for binary in (FILTER_BINARY, rebuilt):
            for path, expected in cases:
                actual = run_filter(binary, path)
                assert actual == expected, (
                    f"{binary} returned {actual}, expected {expected}, for payload {path}"
                )


def test_memory_leak_fixed_and_parser_still_works():
    assert os.path.isfile(JSON11_CPP), f"{JSON11_CPP} is missing."

    evil_dir = "/app/corpora/evil"
    original_evil = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".json")]
    assert original_evil, "No evil corpus files found to test memory leak."

    token = "".join(random.SystemRandom().choices(string.ascii_letters + string.digits, k=25))
    number = random.randint(10000, 9999999)
    valid_object = json.dumps({"marker": token, "number": number, "items": [1, 2, 3]})
    valid_array = json.dumps([token[::-1], number + 1, {"ok": True}])

    malformed = [
        f'[{number}, "{token}",]',
        f'[{{"marker":"{token}"}}, null, ]',
        f'{{"data": [1, 2, 3,], "marker":"{token}"}}',
        f'[["{token}",], 9]',
    ]

    # Besides requiring errors for several trailing-comma forms, verify successful parsing
    # and semantic values so Json::parse cannot simply return immediately for every input.
    harness_code = f'''\
#include "json11.hpp"
#include <fstream>
#include <sstream>
#include <string>
using json11::Json;

static std::string read_file(const char *path) {{
    std::ifstream input(path);
    if (!input) return std::string();
    std::stringstream buffer;
    buffer << input.rdbuf();
    return buffer.str();
}}

int main(int argc, char **argv) {{
    if (argc < 2) return 20;
    for (int i = 1; i < argc; ++i) {{
        std::string err;
        Json parsed = Json::parse(read_file(argv[i]), err);
        if (err.empty()) return 21;
    }}

    std::string err;
    Json object = Json::parse({json.dumps(valid_object)}, err);
    if (!err.empty()) return 22;
    if (object["marker"].string_value() != {json.dumps(token)}) return 23;
    if (object["number"].int_value() != {number}) return 24;
    if (object["items"].array_items().size() != 3) return 25;

    err.clear();
    Json array = Json::parse({json.dumps(valid_array)}, err);
    if (!err.empty()) return 26;
    if (array.array_items().size() != 3) return 27;
    if (array[0].string_value() != {json.dumps(token[::-1])}) return 28;
    if (array[1].int_value() != {number + 1}) return 29;
    if (!array[2]["ok"].bool_value()) return 30;
    return 0;
}}
'''

    with tempfile.TemporaryDirectory() as tmpdir:
        generated_evil = []
        for index, payload in enumerate(malformed):
            path = os.path.join(tmpdir, f"malformed_{token}_{index}.json")
            with open(path, "w") as handle:
                handle.write(payload)
            generated_evil.append(path)

        harness_path = os.path.join(tmpdir, "harness.cpp")
        with open(harness_path, "w") as handle:
            handle.write(harness_code)

        executable = os.path.join(tmpdir, "harness")
        compile_command = [
            "g++", "-std=c++11", "-I" + JSON11_INCLUDE,
            JSON11_CPP, harness_path, "-o", executable,
        ]
        result = subprocess.run(compile_command, capture_output=True, text=True)
        assert result.returncode == 0, (
            f"Failed to compile test harness with user's json11.cpp: {result.stderr}"
        )

        tested_payloads = original_evil + generated_evil
        direct = subprocess.run([executable] + tested_payloads, capture_output=True, text=True)
        assert direct.returncode == 0, (
            f"json11 parser did not report malformed inputs correctly or no longer parses "
            f"valid JSON (exit {direct.returncode})."
        )

        valgrind_command = [
            "valgrind", "--leak-check=full", "--show-leak-kinds=definite",
            "--errors-for-leak-kinds=definite", "--error-exitcode=1",
            executable,
        ] + tested_payloads
        result = subprocess.run(valgrind_command, capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, (
            "Memory leak detected, malformed input was not rejected, or valid parsing was "
            f"broken:\n{result.stderr}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
