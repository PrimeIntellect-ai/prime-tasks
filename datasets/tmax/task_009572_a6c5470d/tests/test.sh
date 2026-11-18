#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess

BASE = "/home/user/mathvm"
BENCH_RE = re.compile(r"(?m)^BenchmarkEvaluate(?:-\d+)?\s+\d+\s+[0-9.]+\s+ns/op(?:\s|$)")


def run(cmd, cwd=BASE, timeout=120):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def reference_evaluate(program):
    stack = []
    for line in program.strip().split("\n"):
        parts = line.split()
        if not parts:
            continue
        op = parts[0]
        if op == "PUSH":
            stack.append(int(parts[1]))
        elif op == "ADD":
            a, b = stack.pop(), stack.pop()
            stack.append(b + a)
        elif op == "SUB":
            a, b = stack.pop(), stack.pop()
            stack.append(b - a)
        elif op == "MUL":
            a, b = stack.pop(), stack.pop()
            stack.append(b * a)
        elif op == "DIV":
            a, b = stack.pop(), stack.pop()
            stack.append(b // a)
    return stack[-1] if stack else 0


def generated_programs():
    programs = [
        "",
        "PUSH 0",
        "PUSH -7\nPUSH 3\nDIV",
        "PUSH 7\nPUSH -3\nDIV",
        "PUSH -7\nPUSH -3\nDIV",
        "PUSH 8\nPUSH 3\nSUB\nPUSH -4\nMUL\nPUSH 6\nADD",
    ]
    rng = random.SystemRandom()
    for _ in range(10):
        lines = []
        stack = []
        for _ in range(12):
            if len(stack) < 2 or rng.randrange(3) == 0:
                value = rng.randint(-30, 30)
                lines.append(f"PUSH {value}")
                stack.append(value)
                continue
            choices = ["ADD", "SUB", "MUL"]
            if stack[-1] != 0:
                choices.append("DIV")
            op = rng.choice(choices)
            a, b = stack.pop(), stack.pop()
            if op == "ADD":
                value = b + a
            elif op == "SUB":
                value = b - a
            elif op == "MUL":
                value = b * a
            else:
                value = b // a
            lines.append(op)
            stack.append(value)
        while len(stack) > 1:
            a, b = stack.pop(), stack.pop()
            op = rng.choice(["ADD", "SUB"])
            lines.append(op)
            stack.append(b + a if op == "ADD" else b - a)
        programs.append("\n".join(lines))
    return programs


def test_go_output():
    path = "/home/user/go_output.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "148", f"Expected go_output.txt to contain '148', got '{content}'"


def test_mathvm_directory_and_files():
    assert os.path.isdir(BASE), f"Directory {BASE} does not exist"
    for name in ["vm.go", "main.go", "vm_test.go", "go.mod"]:
        path = os.path.join(BASE, name)
        assert os.path.isfile(path), f"Missing required file: {path}"

    module = run(["go", "list", "-m"])
    assert module.returncode == 0, module.stdout + module.stderr
    assert module.stdout.strip() == "mathvm", f"Expected module name mathvm, got {module.stdout.strip()!r}"


def test_benchmark_results():
    path = "/home/user/benchmark_results.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "BenchmarkEvaluate" in content, f"Expected 'BenchmarkEvaluate' in {path}"
    assert BENCH_RE.search(content), f"{path} does not contain standard Go benchmark output"

    test_source = open(os.path.join(BASE, "vm_test.go"), encoding="utf-8").read()
    assert re.search(r"func\s+BenchmarkEvaluate\s*\(\s*\w+\s+\*testing\.B\s*\)", test_source), \
        "vm_test.go must define func BenchmarkEvaluate(b *testing.B)"
    assert re.search(r"\bEvaluate\s*\(", test_source), "BenchmarkEvaluate must invoke Evaluate"
    assert "test_program.txt" in test_source, "BenchmarkEvaluate must use test_program.txt"

    actual = run(["go", "test", "-run", "^$", "-bench", "^BenchmarkEvaluate$", "-count=1"])
    assert actual.returncode == 0, f"Benchmark execution failed:\n{actual.stdout}\n{actual.stderr}"
    assert BENCH_RE.search(actual.stdout), f"BenchmarkEvaluate did not produce a benchmark result:\n{actual.stdout}"


def test_go_code_compiles_and_tests_pass():
    result = run(["go", "test", "-count=1"])
    assert result.returncode == 0, f"'go test' failed in {BASE}:\n{result.stdout}\n{result.stderr}"

    binary = "/tmp/mathvm-entrypoint"
    result_build = run(["go", "build", "-o", binary, "."])
    assert result_build.returncode == 0, f"'go build .' failed in {BASE}:\n{result_build.stdout}\n{result_build.stderr}"

    programs = generated_programs()

    # Exercise the submitted entrypoint on verifier-generated inputs.
    input_path = "/home/user/test_program.txt"
    output_path = "/home/user/go_output.txt"
    old_input = open(input_path, "rb").read()
    old_output = open(output_path, "rb").read() if os.path.exists(output_path) else None
    try:
        for program in programs:
            with open(input_path, "w", encoding="utf-8") as f:
                f.write(program)
            if os.path.exists(output_path):
                os.remove(output_path)
            executed = subprocess.run([binary], cwd=BASE, capture_output=True, text=True, timeout=20)
            assert executed.returncode == 0, f"Entrypoint failed for {program!r}:\n{executed.stdout}\n{executed.stderr}"
            assert os.path.isfile(output_path), "Entrypoint did not create go_output.txt"
            actual = open(output_path, "rb").read()
            expected = str(reference_evaluate(program)).encode()
            assert actual == expected, f"Entrypoint returned {actual!r}, expected {expected!r} for {program!r}"
    finally:
        with open(input_path, "wb") as f:
            f.write(old_input)
        if old_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(old_output)

    # Replace only the entrypoint temporarily so Evaluate itself is called directly,
    # independently of submitted tests or a submitted TestMain.
    main_path = os.path.join(BASE, "main.go")
    original_main = open(main_path, "rb").read()
    cases = ",\n".join(
        "{" + json.dumps(program) + ", " + str(reference_evaluate(program)) + "}"
        for program in programs
    )
    verifier_main = f'''package main
import ("fmt"; "os")
func main() {{
    cases := []struct {{ program string; want int }}{{
{cases}
    }}
    for _, c := range cases {{
        if got := Evaluate(c.program); got != c.want {{
            fmt.Fprintf(os.Stderr, "Evaluate(%q) = %d, want %d\\n", c.program, got, c.want)
            os.Exit(1)
        }}
    }}
}}
'''
    try:
        with open(main_path, "w", encoding="utf-8") as f:
            f.write(verifier_main)
        direct = run(["go", "run", "."])
        assert direct.returncode == 0, f"Direct Evaluate checks failed:\n{direct.stdout}\n{direct.stderr}"
    finally:
        with open(main_path, "wb") as f:
            f.write(original_main)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
