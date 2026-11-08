#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import dataclasses
import heapq
import json
import os
import random
import re
import shutil
import string
import subprocess
import sys
import tempfile
import types
import urllib.error
import urllib.request

POLYBUILD_DIR = "/home/user/polybuild"


def test_polybuild_dir_exists():
    assert os.path.isdir(POLYBUILD_DIR), f"Directory {POLYBUILD_DIR} does not exist."


def test_required_inputs_exist_and_match_configuration():
    schema_path = os.path.join(POLYBUILD_DIR, "schema.json")
    build_path = os.path.join(POLYBUILD_DIR, "build.json")
    main_py = os.path.join(POLYBUILD_DIR, "main.py")
    main_c = os.path.join(POLYBUILD_DIR, "main.c")

    for path in (schema_path, build_path, main_py, main_c):
        assert os.path.isfile(path), f"Required file {path} does not exist."

    with open(schema_path) as f:
        schema = json.load(f)
    assert schema == {"Person": {"name": "string", "age": "int"}}, \
        f"schema.json does not contain the required Person schema: {schema!r}"

    with open(build_path) as f:
        build = json.load(f)
    assert isinstance(build, dict) and isinstance(build.get("tasks"), dict), \
        "build.json must contain a tasks dictionary."
    tasks = build["tasks"]
    expected_deps = {
        "translate": [],
        "compile_c": ["translate"],
        "run_c": ["compile_c"],
        "run_py": ["translate"],
        "combine": ["run_c", "run_py"],
    }
    assert set(tasks) == set(expected_deps), \
        f"build.json has incorrect task names: {sorted(tasks)}"
    for name, deps in expected_deps.items():
        assert sorted(tasks[name].get("deps", [])) == sorted(deps), \
            f"Task {name} has incorrect dependencies."
        assert isinstance(tasks[name].get("cmd"), str) and tasks[name]["cmd"].strip(), \
            f"Task {name} is missing its command."


def test_generated_schema_python():
    py_schema_path = os.path.join(POLYBUILD_DIR, "generated_schema.py")
    assert os.path.isfile(py_schema_path), f"File {py_schema_path} does not exist."
    with open(py_schema_path) as f:
        content = f.read()
    assert "@dataclass" in content, "Python schema does not use @dataclass."
    assert "class Person" in content or "class Person:" in content, "Python schema does not define class Person."
    assert re.search(r"name\s*:\s*str", content), "Python schema missing 'name: str' field."
    assert re.search(r"age\s*:\s*int", content), "Python schema missing 'age: int' field."


def test_generated_schema_c():
    c_schema_path = os.path.join(POLYBUILD_DIR, "generated_schema.h")
    assert os.path.isfile(c_schema_path), f"File {c_schema_path} does not exist."
    with open(c_schema_path) as f:
        content = f.read()
    content_no_ws = re.sub(r"\s+", "", content)
    assert "typedefstruct{" in content_no_ws, "C schema missing 'typedef struct {'."
    assert "char*name;" in content_no_ws, "C schema missing 'char* name;'."
    assert "intage;" in content_no_ws, "C schema missing 'int age;'."
    assert "}Person;" in content_no_ws, "C schema missing '} Person;'."


def test_execution_log():
    log_path = os.path.join(POLYBUILD_DIR, "execution_log.txt")
    assert os.path.isfile(log_path), f"File {log_path} does not exist."
    with open(log_path) as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_order = ["translate", "compile_c", "run_c", "run_py", "combine"]
    assert lines == expected_order, f"Execution log order is incorrect. Expected {expected_order}, got {lines}."


def test_final_output():
    out_path = os.path.join(POLYBUILD_DIR, "final_output.txt")
    assert os.path.isfile(out_path), f"File {out_path} does not exist."
    with open(out_path) as f:
        content = f.read()
    assert "C: Bob is 25" in content, "final_output.txt missing C output."
    assert "Python: Alice is 30" in content, "final_output.txt missing Python output."


def _snapshot(paths):
    result = {}
    for path in paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                result[path] = f.read()
        else:
            result[path] = None
    return result


def _restore(snapshot):
    for path, data in snapshot.items():
        if data is None:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        else:
            with open(path, "wb") as f:
                f.write(data)


def _alphabetical_toposort(tasks):
    indegree = {name: len(spec["deps"]) for name, spec in tasks.items()}
    children = {name: [] for name in tasks}
    for name, spec in tasks.items():
        for dep in spec["deps"]:
            children[dep].append(name)
    ready = [name for name, degree in indegree.items() if degree == 0]
    heapq.heapify(ready)
    order = []
    while ready:
        name = heapq.heappop(ready)
        order.append(name)
        for child in children[name]:
            indegree[child] -= 1
            if indegree[child] == 0:
                heapq.heappush(ready, child)
    assert len(order) == len(tasks)
    return order


def test_translator_and_builder_function_on_derived_inputs():
    translator = os.path.join(POLYBUILD_DIR, "translator.py")
    builder = os.path.join(POLYBUILD_DIR, "builder.py")
    assert os.path.isfile(translator), "translator.py does not exist."
    assert os.path.isfile(builder), "builder.py does not exist."

    with open(builder) as f:
        builder_source = f.read()
    tree = ast.parse(builder_source, filename=builder)
    imports_subprocess = any(
        (isinstance(node, ast.Import) and any(alias.name == "subprocess" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "subprocess")
        for node in ast.walk(tree)
    )
    assert imports_subprocess, "builder.py must use the subprocess module."

    schema_path = os.path.join(POLYBUILD_DIR, "schema.json")
    build_path = os.path.join(POLYBUILD_DIR, "build.json")
    generated_py = os.path.join(POLYBUILD_DIR, "generated_schema.py")
    generated_h = os.path.join(POLYBUILD_DIR, "generated_schema.h")
    execution_log = os.path.join(POLYBUILD_DIR, "execution_log.txt")
    paths = [schema_path, build_path, generated_py, generated_h, execution_log]
    saved = _snapshot(paths)

    suffix = "".join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(10))
    class_a = "Record" + suffix.capitalize()
    class_b = "Item" + suffix.capitalize()
    dynamic_schema = {
        class_a: {"label_" + suffix: "string", "count_" + suffix: "int"},
        class_b: {"code_" + suffix: "int", "text_" + suffix: "string"},
    }

    temp_dir = tempfile.mkdtemp(prefix="polybuild_verify_")
    marker = os.path.join(temp_dir, "commands.log")
    module_name = "generated_schema_verify_" + suffix
    try:
        with open(schema_path, "w") as f:
            json.dump(dynamic_schema, f)
        for path in (generated_py, generated_h):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        result = subprocess.run(
            [sys.executable, translator], cwd=POLYBUILD_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
        )
        assert result.returncode == 0, f"translator.py failed on a derived schema: {result.stderr}"
        assert os.path.isfile(generated_py) and os.path.isfile(generated_h), \
            "translator.py did not generate both requested files."

        with open(generated_py) as f:
            generated_source = f.read()
        module = types.ModuleType(module_name)
        sys.modules[module_name] = module
        exec(compile(generated_source, generated_py, "exec"), module.__dict__)
        for class_name, fields in dynamic_schema.items():
            cls = getattr(module, class_name, None)
            assert cls is not None and dataclasses.is_dataclass(cls), \
                f"Generated Python class {class_name} is not a dataclass."
            expected_annotations = {
                field: (str if kind == "string" else int) for field, kind in fields.items()
            }
            assert cls.__annotations__ == expected_annotations, \
                f"Incorrect annotations for generated class {class_name}."
            values = {
                field: ("value_" + suffix if kind == "string" else 731)
                for field, kind in fields.items()
            }
            instance = cls(**values)
            assert all(getattr(instance, key) == value for key, value in values.items())

        c_test = os.path.join(temp_dir, "schema_test.c")
        c_binary = os.path.join(temp_dir, "schema_test")
        c_lines = ["#include <string.h>", f'#include "{generated_h}"', "int main(void) {"]
        for index, (class_name, fields) in enumerate(dynamic_schema.items()):
            variable = f"v{index}"
            c_lines.append(f"  {class_name} {variable};")
            for field, kind in fields.items():
                if kind == "string":
                    c_lines.append(f'  {variable}.{field} = "value_{suffix}";')
                    c_lines.append(f'  if (strcmp({variable}.{field}, "value_{suffix}") != 0) return 2;')
                else:
                    c_lines.append(f"  {variable}.{field} = 731;")
                    c_lines.append(f"  if ({variable}.{field} != 731) return 3;")
        c_lines.extend(["  return 0;", "}"])
        with open(c_test, "w") as f:
            f.write("\n".join(c_lines) + "\n")
        compile_result = subprocess.run(
            ["gcc", "-Wall", "-Werror", c_test, "-o", c_binary],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
        )
        assert compile_result.returncode == 0, \
            f"Generated C schema did not compile for a derived schema: {compile_result.stderr}"
        assert subprocess.run([c_binary], timeout=5).returncode == 0

        names = {
            "root": "root_" + suffix,
            "first": "alpha_" + suffix,
            "second": "beta_" + suffix,
            "child": "aardvark_" + suffix,
            "final": "finish_" + suffix,
        }
        deps = {
            names["root"]: [],
            names["first"]: [names["root"]],
            names["second"]: [names["root"]],
            names["child"]: [names["first"]],
            names["final"]: [names["child"], names["second"]],
        }
        dynamic_tasks = {}
        for name, task_deps in deps.items():
            quoted_marker = json.dumps(marker)
            quoted_name = json.dumps(name + "\\n")
            command = f"python3 -c 'import os; open({quoted_marker}, \"a\").write({quoted_name})'"
            dynamic_tasks[name] = {"deps": task_deps, "cmd": command}
        expected_order = _alphabetical_toposort(dynamic_tasks)

        with open(build_path, "w") as f:
            json.dump({"tasks": dynamic_tasks}, f)
        try:
            os.remove(execution_log)
        except FileNotFoundError:
            pass

        result = subprocess.run(
            [sys.executable, builder], cwd=POLYBUILD_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert result.returncode == 0, f"builder.py failed on a derived DAG: {result.stderr}"
        assert os.path.isfile(execution_log), "builder.py did not create execution_log.txt."
        with open(execution_log) as f:
            logged = [line.strip() for line in f if line.strip()]
        assert logged == expected_order, \
            f"builder.py did not use alphabetical topological order: expected {expected_order}, got {logged}."
        assert os.path.isfile(marker), "builder.py did not execute the derived task commands."
        with open(marker) as f:
            executed = [line.strip() for line in f if line.strip()]
        assert executed == expected_order, \
            f"Commands were not executed in the resolved order: expected {expected_order}, got {executed}."
    finally:
        sys.modules.pop(module_name, None)
        _restore(saved)
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_http_server_running_and_serving_workspace():
    url = "http://127.0.0.1:8080/execution_log.txt"
    try:
        with urllib.request.urlopen(url, timeout=2) as response:
            status = response.getcode()
            content = response.read().decode("utf-8")
        assert status == 200, f"Expected HTTP status 200, got {status}."
        assert "translate" in content and "combine" in content, \
            "HTTP server did not serve the correct execution_log.txt content."
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to HTTP server on port 8080: {e}"

    nonce = "verify_" + "".join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(16))
    nonce_path = os.path.join(POLYBUILD_DIR, nonce + ".txt")
    try:
        with open(nonce_path, "w") as f:
            f.write(nonce)
        with urllib.request.urlopen(f"http://127.0.0.1:8080/{nonce}.txt", timeout=2) as response:
            served = response.read().decode("utf-8")
        assert response.getcode() == 200 and served == nonce, \
            "Port 8080 is not serving the /home/user/polybuild directory."
    except urllib.error.URLError as e:
        assert False, f"HTTP server did not serve a workspace file: {e}"
    finally:
        try:
            os.remove(nonce_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
