#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import shlex
import stat
import subprocess
import tempfile

import pytest

RUN_PIPELINE = "/home/user/run_pipeline.sh"
ANALYZER = "/home/user/analyze_spectra.sh"
PROTEIN = "/home/user/protein.fasta"
OUTPUT = "/home/user/spectral_output.txt"


def expected_power(sequence):
    hydrophobic = set("AILMFWV")
    polar_charged = set("RNDEQKST")
    f_val = 0.2777
    pi_val = 3.14159265359
    x_sum = 0.0
    y_sum = 0.0
    for n, char in enumerate(sequence):
        if char in hydrophobic:
            value = 1.0
        elif char in polar_charged:
            value = -1.0
        else:
            value = 0.0
        angle = 2 * pi_val * f_val * n
        x_sum += value * math.cos(angle)
        y_sum += value * math.sin(angle)
    return x_sum**2 + y_sum**2


def test_run_pipeline_exists_and_executable():
    """Test that the extracted script exists and is executable."""
    path = RUN_PIPELINE
    assert os.path.isfile(path), f"Missing extracted script at {path}"
    assert os.access(path, os.X_OK), f"The script {path} is not executable"


def test_analyze_spectra_exists_and_executable():
    """Test that the analyze_spectra.sh script exists and is executable."""
    path = ANALYZER
    assert os.path.isfile(path), f"Missing script at {path}"
    assert os.access(path, os.X_OK), f"The script {path} is not executable"


def test_analyze_spectra_on_additional_inputs():
    """Execute the analyzer on fresh FASTA inputs and derive every answer."""
    alphabet = "AILMFWVRNDEQKSTCGPHYBXZ*"
    rng = secrets.SystemRandom()

    for length in (1, 8, 29, 67, 113):
        required = "AILMFWVRNDEQKSTCGPHYBXZ*"
        sequence = (required + "".join(rng.choice(alphabet) for _ in range(length + 25)))[:length]
        width = rng.randint(3, 13)
        body = "\n".join(sequence[i:i + width] for i in range(0, len(sequence), width))

        fd, fasta_path = tempfile.mkstemp(prefix="spectra_", suffix=".fasta")
        try:
            with os.fdopen(fd, "w") as fasta:
                fasta.write(f">generated-{secrets.token_hex(8)}\n{body}\n")

            result = subprocess.run(
                [ANALYZER, fasta_path],
                text=True,
                capture_output=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"Analyzer failed for generated FASTA: {result.stderr}"
            )
            assert re.fullmatch(r"[0-9]+\.[0-9]{2}\n?", result.stdout), (
                "Analyzer output must contain only a power formatted to exactly "
                f"two decimal places; got {result.stdout!r}"
            )
            expected = f"{expected_power(sequence):.2f}"
            assert result.stdout.strip() == expected, (
                f"Analyzer returned {result.stdout.strip()!r}; expected {expected!r}"
            )
        finally:
            os.unlink(fasta_path)


def test_spectral_output():
    """Execute the pipeline and test its output against the computed DFT power."""
    fasta_path = PROTEIN
    assert os.path.isfile(fasta_path), f"Missing FASTA file at {fasta_path}"

    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run([RUN_PIPELINE], text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, f"Pipeline failed: {result.stderr}"

    with open(fasta_path, "r") as f:
        lines = f.readlines()

    seq = "".join(line.strip() for line in lines if not line.startswith(">"))
    expected_P = expected_power(seq)

    output_path = OUTPUT
    assert os.path.isfile(output_path), f"Missing output file at {output_path}"

    with open(output_path, "r") as f:
        content = f.read().strip()

    try:
        actual_P = float(content)
    except ValueError:
        pytest.fail(
            f"Output file {output_path} does not contain a valid float. Found: '{content}'"
        )

    assert math.isclose(actual_P, expected_P, abs_tol=0.02), (
        f"Computed power {actual_P} in {output_path} does not match expected {expected_P:.2f}"
    )


def test_pipeline_invokes_analyzer_with_required_fasta_and_redirects_output():
    """Probe the extracted workflow to ensure it actually orchestrates the analyzer."""
    with open(ANALYZER, "rb") as f:
        saved_analyzer = f.read()
    saved_mode = stat.S_IMODE(os.stat(ANALYZER).st_mode)

    marker = f"/tmp/analyzer_called_{secrets.token_hex(12)}"
    token = f"probe-{secrets.token_hex(16)}"
    probe = (
        "#!/bin/bash\n"
        f"printf '%s\\n' \"$#\" \"$1\" > {shlex.quote(marker)}\n"
        f"printf '%s\\n' {shlex.quote(token)}\n"
    )

    try:
        with open(ANALYZER, "w") as f:
            f.write(probe)
        os.chmod(ANALYZER, 0o755)
        if os.path.exists(OUTPUT):
            os.unlink(OUTPUT)

        result = subprocess.run([RUN_PIPELINE], text=True, capture_output=True, timeout=10)
        assert result.returncode == 0, f"Pipeline failed under invocation probe: {result.stderr}"
        assert os.path.isfile(marker), "Pipeline did not execute /home/user/analyze_spectra.sh"
        with open(marker, "r") as f:
            invocation = f.read().splitlines()
        assert invocation == ["1", PROTEIN], (
            f"Pipeline invoked analyzer with wrong arguments: {invocation!r}"
        )
        assert os.path.isfile(OUTPUT), "Pipeline did not create spectral_output.txt"
        with open(OUTPUT, "r") as f:
            assert f.read().strip() == token, (
                "Pipeline did not redirect analyzer standard output to spectral_output.txt"
            )
    finally:
        with open(ANALYZER, "wb") as f:
            f.write(saved_analyzer)
        os.chmod(ANALYZER, saved_mode)
        if os.path.exists(marker):
            os.unlink(marker)
        subprocess.run([RUN_PIPELINE], text=True, capture_output=True, timeout=10)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
