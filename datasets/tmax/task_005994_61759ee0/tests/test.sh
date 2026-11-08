#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import importlib.util
import inspect
import os
import random
import re
import shutil
import stat
import subprocess
import sys
import tempfile

PROJECT_DIR = "/home/user/project"
PATCH_FILE = os.path.join(PROJECT_DIR, "pipeline.patch")
CI_SCRIPT = os.path.join(PROJECT_DIR, "run_ci.sh")
TEST_FILE = os.path.join(PROJECT_DIR, "test_processor.py")
PY_FILE = os.path.join(PROJECT_DIR, "pipeline_util.py")
LIB_FILE = os.path.join(PROJECT_DIR, "libstring_processor.so")

ORIGINAL = '''import ctypes
import os

lib_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "libstring_processor.so"))
if os.path.exists(lib_path):
    lib = ctypes.CDLL(lib_path)
    lib.process_string.argtypes = [ctypes.c_char_p, ctypes.c_char_p]

def process_string_c(input_str: str) -> str:
    b_in = input_str.encode('ascii', errors='ignore')
    b_out = ctypes.create_string_buffer(len(b_in) + 1)
    lib.process_string(b_in, b_out)
    return b_out.value.decode('ascii')
'''


def apply_single_unified_diff(original, patch_text):
    lines = patch_text.splitlines(keepends=True)
    headers = [i for i, line in enumerate(lines) if line.startswith("--- ")]
    assert len(headers) == 1, "Patch must contain exactly one file diff."
    start = headers[0]
    assert start + 1 < len(lines) and lines[start + 1].startswith("+++ "), "Malformed unified diff headers."
    assert "pipeline_util.py" in lines[start] and "pipeline_util.py" in lines[start + 1], "Patch must describe pipeline_util.py."

    old = original.splitlines(keepends=True)
    result = []
    old_pos = 0
    i = start + 2
    saw_hunk = False
    hunk_re = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
    while i < len(lines):
        match = hunk_re.match(lines[i])
        assert match, f"Unexpected content outside a unified-diff hunk: {lines[i]!r}"
        saw_hunk = True
        hunk_old_start = int(match.group(1)) - 1
        assert hunk_old_start >= old_pos, "Overlapping or out-of-order patch hunks."
        result.extend(old[old_pos:hunk_old_start])
        old_pos = hunk_old_start
        i += 1
        while i < len(lines) and not lines[i].startswith("@@ "):
            line = lines[i]
            if line.startswith("\\ No newline at end of file"):
                i += 1
                continue
            assert line and line[0] in " +-", f"Invalid unified-diff line: {line!r}"
            payload = line[1:]
            if line[0] == " ":
                assert old_pos < len(old) and old[old_pos] == payload, "Patch context does not match the original file."
                result.append(payload)
                old_pos += 1
            elif line[0] == "-":
                assert old_pos < len(old) and old[old_pos] == payload, "Patch deletion does not match the original file."
                old_pos += 1
            else:
                result.append(payload)
            i += 1
    assert saw_hunk, "Patch contains no diff hunks."
    result.extend(old[old_pos:])
    return "".join(result)


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def test_patch_file_exists_and_valid():
    assert os.path.isfile(PATCH_FILE), f"Patch file {PATCH_FILE} does not exist."
    with open(PATCH_FILE, "r", encoding="utf-8") as f:
        content = f.read()
    assert "---" in content and "+++" in content, "Patch file does not appear to be a unified diff."
    assert "pipeline_util.py" in content, "Patch file does not reference pipeline_util.py."
    with open(PY_FILE, "r", encoding="utf-8") as f:
        current = f.read()
    assert current.startswith(ORIGINAL), "The original pipeline_util.py content must remain intact and the new function must be appended."
    assert apply_single_unified_diff(ORIGINAL, content) == current, "pipeline.patch does not reproduce the submitted pipeline_util.py from the original file."


def called_name(call):
    if not isinstance(call, ast.Call):
        return None
    func = call.func
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        return func.attr
    return None


def expression_tags(node, assignments):
    tags = set()
    for child in ast.walk(node):
        if isinstance(child, ast.Call):
            name = called_name(child)
            if name == "process_string_c":
                tags.add("c")
            elif name == "process_string_py":
                tags.add("py")
        elif isinstance(child, ast.Name):
            tags.update(assignments.get(child.id, set()))
    return tags


def test_test_processor_exists_and_uses_hypothesis():
    assert os.path.isfile(TEST_FILE), f"Test file {TEST_FILE} does not exist."
    with open(TEST_FILE, "r", encoding="utf-8") as f:
        content = f.read()
    assert "hypothesis" in content, "Test file does not seem to import/use hypothesis."
    assert "pytest" in content, "Test file does not seem to import/use pytest."

    tree = ast.parse(content, filename=TEST_FILE)
    imported_hypothesis = any(
        isinstance(n, (ast.Import, ast.ImportFrom)) and
        ((isinstance(n, ast.ImportFrom) and n.module and n.module.startswith("hypothesis")) or
         (isinstance(n, ast.Import) and any(a.name.startswith("hypothesis") for a in n.names)))
        for n in tree.body
    )
    imported_pytest = any(
        isinstance(n, (ast.Import, ast.ImportFrom)) and
        ((isinstance(n, ast.ImportFrom) and n.module == "pytest") or
         (isinstance(n, ast.Import) and any(a.name == "pytest" for a in n.names)))
        for n in tree.body
    )
    assert imported_hypothesis and imported_pytest, "test_processor.py must actually import hypothesis and pytest."
    assert any(isinstance(n, ast.Call) and called_name(n) == "text" for n in ast.walk(tree)), "The property test must use a Hypothesis string strategy."

    valid_property = False
    for fn in [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]:
        if not any(isinstance(d, ast.Call) and called_name(d) == "given" for d in fn.decorator_list):
            continue
        params = {a.arg for a in fn.args.args}
        calls = {"c": False, "py": False}
        assignments = {}
        for node in ast.walk(fn):
            if isinstance(node, ast.Call) and called_name(node) in ("process_string_c", "process_string_py"):
                if node.args and isinstance(node.args[0], ast.Name) and node.args[0].id in params:
                    calls["c" if called_name(node) == "process_string_c" else "py"] = True
            if isinstance(node, (ast.Assign, ast.AnnAssign)):
                value = node.value
                tag = None
                if isinstance(value, ast.Call) and called_name(value) in ("process_string_c", "process_string_py"):
                    tag = "c" if called_name(value) == "process_string_c" else "py"
                if tag:
                    targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                    for target in targets:
                        if isinstance(target, ast.Name):
                            assignments[target.id] = {tag}
        compared = any(isinstance(node, ast.Assert) and {"c", "py"}.issubset(expression_tags(node.test, assignments)) for node in ast.walk(fn))
        if all(calls.values()) and compared:
            valid_property = True
            break
    assert valid_property, "A @given property must pass the same generated string to both implementations and assert their outputs are equal."


def test_run_ci_script():
    assert os.path.isfile(CI_SCRIPT), f"CI script {CI_SCRIPT} does not exist."
    st = os.stat(CI_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"CI script {CI_SCRIPT} is not executable."

    with open(CI_SCRIPT, "r", encoding="utf-8") as f:
        script = f.read()
    executable_lines = "\n".join(line for line in script.splitlines() if not line.lstrip().startswith("#"))
    assert re.search(r"\bgcc\b[^\n]*\bstring_processor\.c\b", executable_lines), "run_ci.sh must invoke gcc on string_processor.c."
    assert re.search(r"\bgcc\b[^\n]*-shared", executable_lines), "run_ci.sh must compile a shared library."
    assert re.search(r"(?:\bpytest\b|python(?:3)?\s+-m\s+pytest)[^\n]*test_processor\.py", executable_lines), "run_ci.sh must run pytest on test_processor.py."

    plugin_dir = tempfile.mkdtemp(prefix="ci_verifier_")
    marker = os.path.join(plugin_dir, "pytest-ran")
    with open(os.path.join(plugin_dir, "verifier_ci_plugin.py"), "w", encoding="utf-8") as f:
        f.write(f"def pytest_sessionstart(session):\n    open({marker!r}, 'w').write('ran')\n")

    if os.path.exists(LIB_FILE):
        os.unlink(LIB_FILE)
    env = os.environ.copy()
    env["PYTHONPATH"] = plugin_dir + os.pathsep + env.get("PYTHONPATH", "")
    env["PYTEST_ADDOPTS"] = (env.get("PYTEST_ADDOPTS", "") + " -p verifier_ci_plugin").strip()
    result = subprocess.run([CI_SCRIPT], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=120, env=env)
    assert result.returncode == 0, f"run_ci.sh failed with return code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert "CI PASS" in result.stdout, "run_ci.sh did not print 'CI PASS' to standard output."
    assert os.path.isfile(marker), "run_ci.sh did not actually start pytest."
    assert os.path.isfile(LIB_FILE) and os.path.getsize(LIB_FILE) > 0, "run_ci.sh did not create libstring_processor.so."
    try:
        library = ctypes.CDLL(LIB_FILE)
        getattr(library, "process_string")
    except Exception as exc:
        raise AssertionError(f"The generated libstring_processor.so is not a loadable shared library exporting process_string: {exc}")


def expected_translation(value):
    vowels = set("aeiou")
    return "".join(ch.upper() if ch in vowels else ch for ch in reversed(value))


def test_process_string_py_logic():
    assert os.path.isfile(PY_FILE), f"Python file {PY_FILE} does not exist."

    try:
        pipeline_util = load_module(PY_FILE, "pipeline_util")
    except Exception as e:
        assert False, f"Failed to import {PY_FILE}: {e}"
    assert hasattr(pipeline_util, "process_string_py"), f"process_string_py function not found in {PY_FILE}."
    process_string_py = pipeline_util.process_string_py

    test_cases = [
        ("hello", "OllEh"),
        ("abcde", "EdcbA"),
        ("aeiou", "UOIEA"),
        ("XYZ", "ZYX"),
        ("123", "321"),
        ("", "")
    ]
    for inp, expected in test_cases:
        out = process_string_py(inp)
        assert out == expected, f"process_string_py({inp!r}) returned {out!r}, expected {expected!r}."

    signature = inspect.signature(process_string_py)
    assert list(signature.parameters) == ["input_str"], "process_string_py must have one parameter named input_str."
    param_annotation = signature.parameters["input_str"].annotation
    return_annotation = signature.return_annotation
    assert param_annotation in (str, "str"), "input_str must be annotated as str."
    assert return_annotation in (str, "str"), "process_string_py must have a str return annotation."

    source = inspect.getsource(process_string_py)
    function_tree = ast.parse(source)
    forbidden = {"process_string_c", "ctypes", "CDLL"}
    used_names = {n.id for n in ast.walk(function_tree) if isinstance(n, ast.Name)}
    used_attrs = {n.attr for n in ast.walk(function_tree) if isinstance(n, ast.Attribute)}
    assert not forbidden.intersection(used_names | used_attrs), "process_string_py must be a pure Python implementation, not a call into the C wrapper."

    # Import an isolated copy with no shared library beside it, ensuring the Python
    # implementation does not depend on the compiled artifact at runtime.
    with tempfile.TemporaryDirectory() as isolated:
        isolated_py = os.path.join(isolated, "pipeline_util.py")
        shutil.copyfile(PY_FILE, isolated_py)
        isolated_module = load_module(isolated_py, "isolated_pipeline_util")
        isolated_fn = isolated_module.process_string_py

        rng = random.SystemRandom()
        alphabet = "".join(chr(i) for i in range(32, 127))
        cases = [alphabet, alphabet[::-1], "a" * 257, "eIoU" * 80]
        cases.extend("".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 350))) for _ in range(400))
        for value in cases:
            expected = expected_translation(value)
            actual = isolated_fn(value)
            assert isinstance(actual, str), f"process_string_py returned a non-string for {value!r}."
            assert actual == expected, f"process_string_py failed for generated input {value!r}: got {actual!r}, expected {expected!r}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
