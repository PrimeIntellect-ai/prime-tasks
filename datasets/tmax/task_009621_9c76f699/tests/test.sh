#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import tempfile

import pytest

INGESTER = "/home/user/ingester"
BATCH = "/home/user/data/batch_491.log"
OUTPUT = "/home/user/output.json"
EXPECTED_CRASH_LINE = 'ts=2023-10-01T12:00:00Z ip=192.168.1.1 ua="Mozilla/5.0 \\"CrashMe\\"'


def parse_expected_line(line):
    fields = {}
    i = 0
    n = len(line)
    while i < n:
        while i < n and line[i] == " ":
            i += 1
        if i >= n:
            break

        eq = line.find("=", i)
        assert eq != -1, f"Malformed source line: {line!r}"
        key = line[i:eq]
        i = eq + 1

        if i < n and line[i] == '"':
            i += 1
            value = []
            while i < n:
                if line[i] == "\\" and i + 1 < n and line[i + 1] in ('"', "\\"):
                    value.append(line[i + 1])
                    i += 2
                elif line[i] == '"':
                    i += 1
                    break
                else:
                    value.append(line[i])
                    i += 1
            value = "".join(value)
        else:
            end = line.find(" ", i)
            if end == -1:
                value = line[i:]
                i = n
            else:
                value = line[i:end]
                i = end + 1
        fields[key] = value

    return {
        "timestamp": fields.get("ts", ""),
        "ip": fields.get("ip", ""),
        "user_agent": fields.get("ua", ""),
    }


def expected_records():
    with open(BATCH, "r", encoding="utf-8") as f:
        lines = [line.rstrip("\n") for line in f if line.rstrip("\n") != ""]
    assert len(lines) == 10000, f"Expected batch to contain 10,000 nonempty lines, got {len(lines)}"
    return [parse_expected_line(line) for line in lines]


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} does not contain valid JSON.")


def test_minimal_crash_log():
    log_path = "/home/user/minimal_crash.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == EXPECTED_CRASH_LINE, (
        f"minimal_crash.log does not contain the exact expected crash line. Got: {content}"
    )


def test_output_json_exists_and_valid():
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} is missing."
    data = load_json(OUTPUT)

    assert isinstance(data, list), f"Expected JSON array in {OUTPUT}, got {type(data).__name__}."
    assert len(data) == 10000, f"Expected exactly 10,000 parsed records in {OUTPUT}, got {len(data)}."

    for idx, record in enumerate(data):
        assert "user_agent" in record, f"Record at index {idx} is missing 'user_agent' field."
        assert record["user_agent"] != "", (
            f"Record at index {idx} has an empty user agent, which should have failed validation."
        )

    expected = expected_records()
    assert data == expected, "output.json does not contain the correctly parsed records from batch_491.log"
    assert data[999]["user_agent"] == 'Mozilla/5.0 "CrashMe"'


def test_processor_assertion_added():
    processor_path = "/home/user/ingester/processor/processor.go"
    assert os.path.isfile(processor_path), f"File {processor_path} is missing."

    with open(processor_path, "r", encoding="utf-8") as f:
        content = f.read()

    expected_error = '"validation failed: empty user agent"'
    assert expected_error in content, (
        f"The required validation error message {expected_error} was not found in {processor_path}."
    )


def test_go_code_builds_and_behaves_correctly():
    parser_test = r'''package parser

import "testing"

func TestVerifierEscapedQuotes(t *testing.T) {
    cases := []struct {
        line string
        want Record
    }{
        {
            line: `ts=2023-10-01T12:00:00Z ip=192.168.1.1 ua="Mozilla/5.0 \"CrashMe\"`,
            want: Record{Timestamp: "2023-10-01T12:00:00Z", IP: "192.168.1.1", UserAgent: `Mozilla/5.0 "CrashMe"`},
        },
        {
            line: `ua="A \"quoted\" agent" ip=10.0.0.1 ts=now`,
            want: Record{Timestamp: "now", IP: "10.0.0.1", UserAgent: `A "quoted" agent`},
        },
        {
            line: `ts=normal ip=127.0.0.1 ua="Mozilla/5.0"`,
            want: Record{Timestamp: "normal", IP: "127.0.0.1", UserAgent: "Mozilla/5.0"},
        },
    }
    for _, tc := range cases {
        got := ParseLine(tc.line)
        if got != tc.want {
            t.Fatalf("ParseLine(%q) = %#v; want %#v", tc.line, got, tc.want)
        }
    }
}
'''

    processor_test = r'''package processor

import (
    "testing"
    "log-ingester/parser"
)

func TestVerifierProcessValidation(t *testing.T) {
    if _, err := Process([]parser.Record{{UserAgent: ""}}); err == nil {
        t.Fatal("Process accepted a record with an empty user agent")
    } else if err.Error() != "validation failed: empty user agent" {
        t.Fatalf("unexpected validation error: %q", err.Error())
    }

    input := []parser.Record{{Timestamp: "now", IP: "127.0.0.1", UserAgent: "ok"}}
    output, err := Process(input)
    if err != nil {
        t.Fatalf("Process rejected a valid record: %v", err)
    }
    if len(output) != 1 || output[0] != input[0] {
        t.Fatalf("Process changed a valid record: %#v", output)
    }
}
'''

    created = []
    try:
        for directory, source in (
            (os.path.join(INGESTER, "parser"), parser_test),
            (os.path.join(INGESTER, "processor"), processor_test),
        ):
            fd, path = tempfile.mkstemp(prefix="zz_verifier_", suffix="_test.go", dir=directory)
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(source)
            created.append(path)

        tested = subprocess.run(
            ["go", "test", "./..."],
            cwd=INGESTER,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
        )
        assert tested.returncode == 0, "go test ./... failed:\n" + tested.stdout

        fd, generated_path = tempfile.mkstemp(prefix="verifier_ingester_", suffix=".json", dir="/tmp")
        os.close(fd)
        os.unlink(generated_path)
        try:
            run = subprocess.run(
                ["go", "run", "main.go", "-input", BATCH, "-output", generated_path],
                cwd=INGESTER,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=120,
            )
            assert run.returncode == 0, "go run main.go failed:\n" + run.stdout
            assert os.path.isfile(generated_path), "The ingester did not create its requested output file"
            generated = load_json(generated_path)
            assert generated == expected_records(), (
                "Executing the submitted ingester did not correctly parse the full batch"
            )
        finally:
            if os.path.exists(generated_path):
                os.unlink(generated_path)
    finally:
        for path in created:
            if os.path.exists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
