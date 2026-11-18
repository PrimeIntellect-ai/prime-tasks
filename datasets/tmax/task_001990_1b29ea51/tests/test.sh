#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import pytest

PROJECT = "/home/user/video_processor"
C_DIR = os.path.join(PROJECT, "c_src")
BINARY = os.path.join(PROJECT, "target/release/video_processor")
LIBRARY = os.path.join(C_DIR, "libintensity.so")


def run_checked(cmd, **kwargs):
    try:
        return subprocess.run(cmd, check=True, timeout=180, **kwargs)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Command failed: {' '.join(cmd)}\n{exc}")


def test_rust_compiled():
    """Rebuild the submitted C and Rust sources and verify the Rust program works."""
    makefile = os.path.join(C_DIR, "Makefile")
    assert os.path.isfile(makefile), "The repaired C Makefile is missing"
    with open(makefile, "r", encoding="utf-8") as f:
        make_content = f.read()
    assert "-fPIC" in make_content, "The C Makefile must compile using -fPIC"

    for artifact in (LIBRARY, os.path.join(C_DIR, "intensity.o")):
        if os.path.lexists(artifact):
            os.remove(artifact)
    run_checked(["make", "-B"], cwd=C_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    assert os.path.isfile(LIBRARY), "Building the C sources did not produce libintensity.so"
    elf = run_checked(["readelf", "-h", LIBRARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert "DYN (Shared object file)" in elf.stdout, "libintensity.so is not an ELF shared object"
    dynamic = run_checked(["readelf", "-d", LIBRARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert "TEXTREL" not in dynamic.stdout, "libintensity.so contains text relocations and was not built correctly as PIC"

    run_checked(["cargo", "clean"], cwd=PROJECT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    run_checked(["cargo", "build", "--release"], cwd=PROJECT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    assert os.path.isfile(BINARY), \
        "The Rust application was not compiled to /home/user/video_processor/target/release/video_processor"
    assert os.access(BINARY, os.X_OK), "The Rust application is not executable"
    binary_type = run_checked(["file", BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert "ELF" in binary_type.stdout and "executable" in binary_type.stdout, \
        "video_processor is not a compiled ELF executable"

    # Exercise the rebuilt Rust/C implementation on unpredictable valid frames.
    with tempfile.TemporaryDirectory() as frames, tempfile.TemporaryDirectory() as outdir:
        expected = []
        for index in range(4):
            data = os.urandom(320 * 240)
            Path(frames, f"frame_{index:04d}.raw").write_bytes(data)
            expected.append(sum(data) / len(data))
        output = os.path.join(outdir, "result.json")
        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = C_DIR + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
        run_checked([BINARY, frames, output], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert os.path.isfile(output), "The rebuilt Rust application did not create its output file"
        try:
            actual = json.loads(Path(output).read_text())
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            pytest.fail(f"The rebuilt Rust application emitted invalid JSON: {exc}")
        assert isinstance(actual, list) and len(actual) == len(expected), \
            "The rebuilt application did not emit one intensity per input frame"
        assert all(isinstance(x, (int, float)) and np.isfinite(x) for x in actual), \
            "The rebuilt application emitted non-numeric intensities"
        assert np.allclose(actual, expected, rtol=0, atol=1e-9), \
            f"The rebuilt Rust/C implementation returned incorrect intensities: {actual}"


def test_c_lib_compiled():
    """Verify that the C library was compiled into a shared object."""
    assert os.path.exists(LIBRARY), \
        "The shared library libintensity.so was not generated in /home/user/video_processor/c_src"


def test_constants_encoding():
    """Verify that constants.rs is now valid UTF-8."""
    try:
        with open(os.path.join(PROJECT, "src/constants.rs"), "r", encoding="utf-8") as f:
            f.read()
    except UnicodeDecodeError:
        pytest.fail("src/constants.rs is still not valid UTF-8")


def test_python_property_tests():
    """Verify and execute the submitted Hypothesis property test."""
    test_path = "/home/user/py_src/test_processor.py"
    assert os.path.exists(test_path), f"{test_path} is missing"

    with open(test_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "hypothesis" in content, "The test file does not seem to use 'hypothesis'"
    assert "pytest" in content or "test_" in content, "The test file does not seem to be a pytest file"

    try:
        tree = ast.parse(content)
    except SyntaxError as exc:
        pytest.fail(f"The submitted Python test file has invalid syntax: {exc}")
    decorators = [
        decorator
        for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        for decorator in node.decorator_list
    ]
    assert any(
        (isinstance(d, ast.Call) and
         ((isinstance(d.func, ast.Name) and d.func.id == "given") or
          (isinstance(d.func, ast.Attribute) and d.func.attr == "given")))
        for d in decorators
    ), "No test function is decorated with Hypothesis @given"

    # First run the submitted tests against the real Python implementation.
    run_checked(
        ["python3", "-m", "pytest", "-q", test_path],
        cwd="/home/user/py_src",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    # Run them again with an instrumented equivalent module. This confirms that a
    # Hypothesis-generated 320x240 bytes value is actually passed to the requested
    # calculate_intensity function, rather than merely mentioning Hypothesis.
    with tempfile.TemporaryDirectory() as meta_dir:
        copied_test = os.path.join(meta_dir, "test_processor.py")
        shutil.copyfile(test_path, copied_test)
        trace = os.path.join(meta_dir, "calls.jsonl")
        Path(meta_dir, "processor.py").write_text(
            "import inspect, json, os\n"
            "def calculate_intensity(data: bytes) -> float:\n"
            "    under_hypothesis = any('hypothesis' in (f.filename or '') for f in inspect.stack())\n"
            "    with open(os.environ['INTENSITY_TRACE'], 'a') as out:\n"
            "        out.write(json.dumps({'is_bytes': isinstance(data, bytes), 'length': len(data) if isinstance(data, bytes) else -1, 'hypothesis': under_hypothesis}) + '\\n')\n"
            "    if not isinstance(data, bytes):\n"
            "        raise TypeError('data must be bytes')\n"
            "    return 0.0 if not data else sum(data) / len(data)\n",
            encoding="utf-8",
        )
        env = os.environ.copy()
        env["INTENSITY_TRACE"] = trace
        env["PYTHONPATH"] = meta_dir
        run_checked(
            ["python3", "-m", "pytest", "-q", copied_test],
            cwd=meta_dir,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        calls = []
        if os.path.exists(trace):
            for line in Path(trace).read_text(encoding="utf-8").splitlines():
                calls.append(json.loads(line))
        assert any(c["is_bytes"] and c["length"] == 320 * 240 and c["hypothesis"] for c in calls), \
            "The submitted Hypothesis test did not exercise calculate_intensity with a valid 320x240 bytes image"


def test_intensities_mse():
    """Compute the MSE between the agent's output and dynamically derived ground truth."""
    output_path = "/home/user/output_intensities.json"
    assert os.path.exists(output_path), f"Output file {output_path} is missing"

    with tempfile.TemporaryDirectory() as temp_dir:
        try:
            subprocess.run([
                "ffmpeg", "-y", "-i", "/app/test_video.mp4", "-r", "5",
                "-vf", "scale=320:240,format=gray",
                "-f", "image2", "-c:v", "rawvideo", f"{temp_dir}/frame_%04d.raw"
            ], check=True, timeout=180, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            pytest.fail("Failed to extract frames from /app/test_video.mp4 using ffmpeg")

        gt_intensities = []
        for file in sorted(os.listdir(temp_dir)):
            if file.endswith(".raw"):
                data = np.fromfile(os.path.join(temp_dir, file), dtype=np.uint8)
                gt_intensities.append(float(np.mean(data)))

    try:
        with open(output_path, "r") as f:
            agent_intensities = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Output file {output_path} is not valid JSON")

    assert isinstance(agent_intensities, list), f"Output file {output_path} must contain a JSON array"

    min_len = min(len(gt_intensities), len(agent_intensities))
    assert min_len > 0, "No frames were processed or ground truth is empty"

    gt_arr = np.array(gt_intensities[:min_len])
    agent_arr = np.array(agent_intensities[:min_len])
    mse = np.mean((gt_arr - agent_arr) ** 2)

    if abs(len(gt_intensities) - len(agent_intensities)) > 2:
        mse += 1000.0

    assert mse <= 2.0, f"MSE is {mse}, which exceeds the threshold of 2.0"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
