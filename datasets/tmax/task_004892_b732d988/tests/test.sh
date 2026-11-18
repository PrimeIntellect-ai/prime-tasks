#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import subprocess
import string
import tempfile

ORACLE_PATH = "/app/legacy_calc"
AGENT_PATH = "/home/user/calc"
SOURCE_PATH = "/home/user/calc.go"
N_TESTS = 2000


def generate_invalid_json():
    return random.choice([
        "",
        "{",
        "{\"expression\": \"1 + 1\"",
        "not a json",
        "[1, 2, 3]",
        "{\"expression\": \"1 + 1\", \"context\": {",
    ])


def generate_missing_keys():
    choices = [
        {"expression": "1 + 1"},
        {"context": {"a": 1}},
        {},
        {"expr": "1 + 1", "ctx": {}},
    ]
    return json.dumps(choices)


def generate_valid_expression(depth=0, force_div_zero=False):
    if depth > 3:
        if force_div_zero:
            return "0", []
        if random.random() < 0.5:
            return str(random.randint(0, 100)), []
        var = random.choice(string.ascii_lowercase)
        return var, [var]

    op = random.choice(["+", "-", "*", "/"])
    if force_div_zero and random.random() < 0.5:
        op = "/"

    left, left_vars = generate_valid_expression(depth + 1)
    if op == "/":
        if force_div_zero:
            right, right_vars = generate_valid_expression(depth + 1, True)
            if right != "0":
                right = "0"
        else:
            right, right_vars = generate_valid_expression(depth + 1)
            if right == "0":
                right = "1"
    else:
        right, right_vars = generate_valid_expression(depth + 1, force_div_zero)

    expr = f"{left} {op} {right}"
    if random.random() < 0.3:
        expr = f"({expr})"
    return expr, left_vars + right_vars


def format_expression(expr):
    result = ""
    for char in expr:
        if char in "+-*/()":
            result += " " * random.randint(0, 2) + char + " " * random.randint(0, 2)
        else:
            result += char
    return " ".join(result.split())


def generate_test_cases():
    random.seed(42)
    cases = []

    for _ in range(int(N_TESTS * 0.1)):
        cases.append(generate_invalid_json())
    for _ in range(int(N_TESTS * 0.1)):
        cases.append(generate_missing_keys())

    valid_count = int(N_TESTS * 0.8)
    for _ in range(int(valid_count * 0.25)):
        expr, vars_ = generate_valid_expression()
        corruption = random.choice([
            lambda e: e + " +",
            lambda e: "(" + e,
            lambda e: e + ")",
            lambda e: e.replace("+", "++"),
            lambda e: e + " invalid",
            lambda e: "!" + e,
        ])
        cases.append(json.dumps({
            "expression": corruption(expr),
            "context": {v: random.randint(0, 100) for v in vars_},
        }))

    for _ in range(int(valid_count * 0.125)):
        expr, vars_ = generate_valid_expression(force_div_zero=True)
        if "/ 0" not in expr:
            expr += " / 0"
        cases.append(json.dumps({
            "expression": expr,
            "context": {v: random.randint(0, 100) for v in vars_},
        }))

    for _ in range(int(valid_count * 0.125)):
        expr, vars_ = generate_valid_expression()
        if not vars_:
            expr += " + undefined_var"
            vars_.append("undefined_var")
        ctx = {v: random.randint(0, 100) for v in vars_}
        if vars_:
            ctx.pop(vars_[0], None)
        cases.append(json.dumps({"expression": expr, "context": ctx}))

    for _ in range(int(valid_count * 0.5)):
        expr, vars_ = generate_valid_expression()
        cases.append(json.dumps({
            "expression": format_expression(expr),
            "context": {v: random.randint(1, 100) for v in vars_},
        }))

    random.shuffle(cases)
    return cases


def drop_privileges():
    os.setgroups([])
    os.setgid(65534)
    os.setuid(65534)


def enter_jail(jail):
    os.chroot(jail)
    os.chdir("/")
    drop_privileges()


def run_process(executable, input_data, preexec_fn=None):
    try:
        result = subprocess.run(
            [executable],
            input=input_data.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=1,
            preexec_fn=preexec_fn,
        )
        return result.stdout.decode("utf-8")
    except subprocess.TimeoutExpired:
        return "<TIMEOUT>"
    except Exception as exc:
        return f"<ERROR: {exc}>"


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent executable missing at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable {AGENT_PATH} is not executable"
    assert os.path.isfile(SOURCE_PATH), f"Go source missing at {SOURCE_PATH}"

    go_info = subprocess.run(
        ["go", "version", "-m", AGENT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert go_info.returncode == 0 and "go1." in go_info.stdout, (
        f"{AGENT_PATH} is not a Go executable"
    )

    build_dir = tempfile.mkdtemp(prefix="calc-build-")
    jail_dir = tempfile.mkdtemp(prefix="calc-jail-")
    try:
        isolated_source = os.path.join(build_dir, "calc.go")
        rebuilt_binary = os.path.join(build_dir, "calc")
        shutil.copyfile(SOURCE_PATH, isolated_source)
        build = subprocess.run(
            ["go", "build", "-trimpath", "-o", rebuilt_binary, isolated_source],
            cwd=build_dir,
            env={**os.environ, "CGO_ENABLED": "0", "GO111MODULE": "off"},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, f"calc.go does not build as Go source:\n{build.stderr}"

        jailed_binary = os.path.join(jail_dir, "calc")
        shutil.copyfile(rebuilt_binary, jailed_binary)
        os.chmod(jailed_binary, 0o755)
        os.chmod(jail_dir, 0o755)

        test_cases = generate_test_cases()
        expected = [run_process(ORACLE_PATH, case) for case in test_cases]

        app_mode = os.stat("/app").st_mode & 0o7777
        os.chmod("/app", 0o700)
        try:
            for i, (case, oracle_out) in enumerate(zip(test_cases, expected)):
                agent_out = run_process(AGENT_PATH, case, drop_privileges)
                assert oracle_out == agent_out, (
                    f"Mismatch from /home/user/calc on test case {i + 1}:\n"
                    f"Input: {case}\n"
                    f"Oracle output: {oracle_out!r}\n"
                    f"Agent output:  {agent_out!r}"
                )

                rebuilt_out = run_process(
                    "/calc", case, lambda: enter_jail(jail_dir)
                )
                assert oracle_out == rebuilt_out, (
                    f"Mismatch from independently rebuilt calc.go on test case {i + 1}:\n"
                    f"Input: {case}\n"
                    f"Oracle output: {oracle_out!r}\n"
                    f"Rebuilt output: {rebuilt_out!r}"
                )
        finally:
            os.chmod("/app", app_mode)
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)
        shutil.rmtree(jail_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
