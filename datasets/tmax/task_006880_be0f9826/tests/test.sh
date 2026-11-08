#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import subprocess
import tempfile


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_audit_plugin_script_exists_and_executable():
    script_path = "/home/user/audit_plugin.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_script_execution_and_outputs():
    script_path = "/home/user/audit_plugin.sh"

    # Ensure all demanded outputs must be produced by this execution.
    for path in [
        "/home/user/src/auth_plugin.so",
        "/home/user/syscall_count.txt",
        "/home/user/runner.c",
        "/home/user/runner",
        "/home/user/execution.log",
    ]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = run(["sudo", "-u", "user", script_path])
    assert result.returncode == 0, (
        f"Script failed to execute. stderr: {result.stderr}\nstdout: {result.stdout}"
    )

    # 1. Verify the Makefile was fixed, retaining the original checks.
    makefile_path = "/home/user/src/Makefile"
    assert os.path.isfile(makefile_path), f"{makefile_path} does not exist."
    with open(makefile_path, "r") as f:
        makefile_content = f.read()
    assert "\t" in makefile_content, "Makefile does not use tabs for the build recipe."
    assert "-shared" in makefile_content, "Makefile is missing the -shared flag."

    recipe_lines = [line for line in makefile_content.splitlines() if line.startswith("\t")]
    assert recipe_lines, "Makefile has no tab-indented recipe."
    assert any("-shared" in line for line in recipe_lines), (
        "The -shared flag is not present in a Makefile recipe."
    )

    # 2. Verify auth_plugin.so is a genuine ELF shared object.
    so_path = "/home/user/src/auth_plugin.so"
    assert os.path.isfile(so_path), f"Shared object {so_path} was not built."
    with open(so_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "auth_plugin.so is not an ELF binary."

    elf_header = run(["readelf", "-h", so_path])
    assert elf_header.returncode == 0, elf_header.stderr
    assert re.search(r"^\s*Type:\s+DYN\b", elf_header.stdout, re.MULTILINE), (
        "auth_plugin.so is not an ELF shared object."
    )

    symbols = run(["nm", "-D", "--defined-only", so_path])
    assert symbols.returncode == 0, symbols.stderr
    assert re.search(r"\bvalidate$", symbols.stdout, re.MULTILINE), (
        "auth_plugin.so does not export validate."
    )

    # 3. Independently disassemble only .text and derive the syscall count.
    count_path = "/home/user/syscall_count.txt"
    assert os.path.isfile(count_path), f"{count_path} does not exist."
    with open(count_path, "r") as f:
        count = f.read().strip()
    assert re.fullmatch(r"[0-9]+", count), "syscall_count.txt must contain only an integer."

    disassembly = run(["objdump", "-d", "-j", ".text", so_path])
    assert disassembly.returncode == 0, disassembly.stderr
    syscall_lines = re.findall(
        r"^\s*[0-9a-fA-F]+:\s+(?:[0-9a-fA-F]{2}\s+)+syscall(?:q)?\b",
        disassembly.stdout,
        re.MULTILINE,
    )
    independent_count = len(syscall_lines)
    assert int(count) == independent_count, (
        f"Recorded syscall count {count} does not match objdump count {independent_count}."
    )
    assert count == "1", f"Expected syscall count to be '1', but got '{count}'."

    # Confirm that the repaired Makefile itself can really build the shared object.
    make_result = run(["sudo", "-u", "user", "make", "-B"], cwd="/home/user/src")
    assert make_result.returncode == 0, (
        f"Repaired Makefile cannot build the artifact: {make_result.stderr}\n{make_result.stdout}"
    )

    # 4 & 5. Retain the original file and log checks.
    runner_c_path = "/home/user/runner.c"
    runner_path = "/home/user/runner"
    assert os.path.isfile(runner_c_path), f"Runner source {runner_c_path} does not exist."
    assert os.path.isfile(runner_path), f"Runner executable {runner_path} does not exist."
    assert os.access(runner_path, os.X_OK), "Runner is not executable."
    with open(runner_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Runner is not a compiled ELF executable."

    log_path = "/home/user/execution.log"
    assert os.path.isfile(log_path), f"Execution log {log_path} does not exist."
    with open(log_path, "r") as f:
        log_content = f.read().strip()
    assert log_content == "42", f"Expected execution output to be '42', but got '{log_content}'."

    direct = run([runner_path])
    assert direct.returncode == 0, f"Runner failed: {direct.stderr}"
    assert direct.stdout.strip() == "42", (
        f"Runner did not call the built plugin; got {direct.stdout!r}."
    )

    # Replace the plugin with an independently generated implementation. A genuine
    # dlopen/dlsym runner must report its unpredictable return value rather than 42.
    alternate_value = random.SystemRandom().randint(1000, 1000000)
    with tempfile.TemporaryDirectory() as td:
        alternate_c = os.path.join(td, "alternate.c")
        backup_so = os.path.join(td, "auth_plugin.so.original")
        shutil.copy2(so_path, backup_so)
        with open(alternate_c, "w") as f:
            f.write(f"int validate(void) {{ return {alternate_value}; }}\n")

        try:
            compiled = run(["gcc", "-shared", "-fPIC", "-o", so_path, alternate_c])
            assert compiled.returncode == 0, compiled.stderr
            dynamic = run([runner_path])
            assert dynamic.returncode == 0, (
                f"Runner failed while loading a valid replacement plugin: {dynamic.stderr}"
            )
            assert dynamic.stdout.strip() == str(alternate_value), (
                "Runner does not dynamically load auth_plugin.so and call validate."
            )
        finally:
            shutil.copy2(backup_so, so_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
