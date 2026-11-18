#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

SRC = Path("/home/user/src/prepare_dataset.c")
BIN = Path("/home/user/bin/prepare_dataset")
FASTA = Path("/home/user/data/sequences.fasta")
TSV = Path("/home/user/data/observational.tsv")
CSV = Path("/home/user/output/ml_features.csv")


def run_program(executable):
    CSV.unlink(missing_ok=True)
    result = subprocess.run(
        [str(executable)],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Running {executable} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert CSV.is_file(), f"Running {executable} did not create {CSV}."


def derive_expected(fasta_path=FASTA, tsv_path=TSV):
    sequences = {}
    current_id = None
    chunks = []

    for raw_line in fasta_path.read_text().splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith(">"):
            if current_id is not None:
                sequences[current_id] = "".join(chunks)
            current_id = line[1:].split()[0]
            chunks = []
        else:
            assert current_id is not None, "Sequence data appeared before a FASTA header."
            chunks.append(line)
    if current_id is not None:
        sequences[current_id] = "".join(chunks)

    labels = {}
    for raw_line in tsv_path.read_text().splitlines():
        if not raw_line.strip():
            continue
        seq_id, label = raw_line.split("\t", 1)
        labels[seq_id] = label.strip()

    rows = ["SeqID,PurineRatio,ObservationLabel"]
    for seq_id in sorted(sequences):
        sequence = sequences[seq_id]
        ratio = (sequence.count("A") + sequence.count("G")) / len(sequence)
        rows.append(f"{seq_id},{ratio:.4f},{labels[seq_id]}")
    return "\n".join(rows) + "\n"


def test_src_exists_and_openmp():
    """Check that the required C source exists and has the required OpenMP loop pragma."""
    assert SRC.is_file(), f"Source file {SRC} does not exist."
    content = SRC.read_text()
    assert "#pragma omp" in content, f"Source file {SRC} is missing OpenMP pragmas ('#pragma omp')."
    assert re.search(r"(?m)^\s*#\s*pragma\s+omp\s+parallel\s+for\b", content), (
        f"Source file {SRC} is missing a '#pragma omp parallel for' directive."
    )

    result = subprocess.run(
        ["gcc", "-fopenmp", str(SRC), "-o", "/tmp/prepare_dataset_from_source"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"Source file {SRC} does not compile with GCC and OpenMP.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_bin_exists_and_linked_openmp():
    """Check if the compiled binary exists, is executable, and is linked with OpenMP."""
    assert BIN.is_file(), f"Binary file {BIN} does not exist."
    assert os.access(BIN, os.X_OK), f"Binary file {BIN} is not executable."

    result = subprocess.run(["ldd", str(BIN)], capture_output=True, text=True)
    assert result.returncode == 0, f"Running ldd on {BIN} failed."
    assert "libgomp" in result.stdout, (
        f"Binary {BIN} is not linked with libgomp. Ensure it was compiled with -fopenmp."
    )


def test_csv_output():
    """Run the submitted executable and check the required dataset exactly."""
    run_program(BIN)

    expected_content = (
        "SeqID,PurineRatio,ObservationLabel\n"
        "seq001,0.5000,0.98\n"
        "seq002,0.4000,0.45\n"
        "seq003,0.5000,1.23\n"
        "seq004,0.5000,0.11\n"
        "seq005,0.5000,0.76\n"
    )
    actual_content = CSV.read_text()
    assert actual_content.strip() == expected_content.strip(), (
        f"Contents of {CSV} do not match the expected output.\n"
        f"Expected:\n{expected_content}\nActual:\n{actual_content}"
    )
    assert actual_content.strip() == derive_expected().strip()


def test_executables_on_derived_input():
    """Exercise both the submitted binary and freshly compiled source on unseen input."""
    original_fasta = FASTA.read_bytes()
    original_tsv = TSV.read_bytes()
    token = secrets.token_hex(5)

    ids = [f"zeta_{token}", f"alpha_{token}", f"middle_{token}", f"beta_{token}"]
    records = [
        (ids[0], "AGAGAGAGAT"),
        (ids[1], "CCCCCTTTTA"),
        (ids[2], "GGGAAACCCCTTT"),
        (ids[3], "ATGCCGTAACGT"),
    ]
    labels = {
        ids[0]: "2.75",
        ids[1]: "-0.04",
        ids[2]: "8.125",
        ids[3]: "0.333",
    }

    fasta_text = ""
    for seq_id, sequence in (records[2], records[0], records[3], records[1]):
        split = max(1, len(sequence) // 2)
        fasta_text += f">{seq_id}\n{sequence[:split]}\n{sequence[split:]}\n"
    tsv_text = "".join(f"{seq_id}\t{labels[seq_id]}\n" for seq_id, _ in reversed(records))

    try:
        FASTA.write_text(fasta_text)
        TSV.write_text(tsv_text)
        expected = derive_expected()

        run_program(BIN)
        assert CSV.read_text().strip() == expected.strip(), (
            "The submitted executable did not correctly process the derived input."
        )

        compiled = Path("/tmp/prepare_dataset_from_source")
        assert compiled.is_file(), "The source-compiled executable is missing."
        run_program(compiled)
        assert CSV.read_text().strip() == expected.strip(), (
            "The submitted source did not correctly process the derived input when compiled."
        )
    finally:
        FASTA.write_bytes(original_fasta)
        TSV.write_bytes(original_tsv)
        restore = subprocess.run(
            [str(BIN)], cwd="/home/user", capture_output=True, text=True, timeout=15
        )
        assert restore.returncode == 0, (
            f"Failed to regenerate the required final CSV after testing.\n{restore.stderr}"
        )

    assert CSV.read_text().strip() == derive_expected().strip(), (
        "The final CSV was not restored for the provided dataset."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
