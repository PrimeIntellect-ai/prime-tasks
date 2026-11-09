#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import difflib
import os
import re
import stat

EXPECTED_RECORDS = [
    ("2023-01-01 10:00:00", "APPEND", "[server]"),
    ("2023-01-01 10:05:00", "APPEND", "port=8080"),
    ("2023-01-01 10:10:00", "APPEND", "host=localhost"),
    ("2023-01-01 10:15:00", "DELETE", "3"),
    ("2023-01-01 10:20:00", "APPEND", "host=0.0.0.0"),
    ("2023-01-01 10:25:00", "APPEND", "[database]"),
    ("2023-01-01 10:30:00", "APPEND", "url=sqlite:///db.sqlite"),
    ("2023-01-01 10:35:00", "APPEND", "[cache]"),
    ("2023-01-01 10:40:00", "APPEND", "redis_host=127.0.0.1"),
    ("2023-01-01 10:45:00", "DELETE", "6"),
    ("2023-01-01 10:50:00", "APPEND", "temp1"),
    ("2023-01-01 10:55:00", "APPEND", "temp2"),
    ("2023-01-01 11:00:00", "DELETE", "7"),
    ("2023-01-01 11:05:00", "DELETE", "7"),
    ("2023-01-01 11:10:00", "APPEND", "temp3"),
    ("2023-01-01 11:15:00", "DELETE", "7"),
    ("2023-01-01 11:20:00", "APPEND", "temp4"),
    ("2023-01-01 11:25:00", "DELETE", "7"),
    ("2023-01-01 11:30:00", "APPEND", "temp5"),
    ("2023-01-01 11:35:00", "DELETE", "7"),
]

RECORD_RE = re.compile(
    r"START_RECORD \[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]\n"
    r"ACTION: (APPEND|DELETE)\n"
    r"([^\n]+)\n"
    r"END_RECORD"
)


def test_server_config_similarity():
    expected = """[server]
port=8080
host=0.0.0.0
[database]
url=sqlite:///db.sqlite
redis_host=127.0.0.1"""

    config_path = "/home/user/server_config.ini"
    assert os.path.exists(config_path), f"The reconstructed configuration file is missing at {config_path}."
    assert os.path.isfile(config_path), f"The path {config_path} exists but is not a file."
    assert not os.path.islink(config_path), f"The path {config_path} must be a regular deployed file, not a symlink."
    assert stat.S_ISREG(os.lstat(config_path).st_mode), f"The path {config_path} is not a regular file."

    with open(config_path, "r") as f:
        actual = f.read().strip()

    ratio = difflib.SequenceMatcher(None, expected, actual).ratio()
    assert ratio >= 0.90, (
        f"Similarity ratio {ratio:.4f} is below the threshold of 0.90.\n"
        f"Expected:\n{expected}\n\nActual:\n{actual}"
    )


def parse_complete_records(content, filename):
    content = content.replace("\r\n", "\n")
    matches = list(RECORD_RE.finditer(content))
    assert matches, f"No complete records found in {filename}."

    cursor = 0
    for match in matches:
        gap = content[cursor:match.start()]
        assert not gap.strip(), f"Unexpected text outside records in {filename}: {gap!r}"
        cursor = match.end()
    trailing = content[cursor:]
    assert not trailing.strip(), f"Unexpected text after the last record in {filename}: {trailing!r}"

    return [match.groups() for match in matches]


def test_parsed_logs_chunks():
    chunks_dir = "/home/user/parsed_logs"
    assert os.path.exists(chunks_dir), f"The parsed logs directory is missing at {chunks_dir}."
    assert os.path.isdir(chunks_dir), f"The path {chunks_dir} is not a directory."

    expected_names = [f"chunk_{i:04d}.log" for i in range(1, 5)]
    chunk_files = sorted(
        f for f in os.listdir(chunks_dir)
        if f.startswith("chunk_") and f.endswith(".log")
    )
    assert chunk_files == expected_names, (
        f"Expected exactly {expected_names}, but found {chunk_files}."
    )

    reconstructed = []
    for index, filename in enumerate(expected_names):
        path = os.path.join(chunks_dir, filename)
        assert not os.path.islink(path), f"Chunk {filename} must not be a symlink."
        assert stat.S_ISREG(os.lstat(path).st_mode), f"Chunk {filename} is not a regular file."

        with open(path, "r") as f:
            content = f.read()

        records = parse_complete_records(content, filename)
        assert len(records) == 5, (
            f"Expected exactly 5 complete records in {filename}, but found {len(records)}."
        )
        expected_slice = EXPECTED_RECORDS[index * 5:(index + 1) * 5]
        assert records == expected_slice, (
            f"Records in {filename} are missing, malformed, duplicated, or out of order.\n"
            f"Expected: {expected_slice}\nActual: {records}"
        )
        reconstructed.extend(records)

    assert reconstructed == EXPECTED_RECORDS, (
        "The chunk files do not reconstruct the complete chronological changelog."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
