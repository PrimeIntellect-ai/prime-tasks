#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import tempfile


def test_c_source_and_executable_exist():
    source_path = "/home/user/process.c"
    executable_path = "/home/user/process"

    assert os.path.isfile(source_path), f"C source code {source_path} is missing."
    assert os.path.isfile(executable_path), f"Executable {executable_path} is missing."
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."

    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {executable_path} is not a compiled ELF executable."


def test_processed_output():
    output_path = "/home/user/processed.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    expected_lines = [
        "user_id|masked_email|type|norm_score|tokens",
        "101|jo***@test.com|A|0.50|good_job",
        "101|jo***@test.com|B|0.75|needs_work",
        "102|ja***@test.com|A|0.90|excellent",
        "103|a***@domain.org|B|0.10|very_bad"
    ]

    with open(output_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Content of {output_path} is incorrect. Expected: {expected_lines}, but got: {actual_lines}"


def test_process_log():
    log_path = "/home/user/process.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

    expected_lines = [
        "LOG: Processed line 1",
        "LOG: Processed line 2",
        "LOG: Processed line 3"
    ]

    with open(log_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Content of {log_path} is incorrect. Expected: {expected_lines}, but got: {actual_lines}"


def mask_email(email):
    local, domain = email.split("@", 1)
    return local[:2] + "***@" + domain


def transformed_lines(rows):
    result = ["user_id|masked_email|type|norm_score|tokens"]
    for user_id, email, score_a, score_b, text_a, text_b in rows:
        for kind, score, text in (("A", score_a, text_a), ("B", score_b, text_b)):
            if score == "":
                continue
            tokens = text.lower().replace(" ", "_")
            result.append(
                f"{user_id}|{mask_email(email)}|{kind}|{int(score) / 100:.2f}|{tokens}"
            )
    return result


def run_and_check(executable, input_data, expected_stdout, expected_stderr):
    completed = subprocess.run(
        [executable],
        input=input_data,
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert completed.returncode == 0, (
        f"{executable} exited with {completed.returncode}. stderr: {completed.stderr!r}"
    )
    assert completed.stdout.splitlines() == expected_stdout, (
        f"Unexpected stdout from {executable}. Expected {expected_stdout!r}, "
        f"got {completed.stdout.splitlines()!r}"
    )
    assert completed.stderr.splitlines() == expected_stderr, (
        f"Unexpected stderr from {executable}. Expected {expected_stderr!r}, "
        f"got {completed.stderr.splitlines()!r}"
    )


def test_program_and_source_transform_dynamic_input():
    rng = secrets.SystemRandom()
    letters = string.ascii_letters

    def word(length=9):
        return "".join(rng.choice(letters) for _ in range(length))

    base = rng.randrange(20000, 90000)
    score_1 = str(rng.randrange(1, 100))
    score_2 = str(rng.randrange(1, 100))
    score_3 = str(rng.randrange(1, 100))
    score_4 = str(rng.randrange(1, 100))
    random_local = word(10)

    rows = [
        (str(base), f"{random_local}@example.net", score_1, score_2,
         f"MiXeD {word()} Words", f"Second  {word()} Value"),
        (str(base + 1), "q@short.org", score_3, "", "ONE SPACE", "ignored"),
        (str(base + 2), "xy@twolen.test", "", score_4, "ignored", "B Text"),
        (str(base + 3), f"{word(7)}@none.test", "", "", "No A", "No B"),
        (str(base + 4), f"{word(8)}@empty.test", score_2, score_1, "", "Final TEXT"),
    ]

    header = "user_id|email|score_A|score_B|text_A|text_B"
    input_data = "\n".join([header] + ["|".join(row) for row in rows]) + "\n"
    expected_stdout = transformed_lines(rows)
    expected_stderr = [f"LOG: Processed line {i}" for i in range(1, len(rows) + 1)]

    run_and_check("/home/user/process", input_data, expected_stdout, expected_stderr)

    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt = os.path.join(temp_dir, "process_from_source")
        compiled = subprocess.run(
            ["gcc", "-std=c11", "-O2", "/home/user/process.c", "-o", rebuilt],
            text=True,
            capture_output=True,
            timeout=15,
        )
        assert compiled.returncode == 0, (
            "The submitted C source could not be compiled. "
            f"stdout: {compiled.stdout!r}, stderr: {compiled.stderr!r}"
        )
        run_and_check(rebuilt, input_data, expected_stdout, expected_stderr)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
