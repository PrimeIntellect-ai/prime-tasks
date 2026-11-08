#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import runpy
import secrets
import shutil
import subprocess
import sys
import tempfile
import types

APP_DIR = "/home/user/app"
GENERATOR = os.path.join(APP_DIR, "generate_limits.py")


def extract_arms(content):
    return [(path, int(limit)) for path, limit in re.findall(
        r'"([^"]+)"\s*=>\s*Some\((\d+)\)', content
    )]


def expected_from_specs():
    merged = {}
    specs_dir = os.path.join(APP_DIR, "specs")
    for name in os.listdir(specs_dir):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(specs_dir, name)) as f:
            data = json.load(f)
        for path, limit in data.items():
            merged[path] = min(merged.get(path, limit), limit)
    return sorted(merged.items())


def test_generator_handles_derived_duplicate_inputs_end_to_end():
    """Execute the generator on unpredictable duplicate and unsorted inputs."""
    token = secrets.token_hex(8)
    duplicate = f"/api/v9/verify_{token}"
    other = f"/api/v8/verify_{token}"
    high = secrets.randbelow(5000) + 5001
    low = secrets.randbelow(4000) + 1
    extra_spec = os.path.join(APP_DIR, "specs", f"verifier_{token}.json")

    with open(extra_spec, "w") as f:
        json.dump({duplicate: high, other: high + 7}, f)
    second_spec = os.path.join(APP_DIR, "specs", f"verifier_second_{token}.json")
    with open(second_spec, "w") as f:
        json.dump({duplicate: low}, f)

    dynamic_result = None
    dynamic_output = ""
    restore_result = None
    try:
        expected = expected_from_specs()
        dynamic_result = subprocess.run(
            ["python3", GENERATOR], cwd=APP_DIR, capture_output=True, text=True
        )
        if dynamic_result.returncode == 0:
            with open(os.path.join(APP_DIR, "src", "limits.rs")) as f:
                dynamic_output = f.read()
    finally:
        for path in (extra_spec, second_spec):
            if os.path.exists(path):
                os.remove(path)
        restore_result = subprocess.run(
            ["python3", GENERATOR], cwd=APP_DIR, capture_output=True, text=True
        )

    assert dynamic_result is not None and dynamic_result.returncode == 0, (
        dynamic_result.stderr if dynamic_result else "generator was not run"
    )
    assert extract_arms(dynamic_output) == expected, (
        "generate_limits.py did not dynamically merge duplicates by minimum "
        "and sort all endpoint paths"
    )
    assert restore_result.returncode == 0, restore_result.stderr


def test_generate_limits_fixed():
    """Keep the original exact assertion for the shipped specifications."""
    limits_rs_path = os.path.join(APP_DIR, "src", "limits.rs")
    assert os.path.isfile(limits_rs_path), "src/limits.rs is missing."

    with open(limits_rs_path, "r") as f:
        content = f.read()

    arms = re.findall(r'"(/api/v[^"]+)"\s*=>\s*Some\((\d+)\)', content)
    expected_arms = [
        ("/api/v1/admin", 5),
        ("/api/v1/posts", 50),
        ("/api/v1/users", 80),
        ("/api/v2/comments", 200),
        ("/api/v2/tags", 500),
        ("/api/v3/status", 1000),
    ]
    actual_arms = [(path, int(limit)) for path, limit in arms]
    assert actual_arms == expected_arms, (
        f"Expected match arms {expected_arms}, but got {actual_arms}. "
        "Check sorting and minimum logic."
    )


def test_unit_test_exists_and_passes_and_detects_bugs():
    """Require a real unittest that detects both the merge and sorting defects."""
    test_file = os.path.join(APP_DIR, "test_generate.py")
    assert os.path.isfile(test_file), "test_generate.py is missing."

    result = subprocess.run(
        ["python3", "-m", "unittest", test_file],
        cwd=APP_DIR,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"test_generate.py failed to run or tests failed:\n{result.stderr}\n{result.stdout}"
    )
    report = result.stdout + result.stderr
    match = re.search(r"Ran\s+(\d+)\s+tests?", report)
    assert match and int(match.group(1)) > 0, "test_generate.py contains no runnable unittest tests."

    with open(test_file) as f:
        tree = ast.parse(f.read(), test_file)
    calls_merge = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "merge_specs"
        for node in ast.walk(tree)
    )
    imports_merge = any(
        isinstance(node, ast.ImportFrom)
        and node.module == "generate_limits"
        and any(alias.name == "merge_specs" for alias in node.names)
        for node in ast.walk(tree)
    )
    assert imports_merge and calls_merge, "The unit test must import and exercise merge_specs."

    mutants = [
        '''import json\ndef merge_specs(spec_files):\n    merged = []\n    for f in spec_files:\n        with open(f) as fp:\n            merged.extend(json.load(fp).items())\n    return merged\n''',
        '''import json\ndef merge_specs(spec_files):\n    merged = {}\n    for f in spec_files:\n        with open(f) as fp:\n            for path, limit in json.load(fp).items():\n                merged[path] = min(merged.get(path, limit), limit)\n    return list(merged.items())\n''',
    ]
    for mutant in mutants:
        with tempfile.TemporaryDirectory() as td:
            shutil.copy2(test_file, os.path.join(td, "test_generate.py"))
            with open(os.path.join(td, "generate_limits.py"), "w") as f:
                f.write(mutant)
            bad = subprocess.run(
                ["python3", "-m", "unittest", "test_generate.py"],
                cwd=td,
                capture_output=True,
                text=True,
            )
            assert bad.returncode != 0, (
                "test_generate.py passed a deliberately defective merge_specs implementation"
            )


def test_tracemalloc_is_used_to_write_the_measured_peak():
    with open(GENERATOR) as f:
        source = f.read()
    tree = ast.parse(source, GENERATOR)
    assert "peak_memory.txt" in source, "Generator does not name peak_memory.txt."

    main_blocks = [
        node for node in tree.body
        if isinstance(node, ast.If)
        and isinstance(node.test, ast.Compare)
        and any(isinstance(n, ast.Name) and n.id == "__name__" for n in ast.walk(node.test))
    ]
    assert main_blocks and main_blocks[0].body, "Generator has no executable main block."
    first_statement = main_blocks[0].body[0]
    first_has_start = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id == "tracemalloc"
        and node.func.attr == "start"
        for node in ast.walk(first_statement)
    )
    assert first_has_start, "tracemalloc.start() must be at the beginning of the main block."

    peak_file = os.path.join(APP_DIR, "peak_memory.txt")
    sentinel = 987654321
    events = []
    fake = types.ModuleType("tracemalloc")
    fake.start = lambda *args, **kwargs: events.append("start")
    fake.get_traced_memory = lambda: (12345, sentinel)
    fake.stop = lambda: events.append("stop")
    fake.reset_peak = lambda: None

    old_module = sys.modules.get("tracemalloc")
    old_cwd = os.getcwd()
    try:
        sys.modules["tracemalloc"] = fake
        os.chdir(APP_DIR)
        if os.path.exists(peak_file):
            os.remove(peak_file)
        runpy.run_path(GENERATOR, run_name="__main__")
        assert events and events[0] == "start", "The generator did not start tracemalloc."
        assert os.path.isfile(peak_file), "peak_memory.txt is missing."
        with open(peak_file) as f:
            measured = f.read().strip()
        assert measured == str(sentinel), (
            "peak_memory.txt was not written from tracemalloc.get_traced_memory()'s peak value"
        )
    finally:
        os.chdir(old_cwd)
        if old_module is None:
            sys.modules.pop("tracemalloc", None)
        else:
            sys.modules["tracemalloc"] = old_module

    real_run = subprocess.run(
        ["python3", GENERATOR], cwd=APP_DIR, capture_output=True, text=True
    )
    assert real_run.returncode == 0, real_run.stderr


def test_cargo_build_succeeds():
    result = subprocess.run(["cargo", "build"], cwd=APP_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"cargo build failed:\n{result.stderr}"


def test_peak_memory_file():
    mem_file = os.path.join(APP_DIR, "peak_memory.txt")
    assert os.path.isfile(mem_file), "peak_memory.txt is missing."
    with open(mem_file, "r") as f:
        content = f.read().strip()
    assert content.isdigit(), f"peak_memory.txt does not contain a valid integer: '{content}'"
    assert int(content) > 0, "peak_memory.txt must contain a measured positive peak."


def test_limits_diff_exists_and_valid():
    diff_file = os.path.join(APP_DIR, "limits.diff")
    assert os.path.isfile(diff_file), "limits.diff is missing."
    with open(diff_file, "r") as f:
        content = f.read()

    assert "---" in content and "+++" in content, "limits.diff does not appear to be a unified diff."
    assert "get_limit" in content, "limits.diff does not contain expected diff content."

    expected = subprocess.run(
        ["diff", "-u", "specs/old_limits.rs", "src/limits.rs"],
        cwd=APP_DIR,
        capture_output=True,
        text=True,
    )
    assert expected.returncode == 1, "The old and generated limits files unexpectedly match."
    actual_lines = content.splitlines()
    expected_lines = expected.stdout.splitlines()
    assert len(actual_lines) >= 3 and actual_lines[0].startswith("--- ") and actual_lines[1].startswith("+++ ")
    assert actual_lines[2:] == expected_lines[2:], (
        "limits.diff is not the genuine unified diff between specs/old_limits.rs and src/limits.rs"
    )
    assert os.path.basename(actual_lines[0].split()[1]) == "old_limits.rs"
    assert os.path.basename(actual_lines[1].split()[1]) == "limits.rs"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
