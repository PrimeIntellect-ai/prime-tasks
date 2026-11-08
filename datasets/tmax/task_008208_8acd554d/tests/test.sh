#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import struct
import subprocess

WORKSPACE_DIR = "/home/user/workspace"
DATA_BIN = os.path.join(WORKSPACE_DIR, "data.bin")
MAKEFILE = os.path.join(WORKSPACE_DIR, "Makefile")
PROCESSOR_C = os.path.join(WORKSPACE_DIR, "processor.c")
PROCESSOR_EXE = os.path.join(WORKSPACE_DIR, "processor")
RESULT_TXT = os.path.join(WORKSPACE_DIR, "result.txt")


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def run_processor(path):
    if os.path.exists(RESULT_TXT):
        os.remove(RESULT_TXT)
    completed = subprocess.run(
        [PROCESSOR_EXE, path], cwd=WORKSPACE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=5
    )
    assert completed.returncode == 0, (
        f"processor failed for {path}: stdout={completed.stdout!r}, "
        f"stderr={completed.stderr!r}"
    )
    assert os.path.isfile(RESULT_TXT), "processor did not create result.txt"
    with open(RESULT_TXT, "r") as f:
        return f.read().strip()


def test_makefile_fixed():
    assert os.path.isfile(MAKEFILE), f"File {MAKEFILE} does not exist."
    with open(MAKEFILE, 'r') as f:
        content = f.read()

    assert "processor: processor.c" in content, "Makefile missing target."
    assert "\tgcc" in content, "Makefile must use a tab instead of spaces for the command."


def test_processor_c_fixed():
    assert os.path.isfile(PROCESSOR_C), f"File {PROCESSOR_C} does not exist."
    with open(PROCESSOR_C, 'r') as f:
        content = f.read()

    # Preserve the original source assertions.
    has_packed_attr = "__attribute__((packed))" in content.replace(" ", "")
    has_pragma_pack = "#pragmapack" in content.replace(" ", "")
    assert has_packed_attr or has_pragma_pack, "processor.c must define the struct as packed to fix the deserialization bug."
    assert "__asm__" in content or "asm(" in content or "asm (" in content or "asm\n" in content, "processor.c must implement inline assembly for the gcd function."

    # Ensure the required constructs are code rather than comment keywords.
    code = strip_comments(content)
    compact = re.sub(r"[ \t]", "", code)
    assert "__attribute__((packed))" in compact or re.search(r"#\s*pragma\s+pack", code), \
        "The packed-record declaration must be present outside comments."

    asm_blocks = re.findall(
        r"(?:__asm__|__asm|asm)\s*(?:volatile\s*)?\((.*?)\)\s*;",
        code, flags=re.S
    )
    assert asm_blocks, "gcd must contain a real inline assembly statement, not an assembly keyword in a comment."
    asm_text = "\n".join(asm_blocks)
    instructions = re.findall(
        r"(?:^|[\\n;\"'])\s*(?:[0-9]+:)?\s*"
        r"(mov|xor|test|cmp|sub|add|neg|cdq|cqo|idiv|div|j[a-z]+|loop|shr|sar|shl|and|or|xchg)"
        r"[bwlq]?\b",
        asm_text, flags=re.I
    )
    assert len(instructions) >= 3, "The inline assembly block must contain actual GCD computation instructions."


def test_make_builds_real_executable():
    if os.path.exists(PROCESSOR_EXE):
        os.remove(PROCESSOR_EXE)
    if os.path.exists(RESULT_TXT):
        os.remove(RESULT_TXT)

    completed = subprocess.run(
        ["make", "-B"], cwd=WORKSPACE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20
    )
    assert completed.returncode == 0, (
        f"make failed: stdout={completed.stdout!r}, stderr={completed.stderr!r}"
    )
    assert os.path.isfile(PROCESSOR_EXE), f"Executable {PROCESSOR_EXE} was not built."
    assert os.access(PROCESSOR_EXE, os.X_OK), f"{PROCESSOR_EXE} is not executable."
    with open(PROCESSOR_EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "processor must be a compiled ELF executable."


def test_executable_exists():
    assert os.path.isfile(PROCESSOR_EXE), f"Executable {PROCESSOR_EXE} was not built."
    assert os.access(PROCESSOR_EXE, os.X_OK), f"{PROCESSOR_EXE} is not executable."


def test_result_txt_correct():
    assert os.path.isfile(DATA_BIN), f"File {DATA_BIN} does not exist."
    content = run_processor(DATA_BIN)
    assert content == "GCD: 18", f"Expected result.txt to contain 'GCD: 18', but got '{content}'."


def test_processor_on_derived_payloads(tmp_path):
    cases = [
        [(b'A', 14), (b'B', 25), (b'A', 28), (b'B', 5)],
        [(b'A', 100), (b'B', 120), (b'A', -23), (b'B', 1)],
        [(b'B', 103), (b'A', 40), (b'A', 61)],
        [(b'A', 270), (b'B', 100), (b'B', 92)],
    ]

    for index, records in enumerate(cases):
        payload = tmp_path / f"case_{index}.bin"
        sum_a = sum(value for category, value in records if category == b'A')
        sum_b = sum(value for category, value in records if category == b'B')
        with open(payload, "wb") as f:
            for category, value in records:
                f.write(struct.pack("<ci", category, value))

        expected = f"GCD: {math.gcd(sum_a, sum_b)}"
        actual = run_processor(str(payload))
        assert actual == expected, f"For records {records!r}, expected {expected!r}, got {actual!r}."


def test_gcd_function_directly(tmp_path):
    obj = tmp_path / "processor.o"
    harness_c = tmp_path / "gcd_harness.c"
    harness = tmp_path / "gcd_harness"
    pairs = [(36, 54), (42, 30), (77, 121), (101, 103), (270, 192), (65535, 255), (123456, 7890)]

    compiled = subprocess.run(
        ["gcc", "-O2", "-Dmain=processor_program_main", "-c", PROCESSOR_C, "-o", str(obj)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compiled.returncode == 0, f"processor.c does not compile: {compiled.stderr}"

    rows = ",\n".join(f"{{{a}, {b}, {math.gcd(a, b)}}}" for a, b in pairs)
    harness_c.write_text(f'''\
#include <stdio.h>
int gcd(int, int);
int main(void) {{
    int cases[][3] = {{ {rows} }};
    int n = (int)(sizeof(cases) / sizeof(cases[0]));
    for (int i = 0; i < n; ++i) {{
        int got = gcd(cases[i][0], cases[i][1]);
        if (got != cases[i][2]) {{
            fprintf(stderr, "%d %d: expected %d, got %d\\n",
                    cases[i][0], cases[i][1], cases[i][2], got);
            return 1;
        }}
    }}
    return 0;
}}
''')
    linked = subprocess.run(
        ["gcc", str(harness_c), str(obj), "-o", str(harness)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert linked.returncode == 0, f"Could not link gcd test harness: {linked.stderr}"

    checked = subprocess.run(
        [str(harness)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=5
    )
    assert checked.returncode == 0, f"gcd failed direct tests: {checked.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
