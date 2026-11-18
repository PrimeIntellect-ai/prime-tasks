#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile

HOME = "/home/user"
PROCESS_C = f"{HOME}/process.c"
RUN_SH = f"{HOME}/run.sh"
DATA = f"{HOME}/data.csv"
SUMMARY = f"{HOME}/summary.csv"


def run_script():
    return subprocess.run(
        ["./run.sh"], cwd=HOME, capture_output=True, text=True, timeout=20
    )


def read_summary():
    assert os.path.isfile(SUMMARY), "/home/user/summary.csv was not created by run.sh"
    with open(SUMMARY, "r") as f:
        return f.read().strip()


def test_complete_pipeline():
    # Preserve the original existence and executable assertions.
    assert os.path.isfile(PROCESS_C), "/home/user/process.c is missing"
    assert os.path.isfile(RUN_SH), "/home/user/run.sh is missing"
    assert os.access(RUN_SH, os.X_OK), "/home/user/run.sh is not executable"

    # Preserve the original fixed-data execution and exact output assertion.
    if os.path.exists(SUMMARY):
        os.remove(SUMMARY)
    result = run_script()
    assert result.returncode == 0, f"run.sh failed to execute. stderr: {result.stderr}"
    expected_content = "ALPHA,20.40\nBETA,10.00\nGAMMA,0.50"
    content = read_summary()
    assert content == expected_content, (
        "The content of /home/user/summary.csv is incorrect.\n"
        f"Expected:\n{expected_content}\nGot:\n{content}"
    )

    # Compile process.c independently and exercise it on unpredictable rows.
    rng = random.SystemRandom()
    categories = []
    while len(categories) < 4:
        name = "T" + "".join(rng.choice(string.ascii_uppercase) for _ in range(6))
        if name not in categories:
            categories.append(name)

    rows = []
    expected_lines = []
    for i in range(8):
        cat = categories[i % len(categories)]
        a, b, c = (rng.randrange(-20, 31) for _ in range(3))
        rows.append(f"{cat},{a},{b},{c}")
        score = 0.5 * a + 0.3 * b + 0.2 * c
        expected_lines.append(f"{cat},{score:.2f}")
    direct_input = "\n".join(rows) + "\n"

    with tempfile.TemporaryDirectory() as td:
        executable = os.path.join(td, "process-under-test")
        compiled = subprocess.run(
            ["gcc", "-std=c11", "-O2", PROCESS_C, "-o", executable],
            capture_output=True, text=True, timeout=20
        )
        assert compiled.returncode == 0, f"process.c did not compile: {compiled.stderr}"
        direct = subprocess.run(
            [executable], input=direct_input, capture_output=True, text=True, timeout=10
        )
        assert direct.returncode == 0, f"compiled process failed: {direct.stderr}"
        assert direct.stdout.strip() == "\n".join(expected_lines), (
            "process.c produced incorrect output on verifier-generated input.\n"
            f"Expected:\n{'\n'.join(expected_lines)}\nGot:\n{direct.stdout.strip()}"
        )

    # Verify run.sh really compiles and executes process.c with data.csv as stdin,
    # and aggregates/sorts the program's output rather than writing a fixed answer.
    with open(PROCESS_C, "r") as f:
        original_source = f.read()
    with open(DATA, "r") as f:
        original_data = f.read()

    dynamic_data = "\n".join(
        f"{categories[i % 4]},{rng.randrange(1,20)},{rng.randrange(1,20)},{rng.randrange(1,20)}"
        for i in range(7)
    ) + "\n"
    marker = f"/tmp/process-ran-{rng.randrange(1 << 62)}"

    out_cats = [categories[2], categories[0], categories[2], categories[1], categories[0]]
    out_cents = [rng.randrange(10, 500) for _ in out_cats]
    totals = {}
    for cat, cents in zip(out_cats, out_cents):
        totals[cat] = totals.get(cat, 0) + cents
    expected_dynamic = "\n".join(
        f"{cat},{totals[cat] / 100:.2f}" for cat in sorted(totals)
    )

    def c_escape(value):
        return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

    emit_lines = "\n".join(
        f'    printf("{cat},%.2f\\n", {cents} / 100.0);'
        for cat, cents in zip(out_cats, out_cents)
    )
    instrumented_source = f'''#include <stdio.h>
#include <stddef.h>
int main(void) {{
    static const char expected[] = "{c_escape(dynamic_data)}";
    size_t i = 0;
    int ch;
    while ((ch = getchar()) != EOF) {{
        if (i >= sizeof(expected) - 1 || ch != (unsigned char)expected[i++]) return 41;
    }}
    if (i != sizeof(expected) - 1) return 42;
    FILE *m = fopen("{c_escape(marker)}", "w");
    if (!m) return 43;
    fputs("ran", m);
    fclose(m);
{emit_lines}
    return 0;
}}
'''

    try:
        with open(DATA, "w") as f:
            f.write(dynamic_data)
        with open(PROCESS_C, "w") as f:
            f.write(instrumented_source)
        if os.path.exists(marker):
            os.remove(marker)
        if os.path.exists(SUMMARY):
            os.remove(SUMMARY)
        process_path = os.path.join(HOME, "process")
        if os.path.exists(process_path):
            os.remove(process_path)

        result = run_script()
        assert result.returncode == 0, f"run.sh failed on generated input: {result.stderr}"
        assert os.path.isfile(marker), "run.sh did not execute the C program it compiled"
        assert os.path.isfile(process_path), "run.sh did not create the executable named process"
        assert os.access(process_path, os.X_OK), "the generated process file is not executable"
        with open(process_path, "rb") as f:
            assert f.read(4) == b"\x7fELF", "process is not a compiled executable"
        assert read_summary() == expected_dynamic, (
            "run.sh did not aggregate and alphabetically sort the compiled program's output.\n"
            f"Expected:\n{expected_dynamic}\nGot:\n{read_summary()}"
        )
    finally:
        with open(PROCESS_C, "w") as f:
            f.write(original_source)
        with open(DATA, "w") as f:
            f.write(original_data)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
