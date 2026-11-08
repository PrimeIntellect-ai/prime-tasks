#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile

PORT = "/home/user/port"
LIB = os.path.join(PORT, "libexpr.so")
BIN = os.path.join(PORT, "config_parser")


def run(cmd, **kwargs):
    kwargs.setdefault("timeout", 20)
    kwargs.setdefault("check", True)
    return subprocess.run(cmd, **kwargs)


def parser_env():
    env = os.environ.copy()
    old = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = PORT + ((":" + old) if old else "")
    return env


def test_port_directory_exists():
    assert os.path.isdir(PORT), "Directory /home/user/port does not exist."


def test_libexpr_c_no_python():
    c_file = os.path.join(PORT, "libexpr.c")
    assert os.path.isfile(c_file), f"{c_file} does not exist."
    with open(c_file, "r") as f:
        content = f.read()
    assert "Python.h" not in content, f"{c_file} still contains Python.h or Python dependencies."
    assert "PyObject" not in content, f"{c_file} still contains PyObject references."


def test_libexpr_h_exists_and_correct():
    h_file = os.path.join(PORT, "libexpr.h")
    assert os.path.isfile(h_file), f"{h_file} does not exist."
    with open(h_file, "r") as f:
        content = f.read()
    assert "double evaluate(const char*" in content or "double evaluate(const char *" in content, \
        f"{h_file} does not expose the correct evaluate function signature."


def test_makefile_exists():
    assert os.path.isfile(os.path.join(PORT, "Makefile")), "/home/user/port/Makefile does not exist."


def test_output_txt_correct():
    output_file = os.path.join(PORT, "output.txt")
    assert os.path.isfile(output_file), f"{output_file} does not exist."
    expected_lines = [
        "Timeout=21.00",
        "MaxRetries=5.00",
        "Threshold=84.50",
        "ScaleFactor=0.25"
    ]
    with open(output_file, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]
    assert actual_lines == expected_lines, f"Contents of {output_file} do not match the expected output."


def test_make_actually_builds_artifacts():
    for path in (LIB, BIN):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    result = run(["make", "-B"], cwd=PORT, stdout=subprocess.PIPE,
                 stderr=subprocess.STDOUT, text=True)
    assert os.path.isfile(LIB), "make did not create libexpr.so"
    assert os.path.isfile(BIN), "make did not create config_parser"
    assert os.access(BIN, os.X_OK), "make did not create an executable config_parser"
    assert result.returncode == 0


def test_compiled_artifacts_exist():
    assert os.path.isfile(LIB), f"Shared library {LIB} does not exist."
    assert os.path.isfile(BIN), f"Executable {BIN} does not exist."
    assert os.access(BIN, os.X_OK), f"{BIN} is not executable."


def test_artifacts_are_elf_and_dynamically_linked():
    lib_hdr = run(["readelf", "-h", LIB], stdout=subprocess.PIPE,
                  stderr=subprocess.STDOUT, text=True).stdout
    bin_hdr = run(["readelf", "-h", BIN], stdout=subprocess.PIPE,
                  stderr=subprocess.STDOUT, text=True).stdout
    assert "ELF Header:" in lib_hdr and re.search(r"Type:\s+DYN", lib_hdr), \
        "libexpr.so is not an ELF shared object"
    assert "ELF Header:" in bin_hdr, "config_parser is not an ELF executable"

    lib_dyn = run(["readelf", "-d", LIB], stdout=subprocess.PIPE,
                  stderr=subprocess.STDOUT, text=True).stdout
    bin_dyn = run(["readelf", "-d", BIN], stdout=subprocess.PIPE,
                  stderr=subprocess.STDOUT, text=True).stdout
    needed = re.findall(r"Shared library: \[(.*?)\]", bin_dyn)
    assert any(os.path.basename(item) == "libexpr.so" for item in needed), \
        "config_parser does not dynamically depend on libexpr.so"
    assert "libpython" not in lib_dyn.lower(), "libexpr.so has a Python runtime dependency"
    assert "libpython" not in bin_dyn.lower(), "config_parser has a Python runtime dependency"

    symbols = run(["readelf", "-Ws", LIB], stdout=subprocess.PIPE,
                  stderr=subprocess.STDOUT, text=True).stdout
    assert re.search(r"\bGLOBAL\b.*\bDEFAULT\b.*\bevaluate(?:@@?\S+)?\s*$", symbols, re.MULTILINE), \
        "libexpr.so does not export evaluate"


def test_evaluate_on_derived_inputs():
    library = ctypes.CDLL(LIB)
    evaluate = library.evaluate
    evaluate.argtypes = [ctypes.c_char_p]
    evaluate.restype = ctypes.c_double

    cases = [
        ("7 + 4", 11.0),
        ("7 - 12", -5.0),
        ("-3 * 2.5", -7.5),
        ("9 / 4", 2.25),
        ("9 / 0", 0.0),
        ("not an expression", 0.0),
    ]
    rng = random.Random(secrets.randbits(128))
    for _ in range(40):
        a = rng.randint(-500, 500)
        b = rng.randint(-50, 50)
        op = rng.choice(["+", "-", "*", "/"])
        expression = f"{a}.0 {op} {b}.0"
        if op == "+":
            expected = float(a + b)
        elif op == "-":
            expected = float(a - b)
        elif op == "*":
            expected = float(a * b)
        else:
            expected = 0.0 if b == 0 else a / b
        cases.append((expression, expected))

    for expression, expected in cases:
        actual = evaluate(expression.encode("ascii"))
        assert math.isfinite(actual), f"evaluate returned a non-finite value for {expression!r}"
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), \
            f"evaluate({expression!r}) returned {actual}, expected {expected}"


def test_config_parser_on_generated_and_legacy_inputs():
    rng = random.Random(secrets.randbits(128))
    rows = []
    operations = ["+", "-", "*", "/"]
    for index in range(24):
        a = rng.randint(-200, 200)
        b = rng.randint(1, 40)
        op = operations[index % len(operations)]
        if op == "+":
            value = a + b
        elif op == "-":
            value = a - b
        elif op == "*":
            value = a * b
        else:
            value = a / b
        rows.append((f"GeneratedKey{index}_{secrets.token_hex(3)}", f"{a}.0 {op} {b}.0", value))

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "generated.conf")
        output_path = os.path.join(td, "generated.out")
        with open(input_path, "w") as f:
            for key, expression, _ in rows:
                f.write(f"{key}: {expression}\n")
        run([BIN, input_path, output_path], cwd=td, env=parser_env(),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with open(output_path, "rb") as f:
            actual = f.read()
        expected = "".join(f"{key}={value:.2f}\n" for key, _, value in rows).encode("ascii")
        assert actual == expected, "config_parser produced incorrect output for generated input"

    legacy_output = os.path.join(PORT, "output.txt")
    run([BIN, "/home/user/legacy_tool/config.txt", legacy_output], cwd=PORT,
        env=parser_env(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with open(legacy_output, "rb") as f:
        actual = f.read()
    expected = (b"Timeout=21.00\nMaxRetries=5.00\n"
                b"Threshold=84.50\nScaleFactor=0.25\n")
    assert actual == expected, "Running config_parser did not accurately generate output.txt"


def test_config_parser_really_uses_shared_evaluate():
    with tempfile.TemporaryDirectory() as td:
        shim_c = os.path.join(td, "shim.c")
        shim_so = os.path.join(td, "libexpr.so")
        with open(shim_c, "w") as f:
            f.write("double evaluate(const char *expression) { (void)expression; return 731.25; }\n")
        run(["gcc", "-shared", "-fPIC", shim_c, "-o", shim_so],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        input_path = os.path.join(td, "input.conf")
        output_path = os.path.join(td, "output.txt")
        with open(input_path, "w") as f:
            f.write("ProbeA: 1 + 2\nProbeB: 99 / 3\n")

        backup = os.path.join(td, "original-libexpr.so")
        shutil.copy2(LIB, backup)
        try:
            shutil.copy2(shim_so, LIB)
            run([BIN, input_path, output_path], cwd=PORT, env=parser_env(),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            with open(output_path, "rb") as f:
                actual = f.read()
            assert actual == b"ProbeA=731.25\nProbeB=731.25\n", \
                "config_parser does not obtain its results from libexpr.so's evaluate function"
        finally:
            shutil.copy2(backup, LIB)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
