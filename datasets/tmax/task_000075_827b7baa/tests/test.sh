#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess

SOURCE = "/home/user/parser.c"
PARSER = "/home/user/parser"
INPUT = "/home/user/changes.txt"
OUTPUT = "/home/user/db_import.csv"

CANONICAL_INPUT = r'''{"cfg_id": 10, "delta": 2.50, "status": "active"}
{"cfg_id": 10, "delta": 4.50, "status": "\u0061\u0063\u0074\u0069\u0076\u0065"}
{"cfg_id": 20, "delta": -1.00, "status": "\u0069\u006E\u0061\u0063\u0074\u0069\u0076\u0065"}
{"cfg_id": 20, "delta": 5.00, "status": "inactive"}
{"cfg_id": 30, "delta": 10.00, "status": "active"}
{"cfg_id": 30, "delta": 20.00, "status": "\u0061\u0063\u0074\u0069\u0076\u0065"}
{"cfg_id": 30, "delta": -6.00, "status": "active"}
{"cfg_id": 45, "delta": 0.00, "status": "\u0061\u0063\u0074\u0069\u0076\u0065"}
'''

CANONICAL_EXPECTED = [
    "cfg_id,avg_delta",
    "10,3.50",
    "30,8.00",
    "45,0.00",
]


def read_output():
    assert os.path.isfile(OUTPUT), f"The output file {OUTPUT} is missing."
    with open(OUTPUT, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def run_parser(executable, input_text):
    with open(INPUT, "w", encoding="utf-8") as f:
        f.write(input_text)
    try:
        os.remove(OUTPUT)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        [executable], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return read_output()


def encoded_status(value, rng, mode):
    if mode == 0:
        return value
    if mode == 1:
        return "".join(f"\\u{ord(ch):04X}" for ch in value)
    return "".join(
        ch if rng.randrange(2) else f"\\u{ord(ch):04X}"
        for ch in value
    )


def make_random_case():
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    ids = sorted(rng.sample(range(1, 101), 6))
    active_ids = ids[:4]
    records = []
    expected_means = {}

    for index, cfg_id in enumerate(active_ids):
        mean_cents = rng.randint(-2500, 2500)
        offset = rng.randint(1, 900)
        expected_means[cfg_id] = mean_cents
        for row_index, cents in enumerate(
            [mean_cents - offset, mean_cents, mean_cents + offset]
        ):
            status = encoded_status("active", rng, (index + row_index) % 3)
            records.append((cfg_id, cents, status))
        # Inactive values for an otherwise included ID must not affect its mean.
        records.append((cfg_id, rng.randint(-9000, 9000),
                        encoded_status("inactive", rng, (index + 1) % 3)))

    # These IDs have only inactive records and therefore must be absent.
    for index, cfg_id in enumerate(ids[4:]):
        for _ in range(2):
            records.append((cfg_id, rng.randint(-9000, 9000),
                            encoded_status("inactive", rng, index + 1)))

    rng.shuffle(records)
    lines = []
    for cfg_id, cents, status in records:
        sign = "-" if cents < 0 else ""
        amount = abs(cents)
        delta = f"{sign}{amount // 100}.{amount % 100:02d}"
        lines.append(
            f'{{"cfg_id": {cfg_id}, "delta": {delta}, "status": "{status}"}}'
        )

    expected = ["cfg_id,avg_delta"]
    for cfg_id in sorted(expected_means):
        cents = expected_means[cfg_id]
        sign = "-" if cents < 0 else ""
        amount = abs(cents)
        expected.append(f"{cfg_id},{sign}{amount // 100}.{amount % 100:02d}")
    return "\n".join(lines) + "\n", expected


def test_final_state():
    assert os.path.isfile(SOURCE), "The C source file /home/user/parser.c is missing."
    assert os.path.isfile(PARSER), "The compiled executable /home/user/parser is missing."
    assert os.access(PARSER, os.X_OK), "The file /home/user/parser is not executable."
    with open(PARSER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/parser is not a compiled ELF executable."

    # Compile the submitted source so behavior cannot be supplied only by an
    # unrelated prebuilt executable.
    compiled = "/tmp/parser_from_submitted_source"
    build = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", compiled],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert build.returncode == 0, f"parser.c does not compile:\n{build.stderr}"

    # Preserve the original exact output assertion, but first regenerate the
    # file by executing the submitted parser on the original input.
    actual_lines = run_parser(PARSER, CANONICAL_INPUT)
    assert actual_lines == CANONICAL_EXPECTED, (
        f"The content of {OUTPUT} does not match the expected output.\n"
        f"Expected:\n{chr(10).join(CANONICAL_EXPECTED)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )

    # Exercise both the delivered executable and a fresh build of parser.c on
    # unpredictable inputs. Means are constructed in integer cents so their
    # required two-decimal representation is unambiguous.
    for executable in (PARSER, compiled):
        for _ in range(3):
            input_text, expected = make_random_case()
            actual = run_parser(executable, input_text)
            assert actual == expected, (
                f"Incorrect output from {executable}.\n"
                f"Expected:\n{chr(10).join(expected)}\n"
                f"Actual:\n{chr(10).join(actual)}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
