#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile


def parse_fasta_output(fasta_path):
    records = []
    current_id = None
    current_seq = []

    with open(fasta_path, "r") as f:
        for raw_line in f:
            line = raw_line.rstrip("\n")
            if not line:
                continue
            if line.startswith(">"):
                if current_id is not None:
                    seq = "".join(current_seq)
                    total = sum(1 for c in seq if c.isalpha())
                    if total > 0:
                        gc = sum(1 for c in seq if c in "GCgc")
                        records.append((current_id, 100.0 * gc / total))
                current_id = line[1:]
                current_seq = []
            else:
                current_seq.append(line)

    if current_id is not None:
        seq = "".join(current_seq)
        total = sum(1 for c in seq if c.isalpha())
        if total > 0:
            gc = sum(1 for c in seq if c in "GCgc")
            records.append((current_id, 100.0 * gc / total))

    return "".join(f"{seq_id}\t{gc:.2f}\n" for seq_id, gc in records)


def compute_gc_content(fasta_path):
    sequences = []
    current_seq = []
    with open(fasta_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith('>'):
                if current_seq:
                    sequences.append("".join(current_seq))
                    current_seq = []
            else:
                current_seq.append(line)
        if current_seq:
            sequences.append("".join(current_seq))

    gc_percentages = []
    for seq in sequences:
        total = sum(1 for c in seq if c.isalpha())
        gc = sum(1 for c in seq if c in 'GCgc')
        if total > 0:
            gc_percentages.append(100.0 * gc / total)

    if not gc_percentages:
        return 0.0
    return sum(gc_percentages) / len(gc_percentages)


def run_tool(fasta_path):
    result = subprocess.run(
        ["/home/user/fasta_stats", fasta_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"fasta_stats failed on {fasta_path} with exit code {result.returncode}: "
        f"{result.stderr}"
    )
    return result.stdout


def test_executable_exists_and_compiled():
    executable_path = "/home/user/fasta_stats"
    assert os.path.isfile(executable_path), f"Executable {executable_path} is missing."
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."

    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fasta_stats is not a compiled ELF executable."

    with tempfile.TemporaryDirectory() as tmpdir:
        reference_path = os.path.join(tmpdir, "fasta_stats_O3")
        compile_result = subprocess.run(
            ["g++", "-O3", "fasta_stats.cpp", "-o", reference_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert compile_result.returncode == 0, (
            "Could not compile the supplied source with g++ -O3: " + compile_result.stderr
        )

        submitted_text = os.path.join(tmpdir, "submitted.text")
        reference_text = os.path.join(tmpdir, "reference.text")
        for binary, output in ((executable_path, submitted_text), (reference_path, reference_text)):
            result = subprocess.run(
                ["objcopy", f"--dump-section", f".text={output}", binary],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0 and os.path.isfile(output), (
                f"Unable to inspect compiled code in {binary}: {result.stderr}"
            )

        with open(submitted_text, "rb") as f:
            submitted_code = f.read()
        with open(reference_text, "rb") as f:
            reference_code = f.read()
        assert submitted_code == reference_code, (
            "fasta_stats does not match the supplied C++ source compiled with g++ -O3."
        )


def test_executable_runs_on_required_and_independent_inputs():
    required_inputs = ["/home/user/groupA.fasta", "/home/user/groupB.fasta"]
    for fasta_path in required_inputs:
        assert run_tool(fasta_path) == parse_fasta_output(fasta_path), (
            f"fasta_stats produced incorrect output for {fasta_path}."
        )

    with tempfile.NamedTemporaryFile("w", suffix=".fasta", delete=False) as probe:
        probe.write(
            ">probe_one\n"
            "ACGTacgtNN\n"
            ">probe_two\n"
            "AAAA\n"
            "CCCCGG\n"
            ">probe_three\n"
            "tttgggcccaaa\n"
        )
        probe_path = probe.name
    try:
        assert run_tool(probe_path) == parse_fasta_output(probe_path), (
            "fasta_stats produced incorrect output for an independent FASTA input."
        )
    finally:
        os.unlink(probe_path)


def test_analysis_report_content():
    report_path = "/home/user/analysis_report.txt"
    assert os.path.isfile(report_path), f"File {report_path} is missing."

    group_a_path = "/home/user/groupA.fasta"
    group_b_path = "/home/user/groupB.fasta"

    mean_a = compute_gc_content(group_a_path)
    mean_b = compute_gc_content(group_b_path)

    abs_diff = abs(mean_a - mean_b)
    higher_group = "GroupA" if mean_a > mean_b else "GroupB"

    expected_content = (
        f"Mean_GroupA: {mean_a:.2f}\n"
        f"Mean_GroupB: {mean_b:.2f}\n"
        f"Absolute_Difference: {abs_diff:.2f}\n"
        f"Higher_Group: {higher_group}\n"
    )

    with open(report_path, "r") as f:
        actual_content = f.read().strip()

    expected_lines = expected_content.strip().split('\n')
    actual_lines = actual_content.split('\n')

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {report_path}, but found {len(actual_lines)}."

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual.strip() == expected.strip(), f"Line {i+1} mismatch in {report_path}.\nExpected: {expected}\nGot: {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
