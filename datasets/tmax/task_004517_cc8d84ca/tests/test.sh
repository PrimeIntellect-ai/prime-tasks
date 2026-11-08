#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import functools
import importlib.util
import os
import secrets
import subprocess
import urllib.parse

PROJECT_DIR = "/home/user/project"
REPORT_FILE = "/home/user/report.txt"


def test_project_structure():
    """Verify the project has been reorganized correctly."""
    src_dir = os.path.join(PROJECT_DIR, "src")
    app_dir = os.path.join(src_dir, "app")
    tests_dir = os.path.join(PROJECT_DIR, "tests")

    assert os.path.isdir(src_dir), f"Directory {src_dir} does not exist."
    assert os.path.isdir(app_dir), f"Directory {app_dir} does not exist."
    assert os.path.isdir(tests_dir), f"Directory {tests_dir} does not exist."

    assert os.path.isfile(os.path.join(src_dir, "__init__.py")), "src/__init__.py is missing."
    assert os.path.isfile(os.path.join(app_dir, "__init__.py")), "src/app/__init__.py is missing."
    assert os.path.isfile(os.path.join(tests_dir, "__init__.py")), "tests/__init__.py is missing."

    for file in ["main.py", "router.py", "utils.py"]:
        app_file = os.path.join(app_dir, file)
        root_file = os.path.join(PROJECT_DIR, file)
        assert os.path.isfile(app_file), f"{file} was not moved to {app_dir}."
        assert not os.path.exists(root_file), f"{file} still exists in the root directory."


def test_report_file():
    """Verify the report file content."""
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} does not exist."
    with open(REPORT_FILE, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) == 2, f"Report file should contain exactly 2 lines, found {len(lines)}."
    assert lines[0] == "/home/user/project/src/app/router.py", f"Line 1 is incorrect: {lines[0]}"
    assert lines[1] == "_route_cache", f"Line 2 is incorrect: {lines[1]}"


def test_router_memory_leak_fix():
    """Verify the memory leak was fixed using lru_cache."""
    router_path = os.path.join(PROJECT_DIR, "src", "app", "router.py")
    assert os.path.isfile(router_path), f"File {router_path} does not exist."

    with open(router_path, "r") as f:
        content = f.read()

    assert "_route_cache" not in content, "The global dictionary '_route_cache' must be removed."

    tree = ast.parse(content)
    has_lru_cache = False
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == "parse_url":
            for decorator in node.decorator_list:
                if isinstance(decorator, ast.Call):
                    if getattr(decorator.func, "id", "") == "lru_cache" or getattr(decorator.func, "attr", "") == "lru_cache":
                        for kw in decorator.keywords:
                            if kw.arg == "maxsize" and isinstance(kw.value, ast.Constant) and kw.value.value == 128:
                                has_lru_cache = True

    assert has_lru_cache, "parse_url must be decorated with @lru_cache(maxsize=128)."


def _expected_params(url):
    parsed = urllib.parse.urlparse(url)
    params = urllib.parse.parse_qs(parsed.query)
    return {key: values[0] if len(values) == 1 else values for key, values in params.items()}


def test_router_runtime_behavior_and_cache_bounds():
    """Execute the submitted module and validate parsing and bounded-cache semantics."""
    router_path = os.path.join(PROJECT_DIR, "src", "app", "router.py")
    spec = importlib.util.spec_from_file_location("submitted_router", router_path)
    assert spec is not None and spec.loader is not None, "Could not load router.py."
    router = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(router)

    assert hasattr(router, "parse_url") and callable(router.parse_url), "parse_url must be callable."
    assert isinstance(router.parse_url, functools._lru_cache_wrapper), "parse_url must use functools.lru_cache."

    token = secrets.token_hex(16)
    urls = [
        f"/api/data?user={urllib.parse.quote(token)}&id=5",
        f"https://example.invalid/path?tag={token}&tag=second&space=hello+world&encoded=%2Fitem%2F{token}",
        "/path/without/query",
    ]
    for url in urls:
        assert router.parse_url(url) == _expected_params(url), f"parse_url returned incorrect parameters for {url!r}."

    router.parse_url.cache_clear()
    probe = f"/cache-probe?nonce={secrets.token_hex(16)}"
    first = router.parse_url(probe)
    after_first = router.parse_url.cache_info()
    assert after_first.maxsize == 128, "parse_url cache maxsize must be exactly 128."
    assert after_first.misses == 1 and after_first.hits == 0 and after_first.currsize == 1, "First lookup must populate the cache."

    second = router.parse_url(probe)
    after_second = router.parse_url.cache_info()
    assert second is first, "A repeated URL should return the cached result."
    assert after_second.hits == after_first.hits + 1, "A repeated URL must register a cache hit."
    assert after_second.misses == after_first.misses, "A repeated URL must not register another miss."

    prefix = secrets.token_hex(16)
    for i in range(128):
        url = f"/unique?batch={prefix}&n={i}"
        assert router.parse_url(url) == _expected_params(url)

    full = router.parse_url.cache_info()
    assert full.maxsize == 128 and full.currsize == 128, "The cache must remain bounded at 128 entries."
    misses_before = full.misses
    router.parse_url(probe)
    evicted = router.parse_url.cache_info()
    assert evicted.misses == misses_before + 1, "The least-recently-used entry was not evicted as expected."
    assert evicted.currsize == 128, "Cache size grew beyond 128 entries."


def test_test_suite_execution():
    """Verify the student's test suite runs successfully."""
    test_file = os.path.join(PROJECT_DIR, "tests", "test_router.py")
    assert os.path.isfile(test_file), f"Test file {test_file} does not exist."

    result = subprocess.run(
        ["python3", "-m", "unittest", "discover", "-s", "tests", "-t", "."],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Tests failed to run successfully:\n{result.stderr}\n{result.stdout}"


def test_required_unittest_cases_are_present():
    """Require separate unittest tests for parsing and cache inspection."""
    test_file = os.path.join(PROJECT_DIR, "tests", "test_router.py")
    with open(test_file, "r") as f:
        tree = ast.parse(f.read(), filename=test_file)

    test_methods = []
    for node in tree.body:
        if not isinstance(node, ast.ClassDef):
            continue
        is_test_case = any(
            (isinstance(base, ast.Name) and base.id == "TestCase") or
            (isinstance(base, ast.Attribute) and base.attr == "TestCase")
            for base in node.bases
        )
        if is_test_case:
            test_methods.extend(
                child for child in node.body
                if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)) and child.name.startswith("test")
            )

    assert len(test_methods) >= 2, "tests/test_router.py must define at least two unittest test methods."

    def has_assertion(method):
        for item in ast.walk(method):
            if isinstance(item, ast.Assert):
                return True
            if isinstance(item, ast.Call) and isinstance(item.func, ast.Attribute) and item.func.attr.startswith("assert"):
                return True
        return False

    def calls_parse_url(method):
        return any(
            isinstance(item, ast.Call) and
            ((isinstance(item.func, ast.Name) and item.func.id == "parse_url") or
             (isinstance(item.func, ast.Attribute) and item.func.attr == "parse_url"))
            for item in ast.walk(method)
        )

    def calls_cache_info(method):
        return any(
            isinstance(item, ast.Call) and isinstance(item.func, ast.Attribute) and item.func.attr == "cache_info"
            for item in ast.walk(method)
        )

    parsing_tests = [method for method in test_methods if has_assertion(method) and calls_parse_url(method)]
    cache_tests = [method for method in test_methods if has_assertion(method) and calls_cache_info(method)]
    assert parsing_tests, "A unittest test with an assertion must call parse_url."
    assert cache_tests, "A unittest test with an assertion must inspect parse_url.cache_info()."
    assert any(p is not c for p in parsing_tests for c in cache_tests), "Parsing and cache behavior must be covered by separate tests."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
