#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import tempfile

import pytest

EMULATOR = "/home/user/emulator.py"
BASE_DSL = """ALLOC X
ALLOC Y
USE X
FREE X
USE Y
ALLOC Z
USE X
FREE Y
FREE Z
"""


def test_success_log_exists_and_correct():
    log_path = "/home/user/success.log"
    assert os.path.isfile(log_path), f"Expected file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "patch_7.diff", f"Expected success.log to contain 'patch_7.diff', but found '{content}'"


def test_emulator_exists():
    emulator_path = "/home/user/emulator.py"
    assert os.path.isfile(emulator_path), f"Expected emulator script at {emulator_path} does not exist."


def run_emulator(dsl_content: str) -> int:
    with tempfile.NamedTemporaryFile(mode="w", suffix=".lt", delete=False) as tmp:
        tmp.write(dsl_content)
        tmp_path = tmp.name

    try:
        result = subprocess.run(
            ["python3", EMULATOR, tmp_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        return result.returncode
    finally:
        os.remove(tmp_path)


def test_emulator_valid_input():
    valid_dsl = """
    # This is a comment
    ALLOC A
    ALLOC B
    USE A
    USE B
    FREE A
    FREE B
    """
    exit_code = run_emulator(valid_dsl)
    assert exit_code == 0, "Emulator failed (non-zero exit code) on valid DSL input."


def test_emulator_double_alloc():
    dsl = """
    ALLOC X
    ALLOC X
    """
    exit_code = run_emulator(dsl)
    assert exit_code == 1, "Emulator did not exit with code 1 on Double Alloc."


def test_emulator_double_free():
    dsl = """
    ALLOC X
    FREE X
    FREE X
    """
    exit_code = run_emulator(dsl)
    assert exit_code == 1, "Emulator did not exit with code 1 on Double Free."


def test_emulator_uninitialized_free():
    dsl = """
    FREE Y
    """
    exit_code = run_emulator(dsl)
    assert exit_code == 1, "Emulator did not exit with code 1 on Uninitialized Free."


def test_emulator_use_after_free():
    dsl = """
    ALLOC Z
    FREE Z
    USE Z
    """
    exit_code = run_emulator(dsl)
    assert exit_code == 1, "Emulator did not exit with code 1 on Use After Free."


def test_emulator_uninitialized_use():
    dsl = """
    USE W
    """
    exit_code = run_emulator(dsl)
    assert exit_code == 1, "Emulator did not exit with code 1 on Uninitialized Use."


def oracle_exit_code(dsl_content: str) -> int:
    alive = set()
    allocated = set()
    for raw_line in dsl_content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        command, variable = line.split()
        if command == "ALLOC":
            if variable in alive:
                return 1
            alive.add(variable)
            allocated.add(variable)
        elif command == "FREE":
            if variable not in allocated or variable not in alive:
                return 1
            alive.remove(variable)
        elif command == "USE":
            if variable not in allocated or variable not in alive:
                return 1
    return 0


def random_variable(rng):
    return "V_" + "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(14))


def render(commands, rng):
    lines = []
    for command in commands:
        if rng.random() < 0.35:
            lines.append("")
        if rng.random() < 0.35:
            lines.append("   # randomized comment " + str(rng.randrange(10**9)))
        lines.append((" " * rng.randrange(4)) + command + (" " * rng.randrange(4)))
    return "\n".join(lines) + "\n"


def make_valid_program(rng):
    variables = [random_variable(rng) for _ in range(rng.randint(5, 12))]
    alive = set()
    commands = []
    for _ in range(rng.randint(15, 45)):
        possible = [("ALLOC", var) for var in variables if var not in alive]
        possible += [("USE", var) for var in alive]
        possible += [("FREE", var) for var in alive]
        command, variable = rng.choice(possible)
        commands.append(f"{command} {variable}")
        if command == "ALLOC":
            alive.add(variable)
        elif command == "FREE":
            alive.remove(variable)
    return render(commands, rng)


def test_emulator_randomized_programs_against_oracle():
    rng = random.Random(secrets.randbits(128))
    programs = [make_valid_program(rng) for _ in range(30)]

    for _ in range(50):
        variables = [random_variable(rng) for _ in range(rng.randint(4, 10))]
        commands = [
            f"{rng.choice(('ALLOC', 'FREE', 'USE'))} {rng.choice(variables)}"
            for _ in range(rng.randint(5, 35))
        ]
        programs.append(render(commands, rng))

    # Explicitly exercise valid re-allocation after a free with unpredictable names.
    for _ in range(10):
        var = random_variable(rng)
        programs.append(render([
            f"ALLOC {var}", f"USE {var}", f"FREE {var}",
            f"ALLOC {var}", f"USE {var}", f"FREE {var}",
        ], rng))

    for program in programs:
        expected = oracle_exit_code(program)
        actual = run_emulator(program)
        assert actual == expected, (
            f"Emulator returned {actual}, expected {expected}, for generated DSL:\n{program}"
        )


def test_logged_patch_is_applied_and_is_the_only_successful_candidate():
    with open("/home/user/success.log", "r") as f:
        selected = f.read().strip()

    successes = []
    for number in range(1, 11):
        patch_name = f"patch_{number}.diff"
        patch_path = os.path.join("/home/user/qa_env/patches", patch_name)
        assert os.path.isfile(patch_path), f"Missing candidate patch {patch_path}"

        with tempfile.TemporaryDirectory() as workdir:
            target = os.path.join(workdir, "test_case.lt")
            with open(target, "w") as f:
                f.write(BASE_DSL)

            applied = subprocess.run(
                ["patch", "--batch", "--forward", "test_case.lt", patch_path],
                cwd=workdir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            if applied.returncode != 0:
                continue

            result = subprocess.run(
                ["python3", EMULATOR, target],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            if result.returncode == 0:
                successes.append(patch_name)

    assert successes == [selected], (
        f"Expected logged patch {selected!r} to be the single successful patch, "
        f"but successful candidates were {successes!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
