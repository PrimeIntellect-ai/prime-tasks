#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import secrets
import subprocess
import tempfile
import pytest

FILTER_BIN = "/home/user/filter_bin"
FILTER_SOURCE = "/home/user/filter.c"
PIPELINE_SH = "/home/user/pipeline.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
WINDOW_SIZE = 5


def run_filter(input_data, executable=FILTER_BIN):
    result = subprocess.run(
        [executable],
        input=input_data.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    return result


def nonempty_lines(data):
    return [line for line in data.decode("utf-8").splitlines() if line.strip()]


def test_adversarial_corpus_filter():
    assert os.path.isfile(FILTER_BIN), f"Filter binary {FILTER_BIN} not found. Did you compile it?"
    assert os.access(FILTER_BIN, os.X_OK), f"Filter binary {FILTER_BIN} is not executable."

    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*"))

    assert len(clean_files) > 0, "No files found in clean corpus directory."
    assert len(evil_files) > 0, "No files found in evil corpus directory."

    clean_modified = []
    evil_bypassed = []

    for c_file in clean_files:
        with open(c_file, "r") as f:
            input_data = f.read()
        input_lines = [line for line in input_data.strip().split("\n") if line]
        try:
            result = run_filter(input_data)
            output_lines = nonempty_lines(result.stdout)
        except (subprocess.TimeoutExpired, UnicodeDecodeError):
            clean_modified.append(os.path.basename(c_file))
            continue

        if len(input_lines) != len(output_lines):
            clean_modified.append(os.path.basename(c_file))
            continue
        try:
            assert [json.loads(x) for x in output_lines] == [json.loads(x) for x in input_lines]
        except (ValueError, AssertionError):
            clean_modified.append(os.path.basename(c_file))

    for e_file in evil_files:
        with open(e_file, "r") as f:
            input_data = f.read()
        try:
            result = run_filter(input_data)
            output_lines = nonempty_lines(result.stdout)
        except (subprocess.TimeoutExpired, UnicodeDecodeError):
            evil_bypassed.append(os.path.basename(e_file))
            continue
        if len(output_lines) > 0:
            evil_bypassed.append(os.path.basename(e_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (or dropped): {', '.join(clean_modified)}")
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def encode_message_line(record, escaped_indexes):
    plain_message = json.dumps(record["message"], ensure_ascii=True)
    encoded = []
    for i, char in enumerate(record["message"]):
        if i in escaped_indexes:
            encoded.append("\\u%04X" % ord(char))
        else:
            encoded.append(json.dumps(char, ensure_ascii=True)[1:-1])
    line = json.dumps(record, ensure_ascii=True, separators=(",", ":"))
    return line.replace(plain_message, '"' + "".join(encoded) + '"', 1)


def exercise_novel_filter(executable):
    token = secrets.token_hex(12)
    deep = {"leaf": token}
    for _ in range(80):
        deep = {"nested": deep}

    clean_records = [
        {"timestamp": "novel-a-" + token, "bytes": 731, "message": "ordinary " + token},
        {"timestamp": "novel-b-" + token, "bytes": -12, "message": "EXFI L and exfil are harmless"},
        {"timestamp": "novel-c-" + token, "bytes": 0, "message": "Unicode snowman \u2603 " + token},
        {"timestamp": "novel-d-" + token, "bytes": 44, "message": "benign", "payload": deep},
        {"timestamp": "novel-e-" + token, "bytes": 19, "message": "top-level clean", "nested": {"message": "EXFIL"}},
    ]
    clean_lines = [json.dumps(r, ensure_ascii=True, separators=(",", ":")) for r in clean_records]

    evil_records = [
        {"timestamp": "evil-a-" + token, "bytes": 991, "message": "prefix EXFIL suffix " + token},
        {"timestamp": "evil-b-" + token, "bytes": 992, "message": "EXFIL" + token},
        {"timestamp": "evil-c-" + token, "bytes": 993, "message": token + "EXFIL"},
    ]
    evil_lines = []
    for record in evil_records:
        start = record["message"].index("EXFIL")
        keyword_positions = set(range(start, start + 5))
        evil_lines.append(encode_message_line(record, keyword_positions))

    sequence = [
        (clean_lines[0], clean_records[0]),
        (evil_lines[0], None),
        (clean_lines[1], clean_records[1]),
        (clean_lines[2], clean_records[2]),
        (evil_lines[1], None),
        (clean_lines[3], clean_records[3]),
        (evil_lines[2], None),
        (clean_lines[4], clean_records[4]),
    ]
    result = run_filter("\n".join(line for line, _ in sequence) + "\n", executable)
    assert result.returncode == 0, f"Filter exited {result.returncode}: {result.stderr.decode('utf-8', 'replace')}"
    output_lines = nonempty_lines(result.stdout)
    parsed = [json.loads(line) for line in output_lines]
    expected = [record for _, record in sequence if record is not None]
    assert parsed == expected, "Filter did not preserve exactly the novel clean records in input order"

    all_evil = run_filter("\n".join(evil_lines) + "\n", executable)
    assert all_evil.returncode == 0
    assert nonempty_lines(all_evil.stdout) == [], "Unicode-escaped EXFIL records were not all rejected"

    malformed = '{"timestamp":"bad","bytes":1,"message":"\\uZZZZ"}\n'
    malformed_result = run_filter(malformed, executable)
    assert malformed_result.returncode >= 0, "Filter crashed on malformed Unicode"
    for line in nonempty_lines(malformed_result.stdout):
        json.loads(line)


def test_filter_source_and_novel_records():
    assert os.path.isfile(FILTER_SOURCE), f"C source {FILTER_SOURCE} not found"
    with open(FILTER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "filter_bin is not a compiled native executable"

    rebuilt = os.path.join(tempfile.mkdtemp(prefix="filter-build-"), "filter_bin")
    compile_result = subprocess.run(
        ["gcc", "-O2", "-std=c11", FILTER_SOURCE, "-o", rebuilt, "-ljansson"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, "filter.c does not compile: " + compile_result.stderr.decode("utf-8", "replace")
    exercise_novel_filter(FILTER_BIN)
    exercise_novel_filter(rebuilt)


def test_pipeline_rolling_average():
    assert os.path.isfile(PIPELINE_SH), f"Pipeline script {PIPELINE_SH} not found."
    assert os.access(PIPELINE_SH, os.X_OK), f"Pipeline script {PIPELINE_SH} is not executable."

    test_input_file = os.path.join(CLEAN_CORPUS_DIR, "clean.jsonl")
    assert os.path.isfile(test_input_file), f"Test input file {test_input_file} not found."

    with open(test_input_file, "r") as f:
        lines = [line for line in f.read().strip().split("\n") if line]

    expected_rows = []
    byte_history = []
    for line in lines:
        record = json.loads(line)
        timestamp = record["timestamp"]
        bytes_val = record["bytes"]
        byte_history.append(bytes_val)
        window = byte_history[-WINDOW_SIZE:]
        avg = sum(window) / len(window)
        expected_rows.append(f"{timestamp},{bytes_val},{avg:.1f}")

    result = subprocess.run(
        [PIPELINE_SH, test_input_file],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )

    assert result.returncode == 0, f"Pipeline script failed with return code {result.returncode}\nStderr: {result.stderr.decode('utf-8')}"
    output_lines = [line for line in result.stdout.decode("utf-8").strip().split("\n") if line]
    assert len(output_lines) > 0, "Pipeline script produced no output."
    header = output_lines[0]
    assert header == "timestamp,bytes,rolling_avg_bytes", f"Incorrect CSV header: {header}"
    data_lines = output_lines[1:]
    assert len(data_lines) == len(expected_rows), f"Expected {len(expected_rows)} data rows, got {len(data_lines)}"

    for i, (actual, expected) in enumerate(zip(data_lines, expected_rows)):
        actual_parts = actual.split(",")
        expected_parts = expected.split(",")
        assert len(actual_parts) == 3, f"Row {i+1} does not have 3 columns: {actual}"
        assert actual_parts[0] == expected_parts[0], f"Row {i+1} timestamp mismatch: {actual_parts[0]} != {expected_parts[0]}"
        assert actual_parts[1] == expected_parts[1], f"Row {i+1} bytes mismatch: {actual_parts[1]} != {expected_parts[1]}"
        actual_avg = float(actual_parts[2])
        expected_avg = float(expected_parts[2])
        assert abs(actual_avg - expected_avg) < 0.1, f"Row {i+1} rolling average mismatch: {actual_avg} != {expected_avg}"


def test_pipeline_novel_window_and_filter_stage():
    token = secrets.token_hex(10)
    accepted = []
    input_lines = []
    for i in range(12):
        value = 37 + ((i * 113 + int(token[:4], 16)) % 997)
        record = {
            "timestamp": f"runtime-{token}-{i:02d}",
            "bytes": value,
            "message": f"accepted-{token}-{i}",
        }
        accepted.append(record)
        input_lines.append(json.dumps(record, separators=(",", ":")))
        if i in (1, 5, 8):
            evil = {
                "timestamp": f"rejected-{token}-{i}",
                "bytes": 900000 + i,
                "message": f"attack-{token}-EXFIL-payload",
            }
            start = evil["message"].index("EXFIL")
            input_lines.append(encode_message_line(evil, set(range(start, start + 5))))

    with tempfile.TemporaryDirectory(prefix="pipeline-test-") as td:
        input_path = os.path.join(td, "novel.jsonl")
        marker = os.path.join(td, "filter-called")
        backup = os.path.join(td, "real-filter")
        with open(input_path, "w", encoding="utf-8") as f:
            f.write("\n".join(input_lines) + "\n")

        os.replace(FILTER_BIN, backup)
        try:
            with open(FILTER_BIN, "w", encoding="utf-8") as f:
                f.write("#!/bin/sh\nprintf called >> " + json.dumps(marker) + "\nexec " + json.dumps(backup) + " \"$@\"\n")
            os.chmod(FILTER_BIN, 0o755)
            result = subprocess.run(
                [PIPELINE_SH, input_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
        finally:
            if os.path.exists(FILTER_BIN):
                os.unlink(FILTER_BIN)
            os.replace(backup, FILTER_BIN)

        assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
        assert os.path.exists(marker), "pipeline.sh did not invoke /home/user/filter_bin"
        rows = list(csv.reader(result.stdout.decode("utf-8").splitlines()))
        assert rows and rows[0] == ["timestamp", "bytes", "rolling_avg_bytes"]
        assert len(rows) == len(accepted) + 1, "Pipeline did not remove malicious records or emitted the wrong row count"

        history = []
        for i, (row, record) in enumerate(zip(rows[1:], accepted), 1):
            assert len(row) == 3, f"CSV row {i} does not have three columns"
            assert row[0] == record["timestamp"]
            assert float(row[1]) == record["bytes"]
            history.append(record["bytes"])
            expected_avg = sum(history[-WINDOW_SIZE:]) / len(history[-WINDOW_SIZE:])
            assert abs(float(row[2]) - expected_avg) < 0.11, f"Incorrect five-record rolling average at row {i}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
