#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import stat
import subprocess
import tempfile

PROJECT_DIR = "/home/user/legacy_project"


def run(cmd, **kwargs):
    return subprocess.run(cmd, cwd=PROJECT_DIR, capture_output=True, **kwargs)


def test_output_txt_content():
    output_file = os.path.join(PROJECT_DIR, "output.txt")
    assert os.path.isfile(output_file), f"Expected output file {output_file} does not exist."

    with open(output_file, "r") as f:
        content = f.read().strip()

    assert content == "2122", f"Expected output.txt to contain '2122', but found '{content}'."


def test_ci_test_sh_exists_and_executable():
    ci_script = os.path.join(PROJECT_DIR, "ci_test.sh")
    assert os.path.isfile(ci_script), f"CI script {ci_script} does not exist."

    st = os.stat(ci_script)
    is_executable = bool(st.st_mode & stat.S_IXUSR)
    assert is_executable, f"CI script {ci_script} is not executable."


def test_ci_test_sh_execution():
    ci_script = os.path.join(PROJECT_DIR, "ci_test.sh")
    assert os.path.isfile(ci_script), f"CI script {ci_script} does not exist."

    output_file = os.path.join(PROJECT_DIR, "output.txt")
    if os.path.exists(output_file):
        os.remove(output_file)

    result = run(["/bin/bash", ci_script])
    assert result.returncode == 0, (
        f"ci_test.sh failed with return code {result.returncode}. "
        f"Stderr: {result.stderr.decode()}"
    )

    assert os.path.isfile(output_file), "ci_test.sh did not generate output.txt."
    with open(output_file, "r") as f:
        content = f.read().strip()
    assert content == "2122", (
        f"After running ci_test.sh, output.txt contains '{content}' instead of '2122'."
    )


def test_main_py_execution():
    main_script = os.path.join(PROJECT_DIR, "main.py")
    result = run(["python3", main_script])
    assert result.returncode == 0, (
        f"main.py failed to execute. Stderr: {result.stderr.decode()}"
    )


def expected_checksum(value):
    total = 0
    for byte in value.encode("utf-8"):
        total = ((total << 1) ^ (byte * 31)) & 0xffffffff
    return total + 10


def test_real_program_on_derived_inputs():
    input_path = os.path.join(PROJECT_DIR, "input.txt")
    output_path = os.path.join(PROJECT_DIR, "output.txt")
    old_input = open(input_path, "rb").read()
    old_output = open(output_path, "rb").read() if os.path.exists(output_path) else None

    try:
        for value in ["A", "terminal-agent", "Z9_xY7", "checksum data"]:
            with open(input_path, "w", encoding="utf-8") as f:
                f.write(f"LOAD {value}\nCHECKSUM\n")
            with open(output_path, "w", encoding="utf-8") as f:
                f.write("decoy-output\n")

            result = run(["python3", "main.py"])
            assert result.returncode == 0, result.stderr.decode()
            with open(output_path, "r", encoding="utf-8") as f:
                actual = f.read().strip()
            assert actual == str(expected_checksum(value)), (
                f"Wrong checksum for derived input {value!r}: {actual}"
            )
    finally:
        with open(input_path, "wb") as f:
            f.write(old_input)
        if old_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(old_output)


def test_main_really_uses_the_c_ffi_library():
    so_path = os.path.join(PROJECT_DIR, "lib_calc.so")
    input_path = os.path.join(PROJECT_DIR, "input.txt")
    output_path = os.path.join(PROJECT_DIR, "output.txt")
    old_so = open(so_path, "rb").read()
    old_input = open(input_path, "rb").read()
    old_output = open(output_path, "rb").read() if os.path.exists(output_path) else None
    secret = random.SystemRandom().randint(100000, 900000000)

    try:
        with tempfile.NamedTemporaryFile("w", suffix=".c", delete=False) as f:
            f.write(
                "#include <stdint.h>\n"
                "uint32_t compute_checksum(const char *data, int length) {\n"
                f"    return {secret}u;\n"
                "}\n"
            )
            alternate_source = f.name
        compiled = subprocess.run(
            ["gcc", "-shared", "-fPIC", alternate_source, "-o", so_path],
            capture_output=True,
        )
        os.unlink(alternate_source)
        assert compiled.returncode == 0, compiled.stderr.decode()

        with open(input_path, "w", encoding="utf-8") as f:
            f.write("LOAD verifier-selected-input\nCHECKSUM\n")
        if os.path.exists(output_path):
            os.remove(output_path)

        result = run(["python3", "main.py"])
        assert result.returncode == 0, result.stderr.decode()
        assert os.path.isfile(output_path), "main.py did not create output.txt"
        with open(output_path, "r", encoding="utf-8") as f:
            actual = f.read().strip()
        assert actual == str(secret + 10), (
            "main.py/checksum.py did not obtain the checksum through lib_calc.so"
        )
    finally:
        with open(so_path, "wb") as f:
            f.write(old_so)
        with open(input_path, "wb") as f:
            f.write(old_input)
        if old_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(old_output)


def test_ci_script_actually_compiles_source_and_runs_main():
    paths = {
        name: os.path.join(PROJECT_DIR, name)
        for name in ["lib_calc.c", "main.py", "input.txt", "lib_calc.so", "output.txt"]
    }
    backups = {
        name: open(path, "rb").read() if os.path.exists(path) else None
        for name, path in paths.items()
    }
    marker = os.path.join(PROJECT_DIR, ".ci_main_executed")
    secret = random.SystemRandom().randint(100000, 900000000)

    try:
        with open(paths["lib_calc.c"], "w", encoding="utf-8") as f:
            f.write(
                "#include <stdint.h>\n"
                "uint32_t compute_checksum(const char *data, int length) {\n"
                f"    return {secret}u;\n"
                "}\n"
            )
        with open(paths["main.py"], "w", encoding="utf-8") as f:
            f.write(
                "import ctypes\n"
                "lib = ctypes.CDLL('./lib_calc.so')\n"
                "lib.compute_checksum.argtypes = [ctypes.c_char_p, ctypes.c_int]\n"
                "lib.compute_checksum.restype = ctypes.c_uint32\n"
                "value = lib.compute_checksum(b'ci-probe', 8)\n"
                "open('.ci_main_executed', 'w').write('ran\\n')\n"
                "open('output.txt', 'w').write(str(value) + '\\n')\n"
            )
        with open(paths["input.txt"], "w", encoding="utf-8") as f:
            f.write("LOAD irrelevant\nCHECKSUM\n")
        for path in [paths["lib_calc.so"], paths["output.txt"], marker]:
            if os.path.exists(path):
                os.remove(path)

        result = run(["/bin/bash", "ci_test.sh"])
        assert result.returncode == 0, (
            f"ci_test.sh failed its build/run probe: {result.stderr.decode()}"
        )
        assert os.path.isfile(paths["lib_calc.so"]), "CI did not build lib_calc.so"
        with open(paths["lib_calc.so"], "rb") as f:
            assert f.read(4) == b"\x7fELF", "CI output lib_calc.so is not an ELF library"

        probe_lib = ctypes.CDLL(paths["lib_calc.so"])
        probe_lib.compute_checksum.argtypes = [ctypes.c_char_p, ctypes.c_int]
        probe_lib.compute_checksum.restype = ctypes.c_uint32
        assert probe_lib.compute_checksum(b"probe", 5) == secret, (
            "CI did not compile the verifier-provided lib_calc.c into lib_calc.so"
        )
        assert os.path.isfile(marker), "CI did not execute main.py"
        with open(paths["output.txt"], "r", encoding="utf-8") as f:
            assert f.read().strip() == str(secret), (
                "CI did not execute main.py against the library it built"
            )
    finally:
        if os.path.exists(marker):
            os.remove(marker)
        for name, path in paths.items():
            data = backups[name]
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
