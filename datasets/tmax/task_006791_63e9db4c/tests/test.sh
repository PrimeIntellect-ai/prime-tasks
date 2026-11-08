#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import heapq
import json
import os
import random
import re
import stat
import subprocess
import sys
import tempfile
import uuid

SCRIPT = "/home/user/merge_and_resolve.py"
ORDER = "/home/user/execution_order.txt"


def expected_order(jobs):
    indegree = {name: 0 for name in jobs}
    dependents = {name: [] for name in jobs}
    for name, spec in jobs.items():
        for dep in spec["deps"]:
            assert dep in jobs
            indegree[name] += 1
            dependents[dep].append(name)

    ready = [name for name, degree in indegree.items() if degree == 0]
    heapq.heapify(ready)
    result = []
    while ready:
        name = heapq.heappop(ready)
        result.append(name)
        for child in dependents[name]:
            indegree[child] -= 1
            if indegree[child] == 0:
                heapq.heappush(ready, child)
    assert len(result) == len(jobs)
    return " ".join(result) + "\n"


def run_script(directory, timeout=15):
    result = subprocess.run(
        [sys.executable, SCRIPT, directory],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Script failed for {directory}: stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(ORDER), "Script did not create execution_order.txt"
    with open(ORDER, "rb") as f:
        return f.read()


def write_graph(directory, jobs, rng):
    names = list(jobs)
    rng.shuffle(names)
    pieces = [names[::3], names[1::3], names[2::3]]
    for index, piece in enumerate(pieces):
        if piece:
            payload = {"jobs": {name: jobs[name] for name in piece}}
            with open(os.path.join(directory, f"part_{index}.json"), "w") as f:
                json.dump(payload, f)
    with open(os.path.join(directory, "ignored.txt"), "w") as f:
        f.write('{ this is deliberately not JSON }')


def test_complete_submission_and_behavior():
    # Preserve the original artifact-existence assertions before executing anything.
    assert os.path.isfile(SCRIPT), f"Python script not found at {SCRIPT}"
    assert not os.path.islink(SCRIPT), "merge_and_resolve.py must be a regular file"
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode)
    for path in (ORDER, "/home/user/order.diff", "/home/user/benchmark.txt"):
        assert os.path.isfile(path), f"Required artifact not found at {path}"

    # Enforce the standard-library-only requirement for statically declared imports.
    with open(SCRIPT, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=SCRIPT)
    stdlib = set(sys.stdlib_module_names)
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            modules = [alias.name.split(".")[0] for alias in node.names]
        elif isinstance(node, ast.ImportFrom):
            assert node.level == 0, "Local/relative imports are not permitted"
            modules = [node.module.split(".")[0]] if node.module else []
        else:
            continue
        for module in modules:
            assert module in stdlib, f"Non-standard-library import found: {module}"

    # Exercise the submitted script on independently generated DAGs.
    rng = random.SystemRandom()
    for case in range(4):
        count = 9 + case
        names = [f"n_{uuid.uuid4().hex[:10]}" for _ in range(count)]
        creation_order = names[:]
        rng.shuffle(creation_order)
        jobs = {}
        for i, name in enumerate(creation_order):
            possible = creation_order[:i]
            dep_count = rng.randrange(0, min(4, len(possible)) + 1)
            deps = rng.sample(possible, dep_count)
            rng.shuffle(deps)
            jobs[name] = {"deps": deps}

        with tempfile.TemporaryDirectory(prefix="resolver_case_") as directory:
            write_graph(directory, jobs, rng)
            actual = run_script(directory)
            expected = expected_order(jobs).encode()
            assert actual == expected, (
                f"Incorrect deterministic topological order. "
                f"Expected {expected!r}, got {actual!r}"
            )

    # Exercise the exact benchmark target through /usr/bin/time -v.
    with tempfile.NamedTemporaryFile(prefix="resolver_time_", delete=False) as timing:
        timing_path = timing.name
    try:
        with open(timing_path, "w") as timing_output:
            result = subprocess.run(
                ["/usr/bin/time", "-v", sys.executable, SCRIPT,
                 "/home/user/large_pipeline"],
                stdout=subprocess.PIPE,
                stderr=timing_output,
                text=True,
                timeout=20,
            )
        assert result.returncode == 0, "Script failed on large_pipeline under time -v"
        large_jobs = {
            "job_0": {"deps": []},
            "job_1": {"deps": ["job_0"]},
            "job_2": {"deps": ["job_0", "job_1"]},
            "job_3": {"deps": ["job_2"]},
            "job_4": {"deps": ["job_3"]},
            "job_5": {"deps": ["job_4", "job_1"]},
        }
        with open(ORDER, "rb") as f:
            assert f.read() == expected_order(large_jobs).encode()
        with open(timing_path, "r") as f:
            verifier_timing = f.read()
        assert "Maximum resident set size" in verifier_timing
        assert "Exit status: 0" in verifier_timing
    finally:
        os.unlink(timing_path)

    # Run the required small pipeline last, resolving the instruction's overwrite
    # ambiguity while retaining the original exact execution-order assertion.
    actual = run_script("/home/user/pipelines")
    expected_small = (
        "setup_env lint_core build_core build_plugin_a "
        "test_plugin_a deploy_all\n"
    ).encode()
    assert actual == expected_small

    # Original execution_order.txt assertions.
    order_path = "/home/user/execution_order.txt"
    assert os.path.isfile(order_path), f"Execution order file not found at {order_path}"
    with open(order_path, "r") as f:
        content = f.read()
    expected_text = "setup_env lint_core build_core build_plugin_a test_plugin_a deploy_all"
    assert content.strip() == expected_text, f"Execution order is incorrect. Got: {content.strip()}"
    assert content.endswith("\n"), "Execution order file must have a trailing newline."

    # Retain the original diff checks and verify the complete unified-diff hunk.
    diff_path = "/home/user/order.diff"
    assert os.path.isfile(diff_path), f"Diff file not found at {diff_path}"
    with open(diff_path, "r") as f:
        diff_content = f.read()
    assert "---" in diff_content and "+++" in diff_content, "Diff file does not appear to be a unified diff."
    assert "old_order.txt" in diff_content, "Diff does not contain a reference to old_order.txt."
    assert "execution_order.txt" in diff_content, "Diff does not contain a reference to execution_order.txt."
    assert diff_content.endswith("\n"), "Unified diff must end with a newline"
    lines = diff_content.splitlines()
    assert lines[0].startswith("--- ") and "old_order.txt" in lines[0]
    assert lines[1].startswith("+++ ") and "execution_order.txt" in lines[1]
    hunk_index = next((i for i, line in enumerate(lines) if line.startswith("@@")), None)
    assert hunk_index is not None, "Diff is missing a unified-diff hunk"
    assert lines[hunk_index:] == [
        "@@ -1 +1 @@",
        "-setup_env build_core lint_core deploy_all build_plugin_a test_plugin_a",
        "+setup_env lint_core build_core build_plugin_a test_plugin_a deploy_all",
    ], "order.diff does not describe the required old and new orders"

    # Retain the original benchmark checks and require a successful relevant command.
    bench_path = "/home/user/benchmark.txt"
    assert os.path.isfile(bench_path), f"Benchmark output file not found at {bench_path}"
    with open(bench_path, "r") as f:
        bench_content = f.read()
    assert "Maximum resident set size" in bench_content, "Benchmark file does not contain expected output from '/usr/bin/time -v'."
    assert "User time" in bench_content, "Benchmark file does not contain expected output from '/usr/bin/time -v'."
    assert "Command being timed" in bench_content
    assert "/home/user/merge_and_resolve.py" in bench_content
    assert "/home/user/large_pipeline" in bench_content
    assert re.search(r"Exit status:\s*0(?:\D|$)", bench_content), "Benchmark did not record a successful run"
    assert "Elapsed (wall clock) time" in bench_content

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
