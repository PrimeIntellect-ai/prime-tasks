#!/bin/bash
set -u
mkdir -p /logs/verifier

if (
    set -e
    BASE=/home/user/fast-router
    PY="$BASE/venv/bin/python"
    PIP="$BASE/venv/bin/pip"

    test -x "$PY"
    test -x "$PIP"

    cat > /tmp/test_final_state.py <<'PY_EOF'
import ast
import os
import random
import runpy
import sys
from unittest.mock import patch

BASE = "/home/user/fast-router"


def test_logs_exist_and_passed():
    log_files = [
        "/home/user/test_pure_python.log",
        "/home/user/test_c_ext.log",
    ]
    for log_file in log_files:
        assert os.path.isfile(log_file), (
            f"Log file {log_file} does not exist. Did you run the tests and redirect output?"
        )
        with open(log_file, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
        assert "2 passed" in content or "passed" in content.lower(), (
            f"{log_file} does not indicate that tests passed successfully."
        )


def test_setup_py_conditional():
    setup_path = os.path.join(BASE, "setup.py")
    assert os.path.isfile(setup_path), f"{setup_path} is missing."
    with open(setup_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "PURE_PYTHON" in content, (
        "setup.py does not contain conditional logic checking for 'PURE_PYTHON'."
    )

    def captured_extensions(value):
        captured = {}

        def fake_setup(*args, **kwargs):
            captured.update(kwargs)

        old = os.environ.get("PURE_PYTHON")
        os.environ["PURE_PYTHON"] = value
        try:
            with patch("setuptools.setup", fake_setup):
                old_cwd = os.getcwd()
                os.chdir(BASE)
                try:
                    runpy.run_path(setup_path, run_name="__verifier_setup__")
                finally:
                    os.chdir(old_cwd)
        finally:
            if old is None:
                os.environ.pop("PURE_PYTHON", None)
            else:
                os.environ["PURE_PYTHON"] = old
        assert "ext_modules" in captured, "setup.py did not pass ext_modules to setup()."
        return captured["ext_modules"]

    pure_extensions = captured_extensions("1")
    assert list(pure_extensions or []) == [], (
        "PURE_PYTHON=1 must omit the C extension from ext_modules."
    )

    native_extensions = list(captured_extensions("0") or [])
    assert len(native_extensions) == 1, (
        "PURE_PYTHON=0 must configure exactly the router C extension."
    )
    extension = native_extensions[0]
    assert getattr(extension, "name", None) == "router._fast_router"
    sources = [os.path.normpath(path) for path in getattr(extension, "sources", [])]
    assert os.path.normpath("router/_fast_router.c") in sources


def test_fetcher_patched():
    fetcher_path = os.path.join(BASE, "tests", "test_fetcher.py")
    assert os.path.isfile(fetcher_path), f"{fetcher_path} is missing."
    with open(fetcher_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "patch" in content, (
        "tests/test_fetcher.py does not appear to use unittest.mock.patch."
    )

    tree = ast.parse(content, filename=fetcher_path)
    functions = [
        node for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "test_update_routes"
    ]
    assert len(functions) == 1, "tests/test_fetcher.py must define test_update_routes."
    function = functions[0]
    assert any(isinstance(node, ast.Assert) for node in ast.walk(function)), (
        "test_update_routes must retain an assertion for the parsed routes."
    )
    assert any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "fetch_and_parse"
        for node in ast.walk(function)
    ), "test_update_routes must exercise fetch_and_parse()."

    patches_urlopen = False
    for node in ast.walk(function):
        if not isinstance(node, ast.Call):
            continue
        is_patch = (
            isinstance(node.func, ast.Name) and node.func.id == "patch"
        ) or (
            isinstance(node.func, ast.Attribute) and node.func.attr in {"patch", "object"}
        )
        if not is_patch:
            continue
        string_args = [arg.value for arg in node.args if isinstance(arg, ast.Constant) and isinstance(arg.value, str)]
        if "urllib.request.urlopen" in string_args or "urlopen" in string_args:
            patches_urlopen = True
            break
    assert patches_urlopen, (
        "test_update_routes must patch urllib.request.urlopen rather than merely mentioning patch."
    )


def test_parser_fixes():
    sys.path.insert(0, BASE)
    try:
        from router.parser import parse_routing_table
    except ImportError as exc:
        raise AssertionError(f"Failed to import parse_routing_table: {exc}")

    test_data = "PREFIX1 => DEST1\n\n# A comment line\nPREFIX2 => DEST2\n   \n#Another comment"
    try:
        result = parse_routing_table(test_data)
    except Exception as exc:
        raise AssertionError(
            f"parse_routing_table crashed on valid input with empty lines and comments: {exc}"
        )
    expected = {"PREFIX1": "DEST1", "PREFIX2": "DEST2"}
    assert result == expected, f"parse_routing_table returned {result}, expected {expected}."

    rng = random.Random(917263)
    expected = {}
    lines = ["", "# generated comment"]
    for index in range(12):
        prefix = f"/route-{rng.randrange(10_000_000)}"
        destination = f"backend-{rng.randrange(10_000_000)}"
        expected[prefix] = destination
        lines.extend([f"  {prefix}  =>  {destination}  ", "", f"# comment {index}"])
    rng.shuffle(lines)
    actual = parse_routing_table("\n".join(lines))
    assert actual == expected, f"Generated routing table parsed as {actual}, expected {expected}."
PY_EOF

    "$PY" -m pytest /tmp/test_final_state.py -q --tb=short

    cat > /tmp/verifier_no_network.py <<'PY_EOF'
import urllib.request


def pytest_sessionstart(session):
    def forbidden_urlopen(*args, **kwargs):
        raise AssertionError("A real urllib.request.urlopen call was attempted")
    urllib.request.urlopen = forbidden_urlopen
PY_EOF

    cd "$BASE"

    "$PIP" uninstall -y fast-router >/tmp/verifier_uninstall_pure.log 2>&1 || true
    rm -rf "$BASE/build"
    find "$BASE/router" -maxdepth 1 -type f \( -name '_fast_router*.so' -o -name '_fast_router*.pyd' \) -delete

    PURE_PYTHON=1 "$PIP" install -e . >/tmp/verifier_build_pure.log 2>&1
    if find "$BASE/router" -maxdepth 1 -type f \( -name '_fast_router*.so' -o -name '_fast_router*.pyd' \) | grep -q .; then
        echo "PURE_PYTHON=1 produced a compiled extension" >&2
        exit 1
    fi
    PURE_PYTHON=1 PYTHONPATH="/tmp:$BASE" "$PY" - <<'PY_EOF'
import importlib.util
spec = importlib.util.find_spec("router._fast_router")
assert spec is None, f"C extension is importable in the pure-Python build: {spec}"
PY_EOF
    PURE_PYTHON=1 PYTHONPATH="/tmp:$BASE" "$PY" -m pytest -q -p verifier_no_network tests >/tmp/verifier_tests_pure.log

    "$PIP" uninstall -y fast-router >/tmp/verifier_uninstall_native.log 2>&1 || true
    rm -rf "$BASE/build"
    find "$BASE/router" -maxdepth 1 -type f \( -name '_fast_router*.so' -o -name '_fast_router*.pyd' \) -delete

    PURE_PYTHON=0 "$PIP" install -e . >/tmp/verifier_build_native.log 2>&1
    if ! find "$BASE/router" -maxdepth 1 -type f \( -name '_fast_router*.so' -o -name '_fast_router*.pyd' \) | grep -q .; then
        echo "PURE_PYTHON=0 did not build the C extension" >&2
        exit 1
    fi
    PURE_PYTHON=0 PYTHONPATH="/tmp:$BASE" "$PY" - <<'PY_EOF'
from router import _fast_router
assert _fast_router.get_version() == "1.0"
PY_EOF
    PURE_PYTHON=0 PYTHONPATH="/tmp:$BASE" "$PY" -m pytest -q -p verifier_no_network tests >/tmp/verifier_tests_native.log
) ; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
