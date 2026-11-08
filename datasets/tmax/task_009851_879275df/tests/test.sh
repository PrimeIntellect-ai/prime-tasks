#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import stat
import subprocess
import sys
from collections import deque

import pytest

try:
    import tomllib
except ImportError:
    tomllib = None

PROJECT = "/home/user/polybuild"
SOURCE = f"{PROJECT}/src/polybuild/ring_buffer.py"


def load_ring_buffer():
    sys.path.insert(0, f"{PROJECT}/src")
    try:
        from polybuild.ring_buffer import RingBuffer
    except ImportError as e:
        pytest.fail(f"Failed to import RingBuffer from polybuild.ring_buffer: {e}")
    return RingBuffer


def test_ring_buffer_implementation():
    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."
    RingBuffer = load_ring_buffer()

    # Preserve the original required checks.
    rb = RingBuffer(2)
    with pytest.raises(IndexError) as excinfo:
        rb.pop()
    assert "empty" in str(excinfo.value).lower(), "Expected IndexError with 'empty' message when popping from empty buffer."

    rb.push(1)
    rb.push(2)
    rb.push(3)
    val = rb.pop()
    assert val == 2, f"Expected 2, got {val}. The oldest element was not correctly overwritten or popped."
    val2 = rb.pop()
    assert val2 == 3, f"Expected 3, got {val2}."
    with pytest.raises(IndexError):
        rb.pop()

    # Exercise several capacities and dynamically generated operation sequences
    # against an independently maintained bounded FIFO model.
    rng = random.SystemRandom()
    for capacity in (1, 3, 5, 8):
        rb = RingBuffer(capacity)
        model = deque(maxlen=capacity)
        for _ in range(120):
            if not model or rng.randrange(100) < 68:
                value = rng.randrange(-10**9, 10**9)
                rb.push(value)
                model.append(value)
            else:
                assert rb.pop() == model.popleft()

        while model:
            assert rb.pop() == model.popleft()
        with pytest.raises(IndexError) as excinfo:
            rb.pop()
        assert str(excinfo.value) == "Buffer is empty"


def test_pyproject_toml_fixed():
    toml_file = f"{PROJECT}/pyproject.toml"
    assert os.path.isfile(toml_file), f"File {toml_file} does not exist."

    if tomllib is None:
        pytest.fail("tomllib is required to validate pyproject.toml")

    with open(toml_file, "rb") as f:
        data = tomllib.load(f)

    # Preserve the original build-system and project assertions.
    build_system = data.get("build-system", {})
    requires = build_system.get("requires", [])
    assert any("setuptools" in req.lower() for req in requires), "pyproject.toml missing setuptools in build-system.requires"
    backend = build_system.get("build-backend", "")
    assert "setuptools" in backend, "pyproject.toml build-backend should use setuptools"

    project = data.get("project", {})
    assert project.get("name") == "polybuild", f"Expected project name 'polybuild', got {project.get('name')}"
    assert project.get("version") == "0.1.0", f"Expected project version '0.1.0', got {project.get('version')}"

    # Confirm setuptools is explicitly pointed at the src layout.
    setuptools_cfg = data.get("tool", {}).get("setuptools", {})
    package_dir = setuptools_cfg.get("package-dir", {})
    explicit_src = isinstance(package_dir, dict) and package_dir.get("") == "src"
    packages_cfg = setuptools_cfg.get("packages", {})
    find_cfg = packages_cfg.get("find", {}) if isinstance(packages_cfg, dict) else {}
    where = find_cfg.get("where", []) if isinstance(find_cfg, dict) else []
    if isinstance(where, str):
        where = [where]
    discovered_from_src = any(os.path.normpath(str(item)) == "src" for item in where)
    assert explicit_src or discovered_from_src, "setuptools is not configured to package modules from the src/ layout"


def test_ci_pipeline_execution():
    script_path = f"{PROJECT}/ci_pipeline.sh"
    log_path = f"{PROJECT}/ci_status.log"
    marker_path = "/tmp/polybuild_pipeline_ring_events.jsonl"

    assert os.path.isfile(script_path), f"File {script_path} does not exist."
    st = os.stat(script_path)
    assert st.st_mode & stat.S_IXUSR, f"Script {script_path} is not executable."

    if os.path.exists(log_path):
        os.remove(log_path)
    if os.path.exists(marker_path):
        os.remove(marker_path)

    # Start without a preinstalled copy so the pipeline must perform installation.
    shutil.rmtree(f"{PROJECT}/venv", ignore_errors=True)
    subprocess.run(
        [sys.executable, "-m", "pip", "uninstall", "-y", "polybuild"],
        cwd="/tmp",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )

    # Temporarily instrument the submitted class. A genuine pipeline test of the
    # required three pushes and pop will leave behavioral evidence. The source is
    # restored after execution.
    with open(SOURCE, "rb") as f:
        original_source = f.read()
    instrumentation = r'''

# Temporary verifier instrumentation
import json as _audit_json
_AUDIT_MARKER = "/tmp/polybuild_pipeline_ring_events.jsonl"
def _audit_write(event):
    with open(_AUDIT_MARKER, "a", encoding="utf-8") as _audit_f:
        _audit_f.write(_audit_json.dumps(event) + "\n")
_audit_original_init = RingBuffer.__init__
_audit_original_push = RingBuffer.push
_audit_original_pop = RingBuffer.pop
def _audit_init(self, size):
    result = _audit_original_init(self, size)
    _audit_write(["init", size])
    return result
def _audit_push(self, data):
    result = _audit_original_push(self, data)
    _audit_write(["push", data])
    return result
def _audit_pop(self):
    try:
        result = _audit_original_pop(self)
    except Exception as exc:
        _audit_write(["pop_error", type(exc).__name__, str(exc)])
        raise
    _audit_write(["pop", result])
    return result
RingBuffer.__init__ = _audit_init
RingBuffer.push = _audit_push
RingBuffer.pop = _audit_pop
'''

    try:
        with open(SOURCE, "ab") as f:
            f.write(instrumentation.encode("utf-8"))
        result = subprocess.run(
            [script_path],
            cwd=PROJECT,
            capture_output=True,
            text=True,
            timeout=180,
        )
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original_source)

    assert result.returncode == 0, f"ci_pipeline.sh failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    assert os.path.isfile(log_path), f"Log file {log_path} was not created by the script."
    with open(log_path, "r", encoding="utf-8") as f:
        log_content = f.read().strip()
    expected_log = "CI_SUCCESS: polybuild pipeline passed"
    assert log_content == expected_log, f"Expected log content '{expected_log}', got '{log_content}'"

    # Verify that the pipeline installed the distribution into either its local
    # virtual environment or the direct Python environment.
    interpreters = []
    venv_python = f"{PROJECT}/venv/bin/python"
    if os.path.isfile(venv_python):
        interpreters.append(venv_python)
    interpreters.append(sys.executable)

    probe = (
        "import importlib.metadata as m; "
        "import polybuild.ring_buffer; "
        "assert m.version('polybuild') == '0.1.0'"
    )
    installed = False
    clean_env = os.environ.copy()
    clean_env.pop("PYTHONPATH", None)
    for interpreter in dict.fromkeys(interpreters):
        check = subprocess.run(
            [interpreter, "-c", probe],
            cwd="/tmp",
            env=clean_env,
            capture_output=True,
            text=True,
        )
        if check.returncode == 0:
            installed = True
            break
    assert installed, "ci_pipeline.sh did not install the polybuild 0.1.0 distribution with its ring_buffer module"

    assert os.path.isfile(marker_path), "ci_pipeline.sh did not execute a RingBuffer behavioral test"
    with open(marker_path, "r", encoding="utf-8") as f:
        events = [json.loads(line) for line in f if line.strip()]

    # Find one contiguous required sequence: size 2, three pushes, then a pop
    # returning the second pushed value.
    exercised_required_case = False
    for i in range(max(0, len(events) - 4)):
        seq = events[i:i + 5]
        if (
            len(seq) == 5
            and seq[0] == ["init", 2]
            and seq[1][0] == "push"
            and seq[2][0] == "push"
            and seq[3][0] == "push"
            and seq[4][0] == "pop"
            and seq[4][1] == seq[2][1]
        ):
            exercised_required_case = True
            break
    assert exercised_required_case, "ci_pipeline.sh did not run the required size-2 overwrite test"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
