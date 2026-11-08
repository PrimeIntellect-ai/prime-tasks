#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from fractions import Fraction

import pytest

RATIONAL_SCRIPT = "/home/user/rational.sh"
TEST_SCRIPT = "/home/user/test_rational.sh"
TEST_LOG = "/home/user/test_result.log"
CALL_LOG = "/tmp/property_calls.log"
COUNTER = "/tmp/property_counter"


def run_bash_function(script_path, func_name, *args):
    cmd = 'source "$1"; shift; fn="$1"; shift; "$fn" "$@"'
    result = subprocess.run(
        ["bash", "-c", cmd, "bash", script_path, func_name, *map(str, args)],
        capture_output=True,
        text=True,
    )
    return result.stdout.strip(), result.returncode


def expected_add(args):
    n1, d1, n2, d2 = args
    value = Fraction(n1, d1) + Fraction(n2, d2)
    return f"{value.numerator}/{value.denominator}"


def expected_mul(args):
    n1, d1, n2, d2 = args
    value = Fraction(n1, d1) * Fraction(n2, d2)
    return f"{value.numerator}/{value.denominator}"


def test_scripts_exist():
    assert os.path.isfile(RATIONAL_SCRIPT), f"{RATIONAL_SCRIPT} is missing."
    assert os.path.isfile(TEST_SCRIPT), f"{TEST_SCRIPT} is missing."


def test_add_rat_logic():
    assert os.path.isfile(RATIONAL_SCRIPT), f"{RATIONAL_SCRIPT} is missing."

    test_cases = [
        ((1, 4, 1, 4), "1/2"),
        ((-1, 3, 1, -2), "-5/6"),
        ((0, 5, 0, 8), "0/1"),
        ((1, 3, 1, 3), "2/3"),
        ((5, 2, -5, 2), "0/1"),
        ((-3, -4, -1, -4), "1/1"),
    ]

    rng = random.SystemRandom()
    for _ in range(150):
        args = (
            rng.randint(-1000, 1000),
            rng.choice([i for i in range(-1000, 1001) if i != 0]),
            rng.randint(-1000, 1000),
            rng.choice([i for i in range(-1000, 1001) if i != 0]),
        )
        test_cases.append((args, expected_add(args)))

    for args, expected in test_cases:
        out, rc = run_bash_function(RATIONAL_SCRIPT, "add_rat", *args)
        assert rc == 0, f"add_rat failed with return code {rc} for args {args}"
        assert out == expected, f"add_rat {args} returned '{out}', expected '{expected}'"


def test_mul_rat_logic():
    assert os.path.isfile(RATIONAL_SCRIPT), f"{RATIONAL_SCRIPT} is missing."

    test_cases = [
        ((-2, 3, 6, 5), "-4/5"),
        ((-1, -2, -3, -4), "1/8"),
        ((5, 1, 0, 2), "0/1"),
        ((3, 4, 4, 3), "1/1"),
        ((-1, 2, 2, 1), "-1/1"),
    ]

    rng = random.SystemRandom()
    for _ in range(150):
        args = (
            rng.randint(-1000, 1000),
            rng.choice([i for i in range(-1000, 1001) if i != 0]),
            rng.randint(-1000, 1000),
            rng.choice([i for i in range(-1000, 1001) if i != 0]),
        )
        test_cases.append((args, expected_mul(args)))

    for args, expected in test_cases:
        out, rc = run_bash_function(RATIONAL_SCRIPT, "mul_rat", *args)
        assert rc == 0, f"mul_rat failed with return code {rc} for args {args}"
        assert out == expected, f"mul_rat {args} returned '{out}', expected '{expected}'"


def test_exact_arity_and_helper():
    for func in ("add_rat", "mul_rat"):
        for args in ((1, 2, 3), (1, 2, 3, 4, 5)):
            _, rc = run_bash_function(RATIONAL_SCRIPT, func, *args)
            assert rc != 0, f"{func} must reject {len(args)} arguments"

    result = subprocess.run(
        ["bash", "-c", 'source "$1"; declare -F', "bash", RATIONAL_SCRIPT],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Could not source {RATIONAL_SCRIPT}: {result.stderr}"
    functions = {line.split()[-1] for line in result.stdout.splitlines() if line.split()}
    assert "add_rat" in functions and "mul_rat" in functions
    helpers = functions - {"add_rat", "mul_rat"}
    assert helpers, "rational.sh must define a helper function for GCD reduction"


def test_no_external_binaries():
    assert os.path.isfile(RATIONAL_SCRIPT), f"{RATIONAL_SCRIPT} is missing."
    with open(RATIONAL_SCRIPT, "r") as f:
        content = f.read()

    forbidden = ["bc", "awk", "python", "perl", "ruby", "node"]
    for word in forbidden:
        assert word not in content.split(), f"Forbidden external tool '{word}' found in {RATIONAL_SCRIPT}"


def write_success_instrument():
    with open(RATIONAL_SCRIPT, "w") as f:
        f.write(r'''#!/bin/bash
_probe_gcd() {
    local a=$1 b=$2 t
    (( a < 0 )) && (( a = -a ))
    (( b < 0 )) && (( b = -b ))
    while (( b != 0 )); do
        (( t = a % b ))
        (( a = b ))
        (( b = t ))
    done
    printf '%s\n' "$a"
}
add_rat() {
    [[ $# -eq 4 ]] || return 2
    printf '%s %s %s %s\n' "$1" "$2" "$3" "$4" >> /tmp/property_calls.log
    local n=$(( $1 * $4 + $3 * $2 )) d=$(( $2 * $4 )) g
    if (( n == 0 )); then
        printf '0/1\n'
        return 0
    fi
    if (( d < 0 )); then
        (( n = -n, d = -d ))
    fi
    g=$(_probe_gcd "$n" "$d")
    printf '%s/%s\n' "$((n / g))" "$((d / g))"
}
''')


def write_failure_instrument():
    with open(RATIONAL_SCRIPT, "w") as f:
        f.write(r'''#!/bin/bash
add_rat() {
    [[ $# -eq 4 ]] || return 2
    local n=0
    printf '%s %s %s %s\n' "$1" "$2" "$3" "$4" >> /tmp/property_calls.log
    if [[ -f /tmp/property_counter ]]; then
        IFS= read -r n < /tmp/property_counter || true
    fi
    (( n += 1 ))
    printf '%s\n' "$n" > /tmp/property_counter
    printf 'forced_mismatch_%s\n' "$n"
}
''')


def read_calls():
    assert os.path.isfile(CALL_LOG), "The property test did not invoke the sourced add_rat"
    calls = []
    with open(CALL_LOG, "r") as f:
        for line in f:
            fields = line.split()
            assert len(fields) == 4, f"add_rat was not called with four arguments: {line!r}"
            calls.append(tuple(map(int, fields)))
    return calls


def test_test_script_execution_and_properties():
    assert os.path.isfile(TEST_SCRIPT), f"{TEST_SCRIPT} is missing."
    with open(RATIONAL_SCRIPT, "rb") as f:
        original = f.read()

    try:
        for path in (TEST_LOG, CALL_LOG, COUNTER):
            if os.path.exists(path):
                os.remove(path)
        write_success_instrument()

        result = subprocess.run(["bash", TEST_SCRIPT], capture_output=True, text=True)
        assert result.returncode == 0, (
            f"{TEST_SCRIPT} failed with return code {result.returncode}. stderr: {result.stderr}"
        )
        assert os.path.isfile(TEST_LOG), f"{TEST_LOG} was not created by the test script."
        with open(TEST_LOG, "r") as f:
            log_content = f.read().strip()
        assert log_content == "ALL_PASS", (
            f"Expected '{TEST_LOG}' to contain 'ALL_PASS', but got '{log_content}'"
        )

        calls = read_calls()
        assert len(calls) == 200, (
            f"Expected exactly 100 commutativity cases (200 add_rat calls), got {len(calls)} calls"
        )
        generated = []
        for i in range(0, 200, 2):
            first, second = calls[i], calls[i + 1]
            assert second == (first[2], first[3], first[0], first[1]), (
                f"Calls {i + 1} and {i + 2} are not the required swapped pair: {first}, {second}"
            )
            n1, d1, n2, d2 = first
            assert -50 <= n1 <= 50 and -50 <= n2 <= 50
            assert -50 <= d1 <= 50 and d1 != 0
            assert -50 <= d2 <= 50 and d2 != 0
            generated.append(first)
        assert len(set(generated)) >= 10, "The test script does not generate varied random cases"

        for path in (TEST_LOG, CALL_LOG, COUNTER):
            if os.path.exists(path):
                os.remove(path)
        write_failure_instrument()

        result = subprocess.run(["bash", TEST_SCRIPT], capture_output=True, text=True)
        assert result.returncode == 1, (
            "The property test must exit with code 1 when the two add_rat results differ"
        )
        assert not os.path.exists(TEST_LOG), "The property test wrote ALL_PASS after a forced failure"
        calls = read_calls()
        assert len(calls) == 2, (
            f"The property test did not exit immediately after its first failed comparison; got {len(calls)} calls"
        )
    finally:
        with open(RATIONAL_SCRIPT, "wb") as f:
            f.write(original)


def test_test_script_contents():
    assert os.path.isfile(TEST_SCRIPT), f"{TEST_SCRIPT} is missing."
    with open(TEST_SCRIPT, "r") as f:
        content = f.read()

    assert "add_rat" in content, f"{TEST_SCRIPT} does not invoke add_rat."
    assert "for " in content or "while " in content, f"{TEST_SCRIPT} does not appear to contain a loop."
    assert re.search(r"(?:\$\{?RANDOM\}?|/dev/urandom)", content), (
        f"{TEST_SCRIPT} does not use a random source"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
