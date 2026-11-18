#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import gzip
import os

LOGS_DIR = "/home/user/logs"

EXPECTED_CONTENTS = {
    "system_01.log.gz": """===RECORD===
Timestamp: 2023-10-12T10:00:00Z
Service: AuthWorker
Message: Login failed
===END===
===RECORD===
Timestamp: 2023-10-12T10:01:00Z
Service: WebApp
Message: Page loaded
===END===
""",
    "system_02.log.gz": """===RECORD===
Timestamp: 2023-10-12T10:05:00Z
Service: WebApp
Message: User clicked button
===END===
===RECORD===
Timestamp: 2023-10-12T10:06:00Z
Service: Payment
Message: Transaction success
===END===
""",
    "system_03.log.gz": """===RECORD===
Timestamp: 2023-10-12T10:10:00Z
Service: AuthWorker
Message: Token expired
===END===
===RECORD===
Timestamp: 2023-10-12T10:11:00Z
Service: AuthWorker
Message: Token renewed
===END===
""",
}


def parse_records(text):
    lines = text.splitlines()
    records = []
    i = 0
    while i < len(lines):
        assert i + 4 < len(lines), "Truncated log record"
        assert lines[i] == "===RECORD===", f"Invalid record start at line {i + 1}"
        assert lines[i + 1].startswith("Timestamp: "), "Missing Timestamp field"
        assert lines[i + 2].startswith("Service: "), "Missing Service field"
        assert lines[i + 3].startswith("Message: "), "Missing Message field"
        assert lines[i + 4] == "===END===", "Invalid record end"
        records.append({
            "timestamp": lines[i + 1][len("Timestamp: "):],
            "service": lines[i + 2][len("Service: "):],
            "message": lines[i + 3][len("Message: "):],
        })
        i += 5
    return records


def test_summary_file():
    summary_path = "/home/user/summary.txt"
    assert os.path.isfile(summary_path), f"The file {summary_path} does not exist."

    with open(summary_path, "r") as f:
        raw = f.read()
    content = raw.strip()

    assert content == "3", f"Expected summary.txt to contain '3', but found '{content}'."
    assert raw in (content, content + "\n") and content.isdigit(), \
        "summary.txt must contain only a single integer"


def test_renamed_archived_files():
    expected_archived = [
        "/home/user/logs/system_01.log.gz.archived",
        "/home/user/logs/system_03.log.gz.archived",
    ]
    for path in expected_archived:
        assert os.path.isfile(path), f"Expected archived file {path} is missing. It was not renamed correctly."

    unexpected_originals = [
        "/home/user/logs/system_01.log.gz",
        "/home/user/logs/system_03.log.gz",
    ]
    for path in unexpected_originals:
        assert not os.path.exists(path), f"Original file {path} still exists. It should have been renamed."


def test_unmodified_files():
    expected_original = "/home/user/logs/system_02.log.gz"
    assert os.path.isfile(expected_original), f"Expected unmodified file {expected_original} is missing."

    unexpected_archived = "/home/user/logs/system_02.log.gz.archived"
    assert not os.path.exists(unexpected_archived), f"File {unexpected_archived} should not exist. It was incorrectly renamed."


def test_compressed_contents_and_derived_result():
    config = configparser.ConfigParser()
    assert config.read("/home/user/config.ini") == ["/home/user/config.ini"], "Could not read config.ini"
    assert config.has_section("Target"), "config.ini is missing the Target section"
    assert config.has_option("Target", "Service"), "config.ini is missing Target.Service"
    target = config.get("Target", "Service")
    assert target == "AuthWorker", "The configured target service was modified"

    actual_names = set(os.listdir(LOGS_DIR))
    expected_names = {
        "system_01.log.gz.archived",
        "system_02.log.gz",
        "system_03.log.gz.archived",
    }
    assert actual_names == expected_names, f"Unexpected files in logs directory: {actual_names ^ expected_names}"

    total = 0
    for original_name, expected_text in EXPECTED_CONTENTS.items():
        expected_records = parse_records(expected_text)
        should_be_archived = any(r["service"] == target for r in expected_records)
        current_name = original_name + ".archived" if should_be_archived else original_name
        current_path = os.path.join(LOGS_DIR, current_name)

        with open(current_path, "rb") as f:
            assert f.read(2) == b"\x1f\x8b", f"{current_path} is not a gzip file"
        try:
            with gzip.open(current_path, "rt", encoding="utf-8", newline="") as f:
                actual_text = f.read()
        except Exception as exc:
            raise AssertionError(f"Could not decompress {current_path}: {exc}")

        assert actual_text == expected_text, f"Archived log contents were altered for {current_name}"
        actual_records = parse_records(actual_text)
        file_target_count = sum(r["service"] == target for r in actual_records)
        assert (file_target_count > 0) == current_name.endswith(".archived"), \
            f"Archive status for {current_name} does not match its records"
        total += file_target_count

    with open("/home/user/summary.txt", "r") as f:
        summary_value = int(f.read().strip())
    assert summary_value == total, f"Summary count {summary_value} does not match derived count {total}"


def test_no_decompressed_files():
    if os.path.isdir(LOGS_DIR):
        for filename in os.listdir(LOGS_DIR):
            assert not filename.endswith(".log"), f"Found uncompressed log file {filename} in {LOGS_DIR}. Files should not be permanently decompressed to disk."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
