#!/bin/bash
set -e
mkdir -p /logs/verifier

# Permit the agent's analysis script to invoke Open MPI while the verifier runs as root.
export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
export OMPI_MCA_rmaps_base_oversubscribe=1
export MPLBACKEND=Agg

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import collections
import contextlib
import importlib
import json
import math
import os
import random
import re
import shutil
import stat
import subprocess
import textwrap

import numpy as np


def test_dependencies_installed():
    """Test that required Python packages are installed."""
    missing = []
    for pkg in ['mpi4py', 'scipy', 'matplotlib']:
        try:
            importlib.import_module(pkg)
        except ImportError:
            missing.append(pkg)
    assert not missing, f"Missing required Python packages: {', '.join(missing)}"


def test_analyze_metric_and_visualization():
    """Execute analyze.py, verify every required simulation, its metric, and its plot."""
    from scipy.stats import wasserstein_distance
    import matplotlib.image as mpimg

    analyze_path = "/home/user/analyze.py"
    reduce_path = "/home/user/reduce_sim.py"
    metric_path = "/home/user/metric.txt"
    img_path = "/home/user/visualization.png"
    log_path = "/tmp/reduce_sim_calls.jsonl"
    saved_path = "/tmp/reduce_sim_original.py"

    assert os.path.isfile(analyze_path), f"{analyze_path} does not exist."
    assert os.path.isfile(reduce_path), f"{reduce_path} does not exist."

    # Instrument the supplied simulation without changing its behavior. This records
    # the process count, seed, and exact value that analyze.py actually received.
    shutil.copy2(reduce_path, saved_path)
    original_mode = stat.S_IMODE(os.stat(reduce_path).st_mode)
    wrapper = textwrap.dedent(f'''\
        import contextlib
        import fcntl
        import io
        import json
        import runpy
        import sys
        from mpi4py import MPI

        ORIGINAL = {saved_path!r}
        LOG = {log_path!r}
        comm = MPI.COMM_WORLD
        capture = io.StringIO()
        with contextlib.redirect_stdout(capture):
            runpy.run_path(ORIGINAL, run_name="__main__")
        output = capture.getvalue()
        if comm.Get_rank() == 0:
            record = {{"size": comm.Get_size(), "seed": int(sys.argv[1]) if len(sys.argv) > 1 else 42,
                      "output": output.strip()}}
            with open(LOG, "a", encoding="utf-8") as fh:
                fcntl.flock(fh.fileno(), fcntl.LOCK_EX)
                fh.write(json.dumps(record) + "\\n")
                fh.flush()
                fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
            sys.stdout.write(output)
    ''')

    for path in (metric_path, img_path, log_path):
        with contextlib.suppress(FileNotFoundError):
            os.remove(path)

    try:
        with open(reduce_path, "w", encoding="utf-8") as fh:
            fh.write(wrapper)
        os.chmod(reduce_path, original_mode)

        result = subprocess.run(
            ["python3", analyze_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=1800,
            env=os.environ.copy(),
        )
        assert result.returncode == 0, (
            f"Running analyze.py failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    finally:
        shutil.copy2(saved_path, reduce_path)
        os.chmod(reduce_path, original_mode)

    assert os.path.isfile(log_path), "analyze.py did not run /home/user/reduce_sim.py."
    records = []
    with open(log_path, encoding="utf-8") as fh:
        for line in fh:
            if line.strip():
                records.append(json.loads(line))

    grouped = collections.defaultdict(list)
    for record in records:
        grouped[(record["seed"], record["size"])].append(record["output"])

    required = {(seed, procs) for seed in range(1, 51) for procs in (1, 4)}
    missing = sorted(required - set(grouped))
    assert not missing, f"analyze.py omitted required seed/process runs: {missing[:10]}"
    duplicates = sorted(key for key in required if len(grouped[key]) != 1)
    assert not duplicates, f"Each required simulation must be run exactly once; bad cases: {duplicates[:10]}"

    one_results = []
    four_results = []
    for seed in range(1, 51):
        try:
            one_results.append(float(grouped[(seed, 1)][0]))
            four_results.append(float(grouped[(seed, 4)][0]))
        except ValueError as exc:
            raise AssertionError(f"Simulation output for seed {seed} was not numeric") from exc

    expected_metric = float(wasserstein_distance(one_results, four_results))

    # Retain the original existence/float/nonnegative assertions, then compare the
    # file to the distance derived from the simulations observed above.
    assert os.path.isfile(metric_path), f"{metric_path} does not exist."
    with open(metric_path, "r", encoding="utf-8") as fh:
        content = fh.read().strip()
    number_pattern = r"[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][+-]?\d+)?"
    assert re.fullmatch(number_pattern, content), (
        f"{metric_path} must contain only one finite floating-point number. Content: {content!r}"
    )
    value = float(content)
    assert value >= 0, "Wasserstein distance should be non-negative."
    assert math.isfinite(value), "Wasserstein distance must be finite."
    assert math.isclose(value, expected_metric, rel_tol=1e-9, abs_tol=1e-15), (
        f"Incorrect Wasserstein distance: wrote {value}, expected {expected_metric}"
    )

    # Retain the PNG-header assertion and additionally decode and inspect the image.
    assert os.path.isfile(img_path), f"{img_path} does not exist."
    with open(img_path, "rb") as fh:
        header = fh.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', f"{img_path} is not a valid PNG file."
    try:
        image = np.asarray(mpimg.imread(img_path))
    except Exception as exc:
        raise AssertionError(f"{img_path} cannot be decoded as a PNG: {exc}") from exc
    assert image.ndim in (2, 3), "Visualization has an invalid pixel array."
    assert image.shape[0] >= 200 and image.shape[1] >= 300, "Visualization is implausibly small."
    assert np.isfinite(image).all(), "Visualization contains invalid pixel values."
    assert float(np.std(image)) > 0.01, "Visualization is blank or nearly uniform."
    sample = image[::max(1, image.shape[0] // 100), ::max(1, image.shape[1] // 100)]
    assert len(np.unique(sample.reshape(-1, sample.shape[-1] if sample.ndim == 3 else 1), axis=0)) > 16, (
        "Visualization does not contain enough graphical content."
    )


def test_fix_sim_reproducibility_and_correctness():
    """Exercise unpredictable seeds with 1, 2, 4, and 8 ranks and verify the sum."""
    fix_sim_path = "/home/user/fix_sim.py"
    assert os.path.isfile(fix_sim_path), f"{fix_sim_path} does not exist."

    with open(fix_sim_path, "r", encoding="utf-8") as fh:
        source = fh.read()
    try:
        tree = ast.parse(source, filename=fix_sim_path)
    except SyntaxError as exc:
        raise AssertionError(f"fix_sim.py is not valid Python: {exc}") from exc
    imports_mpi4py = any(
        (isinstance(node, ast.ImportFrom) and node.module == "mpi4py") or
        (isinstance(node, ast.Import) and any(alias.name.startswith("mpi4py") for alias in node.names))
        for node in ast.walk(tree)
    )
    assert imports_mpi4py, "fix_sim.py must use mpi4py."

    chooser = random.SystemRandom()
    seeds = chooser.sample(range(1000, 2_000_000_000), 2)

    for seed in seeds:
        # Independently derive an accurate value for the same global input array.
        rng = np.random.RandomState(seed)
        data = rng.randn(5_000_000).astype(np.float64) * 1e6
        data[::2] *= 1e-12
        reference = math.fsum(map(float, data))
        del data

        outputs = {}
        for procs in (1, 2, 4, 8):
            cmd = [
                "mpirun", "--allow-run-as-root", "--oversubscribe", "-n", str(procs),
                "python3", fix_sim_path, str(seed),
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300, env=os.environ.copy())
            assert result.returncode == 0, (
                f"Running fix_sim.py with seed {seed} and {procs} processes failed:\n{result.stderr}"
            )
            output = result.stdout.strip()
            assert output, f"Output from fix_sim.py ({procs} processes) is empty."
            assert len(output.splitlines()) == 1, "fix_sim.py must print only the root's final result."
            try:
                numeric = float(output)
            except ValueError as exc:
                raise AssertionError(f"fix_sim.py produced nonnumeric output: {output!r}") from exc
            assert math.isfinite(numeric), "fix_sim.py produced a non-finite result."
            tolerance = max(1e-3, abs(reference) * 2e-13)
            assert abs(numeric - reference) <= tolerance, (
                f"fix_sim.py did not sum the generated data for seed {seed}: "
                f"got {numeric}, reference {reference}"
            )
            outputs[procs] = output

        baseline = outputs[1]
        assert all(value == baseline for value in outputs.values()), (
            f"Output mismatch for seed {seed}: {outputs}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
