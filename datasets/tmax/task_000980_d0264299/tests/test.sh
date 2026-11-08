#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import struct
import subprocess
import time
import zlib

ANALYZE = "/home/user/analyze.go"
INTEGRATOR = "/app/vendor/github.com/phys-sim/wavegraph/integrator.go"
BASELINE = "/home/user/baseline.json"
KL_PATH = "/home/user/kl_divergence.txt"
PLOT_PATH = "/home/user/spectrum_plot.png"


def strip_go_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def run_analyzer():
    for path in (KL_PATH, PLOT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    start = time.time()
    result = subprocess.run(
        ["go", "run", ANALYZE],
        capture_output=True,
        text=True,
        cwd="/home/user",
        timeout=8,
    )
    elapsed = time.time() - start
    assert result.returncode == 0, f"analyze.go failed to run. Stderr: {result.stderr}"
    assert elapsed < 2.0, (
        f"Execution time too slow: {elapsed:.2f}s (Threshold: < 2.0s). "
        "The vendor package might not be fixed."
    )

    assert os.path.isfile(KL_PATH), f"KL divergence output missing: {KL_PATH}"
    content = open(KL_PATH, "r", encoding="utf-8").read().strip()
    try:
        value = float(content)
    except ValueError:
        raise AssertionError(f"KL divergence output is not a valid float: {content!r}")
    assert math.isfinite(value), f"KL divergence must be finite, got {value}"
    assert value >= 0.0, f"KL divergence cannot be negative, got {value}"

    assert os.path.isfile(PLOT_PATH), f"Spectrum plot is missing: {PLOT_PATH}"
    assert os.path.getsize(PLOT_PATH) > 0, "Spectrum plot file is empty."
    plot = open(PLOT_PATH, "rb").read()
    validate_png(plot)
    return value, plot


def validate_png(data):
    assert data.startswith(b"\x89PNG\r\n\x1a\n"), "spectrum_plot.png is not a PNG file"
    pos = 8
    chunks = []
    idat = bytearray()
    width = height = None
    saw_iend = False

    while pos + 12 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        end = pos + 12 + length
        assert end <= len(data), "PNG contains a truncated chunk"
        payload = data[pos + 8:pos + 8 + length]
        stored_crc = struct.unpack(">I", data[pos + 8 + length:end])[0]
        actual_crc = zlib.crc32(kind)
        actual_crc = zlib.crc32(payload, actual_crc) & 0xffffffff
        assert stored_crc == actual_crc, f"PNG chunk {kind!r} has an invalid CRC"
        chunks.append(kind)

        if kind == b"IHDR":
            assert length == 13, "Invalid PNG IHDR"
            width, height = struct.unpack(">II", payload[:8])
            assert width >= 10 and height >= 10, "Plot dimensions are too small to contain the spectra"
        elif kind == b"IDAT":
            idat.extend(payload)
        elif kind == b"IEND":
            saw_iend = True
            break
        pos = end

    assert chunks and chunks[0] == b"IHDR", "PNG does not begin with IHDR"
    assert idat, "PNG has no image data"
    assert saw_iend, "PNG has no IEND chunk"
    try:
        raw = zlib.decompress(bytes(idat))
    except zlib.error as exc:
        raise AssertionError(f"PNG image data is invalid: {exc}")
    assert len(raw) > height, "PNG contains insufficient pixel data"
    assert len(set(raw)) >= 3, "PNG image is visually empty or uniform"


def expected_kl(signal, baseline):
    m = len(baseline)
    assert m > 0 and len(signal) > 0
    assert all(math.isfinite(q) and q > 0.0 for q in baseline)
    assert math.isclose(sum(baseline), 1.0, rel_tol=1e-9, abs_tol=1e-9)

    amplitudes = []
    n = len(signal)
    for k in range(m):
        real = 0.0
        imag = 0.0
        for j, sample in enumerate(signal):
            angle = -2.0 * math.pi * k * j / n
            real += sample * math.cos(angle)
            imag += sample * math.sin(angle)
        amplitudes.append(math.hypot(real, imag))

    total = sum(amplitudes)
    assert total > 0.0
    spectrum = [a / total for a in amplitudes]
    return sum(p * math.log(p / q) for p, q in zip(spectrum, baseline) if p > 0.0)


def get_package_signal():
    probe = r'''package main
import (
    "encoding/json"
    "os"
    "github.com/phys-sim/wavegraph"
)
func main() {
    signal := wavegraph.NewGraphSimulation(100).Run(10.0)
    if err := json.NewEncoder(os.Stdout).Encode(signal); err != nil { panic(err) }
}
'''
    open("/tmp/wave_probe.go", "w", encoding="utf-8").write(probe)
    start = time.time()
    result = subprocess.run(
        ["go", "run", "/tmp/wave_probe.go"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=8,
    )
    elapsed = time.time() - start
    assert result.returncode == 0, f"Vendored wavegraph package failed: {result.stderr}"
    assert elapsed < 2.0, f"wavegraph.Run is still too slow: {elapsed:.2f}s"

    import json
    signal = json.loads(result.stdout)
    assert isinstance(signal, list) and len(signal) >= 90, "Run(10.0) returned an unexpected signal"
    assert all(isinstance(x, (int, float)) and math.isfinite(x) for x in signal)
    return [float(x) for x in signal]


def test_complete_analysis():
    assert os.path.isfile(ANALYZE), f"analyze.go is missing: {ANALYZE}"
    assert os.path.isfile(INTEGRATOR), f"integrator.go is missing: {INTEGRATOR}"

    integrator_source = strip_go_comments(open(INTEGRATOR, "r", encoding="utf-8").read())
    assert re.search(
        r"\bdt\s*=\s*math\s*\.\s*Min\s*\(\s*dt\s*\*\s*1\.5\s*,\s*maxDt\s*\)",
        integrator_source,
    ), "The adaptive dt update in integrator.go has not been restored"

    analyze_source = strip_go_comments(open(ANALYZE, "r", encoding="utf-8").read())
    assert re.search(r"NewGraphSimulation\s*\(\s*100\s*\)", analyze_source), (
        "analyze.go must initialize wavegraph.NewGraphSimulation(100)"
    )
    assert re.search(r"\.\s*Run\s*\(\s*10(?:\.0*)?\s*\)", analyze_source), (
        "analyze.go must call Run(10.0)"
    )

    signal = get_package_signal()
    original_baseline = open(BASELINE, "rb").read()
    try:
        import json
        baseline = json.loads(original_baseline.decode("utf-8"))
        actual1, plot1 = run_analyzer()
        wanted1 = expected_kl(signal, baseline)
        assert math.isclose(actual1, wanted1, rel_tol=1e-6, abs_tol=1e-8), (
            f"Incorrect KL divergence: got {actual1}, expected {wanted1}"
        )

        values = [secrets.randbelow(9000) + 1000 for _ in range(len(baseline))]
        total = float(sum(values))
        alternate = [v / total for v in values]
        open(BASELINE, "w", encoding="utf-8").write(json.dumps(alternate))

        actual2, plot2 = run_analyzer()
        wanted2 = expected_kl(signal, alternate)
        assert math.isclose(actual2, wanted2, rel_tol=1e-6, abs_tol=1e-8), (
            f"KL divergence does not match the runtime baseline: got {actual2}, expected {wanted2}"
        )
        assert plot1 != plot2, "The plot did not change when the baseline spectrum changed"
    finally:
        open(BASELINE, "wb").write(original_baseline)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
