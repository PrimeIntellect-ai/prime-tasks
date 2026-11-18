#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.metadata
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile
import uuid

import numpy as np


def run_detector(script_path, input_dir, output_path, env=None):
    result = subprocess.run(
        [sys.executable, script_path, "--input-dir", input_dir, "--output", output_path],
        capture_output=True,
        text=True,
        env=env,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Script failed for {input_dir}:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(output_path), f"Output JSON not found at {output_path}"
    with open(output_path, "r") as handle:
        result_json = json.load(handle)
    assert isinstance(result_json, dict), "Output JSON must contain a dictionary"
    return result_json


def test_package_is_fixed_and_installed():
    source_dir = "/app/signal-profiler-0.1.0"
    setup_py = os.path.join(source_dir, "setup.py")
    assert os.path.isfile(setup_py), "signal-profiler setup.py is missing"

    # The repaired vendored source must actually be buildable.
    wheel_dir = tempfile.mkdtemp(prefix="signal_profiler_wheel_")
    build = subprocess.run(
        [sys.executable, "-m", "pip", "wheel", "--no-deps", "--no-build-isolation",
         "--wheel-dir", wheel_dir, source_dir],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, (
        "The vendored signal-profiler package is still not buildable:\n"
        + build.stdout + "\n" + build.stderr
    )
    assert glob.glob(os.path.join(wheel_dir, "signal_profiler-0.1.0-*.whl")), (
        "Building signal-profiler did not produce a wheel"
    )

    # It must also have been installed into the current environment.
    assert importlib.metadata.version("signal-profiler") == "0.1.0"
    import signal_profiler
    assert callable(signal_profiler.load_trace)

    probe = os.path.join(wheel_dir, "probe.csv")
    with open(probe, "w") as handle:
        handle.write("timestamp,latency_ns\n0,10.5\n1,20.25\n")
    loaded = signal_profiler.load_trace(probe)
    assert isinstance(loaded, np.ndarray)
    assert np.allclose(loaded, np.array([10.5, 20.25]))


def test_detector_script():
    script_path = "/home/user/detector.py"
    assert os.path.isfile(script_path), f"Detector script not found at {script_path}"

    clean_dir = "/app/test_traces/clean"
    evil_dir = "/app/test_traces/evil"
    clean_out = "/tmp/clean_out.json"
    evil_out = "/tmp/evil_out.json"

    # Preserve the original clean-set assertions.
    clean_results = run_detector(script_path, clean_dir, clean_out)
    clean_files = [os.path.basename(f) for f in glob.glob(os.path.join(clean_dir, "*.csv"))]
    clean_failures = [cf for cf in clean_files if clean_results.get(cf) != "clean"]

    # Preserve the original evil-set assertions.
    evil_results = run_detector(script_path, evil_dir, evil_out)
    evil_files = [os.path.basename(f) for f in glob.glob(os.path.join(evil_dir, "*.csv"))]
    evil_failures = [ef for ef in evil_files if evil_results.get(ef) != "evil"]

    err_msg = []
    if clean_failures:
        err_msg.append(
            f"{len(clean_failures)} of {len(clean_files)} clean modified/flagged as evil: {clean_failures}"
        )
    if evil_failures:
        err_msg.append(
            f"{len(evil_failures)} of {len(evil_files)} evil bypassed/flagged as clean: {evil_failures}"
        )
    assert not err_msg, " | ".join(err_msg)

    # Create a fresh, neutrally named, mixed evaluation directory. Labels and
    # filenames are randomized so neither the directory nor filename reveals them.
    rng = np.random.default_rng()
    mixed_root = tempfile.mkdtemp(prefix="latency_batch_")
    mixed_dir = os.path.join(mixed_root, uuid.uuid4().hex)
    os.makedirs(mixed_dir)
    cases = ["clean"] * 8 + ["evil"] * 8
    random.SystemRandom().shuffle(cases)
    expected = {}
    n_points = 500

    for label in cases:
        filename = uuid.uuid4().hex + ".csv"
        path = os.path.join(mixed_dir, filename)
        if label == "clean":
            latency = rng.normal(5000, 200, n_points)
        else:
            t = np.arange(n_points)
            latency = rng.normal(5000, 200, n_points)
            latency += 1000 * np.sin(2 * np.pi * 0.05 * t)
            latency[rng.random(n_points) > 0.5] += 3000
        with open(path, "w") as handle:
            handle.write("timestamp,latency_ns\n")
            for index, value in enumerate(latency):
                handle.write(f"{index},{value:.8f}\n")
        expected[filename] = label

    # Instrument the required APIs in the detector subprocess. This verifies
    # actual runtime use rather than merely accepting dead imports or comments.
    hook_dir = tempfile.mkdtemp(prefix="detector_hooks_")
    event_log = os.path.join(mixed_root, "events.log")
    hook = r'''import os
_EVENT_LOG = os.environ.get("DETECTOR_EVENT_LOG")
def _record(kind, detail=""):
    if _EVENT_LOG:
        with open(_EVENT_LOG, "a") as _f:
            _f.write(kind + "\t" + str(detail) + "\n")

try:
    import signal_profiler as _sp
    _original_load_trace = _sp.load_trace
    def _checked_load_trace(filepath, *args, **kwargs):
        _record("LOAD", os.path.abspath(os.fspath(filepath)))
        return _original_load_trace(filepath, *args, **kwargs)
    _sp.load_trace = _checked_load_trace
except Exception:
    pass

try:
    import numpy as _np
    for _name in ("fft", "rfft", "fftn", "rfftn"):
        if hasattr(_np.fft, _name):
            _original = getattr(_np.fft, _name)
            def _make_fft_wrapper(fn, name):
                def _wrapper(*args, **kwargs):
                    _record("FFT", name)
                    return fn(*args, **kwargs)
                return _wrapper
            setattr(_np.fft, _name, _make_fft_wrapper(_original, "numpy." + _name))
except Exception:
    pass

try:
    import scipy.fft as _sfft
    for _name in ("fft", "rfft", "fftn", "rfftn"):
        if hasattr(_sfft, _name):
            _original = getattr(_sfft, _name)
            def _make_sfft_wrapper(fn, name):
                def _wrapper(*args, **kwargs):
                    _record("FFT", name)
                    return fn(*args, **kwargs)
                return _wrapper
            setattr(_sfft, _name, _make_sfft_wrapper(_original, "scipy." + _name))
except Exception:
    pass

try:
    import scipy.stats as _stats
    _original_kde = _stats.gaussian_kde
    def _checked_kde(*args, **kwargs):
        _record("KDE", "scipy.stats.gaussian_kde")
        return _original_kde(*args, **kwargs)
    _stats.gaussian_kde = _checked_kde
except Exception:
    pass
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as handle:
        handle.write(hook)

    mixed_out = os.path.join(mixed_root, "results.json")
    env = os.environ.copy()
    env["DETECTOR_EVENT_LOG"] = event_log
    env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
    mixed_results = run_detector(script_path, mixed_dir, mixed_out, env=env)

    assert set(mixed_results) == set(expected), (
        "Output must contain exactly one entry for every CSV in the mixed input directory"
    )
    wrong = {name: (mixed_results.get(name), label) for name, label in expected.items()
             if mixed_results.get(name) != label}
    assert not wrong, f"Incorrect classifications on mixed hidden traces: {wrong}"

    assert os.path.isfile(event_log), "Detector did not use any instrumented required APIs"
    with open(event_log, "r") as handle:
        events = [line.rstrip("\n").split("\t", 1) for line in handle if line.strip()]

    loaded_files = {
        os.path.basename(parts[1]) for parts in events
        if parts[0] == "LOAD" and len(parts) == 2
        and os.path.dirname(parts[1]) == os.path.abspath(mixed_dir)
    }
    fft_count = sum(parts[0] == "FFT" for parts in events)
    kde_count = sum(parts[0] == "KDE" for parts in events)

    assert loaded_files == set(expected), (
        "Every mixed trace must be loaded through signal_profiler.load_trace"
    )
    assert fft_count >= len(expected), "FFT analysis must be performed for every trace"
    assert kde_count >= len(expected), "KDE analysis must be performed for every trace"


if __name__ == "__main__":
    test_package_is_fixed_and_installed()
    test_detector_script()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
