#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

SOURCE = "/home/user/parser.c"
EXECUTABLE = "/home/user/parser"
DATA_FILE = "/home/user/data.csv"
OUTPUT_FILE = "/home/user/output.tsv"

CANONICAL_INPUT = (
    '1,Electronics,"Great TV but costs 500\\u20ac.   Highly recommended."\n'
    '2,Books,"Copyright \\u00a9 2023. \\n\\n Good read."\n'
    '3,Home,"The temperature is 20\\u00b0C."\n'
    '4,Misc,"   Leading and trailing   "\n'
    '5,EdgeCases,"Look at this: \\u2728 magic! \\u0041"\n'
)

EXPECTED_CANONICAL = "\n".join([
    "1\tElectronics\tGreat TV but costs 500€. Highly recommended.",
    "2\tBooks\tCopyright © 2023. Good read.",
    "3\tHome\tThe temperature is 20°C.",
    "4\tMisc\tLeading and trailing",
    "5\tEdgeCases\tLook at this: ✨ magic! A",
]) + "\n"


def compile_parser():
    result = subprocess.run(
        ["gcc", "-O3", SOURCE, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, "parser.c did not compile:\n" + result.stderr
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK)


def run_parser(input_text):
    with open(DATA_FILE, "w", encoding="utf-8", newline="") as f:
        f.write(input_text)
    if os.path.exists(OUTPUT_FILE):
        os.unlink(OUTPUT_FILE)

    result = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, "compiled parser failed:\n" + result.stderr
    assert os.path.isfile(OUTPUT_FILE), f"The output file {OUTPUT_FILE} is missing."
    with open(OUTPUT_FILE, "r", encoding="utf-8", newline="") as f:
        return f.read()


def normalized_text(raw):
    decoded = re.sub(
        r"\\u([0-9a-fA-F]{4})",
        lambda match: chr(int(match.group(1), 16)),
        raw,
    )
    return re.sub(r"[ \t\r\n]+", " ", decoded).strip(" ")


def test_parser_c_exists():
    assert os.path.isfile(SOURCE), "The C source file /home/user/parser.c is missing."


def test_compiled_parser_produces_required_output_and_handles_unseen_input():
    compile_parser()

    # Preserve the original verifier's exact expected-content assertion, but
    # require that the compiled submission generate it from the canonical CSV.
    content = run_parser(CANONICAL_INPUT)
    assert content.strip() == EXPECTED_CANONICAL.strip(), (
        f"The contents of {OUTPUT_FILE} do not match the expected TSV format "
        "or unescaped values."
    )

    # Exercise unseen IDs, Unicode escapes, and real spaces/tabs/newlines. The
    # expected output is independently derived from the generated records.
    rng = random.SystemRandom()
    base_id = rng.randrange(10000, 90000)
    codepoints = rng.sample([0x00A3, 0x03A9, 0x0416, 0x20AC, 0x2603, 0x2728, 0x4E2D], 4)
    escapes = [
        "\\u" + (format(cp, "04X") if i % 2 else format(cp, "04x"))
        for i, cp in enumerate(codepoints)
    ]
    rows = [
        (base_id, "GeneratedA", "   Mixed\t whitespace  across\nlines " + escapes[0] + " end   "),
        (base_id + 1, "GeneratedB", escapes[1] + "  middle\t" + escapes[2] + "\nlast " + escapes[3]),
        (base_id + 2, "GeneratedC", "Value \\u0042 and lowercase \\u007a"),
        (base_id + 3, "GeneratedD", " \t\n   "),
    ]
    generated_csv = "".join(f'{row_id},{category},"{text}"\n' for row_id, category, text in rows)
    expected = "".join(
        f"{row_id}\t{category}\t{normalized_text(text)}\n"
        for row_id, category, text in rows
    )
    generated_content = run_parser(generated_csv)
    assert generated_content.strip() == expected.strip(), (
        "The compiled parser failed on generated Unicode or whitespace cases."
    )

    # Leave the requested artifact corresponding to the task's original input.
    restored_content = run_parser(CANONICAL_INPUT)
    assert restored_content.strip() == EXPECTED_CANONICAL.strip()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
