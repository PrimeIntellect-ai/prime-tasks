#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib
import importlib.machinery
import json
import math
import os
import secrets
import shutil
import subprocess
import sys
from decimal import Decimal, localcontext

import pytest

BASE_DIR = "/home/user/pipeline"


def stable_stats(values):
    """Reference population statistics computed from the exact input floats."""
    with localcontext() as ctx:
        ctx.prec = 80
        vals = [Decimal.from_float(float(v)) for v in values]
        mean = sum(vals) / Decimal(len(vals))
        variance = sum((v - mean) ** 2 for v in vals) / Decimal(len(vals))
    return float(mean), float(variance)


@pytest.fixture(scope="session")
def built_extension():
    """Force a clean in-place build so a pre-created or unrelated .so cannot pass."""
    setup_py = os.path.join(BASE_DIR, "setup.py")
    assert os.path.isfile(setup_py), f"File missing: {setup_py}"

    for path in glob.glob(os.path.join(BASE_DIR, "fast_agg*.so")):
        os.remove(path)
    shutil.rmtree(os.path.join(BASE_DIR, "build"), ignore_errors=True)

    proc = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace"],
        cwd=BASE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert proc.returncode == 0, "Clean extension build failed:\n" + proc.stdout

    so_files = glob.glob(os.path.join(BASE_DIR, "fast_agg*.so"))
    assert len(so_files) > 0, (
        "Cython extension 'fast_agg' shared object (.so) file was not found in "
        "/home/user/pipeline/. Did you run setup.py build_ext --inplace?"
    )
    for path in so_files:
        assert os.path.isfile(path) and not os.path.islink(path), f"Invalid extension artifact: {path}"
        with open(path, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"Extension artifact is not an ELF shared object: {path}"

    sys.path.insert(0, BASE_DIR)
    importlib.invalidate_caches()
    sys.modules.pop("fast_agg", None)
    module = importlib.import_module("fast_agg")
    assert isinstance(module.__loader__, importlib.machinery.ExtensionFileLoader), (
        "fast_agg was not imported as a compiled extension module"
    )
    assert os.path.realpath(module.__file__) in {os.path.realpath(p) for p in so_files}
    return module


def test_cython_extension_built(built_extension):
    """Verify the cleanly built extension implements the required aggregator."""
    module = built_extension
    for mean, variance in [(12.5, 4.0), (1.0e8, 2.5e-10), (-7.25, 3.5)]:
        actual = module.aggregate_metric(mean, variance)
        expected = mean / math.sqrt(variance)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12)

    with pytest.raises(ZeroDivisionError):
        module.aggregate_metric(1.0, 0.0)
    with pytest.raises(ZeroDivisionError):
        module.aggregate_metric(1.0, -1.0)


def test_faulty_sensor_identified():
    """Verify that the faulty sensor was identified from the log timeline."""
    faulty_sensor_file = os.path.join(BASE_DIR, "faulty_sensor.txt")
    assert os.path.exists(faulty_sensor_file), f"File missing: {faulty_sensor_file}"
    with open(faulty_sensor_file, "r") as f:
        content = f.read().strip()
    assert content == "SEN-8842", (
        f"Incorrect faulty sensor ID. Expected 'SEN-8842', but got '{content}'."
    )


def test_processor_uses_stable_variance():
    """Exercise processor.py on independently generated cancellation-prone data."""
    processor_path = os.path.join(BASE_DIR, "processor.py")
    assert os.path.isfile(processor_path), f"File missing: {processor_path}"

    spec = importlib.util.spec_from_file_location("submitted_processor", processor_path)
    processor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(processor)
    assert callable(getattr(processor, "compute_stats", None))
    assert processor.compute_stats([]) == (0.0, 0.0)

    rng = secrets.SystemRandom()
    cases = [
        [100000000.00001, 100000000.00002, 100000000.00001, 100000000.00003]
    ]
    for _ in range(5):
        base = rng.choice([1.0e8, 1.0e10, 1.0e12])
        step = math.ulp(base)
        offsets = [rng.randint(-24, 24) for _ in range(rng.randint(7, 19))]
        if len(set(offsets)) == 1:
            offsets[-1] += 1
        cases.append([base + offset * step for offset in offsets])

    for values in cases:
        expected_mean, expected_variance = stable_stats(values)
        result = processor.compute_stats(values)
        assert isinstance(result, tuple) and len(result) == 2
        mean, variance = result
        assert isinstance(mean, (int, float)) and not isinstance(mean, bool)
        assert isinstance(variance, (int, float)) and not isinstance(variance, bool)
        assert math.isfinite(mean) and math.isfinite(variance)
        assert variance > 0.0, "Cancellation-prone input produced non-positive variance"
        assert math.isclose(mean, expected_mean, rel_tol=2e-14, abs_tol=8 * math.ulp(expected_mean))
        assert math.isclose(variance, expected_variance, rel_tol=0.08, abs_tol=1e-30), (
            f"Unstable or incorrect population variance: got {variance}, expected {expected_variance}"
        )


def test_pipeline_output_generated(built_extension):
    """Run the actual wrapper and validate its freshly generated metrics."""
    output_file = os.path.join(BASE_DIR, "output", "final_metrics.json")
    if os.path.lexists(output_file):
        os.remove(output_file)

    proc = subprocess.run(
        [sys.executable, "run_pipeline.py"],
        cwd=BASE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert proc.returncode == 0, "Pipeline execution failed:\n" + proc.stdout
    assert os.path.exists(output_file), (
        f"Output file missing: {output_file}. The pipeline may have crashed or not been run."
    )

    with open(output_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_file} does not contain valid JSON.")

    assert "SEN-1001" in data, "Key 'SEN-1001' is missing from the final JSON output."
    assert "SEN-8842" in data, (
        "Key 'SEN-8842' is missing from the final JSON output. The precision bug might still be present."
    )

    val_8842 = data["SEN-8842"]
    assert isinstance(val_8842, (float, int)), (
        f"Metric for SEN-8842 should be a number, got {type(val_8842)}"
    )
    assert val_8842 > 0, (
        "Metric for SEN-8842 is invalid. The variance computation may still be failing or returning zero."
    )

    source_data = {
        "SEN-1001": [10.1, 10.2, 10.15, 10.25],
        "SEN-8842": [100000000.00001, 100000000.00002, 100000000.00001, 100000000.00003],
    }
    assert set(data) == set(source_data), "Pipeline output contains unexpected or missing sensors"
    for sensor, values in source_data.items():
        mean, variance = stable_stats(values)
        expected = mean / math.sqrt(variance)
        actual = data[sensor]
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
        assert math.isfinite(actual) and actual > 0
        assert math.isclose(actual, expected, rel_tol=0.08, abs_tol=1e-12), (
            f"Incorrect metric for {sensor}: got {actual}, expected approximately {expected}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
