#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shlex
import stat
import subprocess
import tempfile
import pytest

PROJECT_DIR = "/home/user/project"


def run(cmd, **kwargs):
    return subprocess.run(cmd, cwd=PROJECT_DIR, capture_output=True, text=True,
                          timeout=30, **kwargs)


def test_makefile_builds_real_project_in_dependency_order():
    deps_path = os.path.join(PROJECT_DIR, "deps.json")
    makefile_path = os.path.join(PROJECT_DIR, "Makefile")
    assert os.path.isfile(deps_path)
    assert os.path.isfile(makefile_path)

    with open(deps_path, encoding="utf-8") as f:
        deps = json.load(f)
    assert deps == {"A": ["B"], "B": ["C"], "C": []}, "deps.json was unexpectedly altered."

    # Remove all products so the verifier observes a genuine build rather than a
    # pre-created executable or stale archives.
    for name in ("app", "main.o", "a.o", "b.o", "c.o", "libA.a", "libB.a", "libC.a"):
        path = os.path.join(PROJECT_DIR, name)
        if os.path.lexists(path):
            os.unlink(path)

    result = run(["/usr/bin/make", "app"])
    assert result.returncode == 0, f"make app failed:\n{result.stdout}\n{result.stderr}"
    build_output = result.stdout + "\n" + result.stderr

    # Inspect the link command emitted by the app recipe. Every dependency must
    # occur after the library that depends on it.
    link_lines = [line for line in build_output.splitlines()
                  if re.search(r"(?:^|\s)-o\s*app(?:\s|$)", line)
                  or re.search(r"(?:^|\s)-oapp(?:\s|$)", line)]
    assert link_lines, "make did not emit a linker command producing app."
    link_line = next((line for line in link_lines if "-lA" in line and "-lB" in line and "-lC" in line), "")
    assert link_line, "The app linker command must link libA, libB, and libC using -l options."
    linked = re.findall(r"(?:^|\s)-l\s*([A-Za-z0-9_]+)", link_line)
    for module in deps:
        assert module in linked, f"Library {module} is absent from the app linker command."
    positions = {module: linked.index(module) for module in deps}
    for module, requirements in deps.items():
        for requirement in requirements:
            assert positions[module] < positions[requirement], (
                f"Incorrect static-library order: -l{module} must precede -l{requirement}."
            )

    app_path = os.path.join(PROJECT_DIR, "app")
    assert os.path.isfile(app_path), f"Executable {app_path} was not produced by make."
    assert os.access(app_path, os.X_OK), f"File {app_path} is not executable."
    with open(app_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "make did not produce an ELF executable."

    symbols = subprocess.run(["/usr/bin/nm", app_path], capture_output=True, text=True, timeout=10)
    assert symbols.returncode == 0, f"nm could not inspect app: {symbols.stderr}"
    for symbol in ("main", "funcA", "funcB", "funcC"):
        assert re.search(rf"\b{symbol}$", symbols.stdout, re.MULTILINE), f"app does not contain {symbol}."


def test_app_compiled_and_executable():
    app_path = os.path.join(PROJECT_DIR, "app")
    assert os.path.isfile(app_path), f"Executable {app_path} was not found. Did you run make?"
    assert os.access(app_path, os.X_OK), f"File {app_path} is not executable."


def test_app_output():
    app_path = os.path.join(PROJECT_DIR, "app")
    try:
        result = subprocess.run([app_path], capture_output=True, text=True, check=True, timeout=10)
        assert result.stdout == "Result: 44\n", f"Expected output 'Result: 44\\n', got {result.stdout!r}"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Running {app_path} failed with exit code {e.returncode}")


def test_test_deploy_script_exists():
    script_path = os.path.join(PROJECT_DIR, "test_deploy.py")
    assert os.path.isfile(script_path), f"Python script {script_path} does not exist."


def assert_ready_log(path):
    assert os.path.isfile(path), f"Status log {path} does not exist. Did you run the Python script?"
    with open(path, "rb") as f:
        content = f.read()
    expected_no_bom = "DEPLOY_READY".encode("utf-16le")
    expected_with_bom = "DEPLOY_READY".encode("utf-16")
    assert content in (expected_no_bom, expected_with_bom), (
        "status.log does not contain the correctly UTF-16LE encoded string 'DEPLOY_READY'."
    )


def test_status_log_exists_and_correct():
    assert_ready_log(os.path.join(PROJECT_DIR, "status.log"))


def test_deploy_script_is_executed_and_uses_app_output():
    script_path = os.path.join(PROJECT_DIR, "test_deploy.py")
    app_path = os.path.join(PROJECT_DIR, "app")
    log_path = os.path.join(PROJECT_DIR, "status.log")

    if os.path.lexists(log_path):
        os.unlink(log_path)
    positive = run(["python3", script_path])
    assert positive.returncode == 0, f"test_deploy.py failed:\n{positive.stdout}\n{positive.stderr}"
    assert_ready_log(log_path)

    # Supply a real executable with a derived non-matching result. A script that
    # merely writes the known bytes, rather than checking ./app, must fail here.
    backup = os.path.join(PROJECT_DIR, ".app.verifier-backup")
    if os.path.lexists(backup):
        os.unlink(backup)
    os.replace(app_path, backup)
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".c", delete=False) as src:
            src.write('#include <stdio.h>\nint main(void){puts("Result: 45");return 0;}\n')
            source_path = src.name
        try:
            built = subprocess.run(["/usr/bin/gcc", source_path, "-o", app_path],
                                   capture_output=True, text=True, timeout=20)
            assert built.returncode == 0, built.stderr
        finally:
            os.unlink(source_path)

        if os.path.lexists(log_path):
            os.unlink(log_path)
        negative = run(["python3", script_path])
        assert negative.returncode == 0, f"test_deploy.py failed on non-matching output: {negative.stderr}"
        if os.path.isfile(log_path):
            with open(log_path, "rb") as f:
                assert f.read() not in ("DEPLOY_READY".encode("utf-16le"), "DEPLOY_READY".encode("utf-16")), (
                    "test_deploy.py writes DEPLOY_READY even when ./app output does not match."
                )
    finally:
        if os.path.lexists(app_path):
            os.unlink(app_path)
        os.replace(backup, app_path)
        if os.path.lexists(log_path):
            os.unlink(log_path)
        final = run(["python3", script_path])
        assert final.returncode == 0, f"test_deploy.py failed after restoring app: {final.stderr}"
        assert_ready_log(log_path)


def _strip_yaml_comment(text):
    quote = None
    escaped = False
    depth = 0
    for i, ch in enumerate(text):
        if escaped:
            escaped = False
            continue
        if quote == '"' and ch == "\\":
            escaped = True
            continue
        if quote:
            if ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
        elif ch in "[{(":
            depth += 1
        elif ch in "]})":
            depth -= 1
            if depth < 0:
                raise ValueError("unbalanced flow collection")
        elif ch == "#" and depth == 0 and (i == 0 or text[i - 1].isspace()):
            return text[:i].rstrip()
    if quote or depth != 0:
        raise ValueError("unterminated quote or flow collection")
    return text.rstrip()


def _split_yaml_pair(text):
    quote = None
    escaped = False
    depth = 0
    for i, ch in enumerate(text):
        if escaped:
            escaped = False
        elif quote == '"' and ch == "\\":
            escaped = True
        elif quote:
            if ch == quote:
                quote = None
        elif ch in ("'", '"'):
            quote = ch
        elif ch in "[{(":
            depth += 1
        elif ch in "]})":
            depth -= 1
        elif ch == ":" and depth == 0 and (i + 1 == len(text) or text[i + 1].isspace()):
            key = text[:i].strip()
            if not key:
                raise ValueError("empty YAML key")
            return key.strip("'\""), text[i + 1:].strip()
    raise ValueError(f"expected YAML mapping entry: {text}")


def _yaml_scalar(value):
    value = value.strip()
    if not value:
        return None
    if value[0:1] in ("'", '"'):
        return ast.literal_eval(value) if value[0] == '"' else value[1:-1].replace("''", "'")
    return value


def _fallback_yaml_load(content):
    lines = []
    for number, raw in enumerate(content.splitlines(), 1):
        if "\t" in raw[:len(raw) - len(raw.lstrip())]:
            raise ValueError(f"tab indentation on line {number}")
        text = _strip_yaml_comment(raw.lstrip(" "))
        if not text or text in ("---", "..."):
            continue
        lines.append((len(raw) - len(raw.lstrip(" ")), text, number))
    if not lines:
        raise ValueError("empty YAML")

    def parse_block(index, indent):
        if lines[index][0] != indent:
            raise ValueError("inconsistent indentation")
        is_list = lines[index][1] == "-" or lines[index][1].startswith("- ")
        out = [] if is_list else {}
        while index < len(lines) and lines[index][0] == indent:
            text = lines[index][1]
            if is_list:
                if not (text == "-" or text.startswith("- ")):
                    raise ValueError("mixed sequence and mapping")
                rest = text[1:].strip()
                index += 1
                if not rest:
                    if index >= len(lines) or lines[index][0] <= indent:
                        raise ValueError("empty sequence entry")
                    item, index = parse_block(index, lines[index][0])
                elif ":" in rest:
                    key, value = _split_yaml_pair(rest)
                    item = {key: _yaml_scalar(value)}
                    if index < len(lines) and lines[index][0] > indent:
                        continuation, index = parse_block(index, lines[index][0])
                        if not isinstance(continuation, dict):
                            raise ValueError("invalid sequence mapping")
                        item.update(continuation)
                else:
                    item = _yaml_scalar(rest)
                out.append(item)
            else:
                if text == "-" or text.startswith("- "):
                    raise ValueError("mixed mapping and sequence")
                key, value = _split_yaml_pair(text)
                index += 1
                if value in ("|", ">"):
                    chunks = []
                    while index < len(lines) and lines[index][0] > indent:
                        chunks.append(lines[index][1])
                        index += 1
                    out[key] = "\n".join(chunks) + "\n"
                elif value:
                    out[key] = _yaml_scalar(value)
                elif index < len(lines) and lines[index][0] > indent:
                    out[key], index = parse_block(index, lines[index][0])
                else:
                    out[key] = None
        return out, index

    parsed, end = parse_block(0, lines[0][0])
    if end != len(lines):
        raise ValueError(f"invalid indentation near line {lines[end][2]}")
    return parsed


def load_yaml(content):
    try:
        import yaml
    except ImportError:
        return _fallback_yaml_load(content)
    return yaml.safe_load(content)


def test_github_actions_workflow():
    workflow_path = os.path.join(PROJECT_DIR, ".github", "workflows", "ci.yml")
    assert os.path.isfile(workflow_path), f"GitHub Actions workflow file {workflow_path} does not exist."
    with open(workflow_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "python3 test_deploy.py" in content, (
        f"Workflow file {workflow_path} does not contain the command 'python3 test_deploy.py'."
    )
    assert "jobs:" in content, "Workflow file does not seem to contain 'jobs:'."
    assert "test:" in content or "test" in content, "Workflow file does not seem to contain a 'test' job."
    assert "steps:" in content, "Workflow file does not seem to contain 'steps:'."

    try:
        workflow = load_yaml(content)
    except Exception as exc:
        pytest.fail(f"ci.yml is not valid YAML: {exc}")
    assert isinstance(workflow, dict), "The workflow YAML root must be a mapping."
    jobs = workflow.get("jobs")
    assert isinstance(jobs, dict), "The workflow must define a jobs mapping."
    test_job = jobs.get("test")
    assert isinstance(test_job, dict), "The workflow must contain a job named test."
    steps = test_job.get("steps")
    assert isinstance(steps, list), "The test job must define a steps list."
    run_values = [step.get("run") for step in steps if isinstance(step, dict) and isinstance(step.get("run"), str)]
    assert any(any(line.strip() == "python3 test_deploy.py" for line in command.splitlines())
               for command in run_values), (
        "The test job must have a run step that executes python3 test_deploy.py."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
