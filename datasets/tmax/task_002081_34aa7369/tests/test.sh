#!/bin/bash
mkdir -p /logs/verifier

cat <<'CHECK_EOF' > /tmp/run_verifier_checks.sh
#!/bin/bash
set -euo pipefail

project=/home/user/spectral
workdir=$(mktemp -d)
cp /home/user/data.csv "$workdir/original_data.csv"

restore() {
    cp "$workdir/original_data.csv" /home/user/data.csv
    if [ -f "$workdir/original_convergence.log" ]; then
        cp "$workdir/original_convergence.log" /home/user/convergence.log
    fi
    if [ -f "$workdir/original_spectrum.svg" ]; then
        cp "$workdir/original_spectrum.svg" /home/user/spectrum.svg
    fi
    rm -rf "$workdir"
}
trap restore EXIT

# Verify the requested Go project and module exist.
test -d "$project"
test -f "$project/main.go"
test -f "$project/go.mod"
grep -Eq '^module[[:space:]]+spectral[[:space:]]*$' "$project/go.mod"

# Compile the submitted project, then execute the resulting artifact against the
# original dataset. Remove outputs first so stale files cannot satisfy checks.
(
    cd "$project"
    timeout 180s go build -o "$workdir/spectral-program" .
)
test -x "$workdir/spectral-program"
rm -f /home/user/convergence.log /home/user/spectrum.svg
(cd /tmp && timeout 180s "$workdir/spectral-program")

# Preserve the outputs from the required dataset so they can be restored after
# the additional behavioral test.
cp /home/user/convergence.log "$workdir/original_convergence.log"
cp /home/user/spectrum.svg "$workdir/original_spectrum.svg"

cat <<'PYTEST_EOF' > "$workdir/test_final_state.py"
import os
import re
import xml.etree.ElementTree as ET


def test_convergence_log_exists_and_content():
    """Test that convergence.log exists and contains the expected output."""
    log_file = "/home/user/convergence.log"
    assert os.path.isfile(log_file), f"Expected log file {log_file} does not exist."

    with open(log_file, "r") as f:
        content = f.read()

    expected_lines = [
        "N=1024, PeakFreq=15.430 Hz",
        "N=2048, PeakFreq=15.430 Hz",
        "N=4096, PeakFreq=15.381 Hz",
        "N=8192, PeakFreq=15.405 Hz"
    ]

    for expected in expected_lines:
        assert expected in content, (
            f"Expected line '{expected}' not found in {log_file}. "
            f"Actual content:\n{content}"
        )


def test_spectrum_svg_exists_and_format():
    """Test that spectrum.svg exists and is a valid SVG file."""
    svg_file = "/home/user/spectrum.svg"
    assert os.path.isfile(svg_file), f"Expected plot file {svg_file} does not exist."

    with open(svg_file, "r") as f:
        # Read the first few kilobytes to check for the SVG tag
        header = f.read(2048).lower()

    assert "<svg" in header, f"The file {svg_file} does not appear to be a valid SVG file."

    root = ET.parse(svg_file).getroot()
    assert root.tag.split("}")[-1].lower() == "svg"
    plotted = [
        element for element in root.iter()
        if element.tag.split("}")[-1].lower() in {"path", "polyline", "line"}
    ]
    assert plotted, "The SVG does not contain plotted line geometry."


def test_spectral_directory_exists():
    """Test that the spectral directory was created."""
    spectral_dir = "/home/user/spectral"
    assert os.path.isdir(spectral_dir), f"Expected directory {spectral_dir} does not exist."
PYTEST_EOF

python3 -m pytest "$workdir/test_final_state.py" -x --tb=short

# Generate a fresh, non-fixed dataset. Expected peak bins are independently
# derived from the serialized samples rather than embedded in the verifier.
python3 - "$workdir/expected_dynamic.txt" <<'PY_EOF'
import os
import sys
import numpy as np

seed = int.from_bytes(os.urandom(8), "little")
rng = np.random.default_rng(seed)
fs = 200.0
count = 10000
t = np.arange(count, dtype=float) / fs
primary = rng.uniform(11.0, 31.0)
secondary = rng.uniform(38.0, 73.0)
phase1, phase2 = rng.uniform(0.0, 2.0 * np.pi, 2)
y = (5.0 * np.sin(2.0 * np.pi * primary * t + phase1)
     + 0.8 * np.cos(2.0 * np.pi * secondary * t + phase2)
     + rng.normal(0.0, 0.25, count))

with open("/home/user/data.csv", "w") as f:
    for ti, yi in zip(t, y):
        f.write(f"{ti:.12g},{yi:.17g}\n")

# Reload exactly what the Go program receives before deriving the answers.
signal = np.loadtxt("/home/user/data.csv", delimiter=",", usecols=1)
with open(sys.argv[1], "w") as out:
    for n in (1024, 2048, 4096, 8192):
        magnitudes = np.abs(np.fft.rfft(signal[:n]))
        k = int(np.argmax(magnitudes[1:])) + 1
        frequency = k * fs / n
        out.write(f"N={n}, PeakFreq={frequency:.3f} Hz\n")
PY_EOF

rm -f /home/user/convergence.log /home/user/spectrum.svg
(cd /tmp && timeout 180s "$workdir/spectral-program")

python3 - "$workdir/expected_dynamic.txt" <<'PY_EOF'
import os
import re
import sys
import xml.etree.ElementTree as ET

log_file = "/home/user/convergence.log"
svg_file = "/home/user/spectrum.svg"
assert os.path.isfile(log_file), "Program did not create convergence.log for the new input."
assert os.path.isfile(svg_file), "Program did not create spectrum.svg for the new input."

with open(sys.argv[1]) as f:
    expected = [line.rstrip("\n") for line in f]
with open(log_file) as f:
    actual = [line.rstrip("\n") for line in f]

pattern = re.compile(r"^N=(1024|2048|4096|8192), PeakFreq=\d+\.\d{3} Hz$")
assert len(actual) == 4, f"Expected exactly four convergence entries, got: {actual!r}"
assert all(pattern.fullmatch(line) for line in actual), f"Incorrect log format: {actual!r}"
assert actual == expected, f"FFT peak results are incorrect. Expected {expected!r}, got {actual!r}"

with open(svg_file, "r") as f:
    assert "<svg" in f.read(2048).lower(), "Output is not an SVG file."
root = ET.parse(svg_file).getroot()
assert root.tag.split("}")[-1].lower() == "svg"
geometry = [
    element for element in root.iter()
    if element.tag.split("}")[-1].lower() in {"path", "polyline", "line"}
]
assert geometry, "The generated SVG contains no plotted line geometry."
PY_EOF
CHECK_EOF
chmod +x /tmp/run_verifier_checks.sh

if /tmp/run_verifier_checks.sh 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
