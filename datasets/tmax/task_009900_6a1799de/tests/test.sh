#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import importlib.util
import math
import os
import random
import shutil
import stat
import subprocess

import matplotlib.image as mpimg

HOME = "/home/user"


def solve_ode_fixed(theta, t_max):
    dt = 0.1
    t = 0.0
    x = 10.0
    res = {0.0: x}
    while t < t_max:
        x = x - theta * x * dt
        t += dt
        for target in range(1, int(t_max) + 1):
            if abs(t - target) < dt / 2:
                res[float(target)] = x
    return res


def log_likelihood_fixed(theta, data):
    if theta <= 0:
        return -1e9
    preds = solve_ode_fixed(theta, 5.0)
    ll = 0.0
    for row in data:
        t = float(row["t"])
        obs = float(row["x"])
        pred = preds.get(t, obs)
        ll -= 0.5 * ((obs - pred) / 0.5) ** 2
    return ll


def get_expected_samples():
    random.seed(42)
    data = [
        {"t": t, "x": 10.0 * math.exp(-0.5 * t)}
        for t in [0, 1, 2, 3, 4, 5]
    ]
    current_theta = 0.2
    current_ll = log_likelihood_fixed(current_theta, data)
    samples = []
    for _ in range(2500):
        prop_theta = current_theta + random.gauss(0, 0.05)
        prop_ll = log_likelihood_fixed(prop_theta, data)
        if math.log(random.random()) < prop_ll - current_ll:
            current_theta = prop_theta
            current_ll = prop_ll
        samples.append(current_theta)
    return samples


def get_expected_mean():
    samples = get_expected_samples()[500:]
    return round(sum(samples) / len(samples), 3)


def run(cmd, timeout=90):
    return subprocess.run(
        cmd,
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    )


def check_png(path):
    assert os.path.isfile(path), f"Missing file: {path}"
    assert os.path.getsize(path) > 0, f"File {path} is empty"
    with open(path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", f"{path} is not a PNG file"
    image = mpimg.imread(path)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10
    assert float(image.max()) > float(image.min()), "Trace plot has no visible content"


def check_pipeline_outputs():
    trace_path = os.path.join(HOME, "trace.csv")
    assert os.path.isfile(trace_path), f"Missing file: {trace_path}"
    with open(trace_path, newline="") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ["theta"], "trace.csv must have a theta header"
    assert len(rows) == 2501, "trace.csv must contain exactly 2500 samples"
    actual = [float(row[0]) for row in rows[1:]]
    expected = get_expected_samples()
    assert len(actual) == len(expected)
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert math.isclose(got, want, rel_tol=0.0, abs_tol=1e-12), (
            f"Incorrect MCMC sample at row {i + 2}: got {got}, expected {want}"
        )

    mean_path = os.path.join(HOME, "posterior_mean.txt")
    assert os.path.isfile(mean_path), f"Missing file: {mean_path}"
    with open(mean_path) as f:
        content = f.read().strip()
    expected_mean = get_expected_mean()
    # Preserve the original posterior assertion and additionally require the
    # requested precise output format.
    assert str(expected_mean) in content, (
        f"Expected posterior mean {expected_mean} not found in {mean_path}. Found: {content}"
    )
    assert content == f"{expected_mean:.3f}", "posterior_mean.txt must contain one value rounded to 3 decimals"
    check_png(os.path.join(HOME, "trace_plot.png"))


def execute_analyzer(path):
    if path.endswith(".py"):
        run(["python3", path])
    else:
        assert shutil.which("Rscript"), "analyze.R was supplied but Rscript is unavailable"
        run(["Rscript", path])


def write_synthetic_trace(values):
    with open(os.path.join(HOME, "trace.csv"), "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["theta"])
        writer.writerows([[v] for v in values])


def test_complete_pipeline():
    mcmc_path = os.path.join(HOME, "mcmc_ode.py")
    pipeline_path = os.path.join(HOME, "pipeline.sh")
    mean_path = os.path.join(HOME, "posterior_mean.txt")
    plot_path = os.path.join(HOME, "trace_plot.png")
    trace_path = os.path.join(HOME, "trace.csv")

    # Preserve all original file and source assertions.
    assert os.path.isfile(mcmc_path), f"Missing file: {mcmc_path}"
    with open(mcmc_path) as f:
        content = f.read()
    assert "0.1" in content, "The step size dt does not appear to be changed to 0.1 in mcmc_ode.py"
    assert "dt = 2.0" not in content, "The old step size dt = 2.0 is still present in mcmc_ode.py"
    assert os.path.isfile(pipeline_path), f"Missing file: {pipeline_path}"
    assert os.access(pipeline_path, os.X_OK), f"File {pipeline_path} is not executable"

    analyzers = [
        p for p in (os.path.join(HOME, "analyze.py"), os.path.join(HOME, "analyze.R"))
        if os.path.isfile(p)
    ]
    assert analyzers, "Missing /home/user/analyze.py or /home/user/analyze.R"

    # Exercise the integrator itself on independently selected inputs.
    spec = importlib.util.spec_from_file_location("submitted_mcmc", mcmc_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "solve_ode", None)), "mcmc_ode.py lacks solve_ode"
    for theta, t_max in [(0.37, 5.0), (0.81, 3.0), (0.23, 2.0)]:
        got = module.solve_ode(theta, t_max)
        want = solve_ode_fixed(theta, t_max)
        assert set(got) == set(want)
        for key in want:
            assert math.isclose(got[key], want[key], rel_tol=0.0, abs_tol=1e-12)

    # Temporarily wrap the required scripts, then execute pipeline.sh. This
    # proves that the pipeline actually invokes MCMC first and an analyzer second.
    log_path = "/tmp/verifier_pipeline_calls.log"
    backups = {}
    try:
        if os.path.exists(log_path):
            os.remove(log_path)
        instrument = [mcmc_path] + analyzers
        for index, path in enumerate(instrument):
            backup = f"/tmp/verifier_original_{index}{os.path.splitext(path)[1]}"
            shutil.copy2(path, backup)
            backups[path] = backup
            mode = stat.S_IMODE(os.stat(path).st_mode)
            if path.endswith(".py"):
                label = "mcmc" if path == mcmc_path else os.path.basename(path)
                wrapper = (
                    "#!/usr/bin/env python3\n"
                    "import runpy\n"
                    f"open({log_path!r}, 'a').write({label!r} + '\\n')\n"
                    f"runpy.run_path({backup!r}, run_name='__main__')\n"
                )
            else:
                label = os.path.basename(path)
                wrapper = (
                    f"cat({log_path!r}, file={log_path!r}, append=TRUE)\n"
                    f"cat({(label + chr(10))!r}, file={log_path!r}, append=TRUE)\n"
                    f"source({backup!r})\n"
                )
            with open(path, "w") as f:
                f.write(wrapper)
            os.chmod(path, mode)

        for artifact in (trace_path, mean_path, plot_path):
            if os.path.exists(artifact):
                os.remove(artifact)
        run([pipeline_path])
    finally:
        for path, backup in backups.items():
            shutil.copy2(backup, path)

    assert os.path.isfile(log_path), "pipeline.sh did not execute the required scripts"
    with open(log_path) as f:
        calls = [line.strip() for line in f if line.strip()]
    assert "mcmc" in calls, "pipeline.sh did not execute mcmc_ode.py"
    used = [name for name in ("analyze.py", "analyze.R") if name in calls]
    assert used, "pipeline.sh did not execute an analyze script"
    assert calls.index("mcmc") < min(calls.index(name) for name in used), (
        "pipeline.sh must execute mcmc_ode.py before the analyze script"
    )
    selected_analyzer = os.path.join(HOME, used[0])
    check_pipeline_outputs()

    # Exercise the analyzer on two verifier-selected traces. The result must use
    # rows after the first 500, and the plot must be a real, data-dependent PNG.
    values1 = [-50.0] * 500 + [1.0 + i * 0.001 for i in range(150)]
    write_synthetic_trace(values1)
    execute_analyzer(selected_analyzer)
    expected1 = f"{sum(values1[500:]) / len(values1[500:]):.3f}"
    with open(mean_path) as f:
        assert f.read().strip() == expected1
    check_png(plot_path)
    with open(plot_path, "rb") as f:
        hash1 = hashlib.sha256(f.read()).hexdigest()

    values2 = [99.0] * 500 + [2.0 + math.sin(i / 7.0) for i in range(150)]
    write_synthetic_trace(values2)
    execute_analyzer(selected_analyzer)
    expected2 = f"{sum(values2[500:]) / len(values2[500:]):.3f}"
    with open(mean_path) as f:
        assert f.read().strip() == expected2
    check_png(plot_path)
    with open(plot_path, "rb") as f:
        hash2 = hashlib.sha256(f.read()).hexdigest()
    assert hash1 != hash2, "trace_plot.png does not depend on the post-burn-in samples"

    # Restore the requested final state using the unmodified reproducible pipeline.
    run([pipeline_path])
    check_pipeline_outputs()


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
