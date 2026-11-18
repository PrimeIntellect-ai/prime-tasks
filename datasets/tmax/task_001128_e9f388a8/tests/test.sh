#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import stat
import subprocess

import numpy as np
import pytest

HOME = "/home/user"


def test_build_and_evaluate_mse():
    """Retain the original randomized MSE accuracy assertions."""
    build_script = "/home/user/build.sh"
    wrapper_script = "/home/user/wrapper.py"
    detector_source = "/home/user/detector.c"
    lib_path = "/home/user/libdetector.so"

    assert os.path.isfile(build_script), f"Missing {build_script}"
    assert os.access(build_script, os.X_OK), f"{build_script} is not executable. Please run chmod +x."
    assert os.path.isfile(wrapper_script), f"Missing {wrapper_script}"
    assert os.access(wrapper_script, os.X_OK), f"{wrapper_script} is not executable"
    assert os.path.isfile(detector_source), f"Missing {detector_source}"

    result = subprocess.run([build_script], cwd=HOME, capture_output=True, text=True)
    assert result.returncode == 0, f"build.sh failed with exit code {result.returncode}\nStderr: {result.stderr}"
    assert os.path.isfile(lib_path), f"Shared library {lib_path} was not created by build.sh"

    with open(lib_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{lib_path} is not an ELF shared library"

    np.random.seed(42)
    mae = 0.0
    num_tests = 100
    size = 230400
    tmp1 = "/tmp/test_f1.raw"
    tmp2 = "/tmp/test_f2.raw"

    for i in range(num_tests):
        f1 = np.random.randint(0, 256, size, dtype=np.uint8)
        f2 = np.random.randint(0, 256, size, dtype=np.uint8)
        with open(tmp1, "wb") as f:
            f.write(f1.tobytes())
        with open(tmp2, "wb") as f:
            f.write(f2.tobytes())

        expected_mse = np.mean((f1.astype(float) - f2.astype(float)) ** 2)
        try:
            out = subprocess.check_output(
                ["python3", wrapper_script, tmp1, tmp2, str(size)],
                stderr=subprocess.STDOUT,
                text=True,
            )
            agent_mse = float(out.strip())
        except subprocess.CalledProcessError as e:
            pytest.fail(f"wrapper.py failed on test pair {i}:\nOutput: {e.output}")
        except ValueError:
            pytest.fail(f"wrapper.py did not output a valid float on test pair {i}. Output was: '{out.strip()}'")
        mae += abs(expected_mse - agent_mse)

    mae /= num_tests
    for path in (tmp1, tmp2):
        if os.path.exists(path):
            os.remove(path)
    assert mae <= 0.5, f"MAE {mae:.4f} exceeds threshold 0.5"


def test_real_c_library_and_ctypes_ffi():
    import ctypes

    build_script = f"{HOME}/build.sh"
    wrapper_script = f"{HOME}/wrapper.py"
    lib_path = f"{HOME}/libdetector.so"

    source = open(wrapper_script, encoding="utf-8").read()
    tree = ast.parse(source, wrapper_script)
    imports_ctypes = any(
        (isinstance(n, ast.Import) and any(a.name == "ctypes" for a in n.names))
        or (isinstance(n, ast.ImportFrom) and n.module == "ctypes")
        for n in ast.walk(tree)
    )
    calls_loader = any(
        isinstance(n, ast.Call)
        and ((isinstance(n.func, ast.Name) and n.func.id in {"CDLL", "LoadLibrary"})
             or (isinstance(n.func, ast.Attribute) and n.func.attr in {"CDLL", "LoadLibrary"}))
        for n in ast.walk(tree)
    )
    assert imports_ctypes and calls_loader, "wrapper.py must load the shared library through ctypes"

    lib = ctypes.CDLL(lib_path)
    assert hasattr(lib, "compute_mse"), "libdetector.so does not export compute_mse"
    fn = lib.compute_mse
    fn.argtypes = [ctypes.POINTER(ctypes.c_ubyte), ctypes.POINTER(ctypes.c_ubyte), ctypes.c_int]
    fn.restype = ctypes.c_double
    a = np.array([0, 1, 10, 255, 32, 100, 7], dtype=np.uint8)
    b = np.array([1, 4, 20, 250, 30, 90, 9], dtype=np.uint8)
    got = fn(a.ctypes.data_as(ctypes.POINTER(ctypes.c_ubyte)),
             b.ctypes.data_as(ctypes.POINTER(ctypes.c_ubyte)), len(a))
    expected = float(np.mean((a.astype(float) - b.astype(float)) ** 2))
    assert abs(got - expected) < 1e-9, "exported C compute_mse returned an incorrect result"

    # Replace the library with a sentinel implementation. The wrapper must obtain
    # its answer by calling compute_mse in the library at the required path.
    sentinel_c = "/tmp/verifier_sentinel.c"
    with open(sentinel_c, "w") as f:
        f.write("double compute_mse(const unsigned char*a,const unsigned char*b,int n){(void)a;(void)b;(void)n;return 1234.56789;}\n")
    subprocess.run(["gcc", "-shared", "-fPIC", sentinel_c, "-o", lib_path], check=True)
    p1, p2 = "/tmp/sentinel1.raw", "/tmp/sentinel2.raw"
    open(p1, "wb").write(bytes(range(17)))
    open(p2, "wb").write(bytes(reversed(range(17))))
    try:
        out = subprocess.check_output(["python3", wrapper_script, p1, p2, "17"], text=True)
        assert abs(float(out.strip()) - 1234.56789) < 1e-6, "wrapper.py did not call the C compute_mse function"
    finally:
        subprocess.run([build_script], cwd=HOME, check=True)
        for p in (p1, p2, sentinel_c):
            if os.path.exists(p):
                os.remove(p)


def test_analyze_complete_pipeline():
    analyze = f"{HOME}/analyze.sh"
    wrapper = f"{HOME}/wrapper.py"
    log_path = f"{HOME}/mse_log.txt"
    assert os.path.isfile(analyze), f"Missing {analyze}"
    assert os.access(analyze, os.X_OK), f"{analyze} is not executable"

    video = "/tmp/verifier video.mkv"
    subprocess.run([
        "/usr/bin/ffmpeg", "-y", "-loglevel", "error",
        "-f", "lavfi", "-i", "testsrc2=duration=2:size=48x36:rate=8",
        "-c:v", "ffv1", video,
    ], check=True)

    probe_dir = "/tmp/analyze_probe"
    shutil.rmtree(probe_dir, ignore_errors=True)
    os.makedirs(probe_dir)
    wrapper_saved = "/tmp/verifier_original_wrapper.py"
    ffmpeg_real = "/usr/bin/ffmpeg.verifier-real"
    sort_real = "/usr/bin/sort.verifier-real"
    ffmpeg_trace = "/tmp/verifier_ffmpeg.trace"
    sort_trace = "/tmp/verifier_sort.trace"
    for p in (ffmpeg_trace, sort_trace, log_path):
        if os.path.exists(p):
            os.remove(p)

    shutil.move(wrapper, wrapper_saved)
    probe = '''#!/usr/bin/env python3
import json, os, shutil, subprocess, sys
probe = "/tmp/analyze_probe"
records = os.path.join(probe, "records.jsonl")
try:
    n = sum(1 for _ in open(records))
except FileNotFoundError:
    n = 0
args = sys.argv[1:]
if len(args) != 3:
    sys.exit(91)
a = os.path.join(probe, f"{n:04d}_a.raw")
b = os.path.join(probe, f"{n:04d}_b.raw")
shutil.copyfile(args[0], a)
shutil.copyfile(args[1], b)
with open(records, "a") as f:
    f.write(json.dumps({"args": args, "a": a, "b": b, "sizes": [os.path.getsize(args[0]), os.path.getsize(args[1])]}) + "\\n")
r = subprocess.run([sys.executable, "/tmp/verifier_original_wrapper.py"] + args)
sys.exit(r.returncode)
'''
    open(wrapper, "w").write(probe)
    os.chmod(wrapper, 0o755)

    shutil.move("/usr/bin/ffmpeg", ffmpeg_real)
    open("/usr/bin/ffmpeg", "w").write(
        '#!/bin/bash\nfor a in "$@"; do printf "ARG=%s\\n" "$a" >> /tmp/verifier_ffmpeg.trace; done\nexec /usr/bin/ffmpeg.verifier-real "$@"\n'
    )
    os.chmod("/usr/bin/ffmpeg", 0o755)
    shutil.move("/usr/bin/sort", sort_real)
    open("/usr/bin/sort", "w").write(
        '#!/bin/bash\nprintf "called\\n" >> /tmp/verifier_sort.trace\nexec /usr/bin/sort.verifier-real "$@"\n'
    )
    os.chmod("/usr/bin/sort", 0o755)

    uri = "vidproc:///tmp/verifier video.mkv?width=24&height=18&fps=4"
    try:
        result = subprocess.run([analyze, uri], cwd=HOME, capture_output=True, text=True, timeout=60)
    finally:
        if os.path.exists("/usr/bin/ffmpeg"):
            os.remove("/usr/bin/ffmpeg")
        shutil.move(ffmpeg_real, "/usr/bin/ffmpeg")
        if os.path.exists("/usr/bin/sort"):
            os.remove("/usr/bin/sort")
        shutil.move(sort_real, "/usr/bin/sort")
        if os.path.exists(wrapper):
            os.remove(wrapper)
        shutil.move(wrapper_saved, wrapper)

    assert result.returncode == 0, f"analyze.sh failed\nstdout: {result.stdout}\nstderr: {result.stderr}"
    assert os.path.isfile(ffmpeg_trace), "analyze.sh did not invoke ffmpeg"
    trace = open(ffmpeg_trace).read()
    assert video in trace, "analyze.sh did not parse and pass the absolute video path to ffmpeg"
    assert "rgb24" in trace, "ffmpeg was not asked to extract RGB24 frames"

    records_path = os.path.join(probe_dir, "records.jsonl")
    assert os.path.isfile(records_path), "analyze.sh never called wrapper.py"
    records = [json.loads(line) for line in open(records_path) if line.strip()]
    # A two-second, 8 fps source sampled at 4 fps should produce about 8 frames,
    # hence about 7 consecutive pairs. This rejects ignoring the fps parameter.
    assert 6 <= len(records) <= 8, f"unexpected number of frame pairs: {len(records)}"
    expected_size = 24 * 18 * 3
    assert all(r["sizes"] == [expected_size, expected_size] for r in records), \
        "extracted frames do not have the URI-requested width, height, and RGB24 size"

    pair_results = {}
    for r in records:
        n1 = os.path.basename(r["args"][0])
        n2 = os.path.basename(r["args"][1])
        m1 = re.fullmatch(r"frame_(\d+)\.raw", n1)
        m2 = re.fullmatch(r"frame_(\d+)\.raw", n2)
        assert m1 and m2, f"non-sequential frame naming: {n1}, {n2}"
        assert int(m2.group(1)) == int(m1.group(1)) + 1, f"non-consecutive pair: {n1}, {n2}"
        a = np.fromfile(r["a"], dtype=np.uint8).astype(np.float64)
        b = np.fromfile(r["b"], dtype=np.uint8).astype(np.float64)
        pair_results[(n1, n2)] = float(np.mean((a - b) ** 2))

    assert any(v > 0 for v in pair_results.values()), "extracted frame pairs were not meaningfully processed"
    assert os.path.isfile(log_path), "analyze.sh did not create /home/user/mse_log.txt"
    parsed_log = []
    for line in open(log_path):
        fields = line.split()
        assert len(fields) == 3, f"invalid mse_log.txt line: {line!r}"
        try:
            value = float(fields[2])
        except ValueError:
            pytest.fail(f"invalid MSE in mse_log.txt: {fields[2]!r}")
        parsed_log.append((fields[0], fields[1], value))

    assert len(parsed_log) == len(records), "mse_log.txt does not contain every consecutive frame pair exactly once"
    assert {(a, b) for a, b, _ in parsed_log} == set(pair_results), "mse_log.txt frame pairs do not match wrapper calls"
    for a, b, value in parsed_log:
        assert abs(value - pair_results[(a, b)]) < 1e-4, f"incorrect logged MSE for {a} and {b}"

    values = [v for _, _, v in parsed_log]
    sorted_in_log = all(values[i] >= values[i + 1] for i in range(len(values) - 1))
    used_sort = os.path.isfile(sort_trace) and os.path.getsize(sort_trace) > 0
    assert used_sort or sorted_in_log, "analyze.sh did not sort results to identify highest-MSE transitions"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
