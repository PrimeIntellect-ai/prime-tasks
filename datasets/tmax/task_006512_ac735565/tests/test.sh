#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

import pytest


def test_files_exist():
    assert os.path.isfile("/home/user/extractor.c"), "/home/user/extractor.c is missing"
    assert os.path.isfile("/home/user/Makefile"), "/home/user/Makefile is missing"
    assert os.path.isfile("/home/user/run_pipeline.sh"), "/home/user/run_pipeline.sh is missing"


def test_run_pipeline_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.access(script_path, os.X_OK), f"{script_path} does not have executable permissions"


def test_pipeline_execution_and_output():
    # Remove the output file and executable if they exist to ensure the script builds and runs them
    if os.path.exists("/home/user/amplicon_data.csv"):
        os.remove("/home/user/amplicon_data.csv")
    if os.path.exists("/home/user/extractor"):
        os.remove("/home/user/extractor")

    # Run the pipeline
    result = subprocess.run(
        ["/home/user/run_pipeline.sh"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"run_pipeline.sh failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    # Check if output file was created
    csv_path = "/home/user/amplicon_data.csv"
    assert os.path.isfile(csv_path), f"{csv_path} was not created by the pipeline"

    # The Makefile-generated artifact must be a compiled executable, not a script.
    with open("/home/user/extractor", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/extractor is not an ELF executable"
    assert os.access("/home/user/extractor", os.X_OK), "/home/user/extractor is not executable"

    # Verify CSV contents
    expected_csv = (
        "SeqID,AmpliconLength,GC_Content\n"
        "Read_001,9,0.67\n"
        "Read_002,8,0.00\n"
        "Read_003,7,1.00"
    )

    with open(csv_path, "r") as f:
        actual_csv = f.read().strip()

    assert actual_csv == expected_csv, f"Contents of {csv_path} do not match the expected output.\nExpected:\n{expected_csv}\n\nActual:\n{actual_csv}"


def make_amplicon(length, gc_count):
    rng = secrets.SystemRandom()
    while True:
        chars = (["G"] * ((gc_count + 1) // 2) +
                 ["C"] * (gc_count // 2) +
                 ["A"] * ((length - gc_count + 1) // 2) +
                 ["T"] * ((length - gc_count) // 2))
        rng.shuffle(chars)
        amp = "".join(chars)
        sequence = "AAAAA" + "GACCTACA" + amp + "TGTTGCAG" + "CCCCC"
        fp_start = sequence.find("GACCTACA")
        rp_start = sequence.find("TGTTGCAG", fp_start + len("GACCTACA"))
        intended_rp = 5 + len("GACCTACA") + len(amp)
        if fp_start == 5 and rp_start == intended_rp:
            return amp, sequence


def test_extractor_on_unseen_fasta_inputs_and_arguments():
    # Compile the submitted C source independently so behavior cannot be supplied
    # by a Makefile that merely creates a canned script or output file.
    with tempfile.TemporaryDirectory(prefix="extractor_verify_") as td:
        binary = os.path.join(td, "extractor_from_source")
        build = subprocess.run(
            ["gcc", "-Wall", "-O2", "/home/user/extractor.c", "-o", binary],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"extractor.c did not compile.\nStdout: {build.stdout}\nStderr: {build.stderr}"
        with open(binary, "rb") as f:
            assert f.read(4) == b"\x7fELF"

        # A two-argument program must not report success when required arguments are absent.
        for args in ([], [os.path.join(td, "only_input.fasta")]):
            result = subprocess.run([binary] + args, capture_output=True, text=True, timeout=10)
            assert result.returncode != 0, f"extractor unexpectedly succeeded with {len(args)} argument(s)"

        # Exercise two independently generated, non-fixture inputs and output paths.
        for round_no in range(2):
            token = secrets.token_hex(6)
            input_path = os.path.join(td, f"unseen_{token}.fasta")
            output_path = os.path.join(td, f"result_{token}.csv")

            valid_specs = [(7, 3), (11, 8), (13, 1), (17, 12)]
            records = []
            expected_rows = []
            for index, (length, gc_count) in enumerate(valid_specs):
                seq_id = f"Novel_{round_no}_{index}_{secrets.token_hex(4)}"
                amp, sequence = make_amplicon(length, gc_count)
                records.append((seq_id, sequence))
                expected_rows.append(f"{seq_id},{len(amp)},{gc_count / len(amp):.2f}")

            # These records must all be skipped: missing reverse, reverse before
            # forward, and missing forward respectively.
            records.extend([
                (f"MissingReverse_{token}", "GACCTACA" + "AACCGGTTAAAA"),
                (f"WrongOrder_{token}", "TGTTGCAGAAAAAAGACCTACA"),
                (f"MissingForward_{token}", "CCCCCCCCCTGTTGCAGAAAA"),
            ])

            with open(input_path, "w") as f:
                for seq_id, sequence in records:
                    f.write(f">{seq_id}\n{sequence}\n")

            result = subprocess.run(
                [binary, input_path, output_path],
                capture_output=True,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, f"extractor failed on an alternate FASTA.\nStdout: {result.stdout}\nStderr: {result.stderr}"
            assert os.path.isfile(output_path), "extractor did not honor the requested output path"

            expected = "SeqID,AmpliconLength,GC_Content\n" + "\n".join(expected_rows)
            with open(output_path) as f:
                actual = f.read().strip()
            assert actual == expected, f"Incorrect output for generated FASTA.\nExpected:\n{expected}\n\nActual:\n{actual}"


if __name__ == "__main__":
    pytest.main([__file__])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
