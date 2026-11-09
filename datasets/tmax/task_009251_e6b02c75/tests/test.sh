#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile


def test_c_source_exists():
    assert os.path.isfile("/home/user/cleaner.c"), "The C source file /home/user/cleaner.c does not exist."


def test_executable_exists():
    assert os.path.isfile("/home/user/cleaner"), "The compiled executable /home/user/cleaner does not exist."
    assert os.access("/home/user/cleaner", os.X_OK), "The file /home/user/cleaner is not executable."
    with open("/home/user/cleaner", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/cleaner is not a compiled executable."


def test_output_file_exists():
    assert os.path.isfile("/home/user/cleaned_feedback.txt"), "The output file /home/user/cleaned_feedback.txt does not exist."


def test_output_file_content():
    expected_lines = [
        "1670000000|U001|***@example.com|great service highly recommend",
        "1670000005|U002|***@work.net|terrible just terrible",
        "1670000010|U003|***@domain.org|okay experience",
        "1670000020|U005|***@test.com|i loved it"
    ]

    with open("/home/user/cleaned_feedback.txt", "r") as f:
        content = f.read().strip().split('\n')

    # Remove any empty lines that might have been accidentally added
    content = [line.strip() for line in content if line.strip()]

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in output, but got {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"


def normalize(text):
    lowered = text.lower()
    return "".join(ch for ch in lowered if ("a" <= ch <= "z") or ("0" <= ch <= "9") or ch == " ")


def expected_output(records):
    seen = set()
    result = []
    for timestamp, user_id, email, feedback in records:
        cleaned = normalize(feedback)
        if cleaned in seen:
            continue
        seen.add(cleaned)
        domain = email.split("@", 1)[1]
        result.append(f"{timestamp}|{user_id}|***@{domain}|{cleaned}")
    return result


def test_program_and_source_on_unseen_input():
    raw_path = "/home/user/raw_feedback.txt"
    output_path = "/home/user/cleaned_feedback.txt"
    with open(raw_path, "rb") as f:
        original_raw = f.read()
    original_output = None
    if os.path.exists(output_path):
        with open(output_path, "rb") as f:
            original_output = f.read()

    token = secrets.token_hex(8)
    records = [
        ("1800000000", "R001", f"first.{token}@Example.COM", f"Hello, WORLD!! {token}"),
        ("1800000001", "R002", "second@other.net", f"HELLO WORLD {token}!!!"),
        ("1800000002", "R003", "a.b+c@mask.test", "Hash-based_test: 42?"),
        ("1800000003", "R004", "another@mask.test", "HASHBASEDTEST 42"),
        ("1800000004", "R005", "space@test.org", "Keep  two   spaces"),
        ("1800000005", "R006", "dup@test.org", "KEEP  TWO   SPACES!!!"),
        ("1800000006", "R007", "punct@test.org", "Can't-stop; won't_stop."),
        ("1800000007", "R008", "empty@test.org", "!!!???"),
        ("1800000008", "R009", "empty2@test.org", "...---"),
        ("1800000009", "R010", "edge@test.org", "  Leading AND trailing  "),
        ("1800000010", "R011", "digits@test.org", "Version 2.0 is #1!"),
    ]

    for i in range(180):
        feedback = f"Unique-{i} value {token}"
        records.append((str(1800010000 + i), f"U{i:03d}", f"person{i}@domain{i % 11}.test", feedback))
        if i % 9 == 0:
            records.append((str(1800020000 + i), f"D{i:03d}", f"duplicate{i}@elsewhere.test", f"UNIQUE{i} VALUE {token.upper()}!!!"))

    expected = expected_output(records)
    raw_data = "".join("|".join(record) + "\n" for record in records).encode("utf-8")

    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt = os.path.join(temp_dir, "cleaner_from_source")
        compilation = subprocess.run(
            ["gcc", "-std=c11", "/home/user/cleaner.c", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compilation.returncode == 0, f"cleaner.c did not compile:\n{compilation.stderr}"

        try:
            for executable in ("/home/user/cleaner", rebuilt):
                with open(raw_path, "wb") as f:
                    f.write(raw_data)
                if os.path.exists(output_path):
                    os.remove(output_path)

                run = subprocess.run(
                    [executable],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
                assert run.returncode == 0, f"{executable} exited with {run.returncode}:\n{run.stderr}"
                assert os.path.isfile(output_path), f"{executable} did not create {output_path}."

                with open(output_path, "r", encoding="utf-8", newline=None) as f:
                    actual = f.read().splitlines()
                assert actual == expected, (
                    f"{executable} produced incorrect output on an unseen fixture.\n"
                    f"Expected {len(expected)} records, got {len(actual)}."
                )
        finally:
            with open(raw_path, "wb") as f:
                f.write(original_raw)
            if original_output is None:
                if os.path.exists(output_path):
                    os.remove(output_path)
            else:
                with open(output_path, "wb") as f:
                    f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
