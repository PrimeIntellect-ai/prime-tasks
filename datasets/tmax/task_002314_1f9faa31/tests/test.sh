#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import py_compile
import secrets
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FINAL_REPORT_PATH = Path("/home/user/final_report.json")
MONOREPO_PATH = Path("/home/user/monorepo")
ORCHESTRATOR_PATH = Path("/home/user/orchestrator.py")

EXPECTED_DATA = {
    "core_cpp": {
        "module": "core_cpp",
        "status": "compiled",
        "value": 42
    },
    "utils_py": {
        "module": "utils_py",
        "status": "interpreted",
        "value": 10
    },
    "aggregator_py": {
        "module": "aggregator_py",
        "sum": 52,
        "dependencies_met": True
    },
    "final_cpp": {
        "module": "final_cpp",
        "complete": True
    }
}


def remove_build_outputs():
    for output_path in MONOREPO_PATH.rglob("output.json"):
        output_path.unlink()
    for binary in (
        MONOREPO_PATH / "core_cpp" / "main",
        MONOREPO_PATH / "final_cpp" / "final",
    ):
        if binary.exists() or binary.is_symlink():
            binary.unlink()
    if FINAL_REPORT_PATH.exists() or FINAL_REPORT_PATH.is_symlink():
        FINAL_REPORT_PATH.unlink()


def run_orchestrator():
    result = subprocess.run(
        [sys.executable, str(ORCHESTRATOR_PATH)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=90,
    )
    assert result.returncode == 0, "orchestrator.py failed:\n" + result.stdout


@pytest.fixture(scope="module", autouse=True)
def execute_submitted_orchestrator():
    assert ORCHESTRATOR_PATH.is_file(), f"{ORCHESTRATOR_PATH} does not exist or is not a file."
    assert not ORCHESTRATOR_PATH.is_symlink(), f"{ORCHESTRATOR_PATH} must be a submitted Python file, not a symlink."
    try:
        py_compile.compile(str(ORCHESTRATOR_PATH), doraise=True)
    except py_compile.PyCompileError as exc:
        pytest.fail(f"{ORCHESTRATOR_PATH} is not valid Python: {exc}")

    remove_build_outputs()
    run_orchestrator()


def test_final_report_exists():
    assert os.path.isfile(FINAL_REPORT_PATH), f"The final report file {FINAL_REPORT_PATH} does not exist."


def test_final_report_content():
    assert os.path.isfile(FINAL_REPORT_PATH), f"Cannot check content, {FINAL_REPORT_PATH} is missing."

    with open(FINAL_REPORT_PATH, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {FINAL_REPORT_PATH} does not contain valid JSON.")

    expected_data = EXPECTED_DATA

    # Check that all expected keys exist
    for key, expected_val in expected_data.items():
        assert key in report_data, f"Project '{key}' is missing from the final report."
        assert report_data[key] == expected_val, f"Data for project '{key}' is incorrect. Expected {expected_val}, got {report_data[key]}."

    # Check that no extra keys exist
    for key in report_data.keys():
        assert key in expected_data, f"Unexpected project '{key}' found in the final report."


def test_individual_outputs_exist():
    # If the build script ran correctly, these outputs should be present in the monorepo subdirectories.
    projects = ["core_cpp", "utils_py", "aggregator_py", "final_cpp"]

    for project in projects:
        output_path = os.path.join(MONOREPO_PATH, project, "output.json")
        assert os.path.isfile(output_path), f"The build output file {output_path} is missing. Did the build step for {project} run?"


def test_dynamic_discovery_dependency_order_cwd_and_build_execution():
    nonce = secrets.token_hex(16)
    root_name = "dynamic_root_" + nonce
    child_name = "dynamic_child_" + nonce
    # The dependent directory is created first and sorts before its dependency,
    # so directory traversal order cannot substitute for dependency resolution.
    child_dir = MONOREPO_PATH / ("aa_child_" + nonce)
    root_dir = MONOREPO_PATH / ("zz_root_" + nonce)
    root_sentinel = Path("/tmp/root_build_" + nonce)
    child_sentinel = Path("/tmp/child_build_" + nonce)
    root_command = "root_step_" + nonce + ".py"
    root_output_command = "root_output_" + nonce + ".py"
    child_command = "child_step_" + nonce + ".py"

    child_dir.mkdir()
    root_dir.mkdir()

    try:
        (child_dir / "manifest.json").write_text(json.dumps({
            "name": child_name,
            "deps": [root_name],
            "build_steps": [f"python3 {child_command}"]
        }))
        (root_dir / "manifest.json").write_text(json.dumps({
            "name": root_name,
            "deps": ["final_cpp"],
            "build_steps": [
                f"python3 {root_command}",
                f"python3 {root_output_command}"
            ]
        }))

        (root_dir / root_command).write_text(
            "from pathlib import Path\n"
            "import os\n"
            f"assert Path.cwd() == Path({str(root_dir)!r})\n"
            f"Path({str(root_sentinel)!r}).write_text({nonce!r})\n"
            f"Path('ready').write_text({nonce!r})\n"
        )
        root_value = {"nonce": nonce, "kind": "dynamic root", "cwd_ok": True}
        (root_dir / root_output_command).write_text(
            "from pathlib import Path\n"
            "import json\n"
            f"assert Path.cwd() == Path({str(root_dir)!r})\n"
            f"assert Path('ready').read_text() == {nonce!r}\n"
            f"assert Path({str(root_sentinel)!r}).read_text() == {nonce!r}\n"
            f"Path('output.json').write_text(json.dumps({root_value!r}))\n"
        )

        child_value = {"nonce": nonce, "kind": "dynamic child", "dependency_seen": True}
        (child_dir / child_command).write_text(
            "from pathlib import Path\n"
            "import json\n"
            f"assert Path.cwd() == Path({str(child_dir)!r})\n"
            f"parent = json.loads(Path('../{root_dir.name}/output.json').read_text())\n"
            f"assert parent == {root_value!r}\n"
            f"assert Path({str(root_sentinel)!r}).read_text() == {nonce!r}\n"
            f"Path({str(child_sentinel)!r}).write_text({nonce!r})\n"
            f"Path('output.json').write_text(json.dumps({child_value!r}))\n"
        )

        remove_build_outputs()
        run_orchestrator()

        assert root_sentinel.read_text() == nonce, "The dynamically supplied root build step was not executed."
        assert child_sentinel.read_text() == nonce, "The dynamically supplied dependent build step was not executed."
        assert json.loads((root_dir / "output.json").read_text()) == root_value
        assert json.loads((child_dir / "output.json").read_text()) == child_value

        with open(FINAL_REPORT_PATH) as f:
            report = json.load(f)
        expected = dict(EXPECTED_DATA)
        expected[root_name] = root_value
        expected[child_name] = child_value
        assert report == expected, "The report was not dynamically aggregated from all manifest-defined projects."
    finally:
        shutil.rmtree(child_dir, ignore_errors=True)
        shutil.rmtree(root_dir, ignore_errors=True)
        root_sentinel.unlink(missing_ok=True)
        child_sentinel.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
