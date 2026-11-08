#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

WORKSPACE = "/home/user/workspace"
MANIFEST = os.path.join(WORKSPACE, "manifest.txt")
MRE_SCRIPT = os.path.join(WORKSPACE, "mre_race.sh")
PROCESS_ASSETS_SH = os.path.join(WORKSPACE, "process_assets.sh")
COMPILE_SH = os.path.join(WORKSPACE, "compile.sh")
BUILD_SH = os.path.join(WORKSPACE, "build.sh")


def manifest_lines():
    assert os.path.isfile(MANIFEST), f"Manifest file {MANIFEST} is missing. Did you run build.sh?"
    with open(MANIFEST, "r") as f:
        return [line.strip() for line in f.read().splitlines() if line.strip()]


def assert_original_manifest_checks():
    lines = manifest_lines()
    png_count = sum(1 for line in lines if line.endswith(".png"))
    co_count = sum(1 for line in lines if line.endswith(".c.o"))
    assert png_count == 100, f"Expected exactly 100 .png entries in {MANIFEST}, but found {png_count}."
    assert co_count == 100, f"Expected exactly 100 .c.o entries in {MANIFEST}, but found {co_count}."
    assert len(lines) == 200, f"Expected exactly 200 valid entries in {MANIFEST}, but found {len(lines)}."


def run_process(command, timeout=20):
    proc = subprocess.Popen(
        command,
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        raise AssertionError(f"Command timed out: {command}\nstdout:\n{stdout}\nstderr:\n{stderr}")
    assert proc.returncode == 0, (
        f"Command failed with status {proc.returncode}: {command}\n"
        f"stdout:\n{stdout}\nstderr:\n{stderr}"
    )
    return stdout, stderr


def run_pair(asset_root, source_root, timeout=20):
    with open(MANIFEST, "w"):
        pass

    procs = [
        subprocess.Popen(
            [PROCESS_ASSETS_SH, asset_root], cwd=WORKSPACE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            start_new_session=True,
        ),
        subprocess.Popen(
            [COMPILE_SH, source_root], cwd=WORKSPACE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            start_new_session=True,
        ),
    ]
    deadline = time.monotonic() + timeout
    results = []
    try:
        for proc in procs:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(proc.args, timeout)
            results.append((proc, *proc.communicate(timeout=remaining)))
    except subprocess.TimeoutExpired:
        for proc in procs:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
        for proc in procs:
            proc.communicate()
        raise AssertionError("Concurrent scripts did not terminate; filesystem recursion may still follow a loop.")

    for proc, stdout, stderr in results:
        assert proc.returncode == 0, (
            f"{proc.args[0]} failed with status {proc.returncode}\n"
            f"stdout:\n{stdout}\nstderr:\n{stderr}"
        )


def test_complete_solution():
    # Retain the original delivered-artifact assertions before regenerating anything.
    assert os.path.isfile(MRE_SCRIPT), f"Minimal reproducible example script {MRE_SCRIPT} is missing."
    assert_original_manifest_checks()

    for path in (BUILD_SH, PROCESS_ASSETS_SH, COMPILE_SH, MRE_SCRIPT):
        assert os.path.isfile(path), f"Required script is missing: {path}"
        assert os.access(path, os.X_OK), f"Required script is not executable: {path}"
        run_process(["bash", "-n", path], timeout=5)

    with open(PROCESS_ASSETS_SH, "r") as f:
        process_content = f.read()
    with open(COMPILE_SH, "r") as f:
        compile_content = f.read()

    unsafe_pattern = 'contents=$(cat /home/user/workspace/manifest.txt)\n            echo -e "${contents}\\n$f" > /home/user/workspace/manifest.txt'
    unsafe_pattern_compile = 'contents=$(cat /home/user/workspace/manifest.txt)\n        echo -e "${contents}\\n$f.o" > /home/user/workspace/manifest.txt'
    assert unsafe_pattern not in process_content, "The original race condition pattern is still present in process_assets.sh."
    assert unsafe_pattern_compile not in compile_content, "The original race condition pattern is still present in compile.sh."

    # Actually execute the requested final build and verify its derived output exactly.
    run_process([BUILD_SH], timeout=20)
    expected_assets = {
        os.path.join(WORKSPACE, "assets", f"file_{i}.png") for i in range(1, 101)
    }
    expected_objects = {
        os.path.join(WORKSPACE, "src", f"source_{i}.c") + ".o" for i in range(1, 101)
    }
    assert set(manifest_lines()) == expected_assets | expected_objects
    assert_original_manifest_checks()

    # Exercise both patched workers concurrently on verifier-created names and a
    # recursive asset tree containing a symlink loop. This prevents fabricated
    # manifests and empty scripts from passing and stresses synchronization.
    for round_no in range(3):
        root = tempfile.mkdtemp(prefix="build-verifier-")
        try:
            token = uuid.uuid4().hex
            assets = os.path.join(root, "assets")
            nested = os.path.join(assets, "modules", "nested")
            sources = os.path.join(root, "src")
            os.makedirs(nested)
            os.makedirs(sources)
            os.symlink(assets, os.path.join(nested, "loop"))

            asset_files = []
            for i in range(70):
                path = os.path.join(assets, f"asset_{token}_{round_no}_{i}.png")
                open(path, "w").close()
                asset_files.append(path)
            for i in range(50):
                path = os.path.join(nested, f"nested_{token}_{round_no}_{i}.dat")
                open(path, "w").close()
                asset_files.append(path)

            source_files = []
            for i in range(120):
                path = os.path.join(sources, f"unit_{token}_{round_no}_{i}.c")
                open(path, "w").close()
                source_files.append(path)

            run_pair(assets, sources)
            expected = set(asset_files) | {path + ".o" for path in source_files}
            actual = manifest_lines()
            assert len(actual) == len(expected), (
                f"Concurrent update lost or duplicated entries: expected {len(expected)}, got {len(actual)}"
            )
            assert set(actual) == expected, "Workers did not register exactly the verifier-created input files."
        finally:
            shutil.rmtree(root, ignore_errors=True)

    # Validate and execute the standalone race reproducer. It must contain an
    # unlocked read/overwrite race and produce observable loss among ten writers.
    with open(MRE_SCRIPT, "r") as f:
        mre_content = f.read()
    assert "flock" not in mre_content, "The MRE must reproduce the original race without locking."
    assert re.search(r"(^|\n)\s*(function\s+\w+|\w+\s*\(\s*\))", mre_content), "The MRE must define a bash function."
    assert "&" in mre_content and re.search(r"\bwait\b", mre_content), "The MRE must launch background jobs and wait for them."
    assert re.search(r"\b10\b", mre_content), "The MRE must spawn ten workers."
    assert "mre_test.txt" in mre_content, "The MRE must use mre_test.txt."
    assert ("cat" in mre_content or "$(<" in mre_content) and ">" in mre_content, "The MRE must read and overwrite the shared file."

    observed_loss = False
    mre_output = os.path.join(WORKSPACE, "mre_test.txt")
    for _ in range(6):
        if os.path.lexists(mre_output):
            os.unlink(mre_output)
        run_process([MRE_SCRIPT], timeout=15)
        assert os.path.isfile(mre_output), "Executing mre_race.sh did not create mre_test.txt."
        with open(mre_output, "r") as f:
            entries = [line for line in f.read().splitlines() if line.strip()]
        if 0 < len(entries) < 10:
            observed_loss = True
            break
    assert observed_loss, "mre_race.sh did not demonstrate data loss from ten unlocked updates."

    # Restore and recheck the requested final workspace state.
    run_process([BUILD_SH], timeout=20)
    assert set(manifest_lines()) == expected_assets | expected_objects
    assert_original_manifest_checks()

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
