#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import shutil
import subprocess
import tempfile


def extract_crash_ref():
    with open("/home/user/app/memory.dmp", "rb") as f:
        dump = f.read()
    matches = re.findall(rb"CRASH_REF: ([A-Za-z0-9-]+)", dump)
    assert matches, "No crash reference was found in memory.dmp."
    assert len(matches) == 1, "Expected exactly one crash reference in memory.dmp."
    return matches[0].decode("ascii")


def test_build_py_fixed():
    """Verify that build.py runs successfully and prints 'Build complete'."""
    build_script = "/home/user/app/build.py"
    assert os.path.isfile(build_script), f"{build_script} does not exist."

    result = subprocess.run(
        ["python3", build_script],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"build.py failed with exit code {result.returncode}. stderr: {result.stderr}"
    assert "Build complete" in result.stdout, "build.py did not print 'Build complete'."


def test_crash_ref_extracted():
    """Verify that crash_ref.txt contains the correct extracted ID."""
    crash_ref_file = "/home/user/crash_ref.txt"
    assert os.path.isfile(crash_ref_file), f"{crash_ref_file} does not exist."

    with open(crash_ref_file, "r") as f:
        content = f.read().strip()

    expected = extract_crash_ref()
    assert content == expected, f"Expected '{expected}' in {crash_ref_file}, but got '{content}'."
    # Preserve the original known-state assertion as well.
    assert content == "ERR-9482-SYS", f"Expected 'ERR-9482-SYS' in {crash_ref_file}, but got '{content}'."


def _assert_required_test_structure(source):
    tree = ast.parse(source, filename="test_regression.py")
    process_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "processor":
            for imported in node.names:
                if imported.name == "process":
                    process_names.add(imported.asname or imported.name)
    assert process_names, "test_regression.py must import process from processor."

    def is_runtime_error(node):
        return isinstance(node, ast.Name) and node.id == "RuntimeError"

    def is_process_call(node):
        return (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id in process_names
        )

    found_assertion = False
    for node in ast.walk(tree):
        # Context-manager form: with self.assertRaises(RuntimeError): process(...)
        if isinstance(node, (ast.With, ast.AsyncWith)):
            for item in node.items:
                context = item.context_expr
                if not isinstance(context, ast.Call) or not context.args:
                    continue
                func = context.func
                if (
                    isinstance(func, ast.Attribute)
                    and func.attr == "assertRaises"
                    and is_runtime_error(context.args[0])
                    and any(is_process_call(child) for statement in node.body for child in ast.walk(statement))
                ):
                    found_assertion = True

        # Callable form: self.assertRaises(RuntimeError, process, crash_id)
        if isinstance(node, ast.Call):
            func = node.func
            if (
                isinstance(func, ast.Attribute)
                and func.attr == "assertRaises"
                and len(node.args) >= 2
                and is_runtime_error(node.args[0])
                and isinstance(node.args[1], ast.Name)
                and node.args[1].id in process_names
            ):
                found_assertion = True

    assert found_assertion, "A process call must be executed through assertRaises(RuntimeError)."


def test_regression_test_passes():
    """Verify that a real unittest calls process with the extracted ID and catches RuntimeError."""
    test_script = "/home/user/app/test_regression.py"
    assert os.path.isfile(test_script), f"{test_script} does not exist."

    result = subprocess.run(
        ["python3", "-m", "unittest", "test_regression.py"],
        cwd="/home/user/app",
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Regression test failed with exit code {result.returncode}. Output: {result.stderr or result.stdout}"

    with open(test_script, "r") as f:
        content = f.read()

    # Preserve the original content assertions.
    assert "process" in content, "test_regression.py does not seem to import or use the 'process' function."
    assert "ERR-9482-SYS" in content, "test_regression.py does not contain the correct crash reference ID."
    assert "RuntimeError" in content, "test_regression.py does not assert a RuntimeError."
    _assert_required_test_structure(content)

    # Run against an instrumented processor so a zero-test file or an assertion
    # that never invokes process with the dump-derived value cannot pass.
    expected = extract_crash_ref()
    with tempfile.TemporaryDirectory() as td:
        copied_test = os.path.join(td, "test_regression.py")
        shutil.copyfile(test_script, copied_test)
        marker = os.path.join(td, "process_called")
        fake_processor = os.path.join(td, "processor.py")
        with open(fake_processor, "w") as f:
            f.write(
                "import os\n"
                "def process(ref_id):\n"
                f"    expected = {expected!r}\n"
                f"    marker = {marker!r}\n"
                "    if ref_id != expected:\n"
                "        raise AssertionError('process called with the wrong crash reference')\n"
                "    with open(marker, 'a') as out:\n"
                "        out.write('OK\\n')\n"
                "    raise RuntimeError('instrumented crash')\n"
            )

        instrumented = subprocess.run(
            ["python3", "-m", "unittest", "-v", "test_regression.py"],
            cwd=td,
            capture_output=True,
            text=True
        )
        output = instrumented.stdout + instrumented.stderr
        assert instrumented.returncode == 0, f"Instrumented regression test failed: {output}"
        ran = re.search(r"Ran (\d+) tests?", output)
        assert ran and int(ran.group(1)) > 0, "test_regression.py did not execute any unittest tests."
        assert os.path.isfile(marker), "The regression test never called process with the extracted crash ID."
        with open(marker, "r") as f:
            assert "OK" in f.read(), "The required process call was not observed."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
