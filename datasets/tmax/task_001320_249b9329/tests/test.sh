#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shlex
import shutil
import subprocess
import tempfile

PROJECT = "/home/user/project"
C_DIR = os.path.join(PROJECT, "libmath")
C_BIN = os.path.join(C_DIR, "prime")
RUST_DIR = os.path.join(PROJECT, "rs_calc")
RUST_BIN = os.path.join(RUST_DIR, "target/release/rs_calc")
GO_DIR = os.path.join(PROJECT, "go_machine")
GO_MAIN = os.path.join(GO_DIR, "main.go")
PROGRAM = os.path.join(PROJECT, "program.math")
RESULT = os.path.join(PROJECT, "result.txt")


def get_nth_prime(n):
    if n <= 0:
        return 0
    count = 0
    current = 1
    while count < n:
        current += 1
        is_prime = True
        for i in range(2, int(current ** 0.5) + 1):
            if current % i == 0:
                is_prime = False
                break
        if is_prime:
            count += 1
    return current


def get_distinct_prime_factors_count(n):
    count = 0
    d = 2
    num = n
    while num > 1:
        if num % d == 0:
            count += 1
            while num % d == 0:
                num //= d
        d += 1
        if d * d > num and num > 1:
            count += 1
            break
    return count


def evaluate_program(filepath):
    acc = 0
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 2:
                continue
            cmd = parts[0]
            val = int(parts[1])
            if cmd == "ADD":
                acc += val
            elif cmd == "MUL":
                acc *= val
            elif cmd == "PRIME":
                acc += get_nth_prime(val)
            elif cmd == "FACTORS":
                acc += get_distinct_prime_factors_count(val)
    return acc


def read_integer(path):
    assert os.path.isfile(path), f"{path} was not created."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content.isdigit() or (content.startswith("-") and content[1:].isdigit()), \
        f"{path} does not contain a valid integer. Found: {content}"
    return int(content)


def run(command, cwd, timeout=120):
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    )


def assert_elf(path):
    with open(path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_complete_polyglot_system():
    # Preserve the original verifier's existence, executable, and submitted-result checks.
    assert os.path.isfile(C_BIN), "C binary 'prime' was not successfully compiled in /home/user/project/libmath/."
    assert os.access(C_BIN, os.X_OK), "The compiled C file 'prime' is not executable."
    assert os.path.isfile(RUST_BIN), "Rust binary 'rs_calc' was not successfully compiled in release mode."
    assert os.access(RUST_BIN, os.X_OK), "The compiled Rust file 'rs_calc' is not executable."
    assert os.path.isfile(PROGRAM), "The program.math file is missing."
    assert os.path.isfile(RESULT), "The result.txt file was not created by the Go program."
    expected_original = evaluate_program(PROGRAM)
    actual_original = read_integer(RESULT)
    assert actual_original == expected_original, \
        f"Expected final accumulator value to be {expected_original}, but got {actual_original}."

    assert os.path.isfile(GO_MAIN), "The Go interpreter main.go is missing."

    # Rebuild from the repaired C Makefile and Rust source, then require real binaries.
    run(["make", "-B"], C_DIR)
    run(["cargo", "build", "--release"], RUST_DIR)
    assert os.path.isfile(C_BIN) and os.access(C_BIN, os.X_OK)
    assert os.path.isfile(RUST_BIN) and os.access(RUST_BIN, os.X_OK)
    assert_elf(C_BIN)
    assert_elf(RUST_BIN)

    rng = random.SystemRandom()

    # Exercise each native utility on verifier-selected inputs.
    for _ in range(5):
        n = rng.randint(2, 45)
        completed = run([C_BIN, str(n)], C_DIR, timeout=20)
        assert completed.stdout.strip() == str(get_nth_prime(n)), \
            f"C prime binary returned the wrong answer for n={n}: {completed.stdout!r}"

    for _ in range(5):
        n = rng.randint(2, 100000)
        completed = run([RUST_BIN, str(n)], RUST_DIR, timeout=20)
        assert completed.stdout.strip() == str(get_distinct_prime_factors_count(n)), \
            f"Rust factor utility returned the wrong answer for n={n}: {completed.stdout!r}"

    with open(PROGRAM, "rb") as f:
        original_program = f.read()

    # Run the Go interpreter on the original file rather than trusting result.txt.
    run(["go", "run", "main.go"], GO_DIR)
    assert read_integer(RESULT) == expected_original, \
        "Running the Go interpreter did not produce the correct result for program.math."

    try:
        # Exercise all DSL operations on fresh values selected only at verification time.
        add1 = rng.randint(-50, 50)
        multiplier = rng.randint(2, 8)
        prime_n = rng.randint(3, 40)
        factors_n = rng.randint(2, 100000)
        add2 = rng.randint(-50, 50)
        dynamic_program = (
            f"ADD {add1}\n"
            f"MUL {multiplier}\n"
            f"PRIME {prime_n}\n"
            f"FACTORS {factors_n}\n"
            f"ADD {add2}\n"
        )
        with open(PROGRAM, "w") as f:
            f.write(dynamic_program)
        expected = add1 * multiplier + get_nth_prime(prime_n) + get_distinct_prime_factors_count(factors_n) + add2
        run(["go", "run", "main.go"], GO_DIR)
        assert read_integer(RESULT) == expected, \
            "The Go interpreter failed a verifier-generated DSL program."

        # Replace the utilities briefly with instrumented stand-ins. This proves that
        # PRIME and FACTORS execute the required paths and consume their stdout.
        with tempfile.TemporaryDirectory() as td:
            c_backup = os.path.join(td, "prime.real")
            rust_backup = os.path.join(td, "rs_calc.real")
            c_log = os.path.join(td, "c.log")
            rust_log = os.path.join(td, "rust.log")
            shutil.copy2(C_BIN, c_backup)
            shutil.copy2(RUST_BIN, rust_backup)

            c_value = rng.randint(1000, 9000)
            rust_value = rng.randint(100, 900)
            c_arg = rng.randint(3, 80)
            rust_arg = rng.randint(10, 100000)
            base = rng.randint(-20, 20)
            mul = rng.randint(2, 7)

            try:
                with open(C_BIN, "w") as f:
                    f.write("#!/bin/sh\nprintf '%s\\n' \"$1\" >> " + shlex.quote(c_log) + "\nprintf '%s\\n' " + str(c_value) + "\n")
                os.chmod(C_BIN, 0o755)
                with open(RUST_BIN, "w") as f:
                    f.write("#!/bin/sh\nprintf '%s\\n' \"$1\" >> " + shlex.quote(rust_log) + "\nprintf '%s\\n' " + str(rust_value) + "\n")
                os.chmod(RUST_BIN, 0o755)

                with open(PROGRAM, "w") as f:
                    f.write(f"ADD {base}\nPRIME {c_arg}\nMUL {mul}\nFACTORS {rust_arg}\n")
                run(["go", "run", "main.go"], GO_DIR)
                expected_wrapped = (base + c_value) * mul + rust_value
                assert read_integer(RESULT) == expected_wrapped, \
                    "The Go interpreter did not use stdout from the required C and Rust executables."
                with open(c_log, "r") as f:
                    assert f.read().splitlines() == [str(c_arg)], \
                        "PRIME did not invoke the required C binary with the requested argument."
                with open(rust_log, "r") as f:
                    assert f.read().splitlines() == [str(rust_arg)], \
                        "FACTORS did not invoke the required Rust binary with the requested argument."
            finally:
                shutil.copy2(c_backup, C_BIN)
                shutil.copy2(rust_backup, RUST_BIN)
    finally:
        with open(PROGRAM, "wb") as f:
            f.write(original_program)

    # Leave the project in its requested final state and recheck the original result.
    run(["go", "run", "main.go"], GO_DIR)
    assert read_integer(RESULT) == expected_original

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
