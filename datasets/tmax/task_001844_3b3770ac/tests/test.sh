#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import importlib.metadata
import json
import os
import random
import shlex
import subprocess
import uuid
from pathlib import Path
from urllib.parse import unquote, urlparse

import pytest

DETECTOR = Path("/home/user/detect_bad_spectrum.sh")
ORCHESTRATOR = Path("/home/user/orchestrate.sh")
VENDORED = Path("/app/vendored/papermill-2.3.4")


def run(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, timeout=kwargs.pop("timeout", 30), **kwargs)


def test_papermill_installed_and_fixed():
    """Keep the CLI check and verify that the fixed vendored 2.3.4 package is installed."""
    try:
        result = subprocess.run(
            ["papermill", "--help"],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
        assert "Usage:" in result.stdout or "papermill" in result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"papermill is not properly installed or the typo is not fixed. Running papermill --help failed with: {e.stderr}")
    except FileNotFoundError:
        pytest.fail("papermill command not found. It was not installed correctly.")

    vendor_cli = VENDORED / "papermill" / "cli.py"
    assert vendor_cli.is_file(), "Vendored papermill source is missing"
    source = vendor_cli.read_text()
    tree = ast.parse(source)
    imports = {
        alias.name
        for node in ast.walk(tree)
        if isinstance(node, ast.Import)
        for alias in node.names
    }
    assert "click" in imports, "The vendored CLI's broken click import was not fixed"
    assert "clik" not in imports, "The vendored CLI still imports clik"

    dist = importlib.metadata.distribution("papermill")
    assert dist.version == "2.3.4"
    import papermill.cli

    installed_cli = Path(papermill.cli.__file__).resolve()
    vendor_root = VENDORED.resolve()
    installed_from_vendor = vendor_root == installed_cli or vendor_root in installed_cli.parents

    direct_url_text = dist.read_text("direct_url.json")
    if direct_url_text:
        direct_url = json.loads(direct_url_text).get("url", "")
        parsed = urlparse(direct_url)
        source_path = Path(unquote(parsed.path)).resolve() if parsed.scheme == "file" else None
        if source_path is not None and (source_path == vendor_root or vendor_root in source_path.parents):
            installed_from_vendor = True

    if not installed_from_vendor:
        assert installed_cli.read_bytes() == vendor_cli.read_bytes(), (
            "Installed papermill CLI does not correspond to the repaired vendored source"
        )


def test_scripts_exist_and_executable():
    """Check that the required bash scripts exist and are executable."""
    detector = "/home/user/detect_bad_spectrum.sh"
    orchestrator = "/home/user/orchestrate.sh"

    assert os.path.isfile(detector), f"Script {detector} does not exist."
    assert os.access(detector, os.X_OK), f"Script {detector} is not executable."

    assert os.path.isfile(orchestrator), f"Script {orchestrator} does not exist."
    assert os.access(orchestrator, os.X_OK), f"Script {orchestrator} is not executable."


def test_adversarial_corpus_detector():
    """Retain the original clean/evil corpus assertions."""
    detector = str(DETECTOR)
    clean_files = glob.glob("/app/corpora/clean/*.csv")
    evil_files = glob.glob("/app/corpora/evil/*.csv")

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failures = []
    for f in clean_files:
        result = run([detector, f])
        if result.returncode != 0 or result.stdout.strip() != "VALID":
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = run([detector, f])
        if result.returncode != 1 or result.stdout.strip() != "INVALID":
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failures)}")
    if error_msgs:
        pytest.fail("Corpus verification failed:\n" + "\n".join(error_msgs))


def test_detector_on_generated_content(tmp_path):
    """Exercise content-derived cases under unpredictable, label-free filenames."""
    rng = random.SystemRandom()
    start = rng.uniform(-500, 500)
    steps = [rng.uniform(0.01, 20) for _ in range(6)]
    xs = []
    current = start
    for step in steps:
        current += step
        xs.append(current)
    ys = [rng.uniform(-1000, 1000) for _ in xs]

    valid = "".join(f"{x:.12g}, {y:.12g}\n" for x, y in zip(xs, ys))
    duplicate = list(xs)
    duplicate[3] = duplicate[2]
    decreasing = list(xs)
    decreasing[3], decreasing[4] = decreasing[4], decreasing[3]

    cases = [
        (valid, 0, "VALID"),
        ("".join(f"{x:.12g},{y:.12g}\n" for x, y in zip(duplicate, ys)), 1, "INVALID"),
        ("".join(f"{x:.12g},{y:.12g}\n" for x, y in zip(decreasing, ys)), 1, "INVALID"),
        (f"{xs[0]},1\n{xs[1]},NaN\n{xs[2]},2\n", 1, "INVALID"),
        (f"{xs[0]},1\n{xs[1]},nan\n{xs[2]},2\n", 1, "INVALID"),
        (f"{xs[0]},1\n{xs[1]},Inf\n{xs[2]},2\n", 1, "INVALID"),
        (f"{xs[0]},1\n{xs[1]},inf\n{xs[2]},2\n", 1, "INVALID"),
        (f"{xs[0]},1\nNaN,2\n{xs[2]},3\n", 1, "INVALID"),
    ]
    rng.shuffle(cases)

    for content, expected_rc, expected_stdout in cases:
        path = tmp_path / (uuid.uuid4().hex + ".csv")
        path.write_text(content)
        result = run([str(DETECTOR), str(path)])
        assert result.returncode == expected_rc, (path.name, result.stdout, result.stderr)
        assert result.stdout.strip() == expected_stdout, (path.name, result.stdout, result.stderr)

    assert run([str(DETECTOR)]).returncode != 0, "Detector must require exactly one argument"
    extra = tmp_path / (uuid.uuid4().hex + ".csv")
    extra.write_text(valid)
    assert run([str(DETECTOR), str(extra), "extra"]).returncode != 0, "Detector must reject extra arguments"


def test_orchestrator_calls_detector_and_executes_papermill(tmp_path):
    """Run the orchestrator and verify filtering, parameterization, and real notebook execution."""
    input_dir = tmp_path / "inputs"
    output_dir = tmp_path / "outputs"
    input_dir.mkdir()
    output_dir.mkdir()

    token = uuid.uuid4().hex
    valid_paths = [
        input_dir / f"{token} alpha.csv",
        input_dir / f"{uuid.uuid4().hex}.csv",
    ]
    invalid_paths = [
        input_dir / f"{uuid.uuid4().hex}.csv",
        input_dir / f"{token} omega.csv",
    ]
    valid_paths[0].write_text("-3.5,0.2\n-1.25,0.4\n0.0,0.8\n7.75,0.1\n")
    valid_paths[1].write_text("1e-3,-2\n2e-3,0\n9e-2,4.5\n1e2,3\n")
    invalid_paths[0].write_text("1,2\n3,4\n2,5\n4,6\n")
    invalid_paths[1].write_text("1,2\n2,inf\n3,4\n")

    backup = Path(f"/home/user/.detect_bad_spectrum.{uuid.uuid4().hex}")
    call_log = tmp_path / "detector_calls.log"
    os.replace(DETECTOR, backup)
    try:
        wrapper = (
            "#!/bin/bash\n"
            "printf '%s\\n' \"$1\" >> " + shlex.quote(str(call_log)) + "\n"
            "exec " + shlex.quote(str(backup)) + " \"$@\"\n"
        )
        DETECTOR.write_text(wrapper)
        DETECTOR.chmod(0o755)

        result = run([str(ORCHESTRATOR), str(input_dir), str(output_dir)], timeout=120)
        assert result.returncode == 0, f"orchestrator failed:\nstdout={result.stdout}\nstderr={result.stderr}"
    finally:
        if DETECTOR.exists():
            DETECTOR.unlink()
        os.replace(backup, DETECTOR)
        DETECTOR.chmod(0o755)

    assert call_log.is_file(), "Orchestrator did not call detect_bad_spectrum.sh"
    called = call_log.read_text().splitlines()
    expected_inputs = {str(p) for p in valid_paths + invalid_paths}
    assert set(called) == expected_inputs
    assert len(called) == len(expected_inputs), "Each CSV must be classified exactly once"

    for path in invalid_paths:
        out = output_dir / (path.name + "_out.ipynb")
        assert not out.exists(), f"Invalid input unexpectedly produced {out.name}"

    for path in valid_paths:
        out = output_dir / (path.name + "_out.ipynb")
        assert out.is_file(), f"Valid input did not produce {out.name}"
        notebook = json.loads(out.read_text())
        assert notebook.get("metadata", {}).get("papermill") is not None, "Output was not produced by papermill"
        sources = [
            "".join(cell.get("source", [])) if isinstance(cell.get("source", []), list) else cell.get("source", "")
            for cell in notebook.get("cells", [])
        ]
        assert any("input_file" in source and str(path) in source for source in sources), (
            "papermill was not given the required input_file parameter"
        )
        stream_text = "".join(
            output.get("text", "") if isinstance(output.get("text", ""), str) else "".join(output.get("text", []))
            for cell in notebook.get("cells", [])
            for output in cell.get("outputs", [])
            if output.get("output_type") == "stream"
        )
        assert "Processing" in stream_text and str(path) in stream_text, "Notebook was not actually executed for the input"

    assert run([str(ORCHESTRATOR)]).returncode != 0, "Orchestrator must require its two arguments"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
