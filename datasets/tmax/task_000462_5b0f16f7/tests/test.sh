#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import shutil
import subprocess
import tempfile
import uuid

SCRIPT = "/home/user/organizer.sh"


def run_script(config, timeout=15):
    return subprocess.run(
        [SCRIPT, config],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def expected_topological_order(dependencies):
    reverse = {name: [] for name in dependencies}
    indegree = {name: len(deps) for name, deps in dependencies.items()}
    for name, deps in dependencies.items():
        for dep in deps:
            reverse[dep].append(name)

    ready = [name for name, count in indegree.items() if count == 0]
    heapq.heapify(ready)
    result = []
    while ready:
        name = heapq.heappop(ready)
        result.append(name)
        for dependent in reverse[name]:
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                heapq.heappush(ready, dependent)

    assert len(result) == len(dependencies)
    return result


def write_proto_set(directory, dependencies):
    os.makedirs(directory)
    contents = {}
    for name, deps in dependencies.items():
        body = ['syntax = "proto3";']
        body.extend(f'import "{dep}";' for dep in deps)
        body.append(f'message M_{name.replace(".", "_")} {{}}')
        data = ("\n".join(body) + "\n").encode()
        path = os.path.join(directory, name)
        with open(path, "wb") as f:
            f.write(data)
        contents[name] = data
    with open(os.path.join(directory, "ignored.txt"), "w") as f:
        f.write('import "not_a_proto.proto";\n')
    return contents


def assert_generated(plan, target, dependencies, original_contents):
    expected = expected_topological_order(dependencies)
    assert os.path.isfile(plan)
    with open(plan) as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected

    assert os.path.isdir(target)
    assert sorted(os.listdir(target)) == sorted(expected)
    for index, name in enumerate(expected, 1):
        with open(os.path.join(target, name), "rb") as f:
            copied = f.read()
        assert copied == f"// ORDER: {index}\n".encode() + original_contents[name]


def test_script_exists_and_executable():
    script_path = "/home/user/organizer.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_execute_script_on_supplied_configuration():
    shutil.rmtree("/home/user/compiled_protos", ignore_errors=True)
    try:
        os.unlink("/home/user/build_order.log")
    except FileNotFoundError:
        pass

    result = run_script("/home/user/config.org")
    assert result.returncode == 0, (
        f"organizer.sh failed on /home/user/config.org with code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_build_order_log():
    log_path = "/home/user/build_order.log"
    assert os.path.isfile(log_path), f"Build order log {log_path} does not exist."

    expected_order = [
        "common.proto",
        "db.proto",
        "user.proto",
        "auth.proto",
        "gateway.proto"
    ]

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_order, f"Expected build order {expected_order}, but got {lines}."


def test_compiled_protos_directory():
    target_dir = "/home/user/compiled_protos"
    assert os.path.isdir(target_dir), f"Target directory {target_dir} does not exist."

    expected_files = {
        "common.proto": 1,
        "db.proto": 2,
        "user.proto": 3,
        "auth.proto": 4,
        "gateway.proto": 5
    }

    for filename, order in expected_files.items():
        filepath = os.path.join(target_dir, filename)
        assert os.path.isfile(filepath), f"Compiled proto file {filepath} is missing."

        with open(filepath, 'r') as f:
            first_line = f.readline().strip()

        expected_line = f"// ORDER: {order}"
        assert first_line == expected_line, f"Expected {filepath} to start with '{expected_line}', but got '{first_line}'."

        with open(filepath, "rb") as f:
            copied = f.read()
        with open(os.path.join("/home/user/raw_protos", filename), "rb") as f:
            source = f.read()
        assert copied == f"// ORDER: {order}\n".encode() + source


def test_interprets_additional_configuration_and_preserves_contents():
    with tempfile.TemporaryDirectory(prefix="organizer_test_") as base:
        token = uuid.uuid4().hex[:10]

        src1 = os.path.join(base, "input_one")
        target1 = os.path.join(base, "output_one")
        plan1 = os.path.join(base, "plan_one.log")
        a1 = f"a_{token}.proto"
        b1 = f"b_{token}.proto"
        c1 = f"c_{token}.proto"
        deps1 = {a1: [], b1: [], c1: [a1, b1]}
        contents1 = write_proto_set(src1, deps1)

        src2 = os.path.join(base, "input_two")
        target2 = os.path.join(base, "output_two")
        plan2 = os.path.join(base, "plan_two.log")
        names = {letter: f"{letter}_{token}.proto" for letter in "abcdef"}
        deps2 = {
            names["a"]: [],
            names["b"]: [],
            names["c"]: [names["a"]],
            names["d"]: [names["b"]],
            names["e"]: [names["c"], names["d"]],
            names["f"]: [names["c"]],
        }
        contents2 = write_proto_set(src2, deps2)

        config = os.path.join(base, "generated_config.org")
        with open(config, "w") as f:
            f.write(f"SET_TARGET {target1}\n")
            f.write(f"PARSE_DIR {src1}\n")
            f.write(f"EMIT_PLAN {plan1}\n")
            f.write(f"SET_TARGET {target2}\n")
            f.write(f"PARSE_DIR {src2}\n")
            f.write(f"EMIT_PLAN {plan2}\n")

        result = run_script(config)
        assert result.returncode == 0, (
            f"organizer.sh failed on generated DSL with code {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        assert_generated(plan1, target1, deps1, contents1)
        assert_generated(plan2, target2, deps2, contents2)

        for directory, originals in ((src1, contents1), (src2, contents2)):
            for name, original in originals.items():
                with open(os.path.join(directory, name), "rb") as f:
                    assert f.read() == original


def test_requires_exactly_one_argument():
    no_args = subprocess.run(
        [SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert no_args.returncode != 0

    two_args = subprocess.run(
        [SCRIPT, "/home/user/config.org", "/home/user/config.org"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert two_args.returncode != 0
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
