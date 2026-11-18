#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import struct
import subprocess

import pytest

HOME = "/home/user"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 15)
    return subprocess.run(cmd, **kwargs)


def write_pcap(path, packet_count):
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for _ in range(packet_count):
            f.write(struct.pack("<IIII", 0, 0, 14, 14))
            f.write(b"\x00\x11\x22\x33\x44\x55\x66\x77\x88\x99\xaa\xbb\x08\x00")


def compile_function_harness(source, output, renamed_main):
    harness = f"""
#define main {renamed_main}
#include \"{source}\"
#undef main
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {{
    if (argc != 2) return 2;
    float value = (float)atof(argv[1]);
    printf(\"%.9f\\n\", (double)compute_convergence(value));
    return 0;
}}
"""
    harness_path = output + ".c"
    with open(harness_path, "w") as f:
        f.write(harness)
    proc = run(["gcc", "-o", output, harness_path, "-lm"])
    assert proc.returncode == 0, proc.stderr


def assert_convergence_function(source, label):
    output = f"/tmp/{label}_convergence_test"
    compile_function_harness(source, output, f"{label}_original_main")
    values = [2.0, 17.0, float(secrets.randbelow(250) + 31)]
    for value in values:
        proc = run([output, str(value)], timeout=5)
        assert proc.returncode == 0, f"{label} convergence harness failed: {proc.stderr}"
        try:
            result = float(proc.stdout.strip())
        except ValueError:
            pytest.fail(f"{label} returned a non-numeric convergence result: {proc.stdout!r}")
        assert math.isfinite(result)
        assert abs(result - math.sqrt(value)) < 0.003, (
            f"{label} compute_convergence({value}) returned {result}, "
            f"expected approximately {math.sqrt(value)}"
        )


@pytest.fixture(scope="module")
def pipeline_result():
    script = os.path.join(HOME, "build_and_test.sh")
    analyzer_source = os.path.join(HOME, "analyzer.c")
    assert os.path.isfile(script), "The file /home/user/build_and_test.sh does not exist."
    assert os.access(script, os.X_OK), "/home/user/build_and_test.sh is not executable."
    assert os.path.isfile(analyzer_source), "The file /home/user/analyzer.c does not exist."

    with open(analyzer_source, "r") as f:
        source_text = f.read()
    assert "tcpdump" in source_text and "popen" in source_text, (
        "analyzer.c must invoke tcpdump through popen as required."
    )

    # Independently compile the submitted analyzer.c so the build script cannot
    # hide a broken C implementation behind fabricated output.log contents.
    analyzer_bin = "/tmp/submitted_analyzer"
    proc = run(["gcc", "-o", analyzer_bin, analyzer_source, "-lm"])
    assert proc.returncode == 0, f"Failed to compile analyzer.c:\n{proc.stderr}"

    packet_count = secrets.randbelow(50) + 31
    nonce = secrets.token_hex(5)
    pcap_path = os.path.join(HOME, "pcaps", f"verification capture {nonce}.pcap")
    write_pcap(pcap_path, packet_count)

    # Exercise analyzer.c directly with a filename containing spaces. This tests
    # both the tcpdump command construction and the analytical result.
    proc = run([analyzer_bin, pcap_path], timeout=10)
    assert proc.returncode == 0, f"The compiled analyzer failed:\n{proc.stderr}"
    expected_line = f"File: {pcap_path}, Metric: {math.sqrt(packet_count):.3f}"
    assert proc.stdout.strip() == expected_line, (
        f"Analyzer output was {proc.stdout!r}; expected {expected_line!r}."
    )

    assert_convergence_function(analyzer_source, "analyzer")

    # Execute the requested pipeline and verify that it overwrites, rather than
    # merely appends to, output.log. Run it twice to enforce repeatability.
    output_log = os.path.join(HOME, "output.log")
    with open(output_log, "w") as f:
        f.write("VERIFIER_SENTINEL_SHOULD_BE_OVERWRITTEN\n")

    first = run(["./build_and_test.sh"], cwd=HOME, timeout=20)
    assert first.returncode == 0, f"build_and_test.sh failed:\n{first.stdout}\n{first.stderr}"
    assert os.path.isfile(output_log), "The file /home/user/output.log does not exist."
    with open(output_log, "r") as f:
        first_content = f.read()
    assert "VERIFIER_SENTINEL_SHOULD_BE_OVERWRITTEN" not in first_content

    second = run(["./build_and_test.sh"], cwd=HOME, timeout=20)
    assert second.returncode == 0, f"build_and_test.sh failed on rerun:\n{second.stdout}\n{second.stderr}"
    with open(output_log, "r") as f:
        second_content = f.read()
    assert second_content == first_content, "output.log was not cleanly overwritten on rerun."

    return {
        "content": second_content,
        "dynamic_path": pcap_path,
        "dynamic_metric": f"{math.sqrt(packet_count):.3f}",
    }


def test_output_log_exists(pipeline_result):
    """Test that output.log was generated."""
    assert os.path.isfile("/home/user/output.log"), "The file /home/user/output.log does not exist."


def test_output_log_contents(pipeline_result):
    """Test that output.log associates every pcap with its correct metric."""
    content = pipeline_result["content"]

    # Preserve the original required assertions.
    assert "capture 1.pcap" in content, "output.log is missing 'capture 1.pcap'."
    assert "4.000" in content, "output.log does not contain the expected metric 4.000 for capture 1.pcap."
    assert "capture 2.pcap" in content, "output.log is missing 'capture 2.pcap'."
    assert "5.000" in content, "output.log does not contain the expected metric 5.000 for capture 2.pcap."

    expected = {
        "/home/user/pcaps/capture 1.pcap": "4.000",
        "/home/user/pcaps/capture 2.pcap": "5.000",
        pipeline_result["dynamic_path"]: pipeline_result["dynamic_metric"],
    }
    lines = content.splitlines()
    for filename, metric in expected.items():
        exact = f"File: {filename}, Metric: {metric}"
        assert exact in lines, f"output.log is missing the correctly associated line {exact!r}."


def test_mre_c_exists():
    """Test that mre.c was created."""
    assert os.path.isfile("/home/user/mre.c"), "The file /home/user/mre.c does not exist."


def test_mre_c_compiles_and_runs():
    """Test that mre.c compiles, prints sqrt(100), and contains a working isolated function."""
    compile_cmd = ["gcc", "-o", "/home/user/mre_bin", "/home/user/mre.c", "-lm"]
    compile_proc = run(compile_cmd)
    assert compile_proc.returncode == 0, f"Failed to compile /home/user/mre.c:\n{compile_proc.stderr}"
    assert os.path.isfile("/home/user/mre_bin"), "Compiled binary /home/user/mre_bin was not created."

    run_proc = run(["/home/user/mre_bin"])
    assert run_proc.returncode == 0, f"Running /home/user/mre_bin failed:\n{run_proc.stderr}"
    output = run_proc.stdout
    assert output == "10.000\n", f"Expected output '10.000\\n', but got {output!r}"

    with open("/home/user/mre.c", "r") as f:
        mre_source = f.read()
    assert re.search(r"compute_convergence\s*\(\s*100(?:\.0*)?[fF]?\s*\)", mre_source), (
        "mre.c main must call compute_convergence(100.0)."
    )
    assert_convergence_function("/home/user/mre.c", "mre")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
