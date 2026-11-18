#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess

SOURCE = "/home/user/router_solver.cpp"
BINARY = "/home/user/router_solver"
SCRIPT = "/home/user/test.sh"
OUTPUT = "/home/user/output.json"
REBUILT = "/tmp/router_solver_rebuilt"
EXACT_URL = "/route/calc?eq=x*x+y*y&res=25&range=1,10"


def run_solver(executable, url):
    result = subprocess.run(
        [executable, url], capture_output=True, text=True, timeout=5
    )
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise AssertionError(
            f"{executable} returned invalid JSON for {url!r}: {result.stdout!r}"
        ) from exc
    return result, data


def eval_expression(expression, x, y):
    total = 0
    for term in expression.split("+"):
        product = 1
        for variable in term.split("*"):
            assert variable in ("x", "y")
            product *= x if variable == "x" else y
        total += product
    return total


def expected_solution(expression, target, low, high):
    for x in range(low, high + 1):
        for y in range(x, high + 1):
            if eval_expression(expression, x, y) == target:
                return {"x": x, "y": y}
    return {"error": "no solution"}


def assert_case(executable, expression, target, low, high):
    url = f"/route/calc?eq={expression}&res={target}&range={low},{high}"
    expected = expected_solution(expression, target, low, high)
    result, data = run_solver(executable, url)
    assert result.returncode == 0, (
        f"Expected exit code 0 for valid route {url!r}, got {result.returncode}"
    )
    assert data == expected, f"For {url!r}, expected {expected}, got {data}"


def test_files_exist():
    assert os.path.exists(SOURCE), "/home/user/router_solver.cpp is missing"
    assert os.path.exists(BINARY), "/home/user/router_solver is missing"
    assert os.path.exists(SCRIPT), "/home/user/test.sh is missing"
    assert os.path.exists(OUTPUT), "/home/user/output.json is missing"


def test_executables():
    assert os.access(BINARY, os.X_OK), "/home/user/router_solver is not executable"
    assert os.access(SCRIPT, os.X_OK), "/home/user/test.sh is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/router_solver is not a compiled ELF executable"


def test_output_json_content():
    with open(OUTPUT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/output.json does not contain valid JSON"

    assert "x" in data and "y" in data, "output.json must contain 'x' and 'y' keys"
    assert data["x"] == 3, f"Expected x to be 3, got {data['x']}"
    assert data["y"] == 4, f"Expected y to be 4, got {data['y']}"


def test_router_solver_logic_bad_route():
    cmd = [BINARY, "/bad/route?eq=x+y&res=5&range=1,10"]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    assert result.returncode == 1, "Expected exit code 1 for invalid route"
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        assert False, "Output for invalid route is not valid JSON"
    assert data.get("error") == "not found", "Expected error: 'not found' for invalid route"


def test_router_solver_logic_no_solution():
    cmd = [BINARY, "/route/calc?eq=x+y&res=100&range=1,10"]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, "Expected exit code 0 for valid route but no solution"
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        assert False, "Output for no solution is not valid JSON"
    assert data.get("error") == "no solution", "Expected error: 'no solution' when no solution exists"


def test_router_solver_logic_valid_solution():
    cmd = [BINARY, "/route/calc?eq=x*y+y&res=27&range=1,10"]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, "Expected exit code 0 for valid route"
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        assert False, "Output for valid solution is not valid JSON"
    assert data.get("x") == 2, f"Expected x=2, got {data.get('x')}"
    assert data.get("y") == 9, f"Expected y=9, got {data.get('y')}"


def test_source_compiles():
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-o", REBUILT, SOURCE],
        capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"router_solver.cpp failed to compile:\n{result.stderr}"
    assert os.access(REBUILT, os.X_OK), "Rebuilt router_solver is not executable"


def test_dynamic_expression_range_and_search_logic():
    if not os.path.exists(REBUILT):
        test_source_compiles()

    rng = secrets.SystemRandom()
    expressions = ["x*y+x", "x+x*y", "x*y+y*x", "x*x+y+y*x"]
    for _ in range(24):
        count = rng.randint(3, 8)
        tokens = [rng.choice(("x", "y"))]
        tokens.extend(
            item
            for _ in range(count - 1)
            for item in (rng.choice(("+", "*")), rng.choice(("x", "y")))
        )
        expressions.append("".join(tokens))

    cases = []
    for index, expression in enumerate(expressions):
        low = rng.randint(-5, 3)
        high = low + rng.randint(3, 9)
        values = {
            eval_expression(expression, x, y)
            for x in range(low, high + 1)
            for y in range(x, high + 1)
        }
        if index % 3:
            target = rng.choice(tuple(values))
        else:
            target = max(values) + rng.randint(1, 29)
            while target in values:
                target += 1
        cases.append((expression, target, low, high))

    for executable in (BINARY, REBUILT):
        for case in cases:
            assert_case(executable, *case)

        for _ in range(4):
            bad_path = "/" + secrets.token_hex(9)
            url = f"{bad_path}?eq=x+y&res={rng.randint(-20, 20)}&range=-3,7"
            result, data = run_solver(executable, url)
            assert result.returncode == 1, f"Expected exit code 1 for invalid path {bad_path}"
            assert data == {"error": "not found"}, f"Unexpected invalid-route response: {data}"


def test_shell_script_runs_solver_with_exact_argument_and_redirects_output():
    normal = subprocess.run([SCRIPT], cwd="/home/user", capture_output=True, text=True, timeout=10)
    assert normal.returncode == 0, f"test.sh failed: {normal.stderr}"
    with open(OUTPUT) as f:
        assert json.load(f) == {"x": 3, "y": 4}, "test.sh did not produce the required result"

    backup = "/tmp/router_solver.original"
    marker = f"/tmp/router_solver_called_{secrets.token_hex(12)}"
    probe_x = secrets.randbelow(500) + 100
    probe_y = probe_x + secrets.randbelow(500) + 1
    os.replace(BINARY, backup)
    try:
        wrapper = f'''#!/bin/bash
if [ "$#" -eq 1 ] && [ "$1" = '{EXACT_URL}' ]; then
    printf '%s' "$1" > '{marker}'
    printf '{{"x": {probe_x}, "y": {probe_y}}}\\n'
    exit 0
fi
exit 73
'''
        with open(BINARY, "w") as f:
            f.write(wrapper)
        os.chmod(BINARY, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                          stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
        probe = subprocess.run([SCRIPT], cwd="/home/user", capture_output=True, text=True, timeout=10)
        assert probe.returncode == 0, "test.sh failed while invoking router_solver"
        assert os.path.exists(marker), "test.sh did not invoke router_solver with the exact required URL"
        with open(marker) as f:
            assert f.read() == EXACT_URL
        with open(OUTPUT) as f:
            assert json.load(f) == {"x": probe_x, "y": probe_y}, (
                "test.sh did not redirect router_solver standard output to output.json"
            )
    finally:
        if os.path.exists(BINARY):
            os.remove(BINARY)
        os.replace(backup, BINARY)
        if os.path.exists(marker):
            os.remove(marker)

    final = subprocess.run([SCRIPT], cwd="/home/user", capture_output=True, text=True, timeout=10)
    assert final.returncode == 0, f"test.sh failed after restoring executable: {final.stderr}"
    with open(OUTPUT) as f:
        assert json.load(f) == {"x": 3, "y": 4}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
