#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile
import time


def run_filter(executable, limit, text):
    return subprocess.run(
        [executable, str(limit)],
        input=text.encode(),
        capture_output=True,
        timeout=10,
    )


def test_makefile_fixed():
    makefile_path = "/home/user/project/Makefile"
    assert os.path.isfile(makefile_path), "Makefile is missing."

    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-g" in content, "Makefile does not include debugging symbols (-g)."

    result = subprocess.run(
        ["make", "-C", "/home/user/project", "clean", "all"],
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, f"make failed:\n{result.stderr.decode()}"

    executable = "/home/user/project/artifact_filter"
    assert os.path.isfile(executable), "artifact_filter executable was not created."
    assert os.access(executable, os.X_OK), "artifact_filter is not executable."


def test_c_code_fixed_and_general_behavior():
    c_file = "/home/user/project/artifact_filter.c"
    assert os.path.isfile(c_file), "artifact_filter.c is missing."

    with open(c_file, "r") as f:
        content = f.read()
    assert "free(" in content, "artifact_filter.c does not contain a call to free()."

    built = subprocess.run(
        ["make", "-C", "/home/user/project", "all"],
        capture_output=True,
        timeout=30,
    )
    assert built.returncode == 0, f"make failed:\n{built.stderr.decode()}"

    executable = "/home/user/project/artifact_filter"

    valgrind_cmd = [
        "valgrind",
        "--leak-check=full",
        "--error-exitcode=255",
        executable,
        "100",
    ]
    result = subprocess.run(
        valgrind_cmd, input=b"size: 50\n", capture_output=True, timeout=30
    )
    assert result.returncode != 255, (
        f"Valgrind detected memory leaks or errors:\n{result.stderr.decode()}"
    )
    assert result.returncode == 0 and result.stdout == b"PASS\n"

    # Exercise unpredictable limits and both sides of the strict boundary.
    base = secrets.randbelow(50000) + 2000
    cases = [
        (base, base - 1, b"PASS\n", 0),
        (base, base, b"FAIL\n", 1),
        (base, base + 1, b"FAIL\n", 1),
        (base + 137, base + 12, b"PASS\n", 0),
        (base - 83, base + 19, b"FAIL\n", 1),
    ]
    for limit, size, expected_out, expected_rc in cases:
        result = run_filter(executable, limit, f"size: {size}\n")
        assert result.returncode == expected_rc, (
            f"wrong exit status for size={size}, limit={limit}: "
            f"{result.returncode}, stderr={result.stderr.decode(errors='replace')}"
        )
        assert result.stdout == expected_out, (
            f"wrong output for size={size}, limit={limit}: {result.stdout!r}"
        )

    # Also verify that the failing branch releases its allocations.
    result = subprocess.run(
        [
            "valgrind",
            "--leak-check=full",
            "--error-exitcode=255",
            executable,
            str(base),
        ],
        input=f"size: {base}\n".encode(),
        capture_output=True,
        timeout=30,
    )
    assert result.returncode != 255, (
        f"Valgrind detected memory errors on the FAIL path:\n{result.stderr.decode()}"
    )
    assert result.returncode == 1 and result.stdout == b"FAIL\n"


def test_ci_pipeline_script():
    script_path = "/home/user/ci_pipeline.sh"
    assert os.path.isfile(script_path), "ci_pipeline.sh is missing."
    assert os.access(script_path, os.X_OK), "ci_pipeline.sh is not executable."

    with open(script_path, "r") as f:
        content = f.read()
    assert "sleep 0.5" in content or "sleep .5" in content, (
        "ci_pipeline.sh does not contain the rate limit sleep (sleep 0.5)."
    )
    assert re.search(r"size:\s*50", content), (
        "ci_pipeline.sh does not feed size: 50 to its Valgrind check."
    )


def test_approved_log():
    log_path = "/home/user/approved.log"
    assert os.path.isfile(log_path), "approved.log is missing."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected = ["art1.txt", "art3.txt"]
    assert lines == expected, (
        f"approved.log content is incorrect. Expected {expected}, got {lines}."
    )


def test_pipeline_executes_and_filters_dynamic_artifacts():
    script_path = "/home/user/ci_pipeline.sh"
    artifacts = "/home/user/artifacts"
    log_path = "/home/user/approved.log"

    backup_root = tempfile.mkdtemp(prefix="pipeline-verifier-")
    backup_artifacts = os.path.join(backup_root, "artifacts")
    shutil.copytree(artifacts, backup_artifacts)
    old_log = None
    if os.path.exists(log_path):
        with open(log_path, "rb") as f:
            old_log = f.read()

    token = secrets.token_hex(5)
    dynamic = {
        f"alpha_{token}.txt": 999,
        f"equal_{token}.txt": 1000,
        f"large_{token}.txt": 1000 + secrets.randbelow(5000) + 1,
        f"small_{token}.txt": secrets.randbelow(900),
    }
    expected = sorted(name for name, size in dynamic.items() if size < 1000)

    try:
        shutil.rmtree(artifacts)
        os.makedirs(artifacts)
        for name, size in dynamic.items():
            with open(os.path.join(artifacts, name), "w") as f:
                f.write(f"size: {size}\n")
        with open(os.path.join(artifacts, f"ignored_{token}.dat"), "w") as f:
            f.write("size: 1\n")
        if os.path.exists(log_path):
            os.remove(log_path)

        started = time.monotonic()
        result = subprocess.run(
            ["bash", "-x", script_path],
            capture_output=True,
            text=True,
            timeout=40,
        )
        elapsed = time.monotonic() - started
        assert result.returncode == 0, (
            f"ci_pipeline.sh failed with {result.returncode}:\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(log_path), "Pipeline did not create approved.log."
        with open(log_path, "r") as f:
            actual = [line.strip() for line in f if line.strip()]
        assert actual == expected, (
            f"Pipeline did not derive the correct sorted approvals. "
            f"Expected {expected}, got {actual}."
        )

        trace_lines = [line.strip() for line in result.stderr.splitlines()]
        make_lines = [line for line in trace_lines if re.search(r"(?:^|\s)make\s+-C\s+/home/user/project\s+clean\s+all(?:\s|$)", line)]
        assert make_lines, "Executed pipeline did not run make -C /home/user/project clean all."

        vg_lines = [line for line in trace_lines if re.search(r"(?:^|\s)(?:\S*/)?valgrind(?:\s|$)", line)]
        assert vg_lines, "Executed pipeline did not run Valgrind."
        vg = " ".join(vg_lines)
        assert "--leak-check=full" in vg and "--error-exitcode=1" in vg, (
            "Pipeline Valgrind command is missing required options."
        )
        assert "/home/user/project/artifact_filter" in vg and re.search(r"\s100(?:\s|$)", vg), (
            "Pipeline did not run artifact_filter with limit 100 under Valgrind."
        )

        events = []
        for line in trace_lines:
            if re.search(r"(?:^|\s)/home/user/project/artifact_filter\s+1000(?:\s|$)", line):
                events.append("filter")
            elif re.search(r"^\++\s+sleep\s+(?:0?\.5|\.5)\s*$", line):
                events.append("sleep")
        assert events == [item for _ in dynamic for item in ("filter", "sleep")], (
            "Each .txt artifact must be passed to artifact_filter and immediately followed "
            f"by sleep 0.5; observed command sequence: {events}"
        )
        assert elapsed >= 0.45 * len(dynamic), (
            "Pipeline did not actually apply the required per-artifact delay."
        )
    finally:
        if os.path.exists(artifacts):
            shutil.rmtree(artifacts)
        shutil.copytree(backup_artifacts, artifacts)
        if old_log is None:
            if os.path.exists(log_path):
                os.remove(log_path)
        else:
            with open(log_path, "wb") as f:
                f.write(old_log)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
