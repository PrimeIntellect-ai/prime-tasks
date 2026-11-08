#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import tarfile
import time
import urllib.error
import urllib.request

import pytest

PROJECT_DIR = "/home/user/project"
BUILD_DIR = os.path.join(PROJECT_DIR, "build")
ARTIFACTS_DIR = os.path.join(PROJECT_DIR, "artifacts")
ORCHESTRATOR = os.path.join(PROJECT_DIR, "build_orchestrator.py")
INTEGRATION_TEST = os.path.join(PROJECT_DIR, "test_integration.py")
PROBE = "/tmp/orchestrator_pytest_ran"


def process_cmdline(pid):
    try:
        return Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def stop_recorded_server():
    pid_file = os.path.join(ARTIFACTS_DIR, "server.pid")
    try:
        value = Path(pid_file).read_text().strip()
        pid = int(value)
    except (OSError, ValueError):
        return
    cmdline = process_cmdline(pid)
    if "http.server" not in cmdline or "8080" not in cmdline:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return
    for _ in range(30):
        if not os.path.exists(f"/proc/{pid}"):
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass


def clean_outputs():
    stop_recorded_server()
    for directory in (BUILD_DIR, ARTIFACTS_DIR):
        shutil.rmtree(directory, ignore_errors=True)
        os.makedirs(directory, exist_ok=True)
    try:
        os.unlink(os.path.join(PROJECT_DIR, "build_order.txt"))
    except FileNotFoundError:
        pass
    try:
        os.unlink(PROBE)
    except FileNotFoundError:
        pass


def wait_for_server():
    last_error = None
    for _ in range(50):
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/manifest.json", timeout=1) as response:
                if response.status == 200:
                    return
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    pytest.fail(f"HTTP server did not become ready: {last_error}")


def run_orchestrator():
    Path(PROBE).unlink(missing_ok=True)
    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp" + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["PYTEST_PLUGINS"] = "verification_probe"
    log_path = "/tmp/build_orchestrator.log"
    with open(log_path, "wb") as log:
        try:
            result = subprocess.run(
                ["python3", ORCHESTRATOR],
                cwd=PROJECT_DIR,
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=90,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("build_orchestrator.py timed out")
    output = Path(log_path).read_text(errors="replace")
    assert result.returncode == 0, f"build_orchestrator.py failed with {result.returncode}:\n{output}"
    assert Path(PROBE).is_file(), "build_orchestrator.py did not invoke pytest on test_integration.py"
    wait_for_server()


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    for path in (ORCHESTRATOR, INTEGRATION_TEST):
        assert os.path.isfile(path), f"Required Python artifact missing: {path}"
        assert stat.S_ISREG(os.lstat(path).st_mode), f"Required artifact is not a regular file: {path}"
        assert not os.path.islink(path), f"Required artifact must not be a symlink: {path}"

    Path("/tmp/verification_probe.py").write_text(
        "from pathlib import Path\n"
        "def pytest_collection_finish(session):\n"
        "    target = Path('/home/user/project/test_integration.py').resolve()\n"
        "    if any(Path(str(item.path)).resolve() == target for item in session.items):\n"
        "        Path('/tmp/orchestrator_pytest_ran').write_text('yes')\n"
    )

    deps_path = Path(PROJECT_DIR) / "deps.json"
    original_deps = deps_path.read_bytes()
    alternate_deps = {
        "transform": [],
        "math_ops": ["transform"],
        "test_integration": ["math_ops", "transform"],
    }
    try:
        deps_path.write_text(json.dumps(alternate_deps))
        clean_outputs()
        run_orchestrator()
        alternate_order = Path(PROJECT_DIR, "build_order.txt").read_text().strip()
        assert alternate_order == "transform,math_ops,test_integration", (
            "Orchestrator did not derive a topological order from deps.json"
        )
        assert os.stat(os.path.join(BUILD_DIR, "libtransform.so")).st_mtime_ns <= os.stat(
            os.path.join(BUILD_DIR, "libmath_ops.so")
        ).st_mtime_ns, "Libraries were not produced in the computed order"
    finally:
        stop_recorded_server()
        deps_path.write_bytes(original_deps)

    clean_outputs()
    run_orchestrator()
    yield


def test_build_order():
    build_order_path = os.path.join(PROJECT_DIR, "build_order.txt")
    assert os.path.isfile(build_order_path), f"Build order file missing: {build_order_path}"

    with open(build_order_path, "r") as f:
        content = f.read().strip()

    expected_order = "math_ops,transform,test_integration"
    assert content == expected_order, f"Expected build order '{expected_order}', but got '{content}'"
    assert os.stat(os.path.join(BUILD_DIR, "libmath_ops.so")).st_mtime_ns <= os.stat(
        os.path.join(BUILD_DIR, "libtransform.so")
    ).st_mtime_ns, "Libraries were not produced in the computed order"


def test_shared_libraries():
    lib_math = os.path.join(BUILD_DIR, "libmath_ops.so")
    lib_transform = os.path.join(BUILD_DIR, "libtransform.so")

    for lib in [lib_math, lib_transform]:
        assert os.path.isfile(lib), f"Shared library missing: {lib}"
        with open(lib, "rb") as f:
            magic = f.read(4)
            assert magic == b"\x7fELF", f"File {lib} is not a valid ELF file"

    math_lib = ctypes.CDLL(lib_math)
    transform_lib = ctypes.CDLL(lib_transform)
    math_lib.add.argtypes = [ctypes.c_int, ctypes.c_int]
    math_lib.add.restype = ctypes.c_int
    transform_lib.double_val.argtypes = [ctypes.c_int]
    transform_lib.double_val.restype = ctypes.c_int

    pairs = [(-41, 17), (0, 0), (123, -57), (1001, 99)]
    for left, right in pairs:
        assert math_lib.add(left, right) == left + right
    for value in (-37, 0, 13, 509):
        assert transform_lib.double_val(value) == value * 2


def run_integration_test():
    return subprocess.run(
        ["python3", "-m", "pytest", INTEGRATION_TEST, "-q"],
        cwd=PROJECT_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
    ).returncode


def compile_library(source, output):
    subprocess.run(
        ["gcc", "-shared", "-fPIC", source, "-o", output],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def test_integration_suite_exercises_both_libraries(tmp_path):
    lib_math = Path(BUILD_DIR) / "libmath_ops.so"
    lib_transform = Path(BUILD_DIR) / "libtransform.so"
    good_math = tmp_path / "good_math.so"
    good_transform = tmp_path / "good_transform.so"
    shutil.copy2(lib_math, good_math)
    shutil.copy2(lib_transform, good_transform)

    bad_math_c = tmp_path / "bad_math.c"
    bad_math_c.write_text("int add(int a, int b) { return a + b + 1; }\n")
    compile_library(str(bad_math_c), str(lib_math))
    try:
        assert run_integration_test() != 0, "test_integration.py does not detect an incorrect add implementation"
    finally:
        shutil.copy2(good_math, lib_math)

    bad_transform_c = tmp_path / "bad_transform.c"
    bad_transform_c.write_text("int double_val(int a) { return a * 2 + 1; }\n")
    compile_library(str(bad_transform_c), str(lib_transform))
    try:
        assert run_integration_test() != 0, "test_integration.py does not detect an incorrect double_val implementation"
    finally:
        shutil.copy2(good_transform, lib_transform)

    assert run_integration_test() == 0, "test_integration.py fails against the correctly built libraries"


def test_release_tarball():
    tarball_path = os.path.join(ARTIFACTS_DIR, "release.tar.gz")
    assert os.path.isfile(tarball_path), f"Tarball missing: {tarball_path}"

    expected_files = {"libmath_ops.so", "libtransform.so", "test_integration.py"}

    with tarfile.open(tarball_path, "r:gz") as tar:
        members = [os.path.basename(m.name) for m in tar.getmembers() if m.isfile()]
        for ef in expected_files:
            assert ef in members, f"File {ef} is missing from the release tarball"

        sources = {
            "libmath_ops.so": os.path.join(BUILD_DIR, "libmath_ops.so"),
            "libtransform.so": os.path.join(BUILD_DIR, "libtransform.so"),
            "test_integration.py": INTEGRATION_TEST,
        }
        for name, source in sources.items():
            matches = [m for m in tar.getmembers() if m.isfile() and os.path.basename(m.name) == name]
            assert len(matches) == 1, f"Tarball must contain exactly one {name}"
            assert tar.extractfile(matches[0]).read() == Path(source).read_bytes(), f"Tarball contains stale {name}"


def compute_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


def test_manifest_json():
    manifest_path = os.path.join(ARTIFACTS_DIR, "manifest.json")
    assert os.path.isfile(manifest_path), f"Manifest file missing: {manifest_path}"

    with open(manifest_path, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Manifest is not valid JSON")

    expected_keys = ["libmath_ops.so", "libtransform.so", "test_integration.py"]
    for key in expected_keys:
        assert key in manifest, f"Key {key} missing from manifest.json"
    assert set(manifest) == set(expected_keys), "manifest.json must contain exactly the required three keys"

    lib_math = os.path.join(BUILD_DIR, "libmath_ops.so")
    lib_transform = os.path.join(BUILD_DIR, "libtransform.so")
    test_integration = os.path.join(PROJECT_DIR, "test_integration.py")

    assert manifest["libmath_ops.so"] == compute_sha256(lib_math), "Hash mismatch for libmath_ops.so"
    assert manifest["libtransform.so"] == compute_sha256(lib_transform), "Hash mismatch for libtransform.so"
    assert manifest["test_integration.py"] == compute_sha256(test_integration), "Hash mismatch for test_integration.py"


def test_http_server_and_pid():
    pid_path = os.path.join(ARTIFACTS_DIR, "server.pid")
    assert os.path.isfile(pid_path), f"PID file missing: {pid_path}"

    with open(pid_path, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file does not contain a valid integer: {pid_str}"
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} is not running")

    cmdline = process_cmdline(pid)
    assert "http.server" in cmdline and "8080" in cmdline, "Recorded PID is not the required http.server process"

    try:
        req = urllib.request.urlopen("http://127.0.0.1:8080/manifest.json", timeout=2)
        content = req.read()
        assert req.status == 200, "HTTP server did not return 200 OK for manifest.json"

        with open(os.path.join(ARTIFACTS_DIR, "manifest.json"), "rb") as f:
            local_content = f.read()

        assert content == local_content, "HTTP server served incorrect content for manifest.json"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to HTTP server on port 8080: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
