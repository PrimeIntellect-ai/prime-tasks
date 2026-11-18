#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import random
import re
import subprocess
import sys

ROOT = "/home/user/sysconf_parser"
PARSER_PATH = os.path.join(ROOT, "parser.py")
EXAMPLE_PATH = os.path.join(ROOT, "example.conf")
OUTPUT_PATH = os.path.join(ROOT, "output.json")
RUN_PATH = os.path.join(ROOT, "run_example.py")


def load_parser():
    assert os.path.isfile(PARSER_PATH), f"{PARSER_PATH} does not exist or is not a file."
    spec = importlib.util.spec_from_file_location("submitted_parser", PARSER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "parse_config"), "parser.py does not define parse_config."
    assert callable(module.parse_config), "parse_config is not callable."
    return module.parse_config


def expected_parse(text, env):
    result = {}
    pattern = re.compile(r"\$\{([^}]*)\}")
    for line in text.split("\n"):
        if line.startswith("#") or not line.strip():
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        value = pattern.sub(lambda match: str(env.get(match.group(1), "")), value)
        result[key] = value
    return result


def test_parse_config_varied_inputs():
    parse_config = load_parser()

    fixed_cases = [
        ("a=1\nb=two", {}, {"a": "1", "b": "two"}),
        ("# comment\n\n key = value \ncomplex=a=b=c", {},
         {"key": "value", "complex": "a=b=c"}),
        ("x=${A}-${MISSING}-${A}\ny=pre${B}post", {"A": "ok", "B": "42"},
         {"x": "ok--ok", "y": "pre42post"}),
        ("unknown=${NOPE}/path\nempty=${NOPE}", {},
         {"unknown": "/path", "empty": ""}),
    ]
    for text, env, expected in fixed_cases:
        actual = parse_config(text, env)
        assert actual == expected, f"parse_config({text!r}, {env!r}) returned {actual!r}, expected {expected!r}"

    rng = random.Random(918273)
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    for case_number in range(35):
        env = {
            "VAR0": "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 10))),
            "VAR1": "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 10))),
            "VAR2": "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 10))),
        }
        lines = ["# generated comment", ""]
        count = rng.randint(2, 8)
        for item_number in range(count):
            key = f"key{case_number}_{item_number}"
            literal1 = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 6)))
            literal2 = "".join(rng.choice(alphabet + "=") for _ in range(rng.randint(0, 8)))
            variable = rng.choice(["VAR0", "VAR1", "VAR2", "UNKNOWN"])
            value = literal1 + "${" + variable + "}" + literal2
            if rng.choice([True, False]):
                value += "${VAR0}"
            lines.append(f"  {key}  =  {value}  ")
        text = "\n".join(lines)
        expected = expected_parse(text, env)
        actual = parse_config(text, env)
        assert actual == expected, f"random case {case_number} returned {actual!r}, expected {expected!r}"


def test_requirements_txt():
    req_path = "/home/user/sysconf_parser/requirements.txt"
    assert os.path.exists(req_path), f"{req_path} does not exist."

    with open(req_path, 'r') as f:
        content = f.read().lower()

    assert "pytest" in content, "pytest not found in requirements.txt."
    assert "hypothesis" in content, "hypothesis not found in requirements.txt."

    declared = set()
    for raw_line in content.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        match = re.match(r"^([a-z0-9_.-]+)", line)
        if match:
            declared.add(match.group(1).replace("_", "-").replace(".", "-"))
    assert "pytest" in declared, "requirements.txt does not declare the pytest package."
    assert "hypothesis" in declared, "requirements.txt does not declare the hypothesis package."

    import pytest
    import hypothesis
    assert pytest is not None and hypothesis is not None


def test_test_parser_py():
    test_path = "/home/user/sysconf_parser/test_parser.py"
    assert os.path.exists(test_path), f"{test_path} does not exist."

    with open(test_path, 'r') as f:
        content = f.read()

    assert "hypothesis" in content, "hypothesis not imported in test_parser.py."

    tree = ast.parse(content, filename=test_path)
    genuine_property_test = False
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) or not node.name.startswith("test"):
            continue
        decorators = [part for decorator in node.decorator_list for part in ast.walk(decorator)]
        has_given = any(
            (isinstance(part, ast.Name) and part.id == "given") or
            (isinstance(part, ast.Attribute) and part.attr == "given")
            for part in decorators
        )
        subtree = list(ast.walk(node))
        has_assert = any(isinstance(part, ast.Assert) for part in subtree)
        has_parser_call = any(
            isinstance(part, ast.Call) and (
                (isinstance(part.func, ast.Name) and part.func.id == "parse_config") or
                (isinstance(part.func, ast.Attribute) and part.func.attr == "parse_config")
            ) for part in subtree
        )
        all_parts = subtree + decorators
        has_dict_strategy = any(
            isinstance(part, ast.Call) and (
                (isinstance(part.func, ast.Name) and part.func.id == "dictionaries") or
                (isinstance(part.func, ast.Attribute) and part.func.attr == "dictionaries")
            ) for part in all_parts
        )
        has_text_strategy = any(
            isinstance(part, ast.Call) and (
                (isinstance(part.func, ast.Name) and part.func.id == "text") or
                (isinstance(part.func, ast.Attribute) and part.func.attr == "text")
            ) for part in all_parts
        )
        if has_given and has_assert and has_parser_call and has_dict_strategy and has_text_strategy:
            genuine_property_test = True
            break
    assert genuine_property_test, (
        "test_parser.py must contain a Hypothesis @given property test using dictionary/text "
        "strategies that calls parse_config and asserts the round-trip property."
    )

    result = subprocess.run(["pytest", test_path], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"pytest failed on {test_path}. Output:\n{result.stdout}\n{result.stderr}"


def run_example_and_load():
    result = subprocess.run(
        [sys.executable, RUN_PATH], cwd=ROOT, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"run_example.py failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} was not created by run_example.py."
    with open(OUTPUT_PATH, "r") as handle:
        return json.load(handle)


def test_run_example_reads_and_parses_configuration():
    assert os.path.isfile(RUN_PATH), f"{RUN_PATH} does not exist or is not a file."
    with open(EXAMPLE_PATH, "r") as handle:
        original_example = handle.read()

    probe = (
        "# verifier probe\n"
        "root=${SYSTEM_ROOT}/probe\n"
        "user=${USER}\n"
        "many=left=middle=right\n"
        "unknown=${NOT_DEFINED}/tail\n"
    )
    try:
        with open(EXAMPLE_PATH, "w") as handle:
            handle.write(probe)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        probe_data = run_example_and_load()
        assert probe_data == {
            "root": "/var/lib/probe",
            "user": "admin",
            "many": "left=middle=right",
            "unknown": "/tail",
        }, f"run_example.py did not parse the supplied example.conf correctly: {probe_data!r}"
    finally:
        with open(EXAMPLE_PATH, "w") as handle:
            handle.write(original_example)

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_example_and_load()


def test_output_json():
    output_path = "/home/user/sysconf_parser/output.json"
    assert os.path.exists(output_path), f"{output_path} does not exist."

    with open(output_path, 'r') as f:
        raw = f.read()
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            assert False, f"{output_path} is not valid JSON."

    expected = {
        "host": "localhost",
        "port": "8080",
        "db_path": "/var/lib/db/data.sqlite",
        "fallback_user": "admin",
        "complex_key": "some=value=with=equals",
        "missing_var": "/path"
    }

    assert data == expected, f"Output JSON content is incorrect. Expected {expected}, got {data}"

    content_lines = [line for line in raw.splitlines() if line.strip() not in ("{", "}")]
    assert content_lines, "output.json is not formatted JSON."
    assert all(line.startswith("    ") and not line.startswith("\t") for line in content_lines), (
        "output.json must use 4-space indentation."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
