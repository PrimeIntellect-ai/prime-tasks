#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import stat
import subprocess

CPP_PATH = "/home/user/spectral_analysis.cpp"
FASTA_PATH = "/home/user/sequence.fasta"
RESULT_PATH = "/home/user/result.txt"
EXE_PATH = "/home/user/spectral_analysis"
VERIFIER_EXE = "/tmp/verified_spectral_analysis"


def get_expected_result():
    assert os.path.isfile(FASTA_PATH), f"File missing: {FASTA_PATH}"

    seq = ""
    with open(FASTA_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(">"):
                continue
            seq += line

    signal = []
    for c in seq:
        if c == 'A': signal.append(1.0)
        elif c == 'C': signal.append(2.0)
        elif c == 'G': signal.append(-1.0)
        elif c == 'T': signal.append(-2.0)

    N = len(signal)
    mags = []
    for k in range(N):
        re_value = 0.0
        im_value = 0.0
        for n in range(N):
            angle = -2.0 * math.pi * k * n / N
            re_value += signal[n] * math.cos(angle)
            im_value += signal[n] * math.sin(angle)
        mags.append(math.sqrt(re_value ** 2 + im_value ** 2))

    total = 0.0
    compensation = 0.0
    for magnitude in mags:
        adjusted = magnitude - compensation
        temporary = total + adjusted
        compensation = (temporary - total) - adjusted
        total = temporary

    return f"{total:.6f}"


def run_program(path):
    completed = subprocess.run(
        [path], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30, check=False
    )
    assert completed.returncode == 0, (
        f"{path} exited with status {completed.returncode}: "
        f"{completed.stderr.decode(errors='replace')}"
    )
    return completed.stdout


def test_result_txt_content():
    """Verify that result.txt exists and contains the correct Kahan sum output."""
    assert os.path.isfile(RESULT_PATH), f"Result file missing: {RESULT_PATH}"
    expected_output = get_expected_result()
    with open(RESULT_PATH, "r") as f:
        actual_output = f.read().strip()
    assert actual_output == expected_output, (
        f"Output in result.txt is incorrect. Expected '{expected_output}', "
        f"got '{actual_output}'"
    )


def test_cpp_modifications():
    """Verify double declarations and an actual Kahan accumulation recurrence."""
    assert os.path.isfile(CPP_PATH), f"C++ source file missing: {CPP_PATH}"
    with open(CPP_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "vector<double>" in content.replace(" ", ""), \
        "The C++ code must use std::vector<double> for the signal."
    assert "double" in content, "The C++ code must use 'double' precision variables."

    code = re.sub(r"//.*?$|/\*.*?\*/", "", content,
                  flags=re.MULTILINE | re.DOTALL)
    assert not re.search(r"\bfloat\b", code), \
        "Single-precision float declarations remain in the implementation."
    assert not re.search(r"(?:\d(?:[\d.]*\d)?|\.\d+)[fF]\b", code), \
        "Single-precision floating-point literals remain in the implementation."

    for variable in ("re", "im", "angle", "mag", "total_magnitude"):
        assert re.search(r"\bdouble\b[^;{}]*\b" + variable + r"\b[^;{}]*;", code), \
            f"{variable} must be declared as double."

    compact = re.sub(r"\s+", "", code)
    assert "total_magnitude+=mag" not in compact, \
        "The naive total_magnitude += mag accumulation is still present."
    assert "total_magnitude=total_magnitude+mag" not in compact, \
        "A naive total_magnitude = total_magnitude + mag accumulation is present."

    # Match the four dependent operations of strict Kahan summation while
    # allowing the temporary and compensation variables to have any names.
    kahan = re.search(
        r"(?:double|auto)(?P<adjusted>[A-Za-z_]\w*)=mag-(?P<comp>[A-Za-z_]\w*);"
        r"(?:double|auto)(?P<temporary>[A-Za-z_]\w*)="
        r"total_magnitude\+(?P=adjusted);"
        r"(?P=comp)=\((?P=temporary)-total_magnitude\)-(?P=adjusted);"
        r"total_magnitude=(?P=temporary);",
        compact
    )
    assert kahan, \
        "The magnitude loop must perform the strict Kahan compensation recurrence."

    compensation = kahan.group("comp")
    assert re.search(r"\bdouble\b[^;{}]*\b" + re.escape(compensation) + r"\b[^;{}]*;", code), \
        "The Kahan compensation variable must use double precision."
    assert re.search(r"\b" + re.escape(compensation) +
                     r"\s*(?:=\s*0(?:\.0*)?(?:[eE][+-]?0)?|\{\s*0(?:\.0*)?\s*\})", code), \
        "The Kahan compensation variable must be initialized to zero."


def test_compiled_executable_and_behavior():
    assert os.path.isfile(EXE_PATH), f"Compiled executable missing: {EXE_PATH}"
    mode = os.stat(EXE_PATH).st_mode
    assert stat.S_ISREG(mode) and os.access(EXE_PATH, os.X_OK), \
        "spectral_analysis must be a regular executable file."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", \
            "spectral_analysis must be a compiled ELF executable."

    compile_result = subprocess.run(
        ["g++", "-O2", "-std=c++17", CPP_PATH, "-o", VERIFIER_EXE],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False
    )
    assert compile_result.returncode == 0, (
        "Modified source does not compile:\n" +
        compile_result.stderr.decode(errors="replace")
    )

    with open(FASTA_PATH, "rb") as f:
        original_fasta = f.read()
    with open(RESULT_PATH, "rb") as f:
        recorded_result = f.read()

    try:
        # On the original input, result.txt must be the exact redirected output
        # of the submitted compiled executable, including the final newline.
        submitted_original = run_program(EXE_PATH)
        assert recorded_result == submitted_original, \
            "result.txt is not the exact output of the submitted executable."
        assert submitted_original == (get_expected_result() + "\n").encode(), \
            "The submitted executable gives an incorrect result on sequence.fasta."

        rng = random.Random(731927)
        cases = [
            "A",
            "ACGTGCAATTCG",
            "ACGTNNacgtTGCA" * 5,
            "".join(rng.choice("ACGT") for _ in range(97)),
            "".join(rng.choice("ACGT") for _ in range(257)),
        ]

        for index, sequence in enumerate(cases):
            wrapped = "\n".join(sequence[i:i + 31] for i in range(0, len(sequence), 31))
            with open(FASTA_PATH, "w") as f:
                f.write(f">verification_{index}\n{wrapped}\n")

            expected = (get_expected_result() + "\n").encode()
            submitted_output = run_program(EXE_PATH)
            rebuilt_output = run_program(VERIFIER_EXE)
            assert submitted_output == expected, (
                f"Submitted executable failed derived test case {index}: "
                f"expected {expected!r}, got {submitted_output!r}"
            )
            assert rebuilt_output == expected, (
                f"Executable rebuilt from spectral_analysis.cpp failed test case {index}: "
                f"expected {expected!r}, got {rebuilt_output!r}"
            )
            assert submitted_output == rebuilt_output, \
                "The submitted executable does not behave like the modified source."
    finally:
        with open(FASTA_PATH, "wb") as f:
            f.write(original_fasta)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
