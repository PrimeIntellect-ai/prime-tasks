#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import struct
import subprocess
import tempfile


def normalize_arg(arg, cwd):
    if os.path.isabs(arg):
        return os.path.normpath(arg)
    return os.path.normpath(os.path.join(cwd, arg))


def output_path(record, default_name):
    args = record["argv"]
    for index, arg in enumerate(args):
        if arg == "-o" and index + 1 < len(args):
            return normalize_arg(args[index + 1], record["cwd"])
        if arg.startswith("-o") and len(arg) > 2:
            return normalize_arg(arg[2:], record["cwd"])
    return os.path.join(record["cwd"], default_name)


def test_final_state():
    script_path = "/home/user/build_and_test.sh"
    source_path = "/home/user/calc.s"
    calc_path = "/home/user/calc"
    math_result_path = "/home/user/math_result.txt"

    # 1. Verify script exists and is executable
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    trace_dir = tempfile.mkdtemp(prefix="binutils-trace-")
    trace_log = os.path.join(trace_dir, "calls.jsonl")
    wrapper = '''#!/usr/bin/python3
import json
import os
import subprocess
import sys

tool = os.path.basename(sys.argv[0])
real = "/usr/bin/" + tool
record = {"tool": tool, "argv": sys.argv[1:], "cwd": os.getcwd()}
result = subprocess.run([real] + sys.argv[1:])
if result.returncode == 0:
    with open(os.environ["BINUTILS_TRACE_LOG"], "a") as f:
        f.write(json.dumps(record) + "\\n")
sys.exit(result.returncode)
'''
    for tool in ("as", "ld"):
        path = os.path.join(trace_dir, tool)
        with open(path, "w") as f:
            f.write(wrapper)
        os.chmod(path, 0o755)

    # Require the submitted script to create fresh artifacts itself.
    for path in (source_path, calc_path, math_result_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["PATH"] = trace_dir + os.pathsep + env.get("PATH", "")
    env["BINUTILS_TRACE_LOG"] = trace_log

    # 2. Run the script
    result = subprocess.run([script_path], capture_output=True, text=True, env=env)
    assert result.returncode == 0, f"Script failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    # Verify the required assembly source was dynamically created.
    assert os.path.isfile(source_path), f"Assembly source {source_path} was not created."
    assert os.path.getsize(source_path) > 0, f"Assembly source {source_path} is empty."

    # Verify successful GNU as and ld invocations formed a source -> object -> calc chain.
    assert os.path.isfile(trace_log), "The script did not successfully invoke GNU as and ld through PATH."
    with open(trace_log) as f:
        calls = [json.loads(line) for line in f if line.strip()]

    assembled_objects = set()
    for call in calls:
        if call.get("tool") != "as":
            continue
        normalized = [normalize_arg(arg, call["cwd"]) for arg in call["argv"]]
        if source_path in normalized:
            assembled_objects.add(output_path(call, "a.out"))

    assert assembled_objects, f"GNU as was not successfully used to assemble {source_path}."

    linked_correctly = False
    for call in calls:
        if call.get("tool") != "ld" or output_path(call, "a.out") != calc_path:
            continue
        normalized = {normalize_arg(arg, call["cwd"]) for arg in call["argv"]}
        if normalized.intersection(assembled_objects):
            linked_correctly = True
            break
    assert linked_correctly, f"GNU ld was not successfully used to link the assembled object into {calc_path}."

    # 3. Verify calc executable exists
    assert os.path.isfile(calc_path), f"Executable {calc_path} was not created."
    assert os.access(calc_path, os.X_OK), f"File {calc_path} is not executable."

    # Verify calc is an x86_64 ELF executable, not an executable script or other file.
    with open(calc_path, "rb") as f:
        elf_header = f.read(64)
    assert len(elf_header) >= 20 and elf_header[:4] == b"\x7fELF", f"{calc_path} is not an ELF binary."
    assert elf_header[4] == 2, f"{calc_path} is not a 64-bit ELF binary."
    assert elf_header[5] == 1, f"{calc_path} is not a little-endian ELF binary."
    assert struct.unpack_from("<H", elf_header, 18)[0] == 62, f"{calc_path} is not an x86_64 ELF binary."
    assert struct.unpack_from("<H", elf_header, 16)[0] in (2, 3), f"{calc_path} is not an ELF executable."

    # Independently assemble and link calc.s to ensure it is valid and defines _start.
    rebuild_dir = tempfile.mkdtemp(prefix="calc-rebuild-")
    rebuilt_object = os.path.join(rebuild_dir, "calc.o")
    rebuilt_calc = os.path.join(rebuild_dir, "calc")
    rebuilt_as = subprocess.run(["/usr/bin/as", "-o", rebuilt_object, source_path], capture_output=True, text=True)
    assert rebuilt_as.returncode == 0, f"GNU as could not assemble {source_path}: {rebuilt_as.stderr}"
    symbols = subprocess.run(["/usr/bin/nm", "-a", rebuilt_object], capture_output=True, text=True)
    assert symbols.returncode == 0, f"Could not inspect assembled object: {symbols.stderr}"
    assert any(line.split()[-1:] == ["_start"] and len(line.split()) >= 2 and line.split()[-2] != "U" for line in symbols.stdout.splitlines()), "calc.s does not define a _start entry point."
    rebuilt_ld = subprocess.run(["/usr/bin/ld", "-e", "_start", "-o", rebuilt_calc, rebuilt_object], capture_output=True, text=True)
    assert rebuilt_ld.returncode == 0, f"GNU ld could not link {source_path}: {rebuilt_ld.stderr}"
    rebuilt_result = subprocess.run([rebuilt_calc])
    assert rebuilt_result.returncode == 73, f"A fresh GNU as/ld build of {source_path} did not exit with 73."

    # 4. Verify calc exits with 73
    calc_result = subprocess.run([calc_path])
    assert calc_result.returncode == 73, f"Expected {calc_path} to exit with 73, but got {calc_result.returncode}."

    # 5. Calculate expected sum from the generated binary
    with open(calc_path, "rb") as f:
        binary_data = f.read()

    hex_str = binary_data.hex()
    expected_sum = sum(int(char) for char in hex_str if char.isdigit())

    # 6. Verify math_result.txt
    assert os.path.isfile(math_result_path), f"Result file {math_result_path} was not created."

    with open(math_result_path, "r") as f:
        actual_sum_str = f.read().strip()

    assert actual_sum_str.isdigit(), f"Result file {math_result_path} does not contain a valid integer: '{actual_sum_str}'"
    actual_sum = int(actual_sum_str)

    assert actual_sum == expected_sum, f"Expected sum {expected_sum}, but got {actual_sum} in {math_result_path}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
