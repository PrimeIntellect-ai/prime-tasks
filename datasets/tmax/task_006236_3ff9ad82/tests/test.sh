#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

SOURCE = "/home/user/event_parser.c"
EXECUTABLE = "/home/user/event_parser"


def expected_index(days, hour, timezone_offset):
    return (days * 24 + hour + timezone_offset) % 1024


def run_cli(executable, days, hour, timezone_offset):
    result = subprocess.run(
        [executable, str(days), str(hour), str(timezone_offset)],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"Program crashed or returned {result.returncode} for "
        f"{days} {hour} {timezone_offset}. stderr: {result.stderr}"
    )
    return result.stdout.strip()


def test_solution_txt_content():
    path = "/home/user/solution.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "1020", f"Expected solution.txt to contain '1020', but found '{content}'"


def test_source_and_independently_compiled_calculate_index():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    with open(SOURCE, "r") as f:
        source = f.read()

    assert re.search(
        r"\bint\s+calculate_index\s*\(\s*int\s+days_since_epoch\s*,\s*"
        r"int\s+hour\s*,\s*int\s+timezone_offset\s*\)",
        source,
    ), "The calculate_index signature was changed."
    assert re.search(r"\bif\s*\(\s*argc\s*!=\s*4\s*\)", source), "CLI argument-count parsing was changed."
    for argno in (1, 2, 3):
        assert re.search(rf"\batoi\s*\(\s*argv\s*\[\s*{argno}\s*\]\s*\)", source), \
            "CLI integer argument parsing was changed."
    assert re.search(r"\bassert\s*\(\s*index\s*>=\s*0\s*&&\s*index\s*<\s*1024\s*\)", source), \
        "The original index range assertion must remain."

    with tempfile.TemporaryDirectory() as td:
        obj = os.path.join(td, "event_parser.o")
        harness_c = os.path.join(td, "harness.c")
        harness = os.path.join(td, "harness")
        with open(harness_c, "w") as f:
            f.write(r'''#include <stdio.h>
int calculate_index(int days_since_epoch, int hour, int timezone_offset);
int main(void) {
    int d, h, tz;
    while (scanf("%d %d %d", &d, &h, &tz) == 3) {
        printf("%d\n", calculate_index(d, h, tz));
    }
    return 0;
}
''')

        compile_obj = subprocess.run(
            ["gcc", "-Dmain=event_parser_cli_main", "-c", SOURCE, "-o", obj],
            capture_output=True,
            text=True,
        )
        assert compile_obj.returncode == 0, f"Submitted source does not compile: {compile_obj.stderr}"
        compile_harness = subprocess.run(
            ["gcc", harness_c, obj, "-o", harness],
            capture_output=True,
            text=True,
        )
        assert compile_harness.returncode == 0, f"Could not link calculate_index: {compile_harness.stderr}"

        cases = [(0, 4, -8), (0, 0, -1), (1, 0, 0)]
        cases.extend(
            (d, h, tz)
            for d in range(8)
            for h in range(24)
            for tz in range(-12, 15)
        )
        rng = secrets.SystemRandom()
        cases.extend(
            (rng.randrange(0, 1_000_001), rng.randrange(0, 24), rng.randrange(-12, 15))
            for _ in range(1000)
        )

        input_data = "".join(f"{d} {h} {tz}\n" for d, h, tz in cases)
        result = subprocess.run(
            [harness], input=input_data, capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, f"calculate_index crashed. stderr: {result.stderr}"
        outputs = result.stdout.splitlines()
        assert len(outputs) == len(cases), "calculate_index did not return one result per input."
        for case, output in zip(cases, outputs):
            expected = str(expected_index(*case))
            assert output.strip() == expected, (
                f"calculate_index{case} returned {output!r}; expected {expected}."
            )


def test_event_parser_compiled_and_fixed():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist. Did you recompile?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "event_parser must be a compiled executable, not a script."

    # Preserve the original fixed assertions.
    assert run_cli(EXECUTABLE, 0, 4, -8) == "1020"
    assert run_cli(EXECUTABLE, 0, 0, -1) == "1023"
    assert run_cli(EXECUTABLE, 1, 0, 0) == "24"

    # Exercise the delivered executable on verifier-generated inputs.
    rng = secrets.SystemRandom()
    cases = [
        (0, h, tz) for h in range(24) for tz in range(-12, 1)
    ]
    cases.extend(
        (rng.randrange(0, 1_000_001), rng.randrange(0, 24), rng.randrange(-12, 15))
        for _ in range(64)
    )
    for case in cases:
        output = run_cli(EXECUTABLE, *case)
        expected = str(expected_index(*case))
        assert output == expected, f"For inputs {case}, expected {expected}, got {output!r}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
