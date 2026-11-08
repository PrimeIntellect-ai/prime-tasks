#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import tempfile

SOURCE = "/home/user/orbit_fixed.c"
EXECUTABLE = "/home/user/orbit_fixed"
RESULT = "/home/user/orbit_result.txt"
EXPECTED = f"{math.sqrt(612.0):.5f}"


def run_program(path, env=None):
    return subprocess.run(
        [path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
        env=env,
    )


def compile_source(source_path, output_path, extra_flags=None):
    flags = extra_flags or []
    result = subprocess.run(
        ["gcc", "-Wall", "-Wextra", *flags, "-o", output_path, source_path, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Compilation failed:\n{result.stderr}"


def strip_comments_and_literals(source):
    pattern = r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\''
    return re.sub(pattern, " ", source, flags=re.DOTALL)


def extract_while_bodies(source):
    bodies = []
    for match in re.finditer(r"\bwhile\s*\([^)]*\)\s*\{", source):
        start = match.end() - 1
        depth = 0
        for index in range(start, len(source)):
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
                if depth == 0:
                    bodies.append(source[start + 1:index])
                    break
    return bodies


def test_orbit_fixed_c_exists():
    assert os.path.exists(SOURCE), "The file /home/user/orbit_fixed.c does not exist."
    assert os.path.isfile(SOURCE), "/home/user/orbit_fixed.c is not a regular file."


def test_orbit_fixed_executable_exists():
    assert os.path.exists(EXECUTABLE), "The compiled executable /home/user/orbit_fixed does not exist."
    assert os.access(EXECUTABLE, os.X_OK), "The file /home/user/orbit_fixed is not executable."
    with open(EXECUTABLE, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "/home/user/orbit_fixed must be a compiled ELF executable."


def test_orbit_result_txt():
    assert os.path.exists(RESULT), "The file /home/user/orbit_result.txt does not exist."
    with open(RESULT, "r") as result_file:
        content = result_file.read().strip()
    assert content == "24.73863", f"Expected output '24.73863', but got '{content}'."


def test_orbit_fixed_c_content():
    with open(SOURCE, "r") as source_file:
        content = source_file.read()

    # Preserve the original source assertions.
    assert "double" in content, "The fixed program must use 'double' precision variables."
    assert "fabs" in content, "The fixed program must use 'fabs' for the convergence check."
    assert "1e-6" in content.lower() or "0.000001" in content, "The fixed program must use a 1e-6 tolerance check."
    assert "assert" in content, "The fixed program must use 'assert'."
    assert "1000" in content, "The fixed program must check for iterations < 1000."

    malloc_count = len(re.findall(r"\bmalloc\b", content))
    free_count = len(re.findall(r"\bfree\b", content))
    if malloc_count > 0:
        assert free_count >= malloc_count, "There is a malloc without a corresponding free, indicating a potential memory leak."

    # Ensure required constructs are executable code rather than comments or strings.
    code = strip_comments_and_literals(content)
    declarations = re.findall(r"\bdouble\s+([^;]+);", code)
    assert any(re.search(r"\bcurrent\b", declaration) for declaration in declarations), "current must be declared as double."
    assert any(re.search(r"\bnext\b", declaration) for declaration in declarations), "next must be declared as double."

    compact = re.sub(r"\s+", "", code).lower()
    assert re.search(r"fabs\((?:current-next|next-current)\)<(?:1e-6|0\.000001)", compact), "Use fabs(current - next) < 1e-6 for convergence."
    assert "current==next" not in compact and "next==current" not in compact, "The exact-equality convergence check must be removed."

    loop_bodies = extract_while_bodies(code)
    assert loop_bodies, "The iterative solver must contain a while loop."
    assert any(re.search(r"\bassert\s*\(\s*iterations\s*<\s*1000\s*\)\s*;", body) for body in loop_bodies), "assert(iterations < 1000); must be inside the loop."
    assert any(re.search(r"(?:\+\+\s*iterations|iterations\s*\+\+|iterations\s*\+=\s*1|iterations\s*=\s*iterations\s*\+\s*1)", body) for body in loop_bodies), "The iterations counter must be incremented inside the loop."


def test_submitted_executable_and_result_match_computed_answer():
    completed = run_program(EXECUTABLE)
    assert completed.returncode == 0, f"The submitted executable failed: {completed.stderr}"
    assert completed.stdout == EXPECTED + "\n", f"Executable output must be exactly '{EXPECTED}\\n', got {completed.stdout!r}."
    with open(RESULT, "r") as result_file:
        assert result_file.read() == completed.stdout, "orbit_result.txt must contain the executable's actual stdout."


def test_source_compiles_and_runs_as_solver():
    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "orbit_rebuilt")
        compile_source(SOURCE, rebuilt)
        completed = run_program(rebuilt)
        assert completed.returncode == 0, f"Program rebuilt from orbit_fixed.c failed: {completed.stderr}"
        assert completed.stdout == EXPECTED + "\n", f"Rebuilt program produced {completed.stdout!r}, expected '{EXPECTED}\\n'."

        with open(SOURCE, "r") as source_file:
            original_source = source_file.read()

        # Exercise the same solver on independently derived targets by changing
        # the supplied problem constant and recompiling.
        number_pattern = r"(?<![A-Za-z0-9_.])612(?:\.0*)?(?:[fFlL])?(?![A-Za-z0-9_.])"
        assert re.search(number_pattern, original_source), "The source must retain the supplied target value 612.0."
        for target in (2.0, 987.0):
            variant_source = re.sub(number_pattern, repr(target), original_source)
            variant_c = os.path.join(directory, f"variant_{int(target)}.c")
            variant_exe = os.path.join(directory, f"variant_{int(target)}")
            with open(variant_c, "w") as variant_file:
                variant_file.write(variant_source)
            compile_source(variant_c, variant_exe)
            completed = run_program(variant_exe)
            expected = f"{math.sqrt(target):.5f}\n"
            assert completed.returncode == 0, f"Solver failed for target {target}: {completed.stderr}"
            assert completed.stdout == expected, f"Solver output for target {target} was {completed.stdout!r}, expected {expected!r}."


def test_no_runtime_memory_leak():
    with tempfile.TemporaryDirectory() as directory:
        leak_checked = os.path.join(directory, "orbit_leak_checked")
        compile_source(SOURCE, leak_checked, ["-fsanitize=leak", "-fno-omit-frame-pointer"])
        env = os.environ.copy()
        env["LSAN_OPTIONS"] = "exitcode=23"
        completed = run_program(leak_checked, env=env)
        assert completed.returncode == 0, f"LeakSanitizer detected a leak or the program failed:\n{completed.stderr}"
        assert completed.stdout == EXPECTED + "\n"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
