#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import re
import subprocess

HOME = "/home/user"
PROCESS = f"{HOME}/process.sh"
RAW = f"{HOME}/raw_data.log"
CLEAN = f"{HOME}/clean.csv"
LIB_RS = f"{HOME}/telemetry/src/lib.rs"
LIB = f"{HOME}/telemetry/target/release/libtelemetry.so"
RUNNER = f"{HOME}/runner"
REPORT = f"{HOME}/valgrind_report.txt"


def run_process(timeout=120):
    result = subprocess.run(
        [PROCESS], cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout
    )
    assert result.returncode == 0, (
        f"process.sh failed with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_nonempty_lines(path):
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def assert_elf(path, executable=False):
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF binary."
    if executable:
        assert os.access(path, os.X_OK), f"File {path} is not executable."


def assert_clean_valgrind(text, label):
    assert "Memcheck" in text, f"{label} does not contain Valgrind Memcheck output."
    assert re.search(r"ERROR SUMMARY:\s*0 errors", text), (
        f"{label} does not report zero Valgrind errors."
    )
    no_leaks = "All heap blocks were freed -- no leaks are possible" in text
    zero_lost = re.search(r"definitely lost:\s*0 bytes", text) is not None
    assert no_leaks or zero_lost, f"{label} does not report a leak-free execution."


def test_complete_pipeline():
    # Preserve the original static assertions.
    assert os.path.isfile(PROCESS), f"File {PROCESS} does not exist."
    assert os.access(PROCESS, os.X_OK), f"File {PROCESS} is not executable."
    with open(PROCESS, "r") as f:
        script_content = f.read().lower()
    for tool in ["awk", "perl", "python"]:
        assert tool not in script_content, f"Forbidden tool '{tool}' found in {PROCESS}."

    assert os.path.isfile(LIB_RS), f"File {LIB_RS} does not exist."
    with open(LIB_RS, "r") as f:
        lib_content = f.read()
    assert "#[no_mangle]" in lib_content, f"{LIB_RS} is missing #[no_mangle]."
    assert 'extern "C"' in lib_content, f'{LIB_RS} is missing extern "C".'

    # Remove all generated artifacts, restore the supplied input, and require the
    # submitted script to recreate the complete pipeline itself.
    subprocess.run(["cargo", "clean"], cwd=f"{HOME}/telemetry", check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for path in [CLEAN, RUNNER, REPORT]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    canonical = """[START]
ID: 1
VAL: 10.5
[END]
[START]
ID: 2
[START]
ID: 3
VAL: 15.0
[END]
ID: 4
VAL: 20.0
[END]
[START]
ID: 5
VAL: 25.5
"""
    with open(RAW, "w") as f:
        f.write(canonical)
    run_process()

    assert read_nonempty_lines(CLEAN) == ["1,10.5", "3,15.0"], (
        f"Content of {CLEAN} does not match the expected original output."
    )
    assert_elf(LIB)
    assert_elf(RUNNER, executable=True)

    # Ensure runner really is dynamically linked to the produced Rust library
    # and imports the required symbol rather than being a placeholder.
    dynamic = subprocess.run(["readelf", "-d", RUNNER], check=True, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
    assert "libtelemetry.so" in dynamic, "runner is not linked against libtelemetry.so."
    symbols = subprocess.run(["nm", "-D", RUNNER], check=True, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
    assert re.search(r"\bU\s+process_data\b", symbols), (
        "runner does not dynamically import process_data."
    )

    # Actually load the cdylib and resolve/call its C ABI entry point.
    library = ctypes.CDLL(LIB)
    function = library.process_data
    function.argtypes = [ctypes.c_int, ctypes.c_double]
    function.restype = None
    function(987654, 123.75)

    # Exercise the Bash parser on values not known when the solution was written.
    rng = random.SystemRandom()
    ids = rng.sample(range(10000, 90000), 6)
    vals = [f"{rng.randrange(10, 999)}.{rng.randrange(10, 99)}" for _ in range(6)]
    lines = [
        "noise before",
        "[START]", f"ID: {ids[0]}", f"VAL: {vals[0]}", "[END]",
        # Incomplete block is discarded; the following START begins a valid one.
        "[START]", f"ID: {ids[1]}",
        "[START]", f"ID: {ids[2]}", f"VAL: {vals[2]}", "[END]",
        # Wrong field order.
        "[START]", f"VAL: {vals[3]}", f"ID: {ids[3]}", "[END]",
        # Extra content makes this block imperfect.
        "[START]", f"ID: {ids[4]}", "corrupt", f"VAL: {vals[4]}", "[END]",
        # Another valid block.
        "[START]", f"ID: {ids[5]}", f"VAL: {vals[5]}", "[END]",
        # Missing END.
        "[START]", "ID: 99991", "VAL: 8.25",
    ]
    expected = [f"{ids[0]},{vals[0]}", f"{ids[2]},{vals[2]}", f"{ids[5]},{vals[5]}"]
    with open(RAW, "w") as f:
        f.write("\n".join(lines) + "\n")
    try:
        os.remove(REPORT)
    except FileNotFoundError:
        pass
    run_process()
    assert read_nonempty_lines(CLEAN) == expected, (
        f"Parser failed generated malformed-block test: got {read_nonempty_lines(CLEAN)}, "
        f"expected {expected}."
    )

    # Execute the actual compiled runner against the generated CSV.
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = f"{HOME}/telemetry/target/release"
    executed = subprocess.run([RUNNER], env=env, cwd=HOME, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert executed.returncode == 0, (
        f"runner failed with status {executed.returncode}: {executed.stderr}"
    )

    # The script itself must have produced a real, clean Valgrind report.
    assert os.path.isfile(REPORT), f"File {REPORT} does not exist."
    with open(REPORT, "r", errors="replace") as f:
        report_content = f.read()
    assert_clean_valgrind(report_content, REPORT)
    assert "runner" in report_content, f"{REPORT} does not identify the runner command."

    # Independently profile the submitted runner so a fabricated report cannot pass.
    verified_report = "/tmp/verifier_valgrind.txt"
    with open(verified_report, "w") as output:
        vg = subprocess.run(
            ["valgrind", "--leak-check=full", "--error-exitcode=97", RUNNER],
            env=env, cwd=HOME, stdout=output, stderr=subprocess.STDOUT, timeout=60
        )
    assert vg.returncode == 0, f"Valgrind found errors or runner failed (status {vg.returncode})."
    with open(verified_report, "r", errors="replace") as f:
        assert_clean_valgrind(f.read(), "independent Valgrind run")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
