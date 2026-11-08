#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

BINARY = "/home/user/deploy/bin/waf_analyzer"
LIBRARY = "/home/user/deploy/lib/libwafparser.so"
RESULTS = "/home/user/deploy/analysis_results.log"
REQUESTS = "/home/user/waf_project/requests.log"
CLEAN_ENV = {"PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", "LC_ALL": "C"}

EXPECTED_ORIGINAL = [
    'ALLOWED: GET /index.html HTTP/1.1',
    'BLOCKED: POST /login HTTP/1.1 payload="admin\' OR 1=1 --"',
    'BLOCKED: GET /search?q=<script>alert(1)</script> HTTP/1.1',
    'ALLOWED: GET /about HTTP/1.1',
    'BLOCKED: POST /api/data HTTP/1.1 payload="DROP TABLE users;"',
]


def readelf(*args):
    return subprocess.check_output(["readelf", *args], text=True, env=CLEAN_ENV)


def test_deployment_structure():
    assert os.path.exists(BINARY), "waf_analyzer executable is missing in /home/user/deploy/bin/"
    assert os.path.exists(LIBRARY), "libwafparser.so is missing in /home/user/deploy/lib/"
    assert os.access(BINARY, os.X_OK), "waf_analyzer is not executable"

    binary_header = readelf("-h", BINARY)
    library_header = readelf("-h", LIBRARY)
    assert "ELF Header:" in binary_header
    assert re.search(r"^\s*Type:\s+(EXEC|DYN)\b", binary_header, re.MULTILINE), "waf_analyzer is not an ELF executable"
    assert re.search(r"^\s*Type:\s+DYN\b", library_header, re.MULTILINE), "libwafparser.so is not an ELF shared object"


def test_rpath_configuration_and_linkage():
    dynamic = readelf("-d", BINARY)
    paths = re.findall(r"\((?:RPATH|RUNPATH)\).*?\[([^]]*)\]", dynamic)
    assert paths == ["$ORIGIN/../lib"], "waf_analyzer does not have exactly one RPATH/RUNPATH equal to '$ORIGIN/../lib'"

    needed = re.findall(r"\(NEEDED\).*?\[([^]]+)\]", dynamic)
    assert "libwafparser.so" in needed, "waf_analyzer is not dynamically linked against libwafparser.so"

    ldd_output = subprocess.check_output(["ldd", BINARY], text=True, env=CLEAN_ENV)
    match = re.search(r"^\s*libwafparser\.so\s+=>\s+(\S+)", ldd_output, re.MULTILINE)
    assert match and match.group(1) != "not", "the dynamic loader cannot resolve libwafparser.so"
    assert os.path.realpath(match.group(1)) == os.path.realpath(LIBRARY), "waf_analyzer does not load the packaged libwafparser.so"


def test_packaged_library_contains_patched_parser_logic():
    token = secrets.token_hex(12)
    probe_source = r'''
#include <iostream>
#include <string>
#include <vector>

class PayloadParser {
public:
    PayloadParser();
    ~PayloadParser();
    bool analyze(const std::string& payload);
private:
    std::vector<std::string> signatures;
};

int main(int argc, char **argv) {
    PayloadParser parser;
    for (int i = 1; i < argc; ++i)
        std::cout << (parser.analyze(argv[i]) ? "1" : "0") << "\n";
    return 0;
}
'''
    samples = [
        "benign-" + token,
        "prefix DROP TABLE suffix-" + token,
        "prefix <script> suffix-" + token,
        "prefix UNION SELECT suffix-" + token,
        "prefix OR 1=1 suffix-" + token,
        "drop table-" + token,
        "UNION  SELECT-" + token,
    ]
    expected = ["0", "1", "1", "1", "1", "0", "0"]

    with tempfile.TemporaryDirectory() as td:
        source = os.path.join(td, "probe.cpp")
        probe = os.path.join(td, "probe")
        with open(source, "w") as f:
            f.write(probe_source)
        subprocess.check_call([
            "g++", "-std=c++11", source, "-L/home/user/deploy/lib",
            "-lwafparser", "-o", probe,
        ], env=CLEAN_ENV)
        probe_env = dict(CLEAN_ENV)
        probe_env["LD_LIBRARY_PATH"] = "/home/user/deploy/lib"
        completed = subprocess.run([probe, *samples], text=True, capture_output=True, env=probe_env, timeout=10)
        assert completed.returncode == 0, completed.stderr
        assert completed.stdout.splitlines() == expected, "the packaged library does not implement all patched signatures"


def test_analyzer_executes_with_relocated_library_on_derived_inputs():
    token = secrets.token_hex(16)
    lines = [
        "GET /safe/" + token + " HTTP/1.1",
        "POST /x/" + token + " payload=DROP TABLE accounts",
        "GET /x?q=<script>" + token + "</script> HTTP/1.1",
        "POST /x/" + token + " payload=UNION SELECT password",
        "POST /x/" + token + " payload=user OR 1=1",
        "GET /near/" + token + "?q=UNION%20SELECT HTTP/1.1",
    ]
    blocked = [False, True, True, True, True, False]
    expected = [("BLOCKED: " if is_blocked else "ALLOWED: ") + line for line, is_blocked in zip(lines, blocked)]

    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write("\n".join(lines) + "\n")
        input_path = f.name
    try:
        completed = subprocess.run(
            [BINARY, input_path], cwd="/home/user/deploy/bin", env=CLEAN_ENV,
            text=True, capture_output=True, timeout=10,
        )
        assert completed.returncode == 0, completed.stderr
        assert completed.stdout.splitlines() == expected, "waf_analyzer failed derived behavioral tests"
    finally:
        os.unlink(input_path)


def test_analysis_results():
    assert os.path.exists(RESULTS), f"{RESULTS} does not exist. Did you run the analyzer?"
    with open(RESULTS, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == EXPECTED_ORIGINAL, "The contents of analysis_results.log do not match the expected output. Ensure the patch was applied correctly and the binary was run against requests.log."

    completed = subprocess.run(
        [BINARY, REQUESTS], cwd="/home/user/deploy/bin", env=CLEAN_ENV,
        text=True, capture_output=True, timeout=10,
    )
    assert completed.returncode == 0, completed.stderr
    assert completed.stdout.splitlines() == EXPECTED_ORIGINAL, "executing the deployed analyzer does not reproduce analysis_results.log"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
