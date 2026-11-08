#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import subprocess
import tempfile
import time

BUILD = "/home/user/build_env"
RESOLVER = os.path.join(BUILD, "resolver.c")
VALIDATOR = os.path.join(BUILD, "validator")
OUTPUT = os.path.join(BUILD, "output.log")
EXPECTED = "Resolved Dependencies: 5"

# Preserve the original final-state assertions.
assert os.path.isfile(RESOLVER), f"The file {RESOLVER} does not exist. You must create the C implementation."
assert os.path.isfile(VALIDATOR), f"The executable {VALIDATOR} does not exist. Make sure you ran 'make'."
assert os.access(VALIDATOR, os.X_OK), f"The file {VALIDATOR} is not executable."
assert os.path.isfile(OUTPUT), f"The file {OUTPUT} does not exist. Make sure you ran the executable and redirected output."
with open(OUTPUT, "r", encoding="utf-8") as f:
    original_log = f.read().strip()
assert EXPECTED in original_log, (
    f"The output.log does not contain the expected result. Expected '{EXPECTED}', got '{original_log}'."
)

# Force a fresh Makefile build rather than trusting a submitted executable.
for pattern in ("*.o", "*.a", "*.so"):
    for path in glob.glob(os.path.join(BUILD, pattern)):
        os.remove(path)
os.remove(VALIDATOR)
subprocess.run(["make"], cwd=BUILD, check=True, timeout=30,
               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

assert os.path.isfile(VALIDATOR), "make did not create validator"
assert os.access(VALIDATOR, os.X_OK), "make did not create an executable validator"
with open(VALIDATOR, "rb") as f:
    assert f.read(4) == b"\x7fELF", "validator must be a native ELF executable"

# The freshly linked executable must contain the implementation symbol.
nm = subprocess.run(["nm", VALIDATOR], check=True, timeout=10,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout
assert re.search(r"^[0-9A-Fa-f]+\s+[Tt]\s+resolve_deps$", nm, re.MULTILINE), (
    "validator does not contain a linked resolve_deps implementation"
)

# resolver.c must be a real Makefile dependency: changing it must rebuild validator.
old_mtime = os.stat(VALIDATOR).st_mtime_ns
time.sleep(1.1)
os.utime(RESOLVER, None)
subprocess.run(["make"], cwd=BUILD, check=True, timeout=30,
               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
assert os.stat(VALIDATOR).st_mtime_ns > old_mtime, (
    "Makefile does not rebuild validator when resolver.c changes"
)

# Execute the actual artifact and check the exact output produced by main.c.
run = subprocess.run([VALIDATOR], cwd=BUILD, check=True, timeout=10,
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
assert run.stdout == EXPECTED + "\n", (
    f"validator produced unexpected output: {run.stdout!r}"
)
assert original_log == EXPECTED, f"output.log must contain exactly {EXPECTED!r}"

# Compile resolver.c into an independent driver and exercise varying graphs.
runner_source = r'''
#include <stdio.h>
#include <stdlib.h>

int resolve_deps(int matrix[5][5], int num_nodes, int start_node);

int main(int argc, char **argv) {
    int matrix[5][5];
    int n, start, k = 3;
    if (argc != 28) return 2;
    n = atoi(argv[1]);
    start = atoi(argv[2]);
    for (int i = 0; i < 5; ++i)
        for (int j = 0; j < 5; ++j)
            matrix[i][j] = atoi(argv[k++]);
    printf("%d\n", resolve_deps(matrix, n, start));
    return 0;
}
'''

with tempfile.TemporaryDirectory(prefix="resolver-test-") as td:
    driver_c = os.path.join(td, "driver.c")
    driver = os.path.join(td, "driver")
    with open(driver_c, "w", encoding="utf-8") as f:
        f.write(runner_source)
    subprocess.run(["gcc", "-std=c11", "-Wall", "-Wextra", RESOLVER, driver_c, "-o", driver],
                   check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def expected_count(matrix, n, start):
        seen = {start}
        pending = [start]
        while pending:
            node = pending.pop()
            for nxt in range(n):
                if matrix[node][nxt] == 1 and nxt not in seen:
                    seen.add(nxt)
                    pending.append(nxt)
        return len(seen)

    cases = []
    cases.append((5, 0, [[0,1,1,0,0], [0,0,0,1,0], [0,0,0,1,1], [0,0,0,0,1], [0,0,0,0,0]]))
    cases.append((5, 3, [[0,1,0,0,0], [0,0,1,0,0], [1,0,0,0,0], [0,0,0,0,1], [0,0,0,1,0]]))
    cases.append((5, 4, [[0]*5 for _ in range(5)]))

    rng = random.Random(731942)
    for _ in range(45):
        n = rng.randint(1, 5)
        start = rng.randrange(n)
        matrix = [[rng.randint(0, 1) for _ in range(5)] for _ in range(5)]
        cases.append((n, start, matrix))

    for index, (n, start, matrix) in enumerate(cases):
        want = expected_count(matrix, n, start)
        args = [driver, str(n), str(start)] + [str(matrix[i][j]) for i in range(5) for j in range(5)]
        result = subprocess.run(args, check=True, timeout=5,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert result.stdout.strip() == str(want), (
            f"resolve_deps failed graph case {index}: expected {want}, got {result.stdout!r}"
        )
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
