#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import subprocess
from decimal import Decimal

import pytest

VENDOR = "/app/vendored/tiny-json-lines"
AGENT = "/home/user/mask_loc"


def run_checked(cmd, **kwargs):
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30, **kwargs)
    assert proc.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    return proc


def test_vendored_lib_built_and_unicode_patch_works():
    makefile = os.path.join(VENDOR, "Makefile")
    assert os.path.isfile(makefile), "Vendored Makefile is missing."
    with open(makefile, encoding="utf-8") as f:
        content = f.read()
    assert re.search(r"-std=(?:c|gnu)\+\+17(?:\s|$)", content), \
        "Vendored library is not configured for C++17."
    assert "-std=c++11" not in content, "Obsolete C++11 flag remains."

    for name in ("parser.o", "libtinyjson.a"):
        try:
            os.remove(os.path.join(VENDOR, name))
        except FileNotFoundError:
            pass
    run_checked(["make", "-C", VENDOR])

    archive = os.path.join(VENDOR, "libtinyjson.a")
    assert os.path.isfile(archive), "libtinyjson.a was not built."

    harness = r'''
#include <iostream>
#include <string>
std::string parse_string(const std::string&);
int main() {
    if (parse_string(R"(\u00A9)") != std::string("\xC2\xA9")) return 1;
    if (parse_string(R"(A\u20ACZ)") != std::string("A\xE2\x82\xACZ")) return 2;
    if (parse_string(R"(\uD83D\uDE03)") != std::string("\xF0\x9F\x98\x83")) return 3;
    std::cout << parse_string(R"(x\u00A9\u20ACy)");
}
'''
    with open("/tmp/parser_harness.cpp", "w", encoding="utf-8") as f:
        f.write(harness)
    run_checked([
        "g++", "-std=c++17", "/tmp/parser_harness.cpp", archive,
        "-o", "/tmp/parser_harness"
    ])
    proc = run_checked(["/tmp/parser_harness"])
    assert proc.stdout == "x©€y", "Vendored parser did not produce correct UTF-8."


def test_makefile_exists_and_builds_cpp_tool():
    makefile_path = "/home/user/Makefile"
    assert os.path.isfile(makefile_path), "Makefile does not exist in /home/user."
    with open(makefile_path, encoding="utf-8") as f:
        content = f.read()
    assert "build:" in content, "Makefile missing 'build' target."
    assert "run:" in content, "Makefile missing 'run' target."
    assert "libtinyjson.a" in content or "tiny-json-lines" in content, \
        "Build target does not link the vendored library."
    assert os.path.isfile("/home/user/mask_loc.cpp"), "mask_loc.cpp is missing."

    try:
        os.remove(AGENT)
    except FileNotFoundError:
        pass
    run_checked(["make", "-C", "/home/user", "build"])


def test_agent_binary_exists():
    assert os.path.isfile(AGENT), "mask_loc binary was not compiled."
    assert os.access(AGENT, os.X_OK), "mask_loc is not executable."
    with open(AGENT, "rb") as f:
        assert f.read(4) == b"\x7fELF", "mask_loc is not a compiled executable."


def expected_mask(user_id):
    return (user_id * 6364136223846793005 + 1442695040888963407) % (2**32)


def assert_output(raw, obj):
    assert not raw.endswith("\n"), "Output must not have a trailing newline."
    number = r"(-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)"
    pattern = (
        r'^\{"confidence_score": ' + number
        + r', "loc_key": "' + re.escape(obj["loc_key"])
        + r'", "masked_id": ' + str(expected_mask(obj["user_id"]))
        + r', "text": "' + re.escape(obj["text"]) + r'"\}$'
    )
    match = re.fullmatch(pattern, raw)
    assert match is not None, f"Incorrect JSON formatting or values: {raw!r}"

    expected_score = Decimal(math.floor(obj["confidence_score"] * 10)) / Decimal(10)
    assert Decimal(match.group(1)) == expected_score, (
        f"Incorrect confidence score: expected {expected_score}, got {match.group(1)}"
    )


def invoke(obj):
    input_json = json.dumps(obj, ensure_ascii=True, separators=(",", ":"))
    proc = subprocess.run(
        [AGENT], input=input_json, text=True, capture_output=True, timeout=5
    )
    assert proc.returncode == 0, (
        f"Agent failed on {input_json}\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
    )
    assert proc.stderr == "", f"Agent wrote unexpected stderr: {proc.stderr}"
    assert_output(proc.stdout, obj)


def test_required_transformations_and_unicode_fuzz():
    directed = [
        {"loc_key": "copyright_©", "text": "Cost €20", "user_id": 12345,
         "confidence_score": 0.95},
        {"loc_key": "emoji_😃", "text": "日本語 Ω", "user_id": 0,
         "confidence_score": 0.89},
        {"loc_key": "maximum", "text": "©€😃", "user_id": 2**64 - 1,
         "confidence_score": 0.0},
    ]
    for obj in directed:
        invoke(obj)

    random.seed(42)
    ascii_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-./"
    unicode_ranges = [(0x00A0, 0x07FF), (0x0800, 0xD7FF), (0xE000, 0x27FF),
                      (0x1F300, 0x1F64F)]

    def random_string():
        chars = []
        for _ in range(random.randint(5, 20)):
            if random.random() < 0.5:
                chars.append(random.choice(ascii_chars))
            else:
                lo, hi = random.choice(unicode_ranges)
                chars.append(chr(random.randint(lo, hi)))
        return "".join(chars)

    for _ in range(1000):
        invoke({
            "loc_key": random_string(),
            "text": random_string(),
            "user_id": random.randint(0, 2**64 - 1),
            "confidence_score": random.random(),
        })


def test_run_target_processes_input_file():
    obj = {
        "loc_key": "run_©",
        "text": "pipeline € 😃",
        "user_id": 987654321,
        "confidence_score": 0.76,
    }
    input_path = "/home/user/input.jsonl"
    output_path = "/home/user/output.jsonl"
    with open(input_path, "w", encoding="ascii") as f:
        f.write(json.dumps(obj, ensure_ascii=True, separators=(",", ":")))
    try:
        os.remove(output_path)
    except FileNotFoundError:
        pass

    run_checked(["make", "-C", "/home/user", "run"])
    assert os.path.isfile(output_path), "run target did not create output.jsonl."
    with open(output_path, encoding="utf-8", newline="") as f:
        assert_output(f.read(), obj)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
