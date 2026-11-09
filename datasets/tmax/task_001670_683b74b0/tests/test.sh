#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile


def run_checked(cmd, timeout=5):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def compile_cpp(source, output):
    result = run_checked(["g++", source, "-o", output], timeout=20)
    assert result.returncode == 0, f"Failed to compile {source}: {result.stderr}"
    assert os.path.isfile(output)
    assert os.access(output, os.X_OK)


def assert_elf(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled executable"


def exercise_filter(filter_bin):
    nonce = secrets.token_hex(12)
    base = secrets.randbelow(100000) + 100
    cases = [
        (f"SEQ: {base}\nSELECT '{nonce}';\nSEQ: {base + 3}\nUPDATE items SET value='{nonce}';\n", 0),
        (f"header {nonce}\nSEQ: {base}\nSEQ: {base + 1}\n", 0),
        (f"SEQ: {base}\nDROP TABLE data_{nonce};\nSEQ: {base + 1}\n", 1),
        (f"SEQ: {base + 9}\nSELECT '{nonce}';\nSEQ: {base + 2}\n", 1),
        (f"SEQ: {base}\nSEQ: {base}\n", 1),
    ]
    with tempfile.TemporaryDirectory(prefix=f"filter-{nonce}-") as directory:
        for index, (content, expected) in enumerate(cases):
            path = os.path.join(directory, f"random-{secrets.token_hex(8)}-{index}.log")
            with open(path, "w") as f:
                f.write(content)
            result = run_checked([filter_bin, path])
            assert result.returncode == expected, (
                f"Filter returned {result.returncode}, expected {expected}, for generated case {index}"
            )


def test_filter_adversarial_corpus():
    """Test the compiled filter against the clean and evil corpora."""
    filter_bin = "/app/bin/filter"
    assert os.path.isfile(filter_bin), f"Filter binary not found at {filter_bin}"
    assert os.access(filter_bin, os.X_OK), f"Filter binary is not executable at {filter_bin}"
    assert_elf(filter_bin)

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failures = []
    for f in clean_files:
        result = run_checked([filter_bin, f])
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = run_checked([filter_bin, f])
        if result.returncode == 0:
            evil_failures.append(os.path.basename(f))

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    assert not error_messages, " | ".join(error_messages)

    exercise_filter(filter_bin)

    rebuilt = os.path.join(tempfile.gettempdir(), f"filter-rebuilt-{secrets.token_hex(12)}")
    try:
        compile_cpp("/app/src/filter.cpp", rebuilt)
        assert_elf(rebuilt)
        exercise_filter(rebuilt)
    finally:
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)


def exercise_db_parser(parser_bin):
    nonce = secrets.token_hex(12)
    timestamps = [
        f"{secrets.randbelow(900) / 1000.0 + 0.1:.6f}",
        f"{secrets.randbelow(900) / 1000.0 + 1.1:.6f}",
        f"{secrets.randbelow(900) / 1000.0 + 2.1:.6f}",
    ]
    lines = [
        f"{timestamps[0]} QUERY_{nonce}",
        f"{timestamps[1]} INDEX_SCAN_{nonce}",
        f"{timestamps[2]} COMMIT_{nonce}",
    ]
    fd, wal_path = tempfile.mkstemp(prefix=f"wal-{nonce}-", suffix=".wal")
    try:
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(lines) + "\n")
        result = run_checked([parser_bin, wal_path], timeout=3)
        assert result.returncode == 0, f"Parser failed: {result.stderr}"
        assert result.stdout.splitlines() == lines, (
            f"Parser output mismatch: expected {lines!r}, got {result.stdout.splitlines()!r}"
        )
    finally:
        os.unlink(wal_path)


def test_db_parser_compiled():
    """Test that db_parser is compiled, terminates, and parses generated WAL input."""
    parser_bin = "/app/bin/db_parser"
    assert os.path.isfile(parser_bin), f"Database parser binary not found at {parser_bin}"
    assert os.access(parser_bin, os.X_OK), f"Database parser binary is not executable at {parser_bin}"
    assert_elf(parser_bin)

    exercise_db_parser(parser_bin)

    fixed_result = run_checked([parser_bin, "/app/metadata.wal"], timeout=3)
    assert fixed_result.returncode == 0, f"Parser failed on metadata.wal: {fixed_result.stderr}"
    with open("/app/metadata.wal") as f:
        expected = [line.rstrip("\n") for line in f]
    assert fixed_result.stdout.splitlines() == expected

    rebuilt = os.path.join(tempfile.gettempdir(), f"db-parser-rebuilt-{secrets.token_hex(12)}")
    try:
        compile_cpp("/app/src/db_parser.cpp", rebuilt)
        assert_elf(rebuilt)
        exercise_db_parser(rebuilt)
    finally:
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)


def test_timeline_reconstruction():
    """Test that the combined timeline is correctly reconstructed."""
    timeline_path = "/home/user/timeline.txt"
    assert os.path.isfile(timeline_path), f"Timeline file not found at {timeline_path}"

    cmd = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "frame=pts_time", "-of", "csv=p=0", "/app/debug_run.mp4"
    ]
    result = run_checked(cmd, timeout=20)
    assert result.returncode == 0, "Failed to run ffprobe on video"

    pts_list = []
    for line in result.stdout.strip().split("\n"):
        if line:
            try:
                pts_list.append(float(line))
            except ValueError:
                pass

    db_events = []
    wal_path = "/app/metadata.wal"
    if os.path.isfile(wal_path):
        with open(wal_path, "r") as f:
            for line in f:
                parts = line.strip().split(" ", 1)
                if len(parts) == 2:
                    try:
                        db_events.append((float(parts[0]), parts[1]))
                    except ValueError:
                        pass

    expected_timeline = []
    for pts in pts_list:
        for db_time, db_desc in db_events:
            if abs(pts - db_time) <= 0.05:
                expected_timeline.append(f"{pts:.6f} - {db_desc}")
                break

    with open(timeline_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    actual_parsed = []
    for line in actual_lines:
        parts = line.split(" - ", 1)
        if len(parts) == 2:
            try:
                actual_parsed.append((float(parts[0]), parts[1]))
            except ValueError:
                pass

    expected_parsed = []
    for line in expected_timeline:
        parts = line.split(" - ", 1)
        expected_parsed.append((float(parts[0]), parts[1]))

    assert len(actual_parsed) == len(expected_parsed), f"Expected {len(expected_parsed)} timeline entries, got {len(actual_parsed)}"
    for (act_ts, act_desc), (exp_ts, exp_desc) in zip(actual_parsed, expected_parsed):
        assert abs(act_ts - exp_ts) < 0.001, f"Timestamp mismatch: expected {exp_ts}, got {act_ts}"
        assert act_desc == exp_desc, f"Event description mismatch: expected {exp_desc}, got {act_desc}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
