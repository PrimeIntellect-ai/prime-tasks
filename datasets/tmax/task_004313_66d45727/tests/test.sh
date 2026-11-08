#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import pstats
import secrets
import stat
import subprocess

from scipy.integrate import solve_ivp

LIB = "/home/user/libalign.so"
SCRIPT = "/home/user/profile_pcr.py"
PROFILE = "/home/user/ode_profile.prof"
RESULT = "/home/user/result.txt"


def run_script():
    for path in (PROFILE, RESULT):
        if os.path.exists(path):
            os.remove(path)
    subprocess.run(["python3", SCRIPT], cwd="/home/user", check=True, timeout=60)
    assert os.path.isfile(PROFILE), "Running profile_pcr.py did not create ode_profile.prof"
    assert os.path.isfile(RESULT), "Running profile_pcr.py did not create result.txt"


def expected_result(score):
    r = score / 10.0

    def ode(t, y):
        return r * y * (1 - y / 1000)

    solution = solve_ivp(ode, (0, 10), [1])
    return f"{solution.y[0, -1]:.2f}"


def test_libalign_so_exists():
    path = LIB
    assert os.path.exists(path), f"Shared library {path} does not exist. Did you compile the C file?"
    assert os.path.isfile(path), f"Shared library {path} is not a regular file."
    with open(path, "rb") as f:
        header = f.read(20)
    assert header[:4] == b"\x7fELF", f"{path} is not an ELF shared library."
    byteorder = "little" if header[5] == 1 else "big"
    assert len(header) >= 18 and int.from_bytes(header[16:18], byteorder) == 3, \
        f"{path} is not an ELF shared object."

    library = ctypes.CDLL(path)
    get_score = library.get_score
    get_score.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    get_score.restype = ctypes.c_int
    cases = [
        (b"ATGCGTACG", b"ATGCGTACA"),
        (b"AAAAAAAAA", b"AAAATAAAA"),
        (b"ACGTACGT", b"TGCATGCA"),
        (b"GATTACA", b"GACTATA"),
    ]
    for left, right in cases:
        expected = sum(a == b for a, b in zip(left, right))
        assert get_score(left, right) == expected, \
            f"get_score returned an incorrect score for {left!r}, {right!r}."


def test_profile_script_exists_and_declares_ctypes_signatures():
    path = SCRIPT
    assert os.path.exists(path), f"Python script {path} does not exist."
    assert os.path.isfile(path), f"Python script {path} is not a regular file."
    with open(path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=path)

    argtype_values = []
    restype_values = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            value = node.value
            for target in targets:
                if isinstance(target, ast.Attribute) and target.attr == "argtypes":
                    argtype_values.append(ast.dump(value))
                if isinstance(target, ast.Attribute) and target.attr == "restype":
                    restype_values.append(ast.dump(value))

    assert any(value.count("c_char_p") >= 2 for value in argtype_values), \
        "profile_pcr.py must set get_score.argtypes to two c_char_p arguments."
    assert any("c_int" in value for value in restype_values), \
        "profile_pcr.py must set get_score.restype to c_int."


def test_execute_script_and_exercise_score_parameterization():
    with open(LIB, "rb") as f:
        original_library = f.read()
    original_mode = stat.S_IMODE(os.stat(LIB).st_mode)

    scores = list(range(2, 9))
    secrets.SystemRandom().shuffle(scores)
    scores = scores[:2]

    try:
        for index, score in enumerate(scores):
            marker = f"/tmp/get_score_called_{os.getpid()}_{index}_{secrets.token_hex(8)}"
            source = f'''#include <stdio.h>\n#include <string.h>\nint get_score(const char *s1, const char *s2) {{\n    if (strcmp(s1, "ATGCGTACG") != 0 || strcmp(s2, "ATGCGTACA") != 0) return -7;\n    FILE *f = fopen("{marker}", "w");\n    if (f) {{ fputs("called", f); fclose(f); }}\n    return {score};\n}}\n'''
            c_path = f"/tmp/instrumented_align_{os.getpid()}_{index}.c"
            so_path = f"/tmp/instrumented_align_{os.getpid()}_{index}.so"
            with open(c_path, "w", encoding="utf-8") as f:
                f.write(source)
            subprocess.run(
                ["gcc", "-shared", "-fPIC", c_path, "-o", so_path],
                check=True,
                timeout=30,
            )
            os.replace(so_path, LIB)
            run_script()
            assert os.path.exists(marker), \
                "profile_pcr.py did not call get_score with the required primer and target byte strings."
            with open(RESULT, "r", encoding="utf-8") as f:
                actual = f.read().strip()
            assert actual == expected_result(score), \
                "result.txt was not derived from the ctypes alignment score and solve_ivp result."
    finally:
        with open(LIB, "wb") as f:
            f.write(original_library)
        os.chmod(LIB, original_mode)

    # Regenerate the requested final artifacts using the agent's actual library.
    run_script()


def test_ode_profile_exists_and_valid():
    path = PROFILE
    assert os.path.exists(path), f"Profile stats file {path} does not exist."

    try:
        stats = pstats.Stats(path)
        assert len(stats.stats) > 0, "Profile stats file is empty or invalid."
    except Exception as e:
        assert False, f"Failed to parse profile stats file {path}: {e}"

    entries = list(stats.stats)
    assert any(name == "solve_ivp" and "scipy" in filename for filename, line, name in entries), \
        "The cProfile output does not contain the solve_ivp call."
    assert not any(os.path.abspath(filename) == SCRIPT and name == "<module>"
                   for filename, line, name in entries), \
        "The profile includes the whole script rather than only the solve_ivp operation."


def test_result_txt():
    path = RESULT
    assert os.path.exists(path), f"Result file {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "749.00", f"Expected result.txt to contain '749.00', but got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
