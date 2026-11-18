#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import secrets
import string
import subprocess

HOME = "/home/user"
ROUTER = f"{HOME}/router_port.py"
TESTS = f"{HOME}/test_router.py"
CI = f"{HOME}/ci_test.sh"
ORACLE = "/app/legacy_router"
RNG = secrets.SystemRandom()


def test_files_exist():
    assert os.path.exists(ROUTER), "router_port.py is missing"
    assert os.path.exists(TESTS), "test_router.py is missing"
    assert os.path.exists(CI), "ci_test.sh is missing"
    assert os.access(CI, os.X_OK), "ci_test.sh is not executable"


def test_router_is_pure_python():
    with open(ROUTER, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=ROUTER)

    forbidden_imports = {"subprocess", "ctypes"}
    forbidden_os_calls = {
        "system", "popen", "fork", "forkpty",
        "execl", "execle", "execlp", "execlpe", "execv", "execve",
        "execvp", "execvpe", "posix_spawn", "posix_spawnp",
        "spawnl", "spawnle", "spawnlp", "spawnlpe", "spawnv",
        "spawnve", "spawnvp", "spawnvpe",
    }

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                assert alias.name.split(".")[0] not in forbidden_imports, \
                    f"router_port.py may not import {alias.name}"
        elif isinstance(node, ast.ImportFrom) and node.module:
            assert node.module.split(".")[0] not in forbidden_imports, \
                f"router_port.py may not import {node.module}"
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if isinstance(node.func.value, ast.Name) and node.func.value.id == "os":
                assert node.func.attr not in forbidden_os_calls, \
                    f"router_port.py may not launch external processes with os.{node.func.attr}"

    lowered = source.lower()
    assert "legacy_router" not in lowered, "router_port.py must not invoke the legacy binary"
    assert "__import__" not in source, "router_port.py may not use dynamic imports"


def test_property_suite_is_real_and_passes():
    with open(TESTS, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=TESTS)

    imports_hypothesis = False
    has_given_test = False
    process_calls = 0
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports_hypothesis |= any(a.name.split(".")[0] == "hypothesis" for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports_hypothesis |= node.module.split(".")[0] == "hypothesis"
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for dec in node.decorator_list:
                target = dec.func if isinstance(dec, ast.Call) else dec
                if (isinstance(target, ast.Name) and target.id == "given") or \
                   (isinstance(target, ast.Attribute) and target.attr == "given"):
                    has_given_test = True
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr in {"run", "Popen", "check_call", "check_output"}:
                process_calls += 1

    assert imports_hypothesis, "test_router.py must use hypothesis"
    assert has_given_test, "test_router.py must contain a Hypothesis @given property test"
    assert "legacy_router" in source, "property tests must execute the legacy binary"
    assert "router_port.py" in source, "property tests must execute router_port.py"
    assert process_calls >= 2, "property tests must execute and compare both implementations"

    proc = subprocess.run(
        ["python3", "-m", "pytest", TESTS, "-x", "--tb=short"],
        cwd=HOME, capture_output=True, text=True, timeout=420
    )
    assert proc.returncode == 0, (
        "test_router.py did not pass when run by pytest\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )


def test_ci_script_sets_up_and_runs_tests():
    with open(CI, "r", encoding="utf-8") as f:
        raw = f.read()
    active = "\n".join(
        line for line in raw.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )
    normalized = re.sub(r"\\\s*\n", " ", active)

    assert re.search(r"(?:python(?:3)?\s+-m\s+venv|virtualenv)\b", normalized), \
        "ci_test.sh must create a virtual environment"
    assert re.search(r"(?:pip(?:3)?|python(?:3)?\s+-m\s+pip)\s+install\b", normalized), \
        "ci_test.sh must install test dependencies"

    dependency_text = normalized.lower()
    for match in re.finditer(r"(?:-r|--requirement)\s+([^\s;]+)", normalized):
        req = match.group(1).strip("'\"")
        if not os.path.isabs(req):
            req = os.path.join(HOME, req)
        if os.path.isfile(req):
            with open(req, "r", encoding="utf-8", errors="replace") as f:
                dependency_text += "\n" + f.read().lower()
    assert "pytest" in dependency_text and "hypothesis" in dependency_text, \
        "ci_test.sh must install pytest and hypothesis"
    assert re.search(r"(?:^|[;&|\s])(?:pytest|python(?:3)?\s+-m\s+pytest)\b", normalized), \
        "ci_test.sh must run pytest"

    proc = subprocess.run(
        [CI], cwd=HOME, capture_output=True, text=True, timeout=420
    )
    assert proc.returncode == 0, (
        "ci_test.sh failed\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )


def random_piece(min_len=0, max_len=24):
    alphabet = string.ascii_letters + string.digits + "-._~!$'()*+,;=:@%"
    return "".join(RNG.choice(alphabet) for _ in range(RNG.randint(min_len, max_len)))


def generate_random_url():
    schemes = ["http", "https", "ftp", "gopher", "custom+v1", ""]
    hosts = [
        "example.com", "localhost", "127.0.0.1", "[::1]", "test.org",
        random_piece(1, 12) + "." + random_piece(1, 8), ""
    ]
    segments = [
        "api", "v1", "..", ".", "", "%20", "%2F", "%e2%98%83",
        "%FF", "%", "%2", "a+b", "é", "☃", random_piece()
    ]
    path = "/" + "/".join(RNG.choice(segments) for _ in range(RNG.randint(0, 12)))
    if RNG.randrange(4) == 0:
        path += "/"

    pairs = []
    for _ in range(RNG.randint(0, 10)):
        key = RNG.choice(["a", "b", "", "x+y", "%61", "%FF", random_piece(0, 10)])
        value = RNG.choice(["", "1", "%20", "%E2%98%83", "+", "%", random_piece(0, 14)])
        pairs.append(key + ("=" + value if RNG.randrange(5) else ""))
    query = "&".join(pairs)

    scheme = RNG.choice(schemes)
    host = RNG.choice(hosts)
    url = (scheme + "://" if scheme else "") + host + path
    if query or RNG.randrange(8) == 0:
        url += "?" + query
    if RNG.randrange(5) == 0:
        url += "#" + random_piece(0, 20)
    return url


def generate_random_string():
    alphabet = string.printable + "☃🚀é中\u2028\u2029"
    length = RNG.randint(0, 500)
    return "".join(RNG.choice(alphabet) for _ in range(length))


def compare_one(inp):
    oracle_proc = subprocess.run([ORACLE, inp], capture_output=True, text=True)
    agent_proc = subprocess.run(
        ["python3", ROUTER, inp], capture_output=True, text=True, timeout=10
    )
    assert agent_proc.returncode == oracle_proc.returncode, (
        f"Exit code mismatch on input {inp!r}.\n"
        f"Oracle: {oracle_proc.returncode}\nAgent: {agent_proc.returncode}\n"
        f"Oracle stdout: {oracle_proc.stdout!r}\nAgent stdout: {agent_proc.stdout!r}"
    )
    assert agent_proc.stdout == oracle_proc.stdout, (
        f"Stdout mismatch on input {inp!r}.\n"
        f"Oracle stdout: {oracle_proc.stdout!r}\nAgent stdout: {agent_proc.stdout!r}"
    )


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE), "Oracle binary missing"
    targeted = [
        "", "http://example.com", "http://example.com/", "http://example.com/a/../b/",
        "https://example.com/%E2%98%83?b=2&a=1&a=&x=%20",
        "ftp://localhost//a///b?z&z=2", "not a url", "://", "http:///missing-host",
        "custom+v1://host/a%2Fb/%FF?q=hello+world&%61=2", "http://[::1]/./x/../../y"
    ]
    for inp in targeted:
        compare_one(inp)
    for _ in range(1200):
        compare_one(generate_random_url())
    for _ in range(800):
        compare_one(generate_random_string())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
