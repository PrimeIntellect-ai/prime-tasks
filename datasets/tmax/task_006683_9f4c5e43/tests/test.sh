#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import py_compile
import secrets
import subprocess
import tempfile


def test_dfa_models_dir():
    assert os.path.isdir("/home/user/dfa_models"), "/home/user/dfa_models/ directory is missing."
    assert os.path.isfile("/home/user/dfa_models/m1.dfa"), "m1.dfa is missing from /home/user/dfa_models/."
    assert os.path.isfile("/home/user/dfa_models/m2.dfa"), "m2.dfa is missing from /home/user/dfa_models/."


def test_m2_dfa_patched():
    m2_path = "/home/user/dfa_models/m2.dfa"
    assert os.path.isfile(m2_path), f"{m2_path} is missing."
    with open(m2_path, "r") as f:
        content = f.read()
    assert "q2, 1 -> q2" in content, "m2.dfa does not contain the patched transition 'q2, 1 -> q2'."
    assert "q2, 1 -> q0" not in content, "m2.dfa still contains the buggy transition 'q2, 1 -> q0'."


def test_simulator_exists_and_valid():
    sim_path = "/home/user/simulator.py"
    assert os.path.isfile(sim_path), f"{sim_path} is missing."
    try:
        py_compile.compile(sim_path, doraise=True)
    except Exception as e:
        assert False, f"simulator.py contains invalid Python code: {e}"

    result = subprocess.run(
        ["python3", "-c", "import simulator"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        "simulator.py cannot be safely imported.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_test_simulator_passes():
    test_path = "/home/user/test_simulator.py"
    assert os.path.isfile(test_path), f"{test_path} is missing."

    with open(test_path, "r") as f:
        content = f.read()
    assert "unittest" in content, "test_simulator.py does not seem to use the 'unittest' framework."

    tree = ast.parse(content, filename=test_path)
    imported_simulator = any(
        (isinstance(node, ast.Import) and any(alias.name == "simulator" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "simulator")
        for node in ast.walk(tree)
    )
    assert imported_simulator, "test_simulator.py must import simulator logic directly."
    test_methods = [
        node for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test")
    ]
    assert len(test_methods) >= 2, "test_simulator.py must define at least two unit tests."

    result = subprocess.run(
        ["python3", "-m", "unittest", test_path],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"test_simulator.py failed to run successfully.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def write_dfa(path, states, start, accepts, transitions):
    with open(path, "w") as f:
        f.write("STATES: " + ", ".join(states) + "\n")
        f.write("START: " + start + "\n")
        f.write("ACCEPT: " + ", ".join(accepts) + "\n")
        f.write("TRANSITIONS:\n")
        for (state, symbol), target in transitions.items():
            f.write(f"{state}, {symbol} -> {target}\n")


def oracle_result(start, accepts, transitions, input_string):
    state = start
    for symbol in input_string:
        key = (state, symbol)
        if key not in transitions:
            return "REJECT"
        state = transitions[key]
    return "ACCEPT" if state in accepts else "REJECT"


def run_simulator(path, input_string):
    result = subprocess.run(
        ["python3", "/home/user/simulator.py", path, input_string],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"simulator.py failed for {path!r} and input {input_string!r}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    return result.stdout.strip()


def test_simulator_behavior_on_generated_dfas():
    rng = secrets.SystemRandom()
    with tempfile.TemporaryDirectory() as tmpdir:
        cases = [
            (["start", "other"], "start", ["start"], {}, ""),
            (["start", "other"], "start", ["other"], {}, "1"),
            (["a", "b"], "a", ["b"], {("a", "0"): "a", ("a", "1"): "b", ("b", "0"): "b", ("b", "1"): "a"}, "001"),
            (["a", "b"], "a", ["b"], {("a", "0"): "a", ("a", "1"): "b", ("b", "0"): "b", ("b", "1"): "a"}, "0011"),
        ]

        for i in range(24):
            states = [f"state_{i}_{j}" for j in range(rng.randint(2, 7))]
            start = rng.choice(states)
            accepts = [state for state in states if rng.randrange(2)]
            transitions = {}
            for state in states:
                for symbol in "01":
                    if rng.randrange(5) != 0:
                        transitions[(state, symbol)] = rng.choice(states)
            input_string = "".join(rng.choice("01") for _ in range(rng.randint(0, 18)))
            cases.append((states, start, accepts, transitions, input_string))

        observed = set()
        for index, (states, start, accepts, transitions, input_string) in enumerate(cases):
            path = os.path.join(tmpdir, f"generated_{index}_{secrets.token_hex(4)}.dfa")
            write_dfa(path, states, start, accepts, transitions)
            expected = oracle_result(start, set(accepts), transitions, input_string)
            actual = run_simulator(path, input_string)
            assert actual == expected, (
                f"Wrong result for generated DFA and input {input_string!r}: "
                f"expected {expected}, got {actual!r}"
            )
            observed.add(expected)
        assert observed == {"ACCEPT", "REJECT"}


def parse_for_oracle(path):
    states = []
    start = None
    accepts = set()
    transitions = {}
    in_transitions = False
    with open(path) as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith("STATES:"):
                states = [x.strip() for x in line.split(":", 1)[1].split(",") if x.strip()]
            elif line.startswith("START:"):
                start = line.split(":", 1)[1].strip()
            elif line.startswith("ACCEPT:"):
                accepts = {x.strip() for x in line.split(":", 1)[1].split(",") if x.strip()}
            elif line == "TRANSITIONS:":
                in_transitions = True
            elif in_transitions:
                left, target = line.split("->", 1)
                state, symbol = [x.strip() for x in left.split(",", 1)]
                transitions[(state, symbol)] = target.strip()
    assert states and start in states
    return start, accepts, transitions


def test_evaluation_log():
    log_path = "/home/user/evaluation.log"
    assert os.path.isfile(log_path), f"{log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = "m1.dfa: REJECT\nm2.dfa: ACCEPT"
    assert content == expected_content, f"evaluation.log content is incorrect. Expected:\n{expected_content}\nGot:\n{content}"

    derived_lines = []
    for filename in ["m1.dfa", "m2.dfa"]:
        path = os.path.join("/home/user/dfa_models", filename)
        start, accepts, transitions = parse_for_oracle(path)
        expected = oracle_result(start, accepts, transitions, "110011")
        actual = run_simulator(path, "110011")
        assert actual == expected, f"simulator.py produced the wrong result for {filename}."
        derived_lines.append(f"{filename}: {expected}")
    assert content == "\n".join(derived_lines), "evaluation.log does not match actual independently derived simulator results."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
