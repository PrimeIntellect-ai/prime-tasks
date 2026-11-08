#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import shutil
import subprocess

import pytest

SYSDEBUG_DIR = "/home/user/sysdebug"
STANDARD_UNDEFINED = {
    "__cxa_finalize",
    "__gmon_start__",
    "_ITM_deregisterTMCloneTable",
    "_ITM_registerTMCloneTable",
}
EXPECTED_APP = '''import ctypes
import sys
import os

def main():
    try:
        lib = ctypes.CDLL("./libalpha.so")
        res = lib.a()
        with open("result.txt", "w") as f:
            f.write(f"Success: {res}")
        print("Done.")
    except Exception as e:
        print(f"Failed to load or execute: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
'''


def application_undefined(path):
    proc = subprocess.run(
        ["nm", "-D", "--undefined-only", path],
        check=True,
        text=True,
        capture_output=True,
    )
    symbols = []
    for line in proc.stdout.splitlines():
        fields = line.split()
        if not fields:
            continue
        symbol = fields[-1].split("@", 1)[0]
        if symbol in STANDARD_UNDEFINED or "GLIBC" in fields[-1]:
            continue
        symbols.append(symbol)
    return sorted(set(symbols))


def run_analyzer():
    output = os.path.join(SYSDEBUG_DIR, "missing_symbols.json")
    if os.path.exists(output):
        os.remove(output)
    subprocess.run(
        ["python3", os.path.join(SYSDEBUG_DIR, "analyze.py")],
        cwd=SYSDEBUG_DIR,
        check=True,
        timeout=20,
    )
    assert os.path.isfile(output), f"{output} is missing after running analyze.py."
    with open(output, "r") as f:
        return json.load(f)


def call_int_function(library, symbol):
    code = (
        "import ctypes,sys; "
        "lib=ctypes.CDLL(sys.argv[1]); "
        "fn=getattr(lib,sys.argv[2]); "
        "fn.restype=ctypes.c_int; "
        "print(fn())"
    )
    proc = subprocess.run(
        ["python3", "-c", code, library, symbol],
        text=True,
        capture_output=True,
        check=True,
        timeout=10,
    )
    return int(proc.stdout.strip())


def test_analyze_py_exists():
    path = os.path.join(SYSDEBUG_DIR, "analyze.py")
    assert os.path.isfile(path), f"{path} is missing."


def test_analyzer_executes_and_uses_nm_results():
    gamma = os.path.join(SYSDEBUG_DIR, "libgamma.so")
    backup = gamma + ".verifier-backup"
    random_symbol = "verifier_missing_" + secrets.token_hex(8)
    source = os.path.join("/tmp", random_symbol + ".c")

    shutil.copy2(gamma, backup)
    try:
        with open(source, "w") as f:
            f.write(f"extern int {random_symbol}(void);\nint g(void) {{ return {random_symbol}() + 1; }}\n")
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", gamma, source],
            check=True,
            timeout=20,
        )
        data = run_analyzer()
        assert isinstance(data, dict), "Analyzer output must be a dictionary."
        assert "libgamma.so" in data, "libgamma.so missing from analyzer output."
        assert data["libgamma.so"] == [random_symbol], (
            "analyze.py did not report the undefined symbol from the library supplied to it."
        )
    finally:
        if os.path.exists(backup):
            os.replace(backup, gamma)
        if os.path.exists(source):
            os.remove(source)

    # Regenerate the required final output from the original libraries.
    data = run_analyzer()
    expected = {}
    for filename in ("libalpha.so", "libbeta.so", "libgamma.so"):
        expected[filename] = application_undefined(os.path.join(SYSDEBUG_DIR, filename))
        assert filename in data, f"{filename} missing from JSON."
        assert isinstance(data[filename], list), f"{filename} symbols must be a list."
        assert data[filename] == sorted(data[filename]), f"{filename} symbols are not sorted."
        assert data[filename] == expected[filename], (
            f"Incorrect undefined symbols for {filename}: {data[filename]} != {expected[filename]}"
        )


def test_missing_symbols_json():
    path = os.path.join(SYSDEBUG_DIR, "missing_symbols.json")
    assert os.path.isfile(path), f"{path} is missing."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} is not a valid JSON file.")

    assert isinstance(data, dict), f"JSON content in {path} must be a dictionary."
    assert "libgamma.so" in data, "libgamma.so missing from JSON."
    assert "fetch_config_value" in data["libgamma.so"], "fetch_config_value missing from libgamma.so symbols."
    assert "libbeta.so" in data, "libbeta.so missing from JSON."
    assert "g" in data["libbeta.so"], "'g' missing from libbeta.so symbols."
    assert "libalpha.so" in data, "libalpha.so missing from JSON."
    assert "b" in data["libalpha.so"], "'b' missing from libalpha.so symbols."


def test_fixture_files_exist_and_work():
    c_path = os.path.join(SYSDEBUG_DIR, "fixture.c")
    so_path = os.path.join(SYSDEBUG_DIR, "libfixture.so")
    assert os.path.isfile(c_path), f"{c_path} is missing."
    assert os.path.isfile(so_path), f"{so_path} is missing."

    header = subprocess.run(
        ["readelf", "-h", so_path], text=True, capture_output=True, check=True
    ).stdout
    assert "DYN (Shared object file)" in header, "libfixture.so is not an ELF shared object."

    exported = subprocess.run(
        ["nm", "-D", "--defined-only", so_path],
        text=True,
        capture_output=True,
        check=True,
    ).stdout
    assert "fetch_config_value" in exported, "libfixture.so does not export fetch_config_value."
    assert call_int_function(so_path, "fetch_config_value") == 42

    rebuilt = "/tmp/libfixture-from-source.so"
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", rebuilt, c_path],
        check=True,
        timeout=20,
    )
    assert call_int_function(rebuilt, "fetch_config_value") == 42, (
        "fixture.c does not implement fetch_config_value returning 42."
    )


def test_app_is_original_and_orchestration_runs():
    app_path = os.path.join(SYSDEBUG_DIR, "app.py")
    assert os.path.isfile(app_path), f"{app_path} is missing."
    with open(app_path, "r") as f:
        assert f.read() == EXPECTED_APP, "The provided app.py was modified."

    result = os.path.join(SYSDEBUG_DIR, "result.txt")
    if os.path.exists(result):
        os.remove(result)

    clean_env = os.environ.copy()
    clean_env.pop("LD_PRELOAD", None)
    failed = subprocess.run(
        ["python3", "app.py"],
        cwd=SYSDEBUG_DIR,
        env=clean_env,
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert failed.returncode != 0, "app.py unexpectedly ran without dependency preloading."
    assert not os.path.exists(result), "A failed unlinked run unexpectedly produced result.txt."

    env = clean_env.copy()
    env["LD_LIBRARY_PATH"] = SYSDEBUG_DIR
    env["LD_PRELOAD"] = ":".join(
        os.path.join(SYSDEBUG_DIR, name)
        for name in ("libfixture.so", "libgamma.so", "libbeta.so")
    )
    completed = subprocess.run(
        ["python3", "app.py"],
        cwd=SYSDEBUG_DIR,
        env=env,
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert "Done." in completed.stdout


def test_result_txt():
    path = os.path.join(SYSDEBUG_DIR, "result.txt")
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "Success: 89", f"Expected 'Success: 89' in result.txt, but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
