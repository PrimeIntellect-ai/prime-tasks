#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import stat
import string
import subprocess
import tempfile

RELEASE_DIR = "/home/user/release"
OUTPUT_FILE = "/home/user/deployment_sequence.txt"
EXE_PATH = os.path.join(RELEASE_DIR, "release_vm")
PROD_PATH = os.path.join(RELEASE_DIR, "prod_deploy.ops")


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=10, **kwargs)


def interpret(script):
    tokens = script.split()
    state = set()
    output = []
    i = 0
    while i < len(tokens):
        op = tokens[i]
        i += 1
        if op == "SET":
            assert i < len(tokens)
            state.add(tokens[i])
            i += 1
        elif op == "REQ":
            assert i + 1 < len(tokens)
            _x, y = tokens[i], tokens[i + 1]
            i += 2
            if y not in state:
                return False, "".join(output)
        elif op == "OUT":
            assert i < len(tokens)
            output.append(tokens[i])
            i += 1
        else:
            raise AssertionError(f"Unexpected opcode in test input: {op}")
    return True, "".join(output)


def exercise_success(executable, script_path, script):
    expected_success, expected_output = interpret(script)
    assert expected_success, "Verifier generated an invalid success case"
    result = run([executable, script_path], cwd=RELEASE_DIR)
    assert result.returncode == 0, (
        f"VM rejected a valid script (exit {result.returncode}):\n"
        f"stdout: {result.stdout!r}\nstderr: {result.stderr!r}"
    )
    assert result.stdout == expected_output + "\n", (
        f"VM produced {result.stdout!r}; expected {expected_output + chr(10)!r}"
    )


def test_final_state_and_vm_behavior():
    # Preserve the original deployment output assertion.
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."
    with open(OUTPUT_FILE, "r") as f:
        submitted_output = f.read().strip()
    assert submitted_output == "ABCE", (
        f"Expected output sequence 'ABCE', but got '{submitted_output}'"
    )

    # Preserve the original Makefile assertion.
    makefile_path = os.path.join(RELEASE_DIR, "Makefile")
    assert os.path.isfile(makefile_path), "Makefile is missing."
    with open(makefile_path, "r") as f:
        makefile_content = f.read()
    assert "vm.o" in makefile_content.split("release_vm:")[1], (
        "Makefile still does not link vm.o correctly."
    )

    # Preserve the original vm.c assertion.
    vm_c_path = os.path.join(RELEASE_DIR, "vm.c")
    assert os.path.isfile(vm_c_path), "vm.c is missing."
    with open(vm_c_path, "r") as f:
        vm_content = f.read()
    assert "state[(int)arg2] == 1" not in vm_content, (
        "vm.c still contains the logical bug checking for == 1 in the REQ instruction."
    )

    # Preserve the original executable assertions.
    assert os.path.isfile(EXE_PATH), "release_vm executable is missing. Did you run make?"
    assert os.access(EXE_PATH, os.X_OK), "release_vm is not executable."

    with open(PROD_PATH, "r") as f:
        prod_script = f.read()
    prod_success, prod_expected = interpret(prod_script)
    assert prod_success, "The production script should satisfy all dependencies"
    assert submitted_output == prod_expected, (
        "deployment_sequence.txt does not match the sequence independently derived "
        "from prod_deploy.ops"
    )

    # Remove build products ourselves so an unrelated pre-created executable cannot pass.
    for path in glob.glob(os.path.join(RELEASE_DIR, "*.o")) + [EXE_PATH]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    built = run(["make", "-B"], cwd=RELEASE_DIR)
    assert built.returncode == 0, (
        f"make failed with exit {built.returncode}:\n"
        f"stdout: {built.stdout}\nstderr: {built.stderr}"
    )
    assert os.path.isfile(EXE_PATH), "make did not create release_vm"
    assert stat.S_ISREG(os.stat(EXE_PATH).st_mode), "release_vm is not a regular file"
    assert os.access(EXE_PATH, os.X_OK), "make did not create an executable release_vm"
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "release_vm is not a compiled ELF executable"

    # Recheck source assertions after make in case the Makefile rewrites inputs.
    with open(vm_c_path, "r") as f:
        assert "state[(int)arg2] == 1" not in f.read(), (
            "vm.c contains the incorrect REQ condition after building"
        )

    # Execute the rebuilt artifact on production and compare against an independent oracle.
    exercise_success(EXE_PATH, PROD_PATH, prod_script)

    # Exercise hidden, runtime-generated scripts so hardcoded production output cannot pass.
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits
    with tempfile.TemporaryDirectory(prefix="vm_cases_") as td:
        for case_num in range(6):
            a, b, c, d, x, y = rng.sample(alphabet, 6)
            lines = [
                f"OUT {a}",
                f"SET {b}",
                f"REQ {x} {b}",       # X need not itself be set.
                f"OUT {c}",
                f"SET {d}",
                f"REQ {y} {d}",
                f"REQ {x} {b}",
                f"OUT {d}",
                f"OUT {a}",
            ]
            script = "\n".join(lines) + "\n"
            path = os.path.join(td, f"success_{case_num}.ops")
            with open(path, "w") as f:
                f.write(script)
            exercise_success(EXE_PATH, path, script)

        # A missing Y must abort, even when X has been set, and later OUT must not run.
        x, y, prefix, sentinel = rng.sample(alphabet, 4)
        failing_script = (
            f"OUT {prefix}\n"
            f"SET {x}\n"
            f"REQ {x} {y}\n"
            f"OUT {sentinel}\n"
        )
        fail_path = os.path.join(td, "missing_dependency.ops")
        with open(fail_path, "w") as f:
            f.write(failing_script)
        expected_success, prefix_output = interpret(failing_script)
        assert not expected_success
        failed = run([EXE_PATH, fail_path], cwd=RELEASE_DIR)
        assert failed.returncode != 0, "VM did not abort when REQ's Y was not set"
        assert failed.stdout.startswith(prefix_output), "Output before the failed REQ was lost"
        assert f"Dependency fail: {x} needs {y}" in failed.stdout, (
            "VM did not report the missing dependency"
        )
        assert not failed.stdout.endswith(sentinel + "\n"), (
            "VM continued executing after a failed REQ"
        )
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
