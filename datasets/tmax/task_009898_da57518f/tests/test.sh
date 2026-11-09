#!/bin/bash
set -u
mkdir -p /logs/verifier

fail() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

PROJECT=/home/user/gc_analyzer
FASTA=/home/user/data/genome.fasta
OUTPUT=/home/user/output
ORIGINAL_FASTA=/tmp/verifier_original.fasta
VARIANT_FASTA=/tmp/verifier_variant.fasta
ORACLE_SRC="$PROJECT/src/bin/__verifier_oracle.rs"

cleanup() {
    if [ -f "$ORIGINAL_FASTA" ]; then
        cp "$ORIGINAL_FASTA" "$FASTA" 2>/dev/null || true
    fi
    rm -f "$ORACLE_SRC" 2>/dev/null || true
}
trap cleanup EXIT

[ -f "$PROJECT/src/main.rs" ] || fail
[ -f "$PROJECT/Cargo.toml" ] || fail
[ -f "$FASTA" ] || fail
cp "$FASTA" "$ORIGINAL_FASTA" || fail

cd "$PROJECT" || fail
timeout 300 cargo build --release --quiet || fail
[ -x "$PROJECT/target/release/gc_analyzer" ] || fail

# Run the submitted artifact on the required input. Remove outputs first so stale
# or pre-fabricated files cannot satisfy the checks.
rm -f "$OUTPUT/results.json" "$OUTPUT/gc_plot.svg"
timeout 180 "$PROJECT/target/release/gc_analyzer" || fail
[ -f "$OUTPUT/results.json" ] || fail
[ -f "$OUTPUT/gc_plot.svg" ] || fail
cp "$OUTPUT/results.json" /tmp/results_original.json || fail
cp "$OUTPUT/gc_plot.svg" /tmp/plot_original.svg || fail

# Exercise the same binary on a verifier-created data set to prevent hard-coded
# statistics or a hard-coded plot from passing.
python3 - <<'PY' || exit 20
path = "/tmp/verifier_variant.fasta"
seq = []
for i in range(137):
    gc = (i * 37 + i * i * 3 + 11) % 101
    seq.append("G" * gc + "A" * (100 - gc))
s = "".join(seq)
with open(path, "w") as f:
    f.write(">verification_variant\n")
    for i in range(0, len(s), 80):
        f.write(s[i:i+80] + "\n")
PY
[ $? -eq 0 ] || fail
cp "$VARIANT_FASTA" "$FASTA" || fail
rm -f "$OUTPUT/results.json" "$OUTPUT/gc_plot.svg"
timeout 180 "$PROJECT/target/release/gc_analyzer" || fail
[ -f "$OUTPUT/results.json" ] || fail
[ -f "$OUTPUT/gc_plot.svg" ] || fail
cp "$OUTPUT/results.json" /tmp/results_variant.json || fail
cp "$OUTPUT/gc_plot.svg" /tmp/plot_variant.svg || fail

# Restore the requested final outputs and input.
cp "$ORIGINAL_FASTA" "$FASTA" || fail
cp /tmp/results_original.json "$OUTPUT/results.json" || fail
cp /tmp/plot_original.svg "$OUTPUT/gc_plot.svg" || fail

# Build an independent bootstrap oracle using the submission's rand/rand_chacha
# dependency versions. This reproduces ChaCha8Rng seed 42 and exactly 10,000
# resamples, rather than merely checking that the submitted interval looks sane.
mkdir -p "$PROJECT/src/bin" || fail
cat > "$ORACLE_SRC" <<'RUST'
use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;
use std::env;
use std::fs;

fn main() {
    let path = env::args().nth(1).expect("fasta path");
    let text = fs::read_to_string(path).unwrap();
    let seq: String = text.lines()
        .filter(|line| !line.starts_with('>'))
        .map(str::trim)
        .collect();

    let ratios: Vec<f64> = seq.as_bytes().chunks(100)
        .filter(|chunk| chunk.len() == 100)
        .map(|chunk| {
            chunk.iter().filter(|&&b| b == b'G' || b == b'C').count() as f64 / 100.0
        })
        .collect();
    assert!(!ratios.is_empty());

    let n = ratios.len();
    let mut rng = ChaCha8Rng::seed_from_u64(42);
    let mut means = Vec::with_capacity(10_000);
    for _ in 0..10_000 {
        let mut sum = 0.0f64;
        for _ in 0..n {
            let index = rng.gen_range(0..n);
            sum += ratios[index];
        }
        means.push(sum / n as f64);
    }
    means.sort_by(|a, b| a.partial_cmp(b).unwrap());

    // Accept the usual nearest-rank/direct-index and linearly interpolated
    // percentile conventions; all candidates come from this exact RNG stream.
    let lower_interp = means[249] + 0.975 * (means[250] - means[249]);
    let upper_interp = means[9749] + 0.025 * (means[9750] - means[9749]);
    println!(
        "{{\"lower\":[{:.17},{:.17},{:.17}],\"upper\":[{:.17},{:.17},{:.17}]}}",
        means[249], means[250], lower_interp,
        means[9749], means[9750], upper_interp
    );
}
RUST

timeout 300 cargo run --release --quiet --bin __verifier_oracle -- "$ORIGINAL_FASTA" > /tmp/oracle_original.json || fail
timeout 300 cargo run --release --quiet --bin __verifier_oracle -- "$VARIANT_FASTA" > /tmp/oracle_variant.json || fail
rm -f "$ORACLE_SRC"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import xml.etree.ElementTree as ET
import pytest

EXPECTED_KEYS = {
    "total_gc_integral",
    "regression_slope",
    "regression_intercept",
    "bootstrap_ci_lower",
    "bootstrap_ci_upper",
}


def read_ratios(fasta_path):
    seq = []
    with open(fasta_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line.startswith(">"):
                seq.append(line)
    full_seq = "".join(seq)
    ratios = []
    for i in range(0, len(full_seq), 100):
        chunk = full_seq[i:i + 100]
        if len(chunk) == 100:
            ratios.append((chunk.count("G") + chunk.count("C")) / 100)
    assert ratios
    return ratios


def load_results(path):
    assert os.path.isfile(path), f"Results file missing: {path}"
    try:
        with open(path, "r") as f:
            results = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {path} is not valid JSON")
    for key in EXPECTED_KEYS:
        assert key in results, f"Missing key '{key}' in {path}"
        assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool), \
            f"Value for '{key}' must be a number"
        assert math.isfinite(results[key]), f"Value for '{key}' must be finite"
    return results


def check_numeric_results(results_path, fasta_path, oracle_path):
    results = load_results(results_path)
    ratios = read_ratios(fasta_path)
    expected_sum = sum(ratios)

    # Original total-integral assertion.
    assert math.isclose(results["total_gc_integral"], expected_sum, rel_tol=1e-9), \
        f"Expected total_gc_integral ~ {expected_sum}, got {results['total_gc_integral']}"

    # Original regression assertions.
    n = len(ratios)
    x = list(range(n))
    mean_x = sum(x) / n
    mean_y = expected_sum / n
    numerator = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, ratios))
    denominator = sum((xi - mean_x) ** 2 for xi in x)
    expected_slope = numerator / denominator
    expected_intercept = mean_y - expected_slope * mean_x
    assert math.isclose(results["regression_slope"], expected_slope, rel_tol=1e-5, abs_tol=1e-7), \
        f"Expected regression_slope ~ {expected_slope}, got {results['regression_slope']}"
    assert math.isclose(results["regression_intercept"], expected_intercept, rel_tol=1e-5, abs_tol=1e-7), \
        f"Expected regression_intercept ~ {expected_intercept}, got {results['regression_intercept']}"

    # Preserve the original CI sanity checks.
    lower = results["bootstrap_ci_lower"]
    upper = results["bootstrap_ci_upper"]
    assert lower < mean_y < upper, \
        f"Confidence interval [{lower}, {upper}] does not contain the sample mean {mean_y}"
    assert upper - lower > 0, "Confidence interval has zero or negative width"
    assert upper - lower < 0.05, "Confidence interval is unusually wide"

    # Exact deterministic bootstrap stream, allowing standard percentile-index
    # conventions but no arbitrary interval.
    with open(oracle_path) as f:
        oracle = json.load(f)
    assert any(math.isclose(lower, value, rel_tol=0.0, abs_tol=5e-12)
               for value in oracle["lower"]), \
        f"bootstrap_ci_lower {lower} was not produced by the required bootstrap"
    assert any(math.isclose(upper, value, rel_tol=0.0, abs_tol=5e-12)
               for value in oracle["upper"]), \
        f"bootstrap_ci_upper {upper} was not produced by the required bootstrap"


def extract_polyline_points(root):
    candidates = []
    for elem in root.iter():
        tag = elem.tag.rsplit("}", 1)[-1].lower()
        if tag == "polyline":
            nums = [float(v) for v in re.findall(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", elem.attrib.get("points", ""))]
            if len(nums) >= 4 and len(nums) % 2 == 0:
                candidates.append(list(zip(nums[0::2], nums[1::2])))
        elif tag == "path":
            d = elem.attrib.get("d", "")
            pairs = re.findall(r"[ML]\s*([-+]?\d+(?:\.\d+)?)\s*[, ]\s*([-+]?\d+(?:\.\d+)?)", d, re.I)
            if len(pairs) >= 2:
                candidates.append([(float(x), float(y)) for x, y in pairs])
    return candidates


def check_svg(svg_path, fasta_path):
    # Preserve the original existence and SVG marker checks.
    assert os.path.isfile(svg_path), f"Plot file missing: {svg_path}"
    with open(svg_path, "r") as f:
        content = f.read()
    assert "<svg" in content.lower(), f"File {svg_path} does not appear to be a valid SVG"

    try:
        root = ET.fromstring(content)
    except ET.ParseError as exc:
        pytest.fail(f"Invalid SVG XML in {svg_path}: {exc}")
    assert root.tag.rsplit("}", 1)[-1].lower() == "svg"

    ratios = read_ratios(fasta_path)
    candidates = extract_polyline_points(root)
    needed = max(20, int(len(ratios) * 0.8))

    # Locate a long monotone-x line whose rendered y coordinates track the GC
    # ratios (SVG y increases downward, hence the expected negative correlation).
    for points in candidates:
        if len(points) < needed:
            continue
        points = points[:len(ratios)]
        if len(points) < needed:
            continue
        xs = [p[0] for p in points]
        ys = [p[1] for p in points]
        if not all(xs[i] <= xs[i + 1] for i in range(len(xs) - 1)):
            continue
        data = ratios[:len(ys)]
        my = sum(ys) / len(ys)
        md = sum(data) / len(data)
        cov = sum((a - my) * (b - md) for a, b in zip(ys, data))
        vy = sum((a - my) ** 2 for a in ys)
        vd = sum((b - md) ** 2 for b in data)
        if vy > 0 and vd > 0:
            corr = cov / math.sqrt(vy * vd)
            if corr < -0.98:
                return
    pytest.fail(f"{svg_path} does not contain a GC-ratio line plot")


def test_svg_plot_exists():
    check_svg("/home/user/output/gc_plot.svg", "/tmp/verifier_original.fasta")


def test_results_json():
    check_numeric_results(
        "/home/user/output/results.json",
        "/tmp/verifier_original.fasta",
        "/tmp/oracle_original.json",
    )


def test_verifier_generated_input():
    check_numeric_results(
        "/tmp/results_variant.json",
        "/tmp/verifier_variant.fasta",
        "/tmp/oracle_variant.json",
    )
    check_svg("/tmp/plot_variant.svg", "/tmp/verifier_variant.fasta")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
