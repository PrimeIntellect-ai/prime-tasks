#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import secrets
import subprocess
import tempfile


def run_fitter(csv_path):
    result = subprocess.run(
        ["/home/user/fitter", csv_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, (
        f"fitter exited with status {result.returncode}: {result.stderr}"
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def test_clean_spectra_csv():
    """Test that clean_spectra.csv exists and contains the correctly filtered data."""
    csv_path = "/home/user/clean_spectra.csv"
    assert os.path.exists(csv_path), f"File {csv_path} is missing."
    assert os.path.isfile(csv_path), f"{csv_path} is not a file."

    expected_lines = [
        "498.0,1.2",
        "499.0,2.1",
        "499.5,5.4",
        "500.0,10.2",
        "500.5,8.1",
        "501.0,3.2",
        "501.5,1.5",
        "502.5,1.1"
    ]

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {csv_path}, but found {len(lines)}."

    for expected, actual in zip(expected_lines, lines):
        assert expected == actual, f"Expected line '{expected}', but found '{actual}'."


def test_fitter_executable():
    """Test that the Go program was compiled to /home/user/fitter and is executable."""
    exe_path = "/home/user/fitter"
    assert os.path.exists(exe_path), f"Executable {exe_path} is missing."
    assert os.path.isfile(exe_path), f"{exe_path} is not a file."

    st = os.stat(exe_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {exe_path} is not executable."

    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not an ELF executable."

    result = subprocess.run(
        ["go", "version", "-m", exe_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, f"{exe_path} is not recognized as a Go executable: {result.stderr}"
    assert "go1" in result.stdout, f"Go build information is missing from {exe_path}."


def test_final_parameters_log():
    """Test that final_parameters.log exists and contains the correct MCMC estimates."""
    log_path = "/home/user/final_parameters.log"
    assert os.path.exists(log_path), f"File {log_path} is missing."
    assert os.path.isfile(log_path), f"{log_path} is not a file."

    expected_content = {
        "Amplitude": "16.40",
        "Center": "500.25",
        "Width": "1.25",
        "Background": "1.05"
    }

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 4, f"Expected exactly 4 lines in {log_path}, but found {len(lines)}."

    parsed_params = {}
    for line in lines:
        parts = line.split(":")
        assert len(parts) == 2, f"Line '{line}' does not match the format 'Parameter: <value>'."
        key = parts[0].strip()
        val = parts[1].strip()
        parsed_params[key] = val

    for key, expected_val in expected_content.items():
        assert key in parsed_params, f"Missing parameter '{key}' in {log_path}."
        assert parsed_params[key] == expected_val, f"Expected {key} to be {expected_val}, but found {parsed_params[key]}."

    output = run_fitter("/home/user/clean_spectra.csv")
    assert output == ["MCMC chain finished (10000 iterations)"] + lines, (
        "final_parameters.log does not match the output of the compiled fitter "
        "when run on clean_spectra.csv."
    )


def test_fitter_on_derived_input():
    """Execute the submitted Go binary on unpredictable data and derive the answer."""
    base_w = 300 + secrets.randbelow(400)
    wavelengths = [base_w, base_w + 1, base_w + 4, base_w + 8]
    intensities = [1 + secrets.randbelow(20) for _ in range(4)]

    fd, csv_path = tempfile.mkstemp(prefix="fitter_check_", suffix=".csv")
    try:
        with os.fdopen(fd, "w") as f:
            for wavelength, intensity in zip(wavelengths, intensities):
                f.write(f"{wavelength},{intensity}\n")

        expected = [
            "MCMC chain finished (10000 iterations)",
            f"Amplitude: {sum(intensities) * 0.5:.2f}",
            f"Center: {sum(wavelengths) / len(wavelengths):.2f}",
            "Width: 1.25",
            "Background: 1.05",
        ]
        assert run_fitter(csv_path) == expected, (
            "The submitted fitter did not compute the expected parameters for "
            "a verifier-generated input dataset."
        )
    finally:
        os.unlink(csv_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
