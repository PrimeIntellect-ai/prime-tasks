#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import struct
import subprocess
import tempfile

HOME = "/home/user"
SOURCE = f"{HOME}/etl_filter.c"
WRAPPER = f"{HOME}/run_pipeline.sh"
INPUT = f"{HOME}/input_data.bin"
OUTPUT = f"{HOME}/output_data.bin"
METRICS = f"{HOME}/pipeline_metrics.txt"
EXECUTABLE = f"{HOME}/etl_filter"


def expected_result(values):
    mean = sum(values) / len(values)
    variance = sum((x - mean) ** 2 for x in values) / (len(values) - 1)
    sd = math.sqrt(variance)
    low = mean - 2.0 * sd
    high = mean + 2.0 * sd
    filtered = [x for x in values if low <= x <= high]
    metrics = f"Mean: {mean:.6f}\nSD: {sd:.6f}\nCount: {len(filtered)}\n"
    binary = b"".join(struct.pack("<d", x) for x in filtered)
    return metrics, binary


def read_doubles(path):
    data = open(path, "rb").read()
    assert len(data) == 10000 * 8, f"{path} must contain exactly 10,000 doubles"
    return list(struct.unpack("<10000d", data))


def assert_exact_metrics(text, expected):
    assert re.fullmatch(
        r"Mean: -?(?:\d+\.\d{6})\nSD: -?(?:\d+\.\d{6})\nCount: \d+\n?",
        text,
    ), f"Program output must contain exactly the three required lines, got: {text!r}"
    assert text.rstrip("\n") == expected.rstrip("\n"), (
        f"Incorrect metrics. Expected {expected!r}, got {text!r}"
    )


def test_complete_pipeline_and_program():
    assert os.path.exists(WRAPPER), f"Script {WRAPPER} does not exist."
    assert os.path.isfile(WRAPPER), f"{WRAPPER} is not a file."
    assert os.access(WRAPPER, os.X_OK), f"Script {WRAPPER} is not executable."
    wrapper_text = open(WRAPPER, encoding="utf-8").read()
    assert "gcc" in wrapper_text, f"Script {WRAPPER} does not appear to invoke gcc."
    assert "-lgsl" in wrapper_text, f"Script {WRAPPER} does not link GSL (-lgsl)."
    assert "-lgslcblas" in wrapper_text, f"Script {WRAPPER} does not link -lgslcblas."
    assert "-lm" in wrapper_text, f"Script {WRAPPER} does not link -lm."

    assert os.path.exists(SOURCE), f"C program {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."
    source_text = open(SOURCE, encoding="utf-8").read()
    assert re.search(r"\bgsl_stats_mean\s*\(", source_text), "Source does not call gsl_stats_mean."
    assert re.search(r"\bgsl_stats_sd\s*\(", source_text), "Source does not call gsl_stats_sd."

    # Ensure the supplied input was not replaced with an easier dataset.
    generated = []
    for i in range(10000):
        value = math.sin(i / 10.0) * 5.0
        if i % 50 == 0:
            value += 50.0
        generated.append(value)
    expected_input = b"".join(struct.pack("<d", x) for x in generated)
    assert open(INPUT, "rb").read() == expected_input, "input_data.bin was modified."

    for path in (OUTPUT, METRICS, EXECUTABLE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [WRAPPER], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=60
    )
    assert result.returncode == 0, f"Pipeline failed:\nstdout={result.stdout}\nstderr={result.stderr}"
    assert os.path.isfile(EXECUTABLE), "Wrapper did not create /home/user/etl_filter."
    assert open(EXECUTABLE, "rb").read(4) == b"\x7fELF", "etl_filter is not a compiled ELF executable."
    assert os.path.exists(METRICS), f"Metrics file {METRICS} does not exist."
    assert os.path.isfile(OUTPUT), f"Output data file {OUTPUT} does not exist."

    original_metrics, original_binary = expected_result(read_doubles(INPUT))
    assert_exact_metrics(open(METRICS, encoding="utf-8").read(), original_metrics)
    actual_binary = open(OUTPUT, "rb").read()
    assert len(actual_binary) == 9800 * 8, (
        f"Output file size should be {9800 * 8} bytes, got {len(actual_binary)} bytes."
    )
    assert actual_binary == original_binary, "output_data.bin contains incorrect values or ordering."

    # Independently compile the submitted source, then exercise its two path arguments
    # on an unpredictable 10,000-value input.
    with tempfile.TemporaryDirectory() as td:
        checked_exe = os.path.join(td, "etl_filter_checked")
        build = subprocess.run(
            ["gcc", SOURCE, "-o", checked_exe, "-lgsl", "-lgslcblas", "-lm"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
        )
        assert build.returncode == 0, f"Submitted C source does not compile with GSL:\n{build.stderr}"

        symbols = subprocess.run(
            ["nm", "-D", checked_exe], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=10
        )
        assert symbols.returncode == 0
        assert re.search(r"\bU gsl_stats_mean(?:@|$)", symbols.stdout, re.MULTILINE), (
            "Compiled program does not link to gsl_stats_mean."
        )
        assert re.search(r"\bU gsl_stats_sd(?:@|$)", symbols.stdout, re.MULTILINE), (
            "Compiled program does not link to gsl_stats_sd."
        )

        seed = int.from_bytes(os.urandom(16), "little")
        rng = random.Random(seed)
        values = [rng.uniform(-20.0, 20.0) for _ in range(10000)]
        for i in range(0, 10000, 113):
            values[i] += 250.0 if i % 2 else -250.0

        in_path = os.path.join(td, "random_input.bin")
        out_path = os.path.join(td, "random_output.bin")
        with open(in_path, "wb") as f:
            f.write(b"".join(struct.pack("<d", x) for x in values))

        expected_metrics, expected_binary = expected_result(values)
        run = subprocess.run(
            [checked_exe, in_path, out_path], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert run.returncode == 0, f"Compiled program failed:\n{run.stderr}"
        assert_exact_metrics(run.stdout, expected_metrics)
        assert os.path.isfile(out_path), "Program did not create the requested output path."
        assert open(out_path, "rb").read() == expected_binary, (
            "Program produced incorrect filtered binary values on an independent input."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
