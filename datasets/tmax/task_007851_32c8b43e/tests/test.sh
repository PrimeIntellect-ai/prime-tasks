#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import subprocess
import tempfile

import numpy as np

EXE = "/home/user/proc_spec"
SOURCE = "/home/user/process_spectroscopy.c"
INPUT = "/home/user/input.dat"
OUTPUT = "/home/user/smoothed.dat"
REPORT = "/home/user/report.txt"
SIZE = 500


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=30, **kwargs)


def expected_output(input_path):
    data = np.fromfile(input_path, dtype="<f4").reshape(SIZE, SIZE).copy()
    libc = ctypes.CDLL(None)
    libc.srand.argtypes = [ctypes.c_uint]
    libc.rand.restype = ctypes.c_int
    libc.srand(1)

    flat = data.ravel()
    for i in range(flat.size):
        flat[i] = np.float32(float(flat[i]) + 0.0001 * (libc.rand() % 100))

    total = np.zeros((SIZE - 2, SIZE - 2), dtype=np.float32)
    for di in range(3):
        for dj in range(3):
            total += data[di:di + SIZE - 2, dj:dj + SIZE - 2]

    result = np.zeros((SIZE, SIZE), dtype=np.float32)
    result[1:-1, 1:-1] = np.asarray(total, dtype=np.float64) / 9.0
    return result


def test_executable_exists():
    path = "/home/user/proc_spec"
    assert os.path.isfile(path), f"Executable {path} does not exist. Did you compile the C program?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_executable_is_profiled_native_program():
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "proc_spec must be a compiled ELF executable, not a script or dummy file."

    symbols = run(["nm", "-a", EXE], text=True).stdout
    assert re.search(r"\bapply_filter\b", symbols), "Compiled program does not contain apply_filter."
    assert re.search(r"\badd_noise\b", symbols), "Compiled program does not contain add_noise."
    assert ("mcount" in symbols and ("monstartup" in symbols or "__monstartup" in symbols)), \
        "proc_spec lacks gprof (-pg) instrumentation."

    # Compare the optimization structure of the two processing functions with
    # the same source compiled by GCC using the required flags. Operands are
    # ignored so ordinary link-address differences do not matter.
    with tempfile.TemporaryDirectory() as td:
        reference = os.path.join(td, "reference")
        run(["gcc", "-O2", "-pg", SOURCE, "-lm", "-o", reference])

        def mnemonics(binary, function):
            text = run(["objdump", "-d", "--disassemble=" + function, binary], text=True).stdout
            result = []
            for line in text.splitlines():
                match = re.match(r"^\s*[0-9a-f]+:\s+(?:[0-9a-f]{2}\s+)+([A-Za-z][A-Za-z0-9.]*)", line)
                if match:
                    result.append(match.group(1).lower())
            return result

        for function in ("apply_filter", "add_noise"):
            actual = mnemonics(EXE, function)
            wanted = mnemonics(reference, function)
            assert actual and actual == wanted, \
                f"{function} does not have the code structure produced with the required -O2 -pg build."


def test_smoothed_dat_exists():
    path = "/home/user/smoothed.dat"
    assert os.path.isfile(path), f"Output file {path} does not exist. Did you run the compiled executable?"
    expected_size = 500 * 500 * 4
    actual_size = os.path.getsize(path)
    assert actual_size == expected_size, f"Expected {path} to be {expected_size} bytes, but got {actual_size}."


def test_smoothed_dat_is_real_program_output():
    expected = expected_output(INPUT)
    actual = np.fromfile(OUTPUT, dtype="<f4").reshape(SIZE, SIZE)
    assert np.array_equal(actual, expected), \
        "smoothed.dat is not the output produced by process_spectroscopy.c for input.dat."


def test_executable_on_unseen_input_and_gprof_data():
    rng = np.random.default_rng(927431)
    unseen = rng.normal(size=(SIZE, SIZE)).astype("<f4")

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "unseen.dat")
        output_path = os.path.join(td, "output.dat")
        unseen.tofile(input_path)

        completed = subprocess.run(
            [EXE, input_path, output_path], cwd=td,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert completed.returncode == 0, "proc_spec failed when executed on a valid unseen input."
        assert os.path.getsize(output_path) == SIZE * SIZE * 4

        actual = np.fromfile(output_path, dtype="<f4").reshape(SIZE, SIZE)
        expected = expected_output(input_path)
        assert np.array_equal(actual, expected), \
            "proc_spec does not implement the supplied spectroscopy processing program."

        gmon = os.path.join(td, "gmon.out")
        assert os.path.isfile(gmon) and os.path.getsize(gmon) > 20, \
            "Executing proc_spec did not generate valid-looking gprof data."
        profile = run(["gprof", EXE, gmon], text=True).stdout
        assert "Flat profile" in profile and "apply_filter" in profile, \
            "gprof could not profile apply_filter in the submitted executable."


def test_report_txt_contents():
    path = "/home/user/report.txt"
    assert os.path.isfile(path), f"Report file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {path}, but found {len(lines)}."

    assert lines[0] == "apply_filter", f"Line 1 of report.txt is incorrect. Expected 'apply_filter', got '{lines[0]}'."
    assert lines[1] == "15,25", f"Line 2 of report.txt is incorrect. Expected '15,25', got '{lines[1]}'."

    with open(path, "rb") as f:
        assert f.read() == b"apply_filter\n15,25\n", \
            "report.txt must contain exactly the required two lines and no other text."

    data = np.fromfile(OUTPUT, dtype="<f4").reshape(SIZE, SIZE)
    amplitudes = np.abs(np.fft.fft2(data))
    amplitudes[0, 0] = -np.inf
    maximum = np.max(amplitudes)
    candidates = np.argwhere(np.isclose(amplitudes, maximum, rtol=1e-12, atol=1e-9))
    peak = candidates[np.lexsort((candidates[:, 1], candidates[:, 0]))[0]]
    reported = tuple(map(int, lines[1].split(",")))
    assert reported == tuple(map(int, peak)), \
        f"Reported frequency {reported} was not derived from the FFT of smoothed.dat; expected {tuple(peak)}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
