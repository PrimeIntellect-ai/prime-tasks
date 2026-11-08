#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import secrets
import subprocess
import pytest

ANALYZE = "/home/user/analyze.py"
RUN_ALL = "/home/user/run_all.sh"
FASTA = "/home/user/data/target.fasta"
SOURCE = "/home/user/src/fasta_stat.c"
EXECUTABLE = "/home/user/fasta_stat"
RESULT = "/home/user/result.txt"


def run_checked(argv, timeout=20):
    completed = subprocess.run(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert completed.returncode == 0, (
        f"Command {argv!r} failed with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    return completed


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def expected_integral(sequence):
    counts = [
        sum(base in "GC" for base in sequence[i:i + 10])
        for i in range(len(sequence) - 9)
    ]
    derivatives = [counts[i] - counts[i - 1] for i in range(1, len(counts))]
    squares = [value * value for value in derivatives]
    integral = sum(
        (squares[i - 1] + squares[i]) / 2.0
        for i in range(1, len(squares))
    )
    return f"{integral:.2f}"


def test_analyze_script_exists():
    path = "/home/user/analyze.py"
    assert os.path.isfile(path), f"Python script {path} does not exist."


def test_run_all_script_exists_and_executable():
    path = "/home/user/run_all.sh"
    assert os.path.isfile(path), f"Bash script {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Bash script {path} is not executable."


def test_compiled_executable_exists():
    path = "/home/user/fasta_stat"
    assert os.path.isfile(path), f"Compiled executable {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Compiled file {path} is not executable."


def test_analyze_script_on_runtime_generated_fastas():
    with open(FASTA, "rb") as f:
        original_fasta = f.read()
    original_result = None
    if os.path.exists(RESULT):
        with open(RESULT, "rb") as f:
            original_result = f.read()

    rng = secrets.SystemRandom()
    try:
        for case in range(3):
            length = rng.randint(24, 55)
            sequence = "".join(rng.choice("ACGT") for _ in range(length))
            split1 = rng.randint(5, length - 10)
            split2 = rng.randint(split1 + 1, length - 1)
            fasta_text = (
                f">runtime_case_{case}\n"
                f"{sequence[:split1]}\n"
                f"{sequence[split1:split2]}\n"
                f"{sequence[split2:]}\n"
            )
            with open(FASTA, "w") as f:
                f.write(fasta_text)
            if os.path.exists(RESULT):
                os.remove(RESULT)

            run_checked(["python3", ANALYZE])
            assert os.path.isfile(RESULT), "analyze.py did not create result.txt"
            lines = read_nonempty_lines(RESULT)
            assert lines == [expected_integral(sequence)], (
                "analyze.py did not parse and numerically analyze a runtime-generated "
                f"multiline FASTA correctly; got {lines!r}"
            )
    finally:
        with open(FASTA, "wb") as f:
            f.write(original_fasta)
        if original_result is None:
            if os.path.exists(RESULT):
                os.remove(RESULT)
        else:
            with open(RESULT, "wb") as f:
                f.write(original_result)


def test_run_all_compiles_and_executes_the_pipeline():
    with open(ANALYZE, "rb") as f:
        original_analyze = f.read()
    analyze_mode = stat.S_IMODE(os.stat(ANALYZE).st_mode)
    with open(FASTA, "rb") as f:
        original_fasta = f.read()

    rng = secrets.SystemRandom()
    token = "analysis-" + secrets.token_hex(12)
    sequence_count = rng.randint(2, 7)
    probe = (
        "from pathlib import Path\n"
        f"Path({RESULT!r}).write_text({(token + chr(10))!r})\n"
    )
    generated_fasta = "".join(
        f">runtime_{i}\n" + "".join(rng.choice("ACGT") for _ in range(15 + i)) + "\n"
        for i in range(sequence_count)
    )

    pipeline_error = None
    try:
        with open(ANALYZE, "w") as f:
            f.write(probe)
        os.chmod(ANALYZE, analyze_mode)
        with open(FASTA, "w") as f:
            f.write(generated_fasta)
        if os.path.exists(EXECUTABLE):
            os.remove(EXECUTABLE)
        if os.path.exists(RESULT):
            os.remove(RESULT)

        run_checked([RUN_ALL])
        assert os.path.isfile(EXECUTABLE), "run_all.sh did not create fasta_stat"
        assert os.access(EXECUTABLE, os.X_OK), "fasta_stat created by run_all.sh is not executable"
        with open(EXECUTABLE, "rb") as f:
            assert f.read(4) == b"\x7fELF", "fasta_stat is not a compiled ELF executable"

        lines = read_nonempty_lines(RESULT)
        assert lines == [token, f"Number of sequences: {sequence_count}"], (
            "run_all.sh did not invoke analyze.py and append the output of the compiled "
            f"FASTA counter; got {lines!r}"
        )

        counter_input = "/tmp/runtime_counter.fasta"
        extra_count = rng.randint(8, 13)
        with open(counter_input, "w") as f:
            for i in range(extra_count):
                f.write(f">counter_{i}\nACGT\n")
        completed = run_checked([EXECUTABLE, counter_input])
        assert completed.stdout.strip() == f"Number of sequences: {extra_count}", (
            "The compiled fasta_stat executable did not count sequences on a "
            "runtime-generated FASTA file"
        )
    except BaseException as exc:
        pipeline_error = exc
    finally:
        with open(ANALYZE, "wb") as f:
            f.write(original_analyze)
        os.chmod(ANALYZE, analyze_mode)
        with open(FASTA, "wb") as f:
            f.write(original_fasta)

        final_run = subprocess.run(
            [RUN_ALL], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=20
        )
        if pipeline_error is None:
            assert final_run.returncode == 0, (
                "run_all.sh failed after restoring the supplied input and submitted analyze.py.\n"
                f"stdout:\n{final_run.stdout}\nstderr:\n{final_run.stderr}"
            )

    if pipeline_error is not None:
        raise pipeline_error


def test_result_txt_content():
    path = "/home/user/result.txt"
    assert os.path.isfile(path), f"Result file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"Result file {path} should contain at least 2 lines."

    # First line should be the integral value: 9.50
    assert lines[0] == "9.50", f"Expected first line to be '9.50', but got '{lines[0]}'."

    # Second line should be the output of the C program: Number of sequences: 1
    assert lines[1] == "Number of sequences: 1", f"Expected second line to be 'Number of sequences: 1', but got '{lines[1]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
