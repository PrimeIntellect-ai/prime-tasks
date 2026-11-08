#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import secrets
import stat
import subprocess
from pathlib import Path

PROJECT_DIR = Path("/home/user/polyglot-eval")
BUILD_AND_RUN_SCRIPT = PROJECT_DIR / "build_and_run.sh"
CMAKELISTS = PROJECT_DIR / "CMakeLists.txt"
TEST_RUNNER = PROJECT_DIR / "tests/test_runner.cpp"
RESULTS_TXT = PROJECT_DIR / "results.txt"
GENERATE_DATA = PROJECT_DIR / "scripts/generate_data.py"
EXPR_EVAL_BIN = PROJECT_DIR / "build/expr_eval"


def run(cmd, **kwargs):
    kwargs.setdefault("timeout", 180)
    return subprocess.run(cmd, **kwargs)


def canonical_generator_output():
    return [f"{i} + {i * 2}" for i in range(1, 101)]


def expected_for(expressions):
    answers = []
    for expression in expressions:
        a, op, b = expression.split()
        a, b = int(a), int(b)
        if op == "+":
            answers.append(str(a + b))
        elif op == "-":
            answers.append(str(a - b))
        elif op == "*":
            answers.append(str(a * b))
        else:
            raise AssertionError(f"Unsupported verifier expression: {expression}")
    return answers


def output_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def test_build_and_run_script_exists_and_executable():
    assert BUILD_AND_RUN_SCRIPT.is_file(), f"{BUILD_AND_RUN_SCRIPT} does not exist."
    st = BUILD_AND_RUN_SCRIPT.stat()
    assert bool(st.st_mode & stat.S_IXUSR), f"{BUILD_AND_RUN_SCRIPT} is not executable."


def test_cmake_lists_exists_and_targets():
    assert CMAKELISTS.is_file(), f"{CMAKELISTS} does not exist."
    content = CMAKELISTS.read_text()
    assert "expr_lib" in content, "CMakeLists.txt does not contain 'expr_lib' target."
    assert "expr_eval" in content, "CMakeLists.txt does not contain 'expr_eval' target."
    assert "test_runner" in content, "CMakeLists.txt does not contain 'test_runner' target."
    assert re.search(r"CMAKE_CXX_STANDARD\s+17", content, re.I), "CMake does not set C++17."


def test_test_runner_exists():
    assert TEST_RUNNER.is_file(), f"{TEST_RUNNER} does not exist."
    content = TEST_RUNNER.read_text()
    assert "ast.h" in content, "test_runner.cpp does not include ast.h"
    assert "evaluator.h" in content, "test_runner.cpp does not include evaluator.h"


def test_real_cmake_targets_and_clean_build():
    build = Path("/tmp/polyglot-verifier-build")
    subprocess.run(["rm", "-rf", str(build)], check=True)
    query = build / ".cmake/api/v1/query"
    query.mkdir(parents=True)
    (query / "codemodel-v2").write_text("")

    configured = run(
        ["cmake", "-S", str(PROJECT_DIR), "-B", str(build)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert configured.returncode == 0, configured.stdout + configured.stderr
    built = run(
        ["cmake", "--build", str(build), "--target", "expr_lib", "expr_eval", "test_runner", "-j2"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert built.returncode == 0, built.stdout + built.stderr

    indexes = glob.glob(str(build / ".cmake/api/v1/reply/index-*.json"))
    assert indexes, "CMake file-api reply was not produced"
    index = json.loads(Path(indexes[0]).read_text())
    cm_file = index["reply"]["codemodel-v2"]["jsonFile"]
    codemodel = json.loads((build / ".cmake/api/v1/reply" / cm_file).read_text())
    config = codemodel["configurations"][0]
    refs = {target["name"]: target for target in config["targets"]}
    for name in ("expr_lib", "expr_eval", "test_runner"):
        assert name in refs, f"CMake target {name} does not actually exist"

    details = {}
    for name, ref in refs.items():
        details[name] = json.loads((build / ".cmake/api/v1/reply" / ref["jsonFile"]).read_text())

    assert details["expr_lib"]["type"] in ("STATIC_LIBRARY", "SHARED_LIBRARY", "MODULE_LIBRARY")
    assert details["expr_eval"]["type"] == "EXECUTABLE"
    assert details["test_runner"]["type"] == "EXECUTABLE"

    lib_sources = {Path(item["path"]).name for item in details["expr_lib"].get("sources", [])}
    eval_sources = {Path(item["path"]).name for item in details["expr_eval"].get("sources", [])}
    runner_sources = {Path(item["path"]).name for item in details["test_runner"].get("sources", [])}
    assert {"ast.cpp", "evaluator.cpp"}.issubset(lib_sources), "expr_lib must compile ast.cpp and evaluator.cpp"
    assert "main.cpp" in eval_sources, "expr_eval must compile main.cpp"
    assert "test_runner.cpp" in runner_sources, "test_runner must compile tests/test_runner.cpp"

    lib_id = refs["expr_lib"]["id"]
    for name in ("expr_eval", "test_runner"):
        dependency_ids = {item["id"] for item in details[name].get("dependencies", [])}
        assert lib_id in dependency_ids, f"{name} is not linked to expr_lib"

    def artifact(name):
        artifacts = details[name].get("artifacts", [])
        assert artifacts, f"No executable artifact for {name}"
        return build / artifacts[0]["path"]

    runner = run([str(artifact("test_runner"))], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert runner.returncode == 0, f"test_runner failed:\n{runner.stdout}\n{runner.stderr}"

    expressions = []
    for _ in range(40):
        a = secrets.randbelow(2001) - 1000
        b = secrets.randbelow(2001) - 1000
        op = secrets.choice(["+", "-", "*"])
        expressions.append(f"{a} {op} {b}")
    payload = "\n".join(expressions) + "\n"
    evaluated = run(
        [str(artifact("expr_eval"))], input=payload,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert evaluated.returncode == 0, evaluated.stderr
    assert output_lines(evaluated.stdout) == expected_for(expressions)


def test_build_and_run_execution():
    before = run(["python3", str(GENERATE_DATA)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert before.returncode == 0, before.stderr
    assert output_lines(before.stdout) == canonical_generator_output(), "The provided data generator was modified"

    result = run(
        [str(BUILD_AND_RUN_SCRIPT)], cwd=PROJECT_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, (
        f"build_and_run.sh failed with return code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_results_txt_content():
    assert RESULTS_TXT.is_file(), f"{RESULTS_TXT} was not created."
    gen_result = run(
        ["python3", str(GENERATE_DATA)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert gen_result.returncode == 0, gen_result.stderr

    expected_results = []
    for line in gen_result.stdout.strip().split("\n"):
        if not line.strip():
            continue
        try:
            expected_results.append(str(eval(line, {"__builtins__": {}}, {})))
        except Exception:
            pass

    actual_results = output_lines(RESULTS_TXT.read_text())
    assert len(actual_results) == len(expected_results), (
        f"Expected {len(expected_results)} results, got {len(actual_results)} in results.txt"
    )
    for i, (actual, expected) in enumerate(zip(actual_results, expected_results)):
        assert actual == expected, f"Mismatch at line {i+1}: expected {expected}, got {actual}"

    canonical = canonical_generator_output()
    assert output_lines(gen_result.stdout) == canonical, "The provided generator no longer emits its data set"
    assert actual_results == expected_for(canonical), "results.txt does not contain the canonical pipeline results"


def test_valgrind_clean():
    assert EXPR_EVAL_BIN.is_file(), f"Executable {EXPR_EVAL_BIN} not found. Did the build succeed?"
    expressions = []
    for _ in range(60):
        a = secrets.randbelow(10001) - 5000
        b = secrets.randbelow(10001) - 5000
        expressions.append(f"{a} {secrets.choice(['+', '-', '*'])} {b}")
    payload = "\n".join(expressions) + "\n"
    result = run(
        ["valgrind", "--leak-check=full", "--errors-for-leak-kinds=all", "--error-exitcode=1", str(EXPR_EVAL_BIN)],
        input=payload, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, f"Valgrind reported memory errors or leaks.\nSTDERR:\n{result.stderr}"
    assert output_lines(result.stdout) == expected_for(expressions)


def test_ast_fixture_directly_under_valgrind():
    source = Path("/tmp/ast_ownership_fixture.cpp")
    binary = Path("/tmp/ast_ownership_fixture")
    source.write_text(r'''
#include "ast.h"
#include "evaluator.h"
#include <memory>
#include <type_traits>

template<class Node>
std::unique_ptr<Node> binary_node(char op, std::unique_ptr<Node> left, std::unique_ptr<Node> right) {
    if constexpr (std::is_constructible_v<Node, char, Node*, Node*>) {
        return std::unique_ptr<Node>(new Node(op, left.release(), right.release()));
    } else {
        return std::make_unique<Node>(op, std::move(left), std::move(right));
    }
}

int main() {
    auto sum = binary_node<ASTNode>('+', std::make_unique<ASTNode>(10), std::make_unique<ASTNode>(20));
    auto root = binary_node<ASTNode>('*', std::move(sum), std::make_unique<ASTNode>(2));
    if (evaluate(*root) != 60) return 2;
    if (evaluate(*root) != 60) return 3;
    return 0;
}
''')
    compiled = run([
        "g++", "-std=c++17", "-I", str(PROJECT_DIR / "src"),
        str(source), str(PROJECT_DIR / "src/ast.cpp"), str(PROJECT_DIR / "src/evaluator.cpp"),
        "-o", str(binary)
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert compiled.returncode == 0, compiled.stdout + compiled.stderr
    checked = run([
        "valgrind", "--leak-check=full", "--errors-for-leak-kinds=all", "--error-exitcode=1", str(binary)
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert checked.returncode == 0, checked.stdout + checked.stderr


def test_pipeline_runs_test_runner_and_generator():
    original_runner = TEST_RUNNER.read_bytes()
    original_generator = GENERATE_DATA.read_bytes()
    marker = Path(f"/tmp/polyglot-generator-{secrets.token_hex(8)}")
    try:
        TEST_RUNNER.write_text("int main() { return 37; }\n")
        failed = run(
            [str(BUILD_AND_RUN_SCRIPT)], cwd=PROJECT_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert failed.returncode != 0, "build_and_run.sh succeeds even when test_runner fails"

        TEST_RUNNER.write_bytes(original_runner)
        expressions = []
        for _ in range(47):
            a = secrets.randbelow(4001) - 2000
            b = secrets.randbelow(4001) - 2000
            expressions.append(f"{a} {secrets.choice(['+', '-', '*'])} {b}")
        GENERATE_DATA.write_text(
            "from pathlib import Path\n"
            f"Path({str(marker)!r}).write_text('called')\n"
            f"for line in {expressions!r}:\n"
            "    print(line)\n"
        )
        if marker.exists():
            marker.unlink()
        result = run(
            [str(BUILD_AND_RUN_SCRIPT)], cwd=PROJECT_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert result.returncode == 0, result.stdout + result.stderr
        assert marker.is_file(), "build_and_run.sh did not invoke scripts/generate_data.py"
        assert RESULTS_TXT.is_file(), "build_and_run.sh did not create results.txt"
        assert output_lines(RESULTS_TXT.read_text()) == expected_for(expressions), (
            "The pipeline did not send the generated expressions through expr_eval"
        )
    finally:
        TEST_RUNNER.write_bytes(original_runner)
        GENERATE_DATA.write_bytes(original_generator)
        if marker.exists():
            marker.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
