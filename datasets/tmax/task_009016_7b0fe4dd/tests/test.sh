#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import random
import secrets
import subprocess
import sys


def test_symbol_parser_exists():
    assert os.path.isfile("/home/user/symbol_parser.py"), "symbol_parser.py does not exist."


def test_test_symbol_parser_exists_and_passes():
    path = "/home/user/test_symbol_parser.py"
    assert os.path.isfile(path), "test_symbol_parser.py does not exist."

    # Run pytest on the student's test file.
    result = subprocess.run(
        [sys.executable, "-m", "pytest", path],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"pytest on test_symbol_parser.py failed:\n{result.stdout}\n{result.stderr}"


def test_student_suite_really_uses_hypothesis_strategies():
    path = "/home/user/test_symbol_parser.py"
    with open(path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=path)

    given_names = set()
    strategy_modules = set()
    strategy_functions = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "hypothesis":
                    given_names.add((alias.asname or "hypothesis") + ".given")
                if alias.name == "hypothesis.strategies":
                    strategy_modules.add(alias.asname or "hypothesis.strategies")
        elif isinstance(node, ast.ImportFrom):
            if node.module == "hypothesis":
                for alias in node.names:
                    local = alias.asname or alias.name
                    if alias.name == "given":
                        given_names.add(local)
                    elif alias.name == "strategies":
                        strategy_modules.add(local)
            elif node.module == "hypothesis.strategies":
                for alias in node.names:
                    strategy_functions.add(alias.asname or alias.name)

    def dotted_name(node):
        if isinstance(node, ast.Name):
            return node.id
        if isinstance(node, ast.Attribute):
            prefix = dotted_name(node.value)
            return f"{prefix}.{node.attr}" if prefix else node.attr
        return ""

    found_property_test = False
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) or not node.name.startswith("test"):
            continue
        for decorator in node.decorator_list:
            if not isinstance(decorator, ast.Call):
                continue
            called = dotted_name(decorator.func)
            if called not in given_names and not called.endswith(".given"):
                continue
            uses_strategy = False
            for child in ast.walk(decorator):
                if not isinstance(child, ast.Call):
                    continue
                fn = dotted_name(child.func)
                if fn in strategy_functions or any(fn.startswith(module + ".") for module in strategy_modules):
                    uses_strategy = True
                    break
            if uses_strategy:
                found_property_test = True
                break

    assert found_property_test, (
        "test_symbol_parser.py must contain a pytest test decorated with hypothesis.given "
        "and use hypothesis.strategies in that decorator"
    )


def load_parser():
    path = "/home/user/symbol_parser.py"
    spec = importlib.util.spec_from_file_location("submitted_symbol_parser", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "parse_line", None)), "symbol_parser.py must define parse_line"
    return module.parse_line


def test_parse_line_independently_on_generated_inputs():
    parse_line = load_parser()
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

    for _ in range(40):
        address = f"{rng.getrandbits(64):016x}"
        size_value = rng.getrandbits(64)
        size_hex = f"{size_value:016x}"
        symbol = "s" + "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 30)))
        symbol_type = rng.choice("TDRBWU")
        spaces = [" " * rng.randint(1, 12) for _ in range(3)]
        parsed = parse_line(address + spaces[0] + size_hex + spaces[1] + symbol_type + spaces[2] + symbol)
        assert parsed == {
            "address": address,
            "size": size_value,
            "type": symbol_type,
            "name": symbol,
        }

    undefined_name = "external_" + secrets.token_hex(5)
    assert parse_line("                 U " + undefined_name) == {
        "address": None,
        "size": None,
        "type": "U",
        "name": undefined_name,
    }

    address = f"{rng.getrandbits(64):016x}"
    no_size_name = "nosize_" + secrets.token_hex(5)
    assert parse_line(f"{address}      W   {no_size_name}") == {
        "address": address,
        "size": None,
        "type": "W",
        "name": no_size_name,
    }


def test_analyze_symbols_exists():
    assert os.path.isfile("/home/user/analyze_symbols.py"), "analyze_symbols.py does not exist."


def test_conflicts_json_correct():
    json_path = "/home/user/conflicts.json"
    assert os.path.isfile(json_path), "conflicts.json was not generated."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "conflicts.json is not valid JSON."

    expected_data = {
      "init_widget": [
        {
          "address": "0000000000001000",
          "size": 64,
          "type": "T",
          "name": "init_widget"
        },
        {
          "address": "0000000000003000",
          "size": 128,
          "type": "W",
          "name": "init_widget"
        }
      ],
      "const_data": [
        {
          "address": "0000000000007000",
          "size": 32,
          "type": "R",
          "name": "const_data"
        },
        {
          "address": "0000000000008000",
          "size": 48,
          "type": "R",
          "name": "const_data"
        }
      ]
    }

    assert data == expected_data, f"conflicts.json content does not match expected output.\nExpected: {expected_data}\nGot: {data}"


def test_analysis_script_on_unseen_generated_fixture():
    input_path = "/home/user/nm_output.txt"
    output_path = "/home/user/conflicts.json"
    with open(input_path, "rb") as f:
        original_input = f.read()
    original_output = None
    if os.path.exists(output_path):
        with open(output_path, "rb") as f:
            original_output = f.read()

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    suffix = secrets.token_hex(8)
    names = {
        "size": "size_conflict_" + suffix,
        "type": "type_conflict_" + suffix,
        "same": "same_definition_" + suffix,
        "single": "single_symbol_" + suffix,
        "triple": "triple_conflict_" + suffix,
    }

    records = [
        (0x9100, 0x20, "T", names["size"]),
        (0x1100, 0x40, "T", names["size"]),
        (0x2200, 0x18, "D", names["type"]),
        (0x1200, 0x18, "R", names["type"]),
        (0x3300, 0x30, "B", names["same"]),
        (0x1300, 0x30, "B", names["same"]),
        (0x4400, 0x55, "W", names["single"]),
        (0x6500, 0x10, "T", names["triple"]),
        (0x2500, 0x10, "T", names["triple"]),
        (0x4500, 0x10, "W", names["triple"]),
    ]
    rng.shuffle(records)

    grouped = {}
    for address, size, symbol_type, name in records:
        grouped.setdefault(name, []).append({
            "address": f"{address:016x}",
            "size": size,
            "type": symbol_type,
            "name": name,
        })
    expected = {}
    for name, entries in grouped.items():
        if len(entries) > 1 and (len({e["size"] for e in entries}) > 1 or len({e["type"] for e in entries}) > 1):
            expected[name] = sorted(entries, key=lambda e: e["address"])

    try:
        with open(input_path, "w", encoding="utf-8") as f:
            for address, size, symbol_type, name in records:
                f.write(
                    f"{address:016x}{' ' * rng.randint(1, 9)}"
                    f"{size:016x}{' ' * rng.randint(1, 9)}"
                    f"{symbol_type}{' ' * rng.randint(1, 9)}{name}\n"
                )
        if os.path.exists(output_path):
            os.remove(output_path)

        result = subprocess.run(
            [sys.executable, "/home/user/analyze_symbols.py"],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"analyze_symbols.py failed:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(output_path), "analyze_symbols.py did not generate conflicts.json"
        with open(output_path, "r", encoding="utf-8") as f:
            actual = json.load(f)
        assert actual == expected, f"Analysis failed on an unseen fixture. Expected {expected}, got {actual}"
    finally:
        with open(input_path, "wb") as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
