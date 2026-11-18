#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import shutil
import subprocess
import tempfile

ANALYZER = "/home/user/analyzer"
SOURCE = "/home/user/analyzer.c"
EVENTS = "/home/user/events.log"
ANOMALIES = "/home/user/anomalies.txt"
EXPECTED_ORIGINAL = "Anomaly detected at 1620000006: 61000 ms"


def expected_output(rows):
    values = [row[2] for row in rows]
    average = sum(values) / len(values)
    variance = sum(v * v for v in values) / len(values) - average * average
    stddev = math.sqrt(max(0.0, variance))
    threshold = average + 2.0 * stddev
    return "".join(
        f"Anomaly detected at {ts}: {resp} ms\n"
        for ts, status, resp, payload in rows
        if resp > threshold
    )


def write_rows(rows):
    with open(EVENTS, "w") as f:
        for ts, status, resp, payload in rows:
            f.write(f"{ts},{status},{resp},{payload}\n")


def run_analyzer(rows):
    write_rows(rows)
    result = subprocess.run(
        [ANALYZER], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=5, check=False
    )
    assert result.returncode == 0, (
        f"analyzer exited with {result.returncode}; stderr: {result.stderr}"
    )
    assert result.stdout == expected_output(rows), (
        f"unexpected analyzer output for response times {[r[2] for r in rows]}: "
        f"expected {expected_output(rows)!r}, got {result.stdout!r}"
    )


def test_anomalies_file_exists():
    assert os.path.isfile(ANOMALIES), "The file /home/user/anomalies.txt does not exist."


def test_anomalies_file_content():
    with open(ANOMALIES, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 1, f"Expected exactly 1 anomaly in output, but found {len(lines)} lines."
    assert lines[0] == EXPECTED_ORIGINAL, (
        f"Expected output {EXPECTED_ORIGINAL!r}, but got {lines[0]!r}."
    )


def test_analyzer_executable_exists():
    assert os.path.isfile(ANALYZER), "The compiled executable /home/user/analyzer does not exist."
    assert os.access(ANALYZER, os.X_OK), "The file /home/user/analyzer is not executable."
    with open(ANALYZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The analyzer must be a compiled ELF executable."


def test_analyzer_c_fixed_sum_sq():
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "1620000006" not in content, "The source code should not hardcode the expected output."
    assert "61000" not in content, "The source code should not hardcode the expected output."


def test_compiled_analyzer_on_derived_inputs():
    with open(EVENTS, "rb") as f:
        original_events = f.read()
    try:
        cases = [
            [
                (1701000000, 200, 310, "abc"),
                (1701000001, 200, 325, "4869"),
                (1701000002, 200, 295, "1"),
                (1701000003, 500, 58000, "424"),
                (1701000004, 200, 305, "00"),
                (1701000005, 503, 64000, "f"),
                (1701000006, 200, 300, "4142"),
                (1701000007, 200, 315, "deF"),
                (1701000008, 200, 290, "7a"),
                (1701000009, 200, 320, "12345"),
                (1701000010, 200, 300, "beef"),
                (1701000011, 200, 305, "9"),
            ],
            [
                (1702000000 + i, 200, value, "a" if i % 2 else "abcd")
                for i, value in enumerate([
                    1200, 1215, 1195, 1220, 1180, 1235, 1205, 1190,
                    1210, 1175, 1240, 1200, 1225, 1185, 1218, 1198,
                    1230, 1170, 1208, 1192, 55000, 1212, 1188, 62000,
                ])
            ],
        ]
        for rows in cases:
            run_analyzer(rows)
    finally:
        with open(EVENTS, "wb") as f:
            f.write(original_events)


def test_odd_length_payload_decoding():
    # Instrument the submitted source's existing free calls and execute its parser.
    # This makes the otherwise non-output payload bytes observable without replacing
    # the submitted parsing/statistics implementation.
    with open(SOURCE, "r") as f:
        submitted = f.read()
    with open(EVENTS, "rb") as f:
        original_events = f.read()

    rows = [
        (1800000000, 200, 100, "abc"),
        (1800000001, 200, 100, "1"),
        (1800000002, 200, 100, "424"),
        (1800000003, 200, 100, "4869"),
    ]
    prefix = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static const unsigned char expected_decoded[][4] = {
    {0xab, 0xc0, 0x00, 0x00},
    {0x10, 0x00, 0x00, 0x00},
    {0x42, 0x40, 0x00, 0x00},
    {0x48, 0x69, 0x00, 0x00}
};
static const size_t expected_sizes[] = {3, 2, 3, 3};
static int captured = 0;
static int decode_error = 0;
static void capture_free(void *p) {
    if (captured >= 4 || p == NULL) {
        decode_error = 1;
    } else if (memcmp(p, expected_decoded[captured], expected_sizes[captured]) != 0) {
        decode_error = 1;
    }
    captured++;
    free(p);
}
#define free capture_free
#define main submitted_main
'''
    suffix = r'''
#undef main
#undef free
int main(void) {
    char *argv[] = {(char *)"instrumented-analyzer", NULL};
    int rc = submitted_main(1, argv);
    if (rc != 0 || captured != 4 || decode_error) {
        fprintf(stderr, "odd-length payloads were not decoded with an implicit trailing zero nibble\n");
        return 1;
    }
    return 0;
}
'''

    with tempfile.TemporaryDirectory() as td:
        instrumented_c = os.path.join(td, "instrumented.c")
        instrumented_bin = os.path.join(td, "instrumented")
        with open(instrumented_c, "w") as f:
            f.write(prefix)
            f.write("\n")
            f.write(submitted)
            f.write("\n")
            f.write(suffix)
        try:
            write_rows(rows)
            build = subprocess.run(
                ["gcc", "-O0", instrumented_c, "-o", instrumented_bin, "-lm"],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=10, check=False
            )
            assert build.returncode == 0, (
                "The submitted analyzer.c could not be compiled for parser testing: "
                + build.stderr
            )
            result = subprocess.run(
                [instrumented_bin], text=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=5, check=False
            )
            assert result.returncode == 0, result.stderr
        finally:
            with open(EVENTS, "wb") as f:
                f.write(original_events)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
