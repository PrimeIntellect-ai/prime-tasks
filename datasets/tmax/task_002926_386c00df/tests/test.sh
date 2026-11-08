#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sys
import time
import ctypes
import subprocess
import importlib.util
import pytest
import numpy as np
import scipy.io.wavfile as wav

RESULT_RE = re.compile(
    r"MSE: ([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\n"
    r"Speedup: ([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\n?"
)


def load_module_from_path(module_name, file_path):
    spec = importlib.util.spec_from_file_location(module_name, file_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def parse_results(text):
    match = RESULT_RE.fullmatch(text)
    assert match, "benchmark_results.txt does not have the required two-line format."
    return float(match.group(1)), float(match.group(2))


def test_files_exist():
    """Verify that the required files have been created."""
    assert os.path.exists("/home/user/libfilter.so"), "Compiled C library /home/user/libfilter.so is missing."
    assert os.path.exists("/home/user/fast_filter.py"), "Python wrapper /home/user/fast_filter.py is missing."
    assert os.path.exists("/home/user/benchmark.py"), "Benchmark script /home/user/benchmark.py is missing."
    assert os.path.exists("/home/user/benchmark_results.txt"), "Benchmark results /home/user/benchmark_results.txt is missing."

    with open("/home/user/benchmark_results.txt", "r", encoding="utf-8") as handle:
        mse, speedup = parse_results(handle.read())
    assert np.isfinite(mse) and mse < 1e-5, f"Recorded MSE is invalid: {mse}"
    assert np.isfinite(speedup) and speedup >= 50.0, f"Recorded speedup is invalid: {speedup}"


def test_benchmark_script_executes_and_writes_results():
    """Run the requested benchmark artifact on a small fixture and validate its output."""
    audio_path = "/app/test_signal.wav"
    results_path = "/home/user/benchmark_results.txt"
    with open(audio_path, "rb") as handle:
        original_audio = handle.read()
    with open(results_path, "rb") as handle:
        original_results = handle.read()

    rng = np.random.default_rng(7301)
    small_audio = rng.integers(-30000, 30001, size=257, dtype=np.int16)
    try:
        wav.write(audio_path, 44100, small_audio)
        with open(results_path, "w", encoding="utf-8") as handle:
            handle.write("VERIFIER_SENTINEL\n")
        completed = subprocess.run(
            [sys.executable, "/home/user/benchmark.py"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert completed.returncode == 0, (
            "benchmark.py failed when executed:\n" + completed.stdout + completed.stderr
        )
        with open(results_path, "r", encoding="utf-8") as handle:
            generated = handle.read()
        assert generated != "VERIFIER_SENTINEL\n", "benchmark.py did not write benchmark_results.txt"
        mse, speedup = parse_results(generated)
        assert np.isfinite(mse) and mse < 1e-5, f"Executed benchmark reported invalid MSE: {mse}"
        assert np.isfinite(speedup) and speedup >= 0.0, f"Executed benchmark reported invalid speedup: {speedup}"
    finally:
        with open(audio_path, "wb") as handle:
            handle.write(original_audio)
        with open(results_path, "wb") as handle:
            handle.write(original_results)


def test_wrapper_calls_native_library_and_native_call_produces_convolution():
    """Ensure fast_convolve actually invokes libfilter.so and receives convolution from C."""
    target = os.path.realpath("/home/user/libfilter.so")
    expected = None
    state = {"loaded": False, "calls": 0, "produced": False}
    real_cdll = ctypes.CDLL
    real_loader_type = ctypes.cdll._dlltype

    def arrays_in(value, seen=None):
        if seen is None:
            seen = set()
        ident = id(value)
        if ident in seen:
            return []
        seen.add(ident)
        found = []
        if isinstance(value, np.ndarray):
            found.append(value)
        for attr in ("_arr", "_obj"):
            try:
                child = getattr(value, attr)
            except Exception:
                child = None
            if child is not None:
                found.extend(arrays_in(child, seen))
        try:
            objects = getattr(value, "_objects", None)
            if isinstance(objects, dict):
                for child in objects.values():
                    found.extend(arrays_in(child, seen))
        except Exception:
            pass
        return found

    class TrackedFunction:
        def __init__(self, function):
            object.__setattr__(self, "_function", function)

        def __getattr__(self, name):
            return getattr(object.__getattribute__(self, "_function"), name)

        def __setattr__(self, name, value):
            if name == "_function":
                object.__setattr__(self, name, value)
            else:
                setattr(object.__getattribute__(self, "_function"), name, value)

        def __call__(self, *args):
            candidates = []
            seen_arrays = set()
            for arg in args:
                for array in arrays_in(arg):
                    if id(array) not in seen_arrays:
                        seen_arrays.add(id(array))
                        candidates.append((array, np.array(array, copy=True)))

            result = object.__getattribute__(self, "_function")(*args)
            state["calls"] += 1

            for array, before in candidates:
                flat = np.asarray(array).reshape(-1)
                if flat.size == expected.size:
                    after = flat.astype(np.float64, copy=False)
                    was_expected = np.allclose(before.reshape(-1), expected, rtol=2e-5, atol=2e-5)
                    is_expected = np.allclose(after, expected, rtol=2e-5, atol=2e-5)
                    if is_expected and not was_expected:
                        state["produced"] = True

            if isinstance(result, ctypes._Pointer) and bool(result):
                try:
                    returned = np.ctypeslib.as_array(result, shape=(expected.size,)).astype(np.float64)
                    if np.allclose(returned, expected, rtol=2e-5, atol=2e-5):
                        state["produced"] = True
                except Exception:
                    pass
            return result

    class TrackedCDLL(real_cdll):
        def __init__(self, name, *args, **kwargs):
            super().__init__(name, *args, **kwargs)
            try:
                loaded_path = os.path.realpath(os.fsdecode(os.fspath(name)))
            except Exception:
                loaded_path = ""
            object.__setattr__(self, "_is_target_filter", loaded_path == target)
            if loaded_path == target:
                state["loaded"] = True

        def __getattr__(self, name):
            function = super().__getattr__(name)
            if object.__getattribute__(self, "_is_target_filter") and isinstance(function, ctypes._CFuncPtr):
                wrapped = TrackedFunction(function)
                object.__setattr__(self, name, wrapped)
                return wrapped
            return function

    rng = np.random.default_rng(99173)
    signal = rng.uniform(-1.0, 1.0, size=37).astype(np.float32)
    kernel = rng.uniform(-0.5, 0.5, size=11).astype(np.float32)
    expected = np.convolve(signal.astype(np.float64), kernel.astype(np.float64))

    ctypes.CDLL = TrackedCDLL
    ctypes.cdll._dlltype = TrackedCDLL
    try:
        sys.modules.pop("fast_filter_ffi_check", None)
        fast_module = load_module_from_path("fast_filter_ffi_check", "/home/user/fast_filter.py")
        result = np.asarray(fast_module.fast_convolve(signal, kernel), dtype=np.float64)
    finally:
        ctypes.CDLL = real_cdll
        ctypes.cdll._dlltype = real_loader_type

    assert state["loaded"], "fast_filter.py did not load /home/user/libfilter.so through ctypes."
    assert state["calls"] > 0, "fast_convolve did not call a function from /home/user/libfilter.so."
    assert state["produced"], "The native library call did not produce the convolution output."
    assert result.shape == expected.shape
    assert np.allclose(result, expected, rtol=2e-5, atol=2e-5), "Randomized native convolution was inaccurate."


def test_performance_and_accuracy():
    """Evaluate the fast_convolve function for accuracy and speedup."""
    # Ensure modules can be loaded
    assert os.path.exists("/home/user/slow_filter.py"), "slow_filter.py is missing."
    assert os.path.exists("/home/user/fast_filter.py"), "fast_filter.py is missing."

    try:
        slow_module = load_module_from_path("slow_filter", "/home/user/slow_filter.py")
        slow_convolve = slow_module.slow_convolve
    except Exception as e:
        pytest.fail(f"Failed to load slow_convolve from slow_filter.py: {e}")

    try:
        fast_module = load_module_from_path("fast_filter", "/home/user/fast_filter.py")
        fast_convolve = fast_module.fast_convolve
    except Exception as e:
        pytest.fail(f"Failed to load fast_convolve from fast_filter.py: {e}")

    # Load audio data
    audio_path = "/app/test_signal.wav"
    assert os.path.exists(audio_path), f"Audio fixture {audio_path} is missing."

    rate, data = wav.read(audio_path)
    # Normalize to float32
    signal = (data / 32768.0).astype(np.float32).tolist()
    kernel = [1.0 / 500.0] * 500

    # To avoid the test taking multiple minutes, we can test on a subset of the signal for the benchmark,
    # but to be faithful to the prompt, we will use the full signal.
    # If the signal is too large, we cap it to 200,000 samples to keep test times reasonable while still
    # providing a large enough N to measure accurate speedup.
    MAX_SAMPLES = 200000
    if len(signal) > MAX_SAMPLES:
        signal = signal[:MAX_SAMPLES]

    # Measure slow implementation
    t0 = time.time()
    res_slow = slow_convolve(signal, kernel)
    t_slow = time.time() - t0

    # Measure fast implementation
    t0 = time.time()
    try:
        res_fast = fast_convolve(signal, kernel)
    except Exception as e:
        pytest.fail(f"fast_convolve raised an exception during execution: {e}")
    t_fast = time.time() - t0

    # Calculate metrics
    res_slow_arr = np.array(res_slow, dtype=np.float32)
    res_fast_arr = np.array(res_fast, dtype=np.float32)

    assert len(res_slow_arr) == len(res_fast_arr), f"Output length mismatch: expected {len(res_slow_arr)}, got {len(res_fast_arr)}"

    mse = np.mean((res_slow_arr - res_fast_arr) ** 2)
    speedup = t_slow / t_fast if t_fast > 0 else float('inf')

    assert mse < 1e-5, f"Accuracy metric failed: MSE={mse} is not < 1e-5"
    assert speedup >= 50.0, f"Performance metric failed: Speedup={speedup:.2f}x is not >= 50.0x"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
