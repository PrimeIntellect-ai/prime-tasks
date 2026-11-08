#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import pytest

SOURCE = "/home/user/process_subs.cpp"
RAW = "/home/user/subs_raw.log"
DICTIONARY = "/home/user/dict.csv"
OUTPUT = "/home/user/subs_normalized.jsonl"
EXECUTABLE = "/tmp/process_subs_verifier"


def test_process_subs_cpp_exists():
    assert os.path.exists(SOURCE), "/home/user/process_subs.cpp does not exist. You must write your solution in this file."


def test_subs_normalized_jsonl():
    assert os.path.exists(OUTPUT), f"{OUTPUT} does not exist. Did you run your compiled program?"

    expected = [
        {"start_sec": 0, "end_sec": 3, "speaker": "NARRATOR", "text": "hola mundo we begin now"},
        {"start_sec": 3, "end_sec": 6, "speaker": "NARRATOR", "text": "welcome to the lección"},
        {"start_sec": 6, "end_sec": 9, "speaker": "SYS", "text": "[SILENCE]"},
        {"start_sec": 9, "end_sec": 11, "speaker": "GUEST", "text": "this is emocionante right"},
        {"start_sec": 11, "end_sec": 14, "speaker": "GUEST", "text": "i am listo"},
        {"start_sec": 14, "end_sec": 17, "speaker": "SYS", "text": "[SILENCE]"},
        {"start_sec": 17, "end_sec": 20, "speaker": "NARRATOR", "text": "let us continuar"}
    ]

    with open(OUTPUT, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected), f"Expected {len(expected)} records in {OUTPUT}, but found {len(lines)}."

    for i, (line, exp) in enumerate(zip(lines, expected)):
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {OUTPUT} is not valid JSON: {line}")
        assert parsed == exp, f"Line {i+1} mismatch.\nExpected: {exp}\nGot:      {parsed}"


def timestamp(total):
    return f"{total // 3600:02d}:{(total % 3600) // 60:02d}:{total % 60:02d}"


def normalize(text, translations):
    cleaned = "".join(ch.lower() for ch in text if ch.isalnum() or ch == " ")
    return " ".join(translations.get(token, token) for token in cleaned.split())


def expected_timeline(entries, translations):
    result = []
    for index, (start, speaker, text) in enumerate(entries):
        if index == len(entries) - 1:
            result.append({
                "start_sec": start,
                "end_sec": start + 3,
                "speaker": speaker,
                "text": normalize(text, translations),
            })
            continue

        next_start = entries[index + 1][0]
        end = start + 3 if next_start - start > 4 else next_start
        result.append({
            "start_sec": start,
            "end_sec": end,
            "speaker": speaker,
            "text": normalize(text, translations),
        })
        if next_start - start > 4:
            result.append({
                "start_sec": end,
                "end_sec": next_start,
                "speaker": "SYS",
                "text": "[SILENCE]",
            })
    return result


def test_program_compiles_and_processes_varied_inputs():
    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"process_subs.cpp did not compile:\n{compile_result.stderr}"
    assert os.path.isfile(EXECUTABLE), "Compilation did not produce an executable."

    saved = {}
    for path in (RAW, DICTIONARY, OUTPUT):
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = f.read()
        else:
            saved[path] = None

    try:
        for trial in range(2):
            words = []
            while len(words) < 4:
                candidate = "w" + secrets.token_hex(4)
                if candidate not in words:
                    words.append(candidate)
            localized = ["loc" + secrets.token_hex(4) for _ in words]
            translations = dict(zip(words, localized))

            first = 55 + secrets.randbelow(70)
            deltas = [4, 5 + secrets.randbelow(4), 1 + secrets.randbelow(3), 6 + secrets.randbelow(4)]
            starts = [first]
            for delta in deltas:
                starts.append(starts[-1] + delta)

            a, b, c, d = words
            texts = [
                f"{a.upper()}, {b}! MIX{trial + 7}.",
                f"Keep ({c}) and {a}?",
                f"{d}; alpha-beta {b.upper()}!",
                f"Numbers 42, {c}.",
                f"Final: {a}/{d}.",
            ]
            speakers = ["NARRATOR", "GUEST", "HOST", "GUEST", "NARRATOR"]
            entries = list(zip(starts, speakers, texts))

            with open(DICTIONARY, "w", encoding="utf-8", newline="") as f:
                for source_word, localized_word in translations.items():
                    f.write(f"{source_word},{localized_word}\n")

            with open(RAW, "w", encoding="utf-8", newline="") as f:
                for start, speaker, text in entries:
                    f.write(f"[{timestamp(start)}] [{speaker}] {text}\n")

            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)

            run_result = subprocess.run(
                [EXECUTABLE],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert run_result.returncode == 0, f"Compiled program failed on trial {trial + 1}:\n{run_result.stderr}"
            assert os.path.exists(OUTPUT), "Compiled program did not create /home/user/subs_normalized.jsonl."

            with open(OUTPUT, "r", encoding="utf-8") as f:
                lines = [line.strip() for line in f if line.strip()]

            actual = []
            for line_number, line in enumerate(lines, 1):
                try:
                    actual.append(json.loads(line))
                except json.JSONDecodeError:
                    pytest.fail(f"Dynamic trial {trial + 1}, line {line_number} is not valid JSON: {line}")

            expected = expected_timeline(entries, translations)
            assert actual == expected, (
                f"Compiled program produced the wrong timeline on dynamic trial {trial + 1}.\n"
                f"Expected: {expected}\nGot:      {actual}"
            )
    finally:
        for path, contents in saved.items():
            if contents is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(contents)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
