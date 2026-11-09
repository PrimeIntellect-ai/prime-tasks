#!/bin/bash
set -u
mkdir -p /logs/verifier

verify() {
    set -o pipefail

    cd /home/user/pr_review || return 1

    # Force a clean build so stale or fabricated artifacts cannot satisfy the verifier.
    rm -f test_runner
    rm -rf rust_interner/target
    make || return 1
    test -x /home/user/pr_review/test_runner || return 1

    # Run the required executable under Valgrind and create the required report
    # from this actual invocation, including both stdout and stderr.
    valgrind --leak-check=full --show-leak-kinds=all \
        --errors-for-leak-kinds=definite --error-exitcode=97 \
        ./test_runner 2>&1 | tee /home/user/valgrind_report.txt
    test "${PIPESTATUS[0]}" -eq 0 || return 1

    # Build an independent harness with verifier-generated strings and expected IDs.
    python3 - <<'PY' || return 1
import os
import random
import string

rng = random.SystemRandom()
values = []
for _ in range(80):
    values.append('v_' + ''.join(rng.choice(string.ascii_letters + string.digits) for _ in range(24)))

calls = values[:]
for _ in range(240):
    calls.append(rng.choice(values))
rng.shuffle(calls)

seen = {}
expected = []
for value in calls:
    if value not in seen:
        seen[value] = len(seen)
    expected.append(seen[value])

path = '/tmp/verifier_interner_test.c'
with open(path, 'w') as f:
    f.write(r'''#include <stddef.h>
#include <stdio.h>

typedef struct Interner Interner;
extern Interner* interner_new(void);
extern size_t interner_add(Interner*, const char*);
extern void interner_free(Interner*);

int main(void) {
    Interner *interner = interner_new();
    if (!interner) return 10;
''')
    for value, wanted in zip(calls, expected):
        f.write('    if (interner_add(interner, "%s") != %d) return 20;\n' % (value, wanted))
    f.write(r'''    interner_free(interner);

    /* A fresh interner must have independent numbering and also be freed. */
    interner = interner_new();
    if (!interner) return 30;
    if (interner_add(interner, "fresh_value") != 0) return 31;
    if (interner_add(interner, "another_value") != 1) return 32;
    if (interner_add(interner, "fresh_value") != 0) return 33;
    interner_free(interner);
    puts("Verifier tests passed.");
    return 0;
}
''')
PY

    test -f rust_interner/target/debug/librust_interner.a || return 1
    gcc -g -O0 /tmp/verifier_interner_test.c \
        -L./rust_interner/target/debug -lrust_interner -lpthread -ldl -lm \
        -o /tmp/verifier_interner_test || return 1

    valgrind --leak-check=full --show-leak-kinds=all \
        --errors-for-leak-kinds=definite --error-exitcode=98 \
        /tmp/verifier_interner_test > /tmp/verifier_valgrind.txt 2>&1 || {
            cat /tmp/verifier_valgrind.txt
            return 1
        }
    cat /tmp/verifier_valgrind.txt
    grep -q 'Verifier tests passed.' /tmp/verifier_valgrind.txt || return 1

    # Preserve the original final-state assertions.
    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re

def test_cargo_toml_fixed():
    cargo_path = "/home/user/pr_review/rust_interner/Cargo.toml"
    assert os.path.isfile(cargo_path), f"File {cargo_path} is missing."
    with open(cargo_path, 'r') as f:
        content = f.read()
        assert "crate-type" in content and "staticlib" in content, "Cargo.toml must specify crate-type = [\"staticlib\"]"

def test_valgrind_report_exists():
    report_path = "/home/user/valgrind_report.txt"
    assert os.path.isfile(report_path), f"Valgrind report {report_path} is missing."

def test_valgrind_report_no_leaks():
    report_path = "/home/user/valgrind_report.txt"
    assert os.path.isfile(report_path), f"Valgrind report {report_path} is missing."
    with open(report_path, 'r') as f:
        content = f.read()
    assert "Tests passed." in content, "The test executable did not print 'Tests passed.' Check if it ran successfully."
    no_leaks_possible = "All heap blocks were freed -- no leaks are possible" in content
    definitely_lost_zero = re.search(r"definitely lost:\s+0 bytes in 0 blocks", content) is not None
    assert no_leaks_possible or definitely_lost_zero, "Valgrind report does not show 0 bytes definitely lost. Memory leak is not fully fixed."

def test_executable_exists():
    exe_path = "/home/user/pr_review/test_runner"
    assert os.path.isfile(exe_path), f"Executable {exe_path} is missing. Did you run make?"
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
