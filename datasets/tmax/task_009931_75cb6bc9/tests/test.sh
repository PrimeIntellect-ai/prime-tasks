#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import secrets
import subprocess

GO_FILE = "/home/user/suspicious_parser.go"
PAYLOAD_FILE = "/home/user/payload.txt"
BINARY = "/tmp/suspicious_parser"


def build(source, output):
    result = subprocess.run(
        ["go", "build", "-o", output, source],
        capture_output=True,
        text=True,
        env={**os.environ, "CGO_ENABLED": "1"},
    )
    assert result.returncode == 0, f"Go compilation failed:\n{result.stderr}"


def function_body(source, name):
    match = re.search(r"\bfunc\s+" + re.escape(name) + r"\s*\([^)]*\)\s*\{", source)
    assert match, f"Required function {name} was not found."
    start = source.find("{", match.start())
    depth = 0
    for i in range(start, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:i]
    raise AssertionError(f"Could not parse function {name}.")


def test_report_exists_and_correct():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} was not created."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {report_path}, found {len(lines)}."

    expected_path = "/tmp/telemetry_BBCD.sock"
    expected_payload = "BBCDEVGH"

    assert lines[0] == expected_path, f"Line 1: Expected '{expected_path}', got '{lines[0]}'."
    assert lines[1] == expected_payload, f"Line 2: Expected '{expected_payload}', got '{lines[1]}'."


def test_required_source_repairs_are_present():
    assert os.path.isfile(GO_FILE), f"Source file {GO_FILE} is missing."
    source = open(GO_FILE, "r").read()

    cgo_lines = [line.strip().split() for line in source.splitlines()
                 if line.strip().startswith("#cgo") and "LDFLAGS:" in line]
    assert any("-lm" in tokens for tokens in cgo_lines), \
        "The source must include a #cgo LDFLAGS directive linking libm with -lm."

    walk = function_body(source, "walk")
    walk_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", walk, flags=re.S)
    assert not re.search(r"\bstep\s*=\s*0\b", walk_without_comments), \
        "walk still contains the zero-step recursion bug."
    progresses = re.search(
        r"\bwalk\s*\(\s*data\s*\[\s*(?:[1-9][0-9]*|step)\s*:\s*\]\s*\)",
        walk_without_comments,
    )
    assert progresses, "walk must continue traversing a strictly advancing data slice."


def test_dynamic_decoding_and_stat_behavior():
    source = open(GO_FILE, "r").read()

    # Exercise decodePayload directly on an unpadded value not known to the submission.
    plaintext = ("B" + secrets.token_hex(10)).encode("ascii")
    encoded = base64.b64encode(plaintext).decode("ascii").rstrip("=")
    instrumented, count = re.subn(
        r"\bfunc\s+main\s*\(\s*\)\s*\{",
        "func originalMain() {",
        source,
        count=1,
    )
    assert count == 1, "The Go source does not contain a main function."
    instrumented += f'\nfunc main() {{ os.Stdout.Write(decodePayload("{encoded}")) }}\n'
    instrumented_path = "/tmp/instrumented_parser.go"
    with open(instrumented_path, "w") as f:
        f.write(instrumented)
    build(instrumented_path, "/tmp/instrumented_parser")
    decoded = subprocess.run(
        ["/tmp/instrumented_parser"], capture_output=True, timeout=5
    )
    assert decoded.returncode == 0, decoded.stderr.decode(errors="replace")
    assert decoded.stdout == plaintext, \
        "decodePayload did not fully decode a randomized unpadded base64 payload."

    # Run the actual submitted program with a randomized payload beginning with B,
    # which both triggers the original walk bug and produces a derived stat path.
    prefix = "B" + secrets.token_hex(2)[:3]
    dynamic_plaintext = (prefix + secrets.token_hex(12)).encode("ascii")
    dynamic_encoded = base64.b64encode(dynamic_plaintext).rstrip(b"=")
    expected_path = f"/tmp/telemetry_{prefix}.sock"
    old_payload = open(PAYLOAD_FILE, "rb").read()
    trace_path = "/tmp/parser.strace"
    try:
        with open(PAYLOAD_FILE, "wb") as f:
            f.write(dynamic_encoded)
        result = subprocess.run(
            ["strace", "-f", "-e", "trace=file", "-o", trace_path, BINARY],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert result.returncode == 0, \
            f"Program failed or did not terminate on the triggering payload:\n{result.stderr}"
        trace = open(trace_path, "r", errors="replace").read()
        stat_call = re.search(
            r"\b(?:stat|lstat|statx|newfstatat)\([^\n]*\"" + re.escape(expected_path) + r"\"",
            trace,
        )
        assert stat_call, f"Program did not stat the derived path {expected_path}."
    finally:
        with open(PAYLOAD_FILE, "wb") as f:
            f.write(old_payload)


def test_go_code_compiles_and_runs():
    assert os.path.isfile(GO_FILE), f"Source file {GO_FILE} is missing."

    # Check if it compiles
    build(GO_FILE, BINARY)

    # Check if it runs without crashing (infinite recursion fixed)
    run_result = subprocess.run([BINARY], capture_output=True, text=True, timeout=5)
    assert run_result.returncode == 0, f"Program execution failed or crashed:\n{run_result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
