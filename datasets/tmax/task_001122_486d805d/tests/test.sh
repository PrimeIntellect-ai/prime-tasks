#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import traceback

import netCDF4 as nc
import numpy as np

SOURCE = "/home/user/analyze_seq.c"
DATA = "/home/user/sequence_data.nc"
RESULT = "/home/user/analysis_result.txt"
BINARY = "/tmp/analyze_seq_verified"
N = 4096

RESULT_RE = re.compile(
    r"\ATime Energy: ([+-]?\d+\.\d{2})\n"
    r"Freq Energy: ([+-]?\d+\.\d{2})\n"
    r"Stability Error: ([+-]?\d+\.\d{6})\n"
    r"Dominant Frequency Bin: (\d+)\n?\Z"
)


def run_program():
    if os.path.exists(RESULT):
        os.remove(RESULT)
    completed = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert completed.returncode == 0, (
        f"Program exited with {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.exists(RESULT), f"The result file {RESULT} is missing."
    assert os.path.isfile(RESULT), f"The path {RESULT} is not a file."
    with open(RESULT, "r", encoding="utf-8") as f:
        content = f.read()
    match = RESULT_RE.fullmatch(content)
    assert match is not None, (
        "analysis_result.txt does not have exactly the required four-line format; "
        f"got {content!r}"
    )
    values = (float(match.group(1)), float(match.group(2)),
              float(match.group(3)), int(match.group(4)))
    assert all(np.isfinite(v) for v in values[:3]), "Results must be finite numbers."
    return values, content


def write_dataset(signal):
    temporary = DATA + ".verifier_tmp"
    if os.path.exists(temporary):
        os.remove(temporary)
    ds = nc.Dataset(temporary, "w", format="NETCDF4")
    try:
        ds.createDimension("time", N)
        var = ds.createVariable("mapped_sequence", "f8", ("time",))
        var[:] = np.asarray(signal, dtype=np.float64)
    finally:
        ds.close()
    os.replace(temporary, DATA)


def expected(signal):
    signal = np.asarray(signal, dtype=np.float64)
    spectrum = np.fft.fft(signal)
    time_energy = float(np.sum(signal * signal))
    freq_energy = float(np.sum(np.abs(spectrum) ** 2) / N)
    dominant = int(np.argmax(np.abs(spectrum[1:N // 2 + 1])) + 1)
    return time_energy, freq_energy, abs(time_energy - freq_energy), dominant


def check_against_signal(signal):
    write_dataset(signal)
    (time_energy, freq_energy, error, dominant), _ = run_program()
    exp_time, exp_freq, exp_error, exp_dominant = expected(signal)
    assert abs(time_energy - exp_time) <= 0.011, (
        f"Expected time energy {exp_time:.2f}, got {time_energy:.2f}"
    )
    assert abs(freq_energy - exp_freq) <= 0.011, (
        f"Expected frequency energy {exp_freq:.2f}, got {freq_energy:.2f}"
    )
    assert error < 1e-3, f"Expected Stability Error close to 0, got {error}"
    assert abs(error - exp_error) < 1e-3, (
        f"Incorrect Parseval stability error: expected {exp_error}, got {error}"
    )
    assert dominant == exp_dominant, (
        f"Expected dominant frequency bin {exp_dominant}, got {dominant}"
    )


def verify():
    # Preserve the original source-file assertion and strengthen it to require C source.
    assert os.path.exists(SOURCE), f"The C source file {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"The C source path {SOURCE} is not a file."
    assert os.path.getsize(SOURCE) > 0, "The C source file is empty."

    compiled = subprocess.run(
        ["gcc", SOURCE, "-o", BINARY, "-lnetcdf", "-lfftw3", "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compiled.returncode == 0, (
        f"analyze_seq.c did not compile with the required libraries.\n"
        f"stdout:\n{compiled.stdout}\nstderr:\n{compiled.stderr}"
    )

    symbols = subprocess.run(
        ["nm", "-D", BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10, check=True
    ).stdout
    assert re.search(r"\bnc_open(?:\b|_)", symbols), "Program does not use NetCDF to open the input."
    assert re.search(r"\bnc_get_var", symbols), "Program does not use NetCDF to read mapped_sequence."
    assert re.search(r"\bfftw_plan_", symbols), "Program does not create an FFTW transform plan."
    assert re.search(r"\bfftw_execute", symbols), "Program does not execute an FFTW transform."

    # Run on the original dataset before checking the original assertions.
    (time_energy, freq_energy, stability_error, dominant_bin), content = run_program()

    # Original result-file assertions.
    assert os.path.exists(RESULT), f"The result file {RESULT} is missing."
    assert os.path.isfile(RESULT), f"The path {RESULT} is not a file."
    assert re.search(r"Time Energy:\s*([0-9.]+)", content) is not None
    assert abs(time_energy - 10240.00) < 0.1, f"Expected Time Energy ~10240.00, got {time_energy}"
    assert re.search(r"Freq Energy:\s*([0-9.]+)", content) is not None
    assert abs(freq_energy - 10240.00) < 0.1, f"Expected Freq Energy ~10240.00, got {freq_energy}"
    assert re.search(r"Stability Error:\s*([0-9.]+)", content) is not None
    assert stability_error < 1e-3, f"Expected Stability Error close to 0, got {stability_error}"
    assert re.search(r"Dominant Frequency Bin:\s*([0-9]+)", content) is not None
    assert dominant_bin == 1365, f"Expected Dominant Frequency Bin to be 1365, got {dominant_bin}"

    # Exercise the executable on unpredictable replacement inputs. Expected values
    # are independently derived from the generated NetCDF data.
    rng = secrets.SystemRandom()
    for _ in range(2):
        bins = rng.sample(range(17, N // 2 - 17), 3)
        phases = [rng.random() * 2.0 * np.pi for _ in range(3)]
        amplitudes = [2.0 + rng.random(), 0.45 + 0.2 * rng.random(), 0.15 + 0.1 * rng.random()]
        offset = (rng.random() - 0.5) * 0.4
        n = np.arange(N, dtype=np.float64)
        signal = np.full(N, offset, dtype=np.float64)
        for amplitude, frequency, phase in zip(amplitudes, bins, phases):
            signal += amplitude * np.sin(2.0 * np.pi * frequency * n / N + phase)
        check_against_signal(signal)


def main():
    backup_fd, backup_path = tempfile.mkstemp(prefix="sequence_data_", suffix=".nc")
    os.close(backup_fd)
    shutil.copy2(DATA, backup_path)
    success = False
    try:
        verify()
        success = True
    except Exception:
        traceback.print_exc()
    finally:
        try:
            shutil.copy2(backup_path, DATA)
            if os.path.exists(BINARY):
                # Leave the requested result corresponding to the original input.
                run_program()
        except Exception:
            traceback.print_exc()
            success = False
        finally:
            try:
                os.remove(backup_path)
            except OSError:
                pass
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
PY_EOF

python3 /tmp/verify_task.py
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
