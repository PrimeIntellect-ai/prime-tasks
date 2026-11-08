#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import string
import subprocess

import pytest

CPP_FILE = "/home/user/cleaner.cpp"
EXE_FILE = "/home/user/cleaner"
BUILT_EXE = "/tmp/cleaner_from_submitted_source"
INPUT_FILE = "/home/user/etl_dump.txt"
CLEANED_FILE = "/home/user/cleaned_etl.txt"
REPORT_FILE = "/home/user/anomaly_report.json"

ORIGINAL_LINES = [
    "[2023-10-01 10:00:00] JOB-A | SEQ:100 | PAYLOAD:AlphaBeta",
    "[2023-10-01 10:01:00] JOB-A | SEQ:101 | PAYLOAD:GammaDelta",
    "[2023-10-01 10:02:00] JOB-A | SEQ:102 | PAYLOAD:EpsilonZeta",
    "[2023-10-01 10:03:00] JOB-A | SEQ:103 | PAYLOAD:EtaTheta",
    "[2023-10-01 10:05:00] JOB-A | SEQ:102 | PAYLOAD:EpsilomZeta",
    "[2023-10-01 10:06:00] JOB-A | SEQ:103 | PAYLOAD:EtaTheta!",
    "[2023-10-01 10:07:00] JOB-A | SEQ:104 | PAYLOAD:IotaKappa",
    "[2023-10-01 10:08:00] JOB-A | SEQ:105 | PAYLOAD:LambdaMu",
]

LINE_RE = re.compile(
    r"^\[([^\]]+)\] (JOB-[^ ]+) \| SEQ:(\d+) \| PAYLOAD:(.*)$"
)


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def derive_expected(lines):
    records = []
    for line in lines:
        match = LINE_RE.fullmatch(line)
        assert match, f"Verifier generated an invalid fixture line: {line}"
        records.append({"line": line, "seq": int(match.group(3)), "payload": match.group(4)})

    changepoint = None
    for i in range(1, len(records)):
        if records[i]["seq"] < records[i - 1]["seq"]:
            changepoint = i
            break
    assert changepoint is not None

    pre = records[:changepoint]
    cleaned = [record["line"] for record in pre]
    removed = 0
    for record in records[changepoint:]:
        duplicate = any(
            old["seq"] == record["seq"]
            and levenshtein(old["payload"], record["payload"]) <= 2
            for old in pre
        )
        if duplicate:
            removed += 1
        else:
            cleaned.append(record["line"])

    return cleaned, {"changepoint_line": changepoint + 1, "duplicates_removed": removed}


def write_input(lines):
    with open(INPUT_FILE, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def execute_cleaner(executable, lines):
    write_input(lines)
    for path in (CLEANED_FILE, REPORT_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(CLEANED_FILE), f"{executable} did not create {CLEANED_FILE}"
    assert os.path.isfile(REPORT_FILE), f"{executable} did not create {REPORT_FILE}"


def read_outputs():
    with open(CLEANED_FILE, "r", encoding="utf-8") as handle:
        cleaned = [line.strip() for line in handle.read().splitlines() if line.strip()]
    with open(REPORT_FILE, "r", encoding="utf-8") as handle:
        report = json.load(handle)
    return cleaned, report


def changed_char(char):
    return "Z" if char != "Z" else "Y"


def generate_runtime_fixture():
    rng = random.SystemRandom()
    alphabet = string.ascii_letters
    start = rng.randrange(200, 900)
    job = "JOB-" + "".join(rng.choice(string.ascii_uppercase) for _ in range(5))
    payloads = ["".join(rng.choice(alphabet) for _ in range(14)) for _ in range(6)]

    def replace_positions(value, positions):
        chars = list(value)
        for position in positions:
            chars[position] = changed_char(chars[position])
        return "".join(chars)

    post_payloads = [
        replace_positions(payloads[2], [0]),
        payloads[3],
        replace_positions(payloads[4], [0, 1, 2]),
        replace_positions(payloads[5], [3, 8]),
        "".join(rng.choice(alphabet) for _ in range(14)),
    ]

    lines = []
    for i, payload in enumerate(payloads):
        lines.append(
            f"[2026-04-17 08:{i:02d}:00] {job} | SEQ:{start + i} | PAYLOAD:{payload}"
        )
    for i, payload in enumerate(post_payloads):
        lines.append(
            f"[2026-04-17 09:{i:02d}:00] {job} | SEQ:{start + 2 + i} | PAYLOAD:{payload}"
        )
    return lines


RUNTIME_LINES = generate_runtime_fixture()


def test_cpp_files_exist():
    cpp_file = "/home/user/cleaner.cpp"
    exe_file = "/home/user/cleaner"

    assert os.path.exists(cpp_file), f"Source file {cpp_file} is missing."
    assert os.path.exists(exe_file), f"Executable file {exe_file} is missing. Did you compile the program?"
    assert os.access(exe_file, os.X_OK), f"File {exe_file} is not executable."
    assert os.path.isfile(cpp_file), f"{cpp_file} is not a regular file."
    assert os.path.isfile(exe_file), f"{exe_file} is not a regular file."
    with open(exe_file, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"{exe_file} is not a compiled executable."


def test_source_uses_regex_and_compiles():
    with open(CPP_FILE, "r", encoding="utf-8") as handle:
        source = handle.read()
    without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    assert re.search(r"#\s*include\s*<regex>", without_comments), "cleaner.cpp must include <regex>."
    assert (
        re.search(r"\b(?:std::)?(?:regex_match|regex_search|sregex_iterator)\s*\(", without_comments)
        or re.search(r"\b(?:std::)?regex\s+[A-Za-z_]\w*", without_comments)
    ), "cleaner.cpp does not appear to use C++ regex parsing."

    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_FILE, "-o", BUILT_EXE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"cleaner.cpp failed to compile: {result.stderr}"


def test_execute_submitted_cleaner_on_original_fixture():
    execute_cleaner(EXE_FILE, ORIGINAL_LINES)


def test_cleaned_etl_output():
    file_path = "/home/user/cleaned_etl.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing. The C++ program failed to generate the cleaned dataset."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    expected_lines = [
        "[2023-10-01 10:00:00] JOB-A | SEQ:100 | PAYLOAD:AlphaBeta",
        "[2023-10-01 10:01:00] JOB-A | SEQ:101 | PAYLOAD:GammaDelta",
        "[2023-10-01 10:02:00] JOB-A | SEQ:102 | PAYLOAD:EpsilonZeta",
        "[2023-10-01 10:03:00] JOB-A | SEQ:103 | PAYLOAD:EtaTheta",
        "[2023-10-01 10:07:00] JOB-A | SEQ:104 | PAYLOAD:IotaKappa",
        "[2023-10-01 10:08:00] JOB-A | SEQ:105 | PAYLOAD:LambdaMu"
    ]

    with open(file_path, "r") as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, "The content of cleaned_etl.txt does not match the expected deduplicated dataset."


def test_anomaly_report_output():
    file_path = "/home/user/anomaly_report.json"
    assert os.path.exists(file_path), f"File {file_path} is missing. The C++ program failed to generate the anomaly report."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{file_path} does not contain valid JSON.")

    assert "changepoint_line" in report, "Key 'changepoint_line' is missing from anomaly_report.json."
    assert "duplicates_removed" in report, "Key 'duplicates_removed' is missing from anomaly_report.json."

    assert report["changepoint_line"] == 5, f"Expected changepoint_line to be 5, but got {report['changepoint_line']}."
    assert report["duplicates_removed"] == 2, f"Expected duplicates_removed to be 2, but got {report['duplicates_removed']}."


def assert_runtime_behavior(executable):
    expected_cleaned, expected_report = derive_expected(RUNTIME_LINES)
    execute_cleaner(executable, RUNTIME_LINES)
    actual_cleaned, actual_report = read_outputs()
    assert actual_cleaned == expected_cleaned, (
        "Cleaner failed the runtime-generated changepoint and fuzzy-deduplication fixture."
    )
    assert actual_report.get("changepoint_line") == expected_report["changepoint_line"]
    assert actual_report.get("duplicates_removed") == expected_report["duplicates_removed"]


def test_submitted_executable_on_runtime_generated_fixture():
    assert_runtime_behavior(EXE_FILE)


def test_submitted_source_build_on_runtime_generated_fixture():
    assert os.path.isfile(BUILT_EXE), "Verifier build of cleaner.cpp is missing."
    assert_runtime_behavior(BUILT_EXE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
