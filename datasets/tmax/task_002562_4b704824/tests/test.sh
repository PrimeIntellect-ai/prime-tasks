#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

BUILD = Path("/home/user/math_build")

EXPECTED_MAIN = b'''#include <stdio.h>
#include "table.h"

int main() {
    int sum = 0;
    for(int i = 0; i < 10; i++) {
        sum += magic_table[i];
    }
    printf("%d\\n", sum);
    return 0;
}
'''

EXPECTED_MAKEFILE = b'''all: math_app

generator: generator.c mathblob.o
\tgcc -o generator generator.c mathblob.o

table.h: generator
\t./generator

math_app: main.c table.h
\tgcc -o math_app main.c

clean:
\trm -f generator table.h math_app
'''

def parse_table(path):
    content = Path(path).read_text()
    match = re.search(r"magic_table\s*\[\s*10\s*\]\s*=\s*\{(.*?)\}", content, re.S)
    assert match, f"{path} does not contain a ten-element magic_table initializer"
    return [int(value) for value in re.findall(r"-?\d+", match.group(1))]

def test_result_log():
    log_path = "/home/user/math_build/result.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing. Did you redirect the output of ./math_app?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "148", f"Expected result.log to contain '148', but found '{content}'"

def test_math_app_compiled():
    app_path = "/home/user/math_build/math_app"
    assert os.path.isfile(app_path), f"Executable {app_path} is missing. Did you run make?"
    assert os.access(app_path, os.X_OK), f"File {app_path} is not executable."

def test_generator_c_fixed():
    gen_path = "/home/user/math_build/generator.c"
    assert os.path.isfile(gen_path), f"File {gen_path} is missing."

    with open(gen_path, "r") as f:
        content = f.read()

    assert re.search(r"calculate_magic\s*\(\s*i\s*\*\s*2\s*,\s*i\s*\+\s*1\s*\)", content) or \
           re.search(r"calculate_magic\s*\(\s*2\s*\*\s*i\s*,\s*i\s*\+\s*1\s*\)", content), \
           "generator.c does not seem to call calculate_magic with the correct arguments (i * 2, i + 1)."

def test_main_c_unmodified():
    main_path = "/home/user/math_build/main.c"
    assert os.path.isfile(main_path), f"File {main_path} is missing."
    with open(main_path, "r") as f:
        content = f.read()
    assert "sum += magic_table[i];" in content, "main.c appears to have been modified."
    assert Path(main_path).read_bytes() == EXPECTED_MAIN, "main.c was modified."

def test_makefile_unmodified():
    makefile_path = "/home/user/math_build/Makefile"
    assert os.path.isfile(makefile_path), f"File {makefile_path} is missing."
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "math_app: main.c table.h" in content, "Makefile appears to have been modified."
    assert Path(makefile_path).read_bytes() == EXPECTED_MAKEFILE, "Makefile was modified."

def test_clean_rebuild_and_execution():
    subprocess.run(["make", "clean"], cwd=BUILD, check=True, timeout=30)
    subprocess.run(["make"], cwd=BUILD, check=True, timeout=30)

    generator = BUILD / "generator"
    app = BUILD / "math_app"
    assert generator.is_file() and os.access(generator, os.X_OK), "make did not build an executable generator"
    assert app.is_file() and os.access(app, os.X_OK), "make did not build an executable math_app"

    expected_real = [((i * 2) * (i * 2)) // (i + 1) for i in range(10)]
    assert parse_table(BUILD / "table.h") == expected_real, "generator produced incorrect table values"

    app_output = subprocess.run([str(app)], cwd=BUILD, check=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=10).stdout
    assert app_output == b"148\n", f"math_app produced unexpected output: {app_output!r}"
    assert (BUILD / "result.log").read_bytes() == app_output, \
        "result.log is not the exact redirected output of the rebuilt math_app"

def test_generator_actually_calls_calculate_magic():
    salt = secrets.randbelow(500000) + 100000
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        shim = tmp_path / "shim.c"
        executable = tmp_path / "generator_test"
        shim.write_text(f'''#include <stdio.h>
#include <stdlib.h>

static int calls = 0;

int calculate_magic(int a, int b) {{
    if (calls >= 10 || a != calls * 2 || b != calls + 1) {{
        fprintf(stderr, "bad calculate_magic call %d: (%d, %d)\\n", calls, a, b);
        exit(81);
    }}
    int value = {salt} + calls * 137 + a * 11 + b * 7;
    calls++;
    return value;
}}

__attribute__((destructor)) static void verify_calls(void) {{
    if (calls != 10) _Exit(82);
}}
''')
        subprocess.run(["gcc", "-std=c11", "-o", str(executable),
                        str(BUILD / "generator.c"), str(shim)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        subprocess.run([str(executable)], cwd=tmp_path, check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        expected = [salt + i * 137 + (i * 2) * 11 + (i + 1) * 7 for i in range(10)]
        assert parse_table(tmp_path / "table.h") == expected, \
            "generator did not use the values returned by calculate_magic"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
