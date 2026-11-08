#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import textwrap
import uuid

import pytest

PROJECT = "/home/user/log_processor"
RAW_PATH = "/home/user/raw.log"
JSON_PATH = "/home/user/processed_logs.json"
PROCESSOR = os.path.join(PROJECT, "processor")
GO = "/usr/local/go/bin/go"

EXPECTED_LINES = [
    'INFO 2023-10-10 "System started successfully"',
    'WARN 2023-10-10 "High memory usage detected"',
    'ERROR 2023-10-10 "Failed to process filename with spaces unclosed quote',
    'INFO 2023-10-10 "Routine check"',
]


def expected_entries(lines):
    entries = []
    for line in lines:
        first = line.find('"')
        if first >= 0:
            second = line.find('"', first + 1)
            if second < 0:
                continue
            entries.append({"msg": line[first + 1:second], "raw": line})
        else:
            entries.append({"raw": line})
    return entries


EXPECTED_ENTRIES = expected_entries(EXPECTED_LINES)


def run(command, cwd=None, timeout=90):
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}"
    )
    return result


def load_json(path):
    with open(path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"The file {path} does not contain valid JSON: {exc}")


@pytest.fixture(scope="session", autouse=True)
def verifier_go_tests():
    name = f"verifier_{uuid.uuid4().hex}_test.go"
    path = os.path.join(PROJECT, name)
    source = r'''
package main

import "testing"

func TestVerifierParseLogLineValid(t *testing.T) {
    line := `INFO 2023-10-10 "message with spaces" trailing`
    got, err := ParseLogLine(line)
    if err != nil {
        t.Fatalf("valid line returned error: %v", err)
    }
    if got["raw"] != line {
        t.Fatalf("raw mismatch: got %q, want %q", got["raw"], line)
    }
    if got["msg"] != "message with spaces" {
        t.Fatalf("msg mismatch: got %q", got["msg"])
    }
}

func TestVerifierParseLogLineWithoutQuotes(t *testing.T) {
    line := "plain log line"
    got, err := ParseLogLine(line)
    if err != nil {
        t.Fatalf("unquoted line returned error: %v", err)
    }
    if got["raw"] != line {
        t.Fatalf("raw mismatch: got %q, want %q", got["raw"], line)
    }
}

func TestVerifierParseLogLineRejectsUnclosedQuotes(t *testing.T) {
    cases := []string{
        `ERROR "unterminated message with spaces`,
        `"`,
        `prefix "`,
        `unicode λ "still open`,
    }
    for _, line := range cases {
        func() {
            defer func() {
                if recovered := recover(); recovered != nil {
                    t.Fatalf("ParseLogLine panicked for %q: %v", line, recovered)
                }
            }()
            _, err := ParseLogLine(line)
            if err == nil {
                t.Fatalf("ParseLogLine(%q) returned nil error for an unclosed quote", line)
            }
        }()
    }
}

func TestVerifierParseLogLineEmpty(t *testing.T) {
    if _, err := ParseLogLine(""); err == nil {
        t.Fatal("empty line should return an error")
    }
}
'''
    with open(path, "x") as f:
        f.write(textwrap.dedent(source))
    try:
        yield
    finally:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def test_fuzz_test_exists():
    parser_test_path = "/home/user/log_processor/parser_test.go"
    assert os.path.isfile(parser_test_path), f"Fuzz test file {parser_test_path} is missing."

    with open(parser_test_path, "r") as f:
        content = f.read()

    assert "func Fuzz" in content, "The file parser_test.go does not contain a Fuzz test function ('func Fuzz')."


def test_processed_logs_json():
    assert os.path.isfile(JSON_PATH), f"Output JSON file {JSON_PATH} is missing."
    data = load_json(JSON_PATH)
    assert isinstance(data, list), "The JSON output should be a list of log entries."
    assert len(data) == 3, f"Expected exactly 3 valid log lines in JSON, but got {len(data)}."
    assert data == EXPECTED_ENTRIES, f"Parsed log contents are incorrect: {data!r}"


def test_go_mod_updated():
    go_mod_path = "/home/user/log_processor/go.mod"
    assert os.path.isfile(go_mod_path), f"The file {go_mod_path} is missing."

    with open(go_mod_path, "r") as f:
        content = f.read()

    assert "github.com/google/uuid v1.0.0" not in content, "The go.mod file still contains the outdated 'github.com/google/uuid v1.0.0' dependency. It must be updated."


def test_raw_input_is_the_provided_log():
    with open(RAW_PATH, "r") as f:
        lines = f.read().splitlines()
    assert lines == EXPECTED_LINES, "The provided raw.log input was modified."


def test_parse_log_line_and_fuzzer_execute():
    run([GO, "test", "./..."], cwd=PROJECT)
    run(
        [GO, "test", "-run", "^$", "-fuzz", "^FuzzParseLogLine$", "-fuzztime=2s"],
        cwd=PROJECT,
        timeout=120,
    )


def test_processor_artifact_and_fresh_build():
    assert os.path.isfile(PROCESSOR), "The processor artifact is missing."
    mode = os.stat(PROCESSOR).st_mode
    assert stat.S_ISREG(mode), "processor is not a regular file."
    assert mode & 0o111, "processor is not executable."
    with open(PROCESSOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "processor is not a compiled Linux executable."

    existing_output = f"/tmp/processor_existing_{uuid.uuid4().hex}.json"
    rebuilt_output = f"/tmp/processor_rebuilt_{uuid.uuid4().hex}.json"
    try:
        run([PROCESSOR, RAW_PATH, existing_output], cwd=PROJECT)
        assert load_json(existing_output) == EXPECTED_ENTRIES, "The submitted processor produced incorrect parsed entries."

        run([GO, "build", "-o", "processor", "."], cwd=PROJECT)
        run([PROCESSOR, RAW_PATH, rebuilt_output], cwd=PROJECT)
        assert load_json(rebuilt_output) == EXPECTED_ENTRIES, "The freshly built processor produced incorrect parsed entries."

        run([PROCESSOR, RAW_PATH, JSON_PATH], cwd=PROJECT)
        assert load_json(JSON_PATH) == EXPECTED_ENTRIES, "The required processor command produced incorrect output."
    finally:
        for path in (existing_output, rebuilt_output):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
