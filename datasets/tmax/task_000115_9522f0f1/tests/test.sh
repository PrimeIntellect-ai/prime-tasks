#!/bin/bash
set -u
mkdir -p /logs/verifier

fail_verifier() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

# Require the requested C source, then build a fresh executable from it.
[ -f /home/user/processor.c ] || fail_verifier
rm -f /home/user/processor /home/user/results.csv
if ! gcc -o /home/user/processor /home/user/processor.c; then
    fail_verifier
fi
[ -x /home/user/processor ] || fail_verifier

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Exercise the compiled program on an additional valid data set so that a
# pre-created results.csv cannot satisfy the verifier.
cp /home/user/data/profiles.csv /tmp/original_profiles.csv || fail_verifier
cp /home/user/data/chats.txt /tmp/original_chats.txt || fail_verifier
restore_inputs() {
    cp /tmp/original_profiles.csv /home/user/data/profiles.csv
    cp /tmp/original_chats.txt /home/user/data/chats.txt
}
trap restore_inputs EXIT

cat << 'EOF' > /home/user/data/profiles.csv
UserID,Name,Region
201,Zoë,TestRegion
EOF

cat << 'EOF' > /home/user/data/chats.txt
LogID|Message
10|[USER:201] Привет mail a+b@example.org.
11|未知 [USER:777] email x@y.io
EOF

rm -f /home/user/results.csv
if ! (cd /home/user && ./processor); then
    fail_verifier
fi
[ -f /home/user/results.csv ] || fail_verifier
cp /home/user/results.csv /tmp/hidden_results.csv || fail_verifier

# Restore the supplied inputs and require the compiled program to generate the
# requested final output from them as well.
restore_inputs
rm -f /home/user/results.csv
if ! (cd /home/user && ./processor); then
    fail_verifier
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest


def test_processor_artifacts_exist():
    assert os.path.isfile("/home/user/processor.c"), "/home/user/processor.c does not exist"
    assert os.path.isfile("/home/user/processor"), "Compiled processor executable does not exist"
    assert os.access("/home/user/processor", os.X_OK), "Compiled processor is not executable"


def read_utf8_lines(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read().strip().splitlines()
    except UnicodeDecodeError:
        pytest.fail(f"{path} is not valid UTF-8. Did you handle Unicode correctly?")


def assert_exact_lines(actual, expected, path):
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} lines in {path}, but found {len(actual)}. "
        "Ensure you process all lines and include the header."
    )
    for i, (actual_line, expected_line) in enumerate(zip(actual, expected)):
        assert actual_line == expected_line, (
            f"Line {i + 1} mismatch in {path}.\n"
            f"Expected: {expected_line}\nActual:   {actual_line}"
        )


def test_results_csv_exists():
    assert os.path.isfile("/home/user/results.csv"), "/home/user/results.csv does not exist. Did you compile and run your program to generate the output?"


def test_results_csv_content():
    masked = [
        "Hello [USER:101], please email [REDACTED] for help.",
        "¡Hola! [USER:103], contact us at [REDACTED].",
        "[USER:104] says こんにちは, my email is [REDACTED]!",
        "System message for [USER:999]: ping [REDACTED]",
    ]
    expected_lines = [
        "LogID,UserID,Name,Region,MessageLength,MaskedMessage",
        f"1,101,Alice,Europe,{len(masked[0])},{masked[0]}",
        f"2,103,Chlöe,Europe,{len(masked[1])},{masked[1]}",
        f"3,104,Daisuke,Asia,{len(masked[2])},{masked[2]}",
        f"4,999,Unknown,Unknown,{len(masked[3])},{masked[3]}",
    ]
    assert_exact_lines(read_utf8_lines("/home/user/results.csv"), expected_lines, "/home/user/results.csv")


def test_compiled_program_processed_additional_inputs():
    masked = [
        "[USER:201] Привет mail [REDACTED].",
        "未知 [USER:777] email [REDACTED]",
    ]
    expected_lines = [
        "LogID,UserID,Name,Region,MessageLength,MaskedMessage",
        f"10,201,Zoë,TestRegion,{len(masked[0])},{masked[0]}",
        f"11,777,Unknown,Unknown,{len(masked[1])},{masked[1]}",
    ]
    assert_exact_lines(read_utf8_lines("/tmp/hidden_results.csv"), expected_lines, "/tmp/hidden_results.csv")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
