#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
from pathlib import Path

CHAT_FILE = Path("/home/user/chat_logs.txt")
OUTPUT_FILE = Path("/home/user/clean_users.csv")


def read_nonempty_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    return [line.strip() for line in content.splitlines() if line.strip()]


def test_clean_users_csv_exists_and_content():
    assert OUTPUT_FILE.exists(), f"Output file {OUTPUT_FILE} does not exist. Did you run your C program?"
    assert OUTPUT_FILE.is_file(), f"{OUTPUT_FILE} should be a file."

    expected_content = """BØB,2023-12-01T08:12:00Z,SYSTEM FAILURE IMMINENT
ZØE,2023-12-01T08:30:00Z,HéLLO WøRLD
alice,2023-12-01T08:25:00Z,WAIT, MY CAFé SPILLED!
charlie,2023-12-01T08:15:30Z,NEVERMIND, IT WORKS NOW.
dæmon,2023-12-01T08:20:00Z,RESTARTING SERVICES..."""

    actual_lines = read_nonempty_lines(OUTPUT_FILE)
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        "The content of clean_users.csv does not match the expected output. "
        "Check your parsing, deduplication, normalization, and sorting logic."
    )


def normalize_message(message):
    converted = "".join(
        chr(ord(ch) - 32) if "a" <= ch <= "z" else ch
        for ch in message
    )
    return re.sub(r" {2,}", " ", converted).strip(" ")


def expected_from_records(records):
    latest = {}
    for timestamp, username, message in records:
        latest[username] = (timestamp, message)

    lines = []
    for username in sorted(latest, key=lambda value: value.encode("utf-8")):
        timestamp, message = latest[username]
        lines.append(f"{username},{timestamp},{normalize_message(message)}")
    return lines


def write_records(records):
    text = "".join(
        f"[{timestamp}] <{username}> {message}\n"
        for timestamp, username, message in records
    )
    CHAT_FILE.write_text(text, encoding="utf-8")


def test_c_source_compiles_and_generalizes_to_changed_input(tmp_path):
    sources = [
        path for path in Path("/home/user").rglob("*.c")
        if path.is_file()
    ]
    assert sources, "No C source file was created under /home/user."
    assert len(sources) == 1, f"Expected a single C source file, found: {sources}"

    executable = tmp_path / "process_logs"
    compilation = subprocess.run(
        ["gcc", str(sources[0]), "-o", str(executable)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compilation.returncode == 0, f"C source did not compile with gcc:\n{compilation.stderr}"
    assert executable.is_file(), "Compilation did not produce an executable."

    original_chat = CHAT_FILE.read_bytes()
    original_output = OUTPUT_FILE.read_bytes() if OUTPUT_FILE.exists() else None

    try:
        for trial in range(2):
            token = "".join(secrets.choice(string.ascii_lowercase) for _ in range(10))
            word = "".join(secrets.choice(string.ascii_lowercase) for _ in range(8))
            records = [
                (f"204{trial}-01-02T03:04:05Z", f"beta_{token}", "   first    obsolete   message  "),
                (f"204{trial}-01-02T03:05:06Z", f"Alpha_{token}", " lower   CASE   café  "),
                (f"204{trial}-01-02T03:06:07Z", f"écho_{token}", "  héllo    wørld  "),
                (f"204{trial}-01-02T03:07:08Z", f"beta_{token}", f"  final   {word}    value  "),
                (f"204{trial}-01-02T03:08:09Z", f"zeta_{token}", " one     two   THREE "),
                (f"204{trial}-01-02T03:09:10Z", f"Alpha_{token}", "  newest    entry, with   comma  "),
            ]
            write_records(records)
            if OUTPUT_FILE.exists():
                OUTPUT_FILE.unlink()

            execution = subprocess.run(
                [str(executable)],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert execution.returncode == 0, f"Compiled program failed:\n{execution.stderr}"
            assert OUTPUT_FILE.exists() and OUTPUT_FILE.is_file(), (
                "Compiled program did not create /home/user/clean_users.csv"
            )
            assert read_nonempty_lines(OUTPUT_FILE) == expected_from_records(records), (
                "Compiled program failed on a changed input; check parsing, last-message "
                "deduplication, ASCII-only uppercasing, space normalization, and byte-wise sorting."
            )
    finally:
        CHAT_FILE.write_bytes(original_chat)
        if original_output is None:
            if OUTPUT_FILE.exists():
                OUTPUT_FILE.unlink()
        else:
            OUTPUT_FILE.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
