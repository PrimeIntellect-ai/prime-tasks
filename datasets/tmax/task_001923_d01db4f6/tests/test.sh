#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import resource
import secrets
import string
import subprocess

SOURCE = "/home/user/fuzzy_updater.c"
EXECUTABLE = "/home/user/fuzzy_updater"
INPUT = "/home/user/untranslated.txt"
TM = "/home/user/tm.tsv"
OUTPUT = "/home/user/updated_translations.tsv"


def compile_program():
    result = subprocess.run(
        ["gcc", SOURCE, "-o", EXECUTABLE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"Compilation failed:\n{result.stderr}"


def run_program(timeout=30, memory_mb=None):
    preexec_fn = None
    if memory_mb is not None:
        def limit_memory():
            limit = memory_mb * 1024 * 1024
            resource.setrlimit(resource.RLIMIT_AS, (limit, limit))
        preexec_fn = limit_memory

    result = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        preexec_fn=preexec_fn,
    )
    assert result.returncode == 0, (
        f"Program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
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


def test_c_source_exists():
    assert os.path.exists(SOURCE), f"Source file {SOURCE} is missing."
    source = open(SOURCE, "r", encoding="utf-8", errors="replace").read()
    assert re.search(r"#\s*include\s*[<\"]regex\.h[>\"]", source), "Source must include <regex.h>."
    assert re.search(r"\bregcomp\s*\(", source), "Source must use POSIX regcomp()."
    assert re.search(r"\bregexec\s*\(", source), "Source must use POSIX regexec()."


def test_executable_exists():
    assert os.path.exists(EXECUTABLE), f"Executable file {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_updated_translations_output():
    # Retain the original assertion that the agent generated the requested file.
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} is missing."

    with open(INPUT, "w", encoding="utf-8") as f:
        f.write('ERR_FILE_NOT_FOUND="File not found"\n')
        f.write('INVALID_LINE_NO_QUOTES=Welcome to the system\n')
        f.write('MSG_WELCOME="Welcome to the system"\n')
        f.write('BTN_SUBMIT="Submit form"\n')
    with open(TM, "w", encoding="utf-8") as f:
        f.write("File is not found\tEl archivo no se encuentra\n")
        f.write("File cannot be found\tNo se puede encontrar el archivo\n")
        f.write("Welcome to our system\tBienvenido a nuestro sistema\n")
        f.write("Welcome to system\tBienvenido al sistema\n")
        f.write("Submit your form\tEnvíe su formulario\n")
        f.write("Submit the form\tEnviar el formulario\n")

    compile_program()
    run_program()

    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} is missing."
    with open(OUTPUT, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "ERR_FILE_NOT_FOUND\tFile not found\tEl archivo no se encuentra\t3",
        "MSG_WELCOME\tWelcome to the system\tBienvenido a nuestro sistema\t3",
        "BTN_SUBMIT\tSubmit form\tEnviar el formulario\t4",
    ]
    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in output, got {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"


def test_randomized_matching_strict_parsing_and_ties():
    seed = int.from_bytes(secrets.token_bytes(16), "big")
    rng = random.Random(seed)

    def token(length):
        alphabet = string.ascii_letters
        return "".join(rng.choice(alphabet) for _ in range(length))

    queries = [f"{token(6)} {token(7)}" for _ in range(6)]
    keys = [f"RANDOM_KEY_{i}_{token(5).upper()}" for i in range(len(queries))]

    tm_rows = []
    for i in range(45):
        tm_rows.append((f"{token(7)} {token(8)}", f"Spanish_{i}_{token(9)}"))

    # Exact duplicate matches verify that the first translation wins a tie.
    tm_rows.insert(5, (queries[0], "First_exact_translation"))
    tm_rows.insert(6, (queries[0], "Second_exact_translation"))

    # Add close, case-sensitive candidates at varied locations.
    for i, query in enumerate(queries[1:], 1):
        changed = (query[0].swapcase() if query[0].isalpha() else "Z") + query[1:]
        tm_rows.insert(8 + i * 5, (changed, f"Close_translation_{i}_{token(6)}"))
        tm_rows.append((query + "X", f"Trailing_candidate_{i}_{token(6)}"))

    input_lines = [
        f'{keys[0]}="{queries[0]}"',
        'BAD_NO_QUOTES=not quoted',
        f'{keys[1]}="{queries[1]}"',
        'BAD_UNTERMINATED="unterminated',
        f'{keys[2]}="{queries[2]}"',
        'BAD_TRAILING="value" trailing text',
        f'{keys[3]}="{queries[3]}"',
        'BAD_MULTIPLE="one"="two"',
        f'{keys[4]}="{queries[4]}"',
        f'{keys[5]}="{queries[5]}"',
    ]

    with open(INPUT, "w", encoding="utf-8") as f:
        f.write("\n".join(input_lines) + "\n")
    with open(TM, "w", encoding="utf-8") as f:
        for english, spanish in tm_rows:
            f.write(f"{english}\t{spanish}\n")

    expected = []
    for key, query in zip(keys, queries):
        best_spanish = None
        best_distance = None
        for english, spanish in tm_rows:
            distance = levenshtein(query, english)
            if best_distance is None or distance < best_distance:
                best_distance = distance
                best_spanish = spanish
        expected.append(f"{key}\t{query}\t{best_spanish}\t{best_distance}")

    compile_program()
    run_program()
    with open(OUTPUT, "r", encoding="utf-8") as f:
        actual = [line.rstrip("\n") for line in f if line.rstrip("\n")]
    assert actual == expected, (
        f"Randomized result mismatch (seed {seed}).\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )


def test_large_tm_is_processed_under_memory_limit():
    key = "STREAMING_TEST_KEY"
    with open(INPUT, "w", encoding="utf-8") as f:
        f.write(f'{key}="q"\n')

    # The TM is larger than the process memory allowance. A line-by-line
    # implementation can process it, while loading the complete TM cannot.
    chunk = "x\tNo coincide\n" * 10000
    with open(TM, "w", encoding="utf-8") as f:
        for _ in range(400):
            f.write(chunk)
        f.write("q\tFinal Spanish\n")

    compile_program()
    run_program(timeout=40, memory_mb=40)
    with open(OUTPUT, "r", encoding="utf-8") as f:
        actual = [line.rstrip("\n") for line in f if line.rstrip("\n")]
    assert actual == [f"{key}\tq\tFinal Spanish\t0"]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
