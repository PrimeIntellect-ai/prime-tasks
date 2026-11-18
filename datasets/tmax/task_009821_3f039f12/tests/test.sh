#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import uuid

PROJECT = "/home/user/project"
CPP = os.path.join(PROJECT, "minibuild.cpp")
EXE = os.path.join(PROJECT, "minibuild")
BUILD_OLD = os.path.join(PROJECT, "build.old")
BUILD_NEW = os.path.join(PROJECT, "build.new")
LOG = os.path.join(PROJECT, "benchmark.log")


def compile_minibuild():
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP, "-o", EXE],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Compilation failed:\n{result.stderr}"


def parse_old(path):
    records = []
    current = None
    with open(path) as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            if line.startswith("Target: "):
                current = {"name": line[8:].strip(), "deps": [], "cmd": None}
                records.append(current)
            elif line.startswith("Depends:"):
                assert current is not None
                value = line[len("Depends:"):].strip()
                current["deps"] = [x.strip() for x in value.split(",") if x.strip()]
            elif line.startswith("Command: "):
                assert current is not None
                current["cmd"] = line[len("Command: "):]
            else:
                raise AssertionError(f"Unexpected old-schema line: {line}")
    return records


def parse_new(path):
    records = []
    current = None
    with open(path) as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            if line.startswith("TARGET "):
                current = {"name": line[7:].strip(), "deps": [], "cmd": None}
                assert current["name"], "Empty TARGET name"
                records.append(current)
            elif line == "DEPS" or line.startswith("DEPS "):
                assert current is not None, "DEPS appeared before TARGET"
                assert "," not in line, f"Found comma in DEPS line: {line}"
                current["deps"] = line[4:].strip().split()
            elif line.startswith("CMD "):
                assert current is not None, "CMD appeared before TARGET"
                current["cmd"] = line[4:]
            else:
                raise AssertionError(f"Unexpected new-schema line: {line}")
    return records


def read_benchmark(path=LOG):
    assert os.path.isfile(path), f"File {path} does not exist."
    entries = []
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            match = re.fullmatch(r"([^\s]+)\s+(\d+)ms", line)
            assert match, f"Malformed benchmark line: {line!r}"
            entries.append((match.group(1), int(match.group(2))))
    return entries


def test_build_new_exists_and_format():
    assert os.path.isfile(BUILD_NEW), f"File {BUILD_NEW} does not exist."

    with open(BUILD_NEW) as f:
        content = f.read()

    # Preserve the original schema assertions.
    for line in content.splitlines():
        if line.startswith("DEPS"):
            assert "," not in line, f"Found comma in DEPS line: {line}"
    assert "TARGET all" in content, "Missing 'TARGET all' in build.new"
    assert "TARGET frontend" in content, "Missing 'TARGET frontend' in build.new"
    assert "TARGET backend" in content, "Missing 'TARGET backend' in build.new"
    assert (re.search(r"DEPS\s+frontend\s+backend", content) or
            re.search(r"DEPS\s+backend\s+frontend", content)), \
        "Missing 'DEPS frontend backend' in build.new"

    # Verify the complete migration rather than a few substrings.
    old_records = parse_old(BUILD_OLD)
    new_records = parse_new(BUILD_NEW)
    assert new_records == old_records, \
        f"build.new is not a faithful migration of build.old:\n{new_records!r}"
    names = [r["name"] for r in new_records]
    assert len(names) == len(set(names)), "Duplicate TARGET definitions"
    assert all(r["cmd"] is not None for r in new_records), "A target is missing CMD"


def test_minibuild_artifact_and_generated_behavior():
    assert os.path.isfile(CPP), f"File {CPP} does not exist."
    assert os.path.isfile(EXE), f"File {EXE} does not exist; minibuild was not compiled."
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "minibuild is not a compiled ELF executable"

    compile_minibuild()

    nonce = uuid.uuid4().hex
    names = {key: f"{key}_{nonce}" for key in ["root", "left", "right", "shared", "solo"]}
    with tempfile.TemporaryDirectory(prefix="minibuild_verify_") as td:
        config = os.path.join(td, "generated.build")
        marker = os.path.join(td, "commands.log")

        def command(token):
            return f"printf '{token}\\n' >> {marker}"

        with open(config, "w") as f:
            f.write(
                f"TARGET {names['root']}\n"
                f"DEPS {names['left']} {names['right']}\n"
                f"CMD {command(names['root'])}\n\n"
                f"TARGET {names['left']}\n"
                f"DEPS {names['shared']}\n"
                f"CMD {command(names['left'])}\n\n"
                f"TARGET {names['right']}\n"
                f"DEPS {names['shared']}\n"
                f"CMD {command(names['right'])}\n\n"
                f"TARGET {names['shared']}\n"
                f"DEPS\n"
                f"CMD {command(names['shared'])}\n\n"
                f"TARGET {names['solo']}\n"
                f"DEPS\n"
                f"CMD {command(names['solo'])}\n"
            )

        if os.path.exists(LOG):
            os.remove(LOG)
        result = subprocess.run([EXE, config], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, \
            f"minibuild failed on generated input:\nstdout={result.stdout}\nstderr={result.stderr}"
        assert os.path.isfile(marker), "Generated target commands were not executed"
        with open(marker) as f:
            order = [line.strip() for line in f if line.strip()]

        expected = set(names.values())
        assert set(order) == expected, f"Wrong commands executed: {order!r}"
        assert len(order) == len(expected), "A target command was executed more than once"
        position = {name: order.index(name) for name in expected}
        assert position[names["shared"]] < position[names["left"]]
        assert position[names["shared"]] < position[names["right"]]
        assert position[names["left"]] < position[names["root"]]
        assert position[names["right"]] < position[names["root"]]

        entries = read_benchmark()
        logged_names = [name for name, _ in entries]
        assert len(logged_names) == len(expected), "Wrong number of benchmark entries"
        assert set(logged_names) == expected, "benchmark.log does not describe executed targets"
        assert len(logged_names) == len(set(logged_names)), "Duplicate benchmark entries"

        # Exercise the shared dependency graph under Valgrind as well.
        result = subprocess.run([
            "valgrind", "--leak-check=full", "--show-leak-kinds=all",
            "--errors-for-leak-kinds=all", "--error-exitcode=1", EXE, config
        ], capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, \
            f"Valgrind found errors on generated graph:\n{result.stderr}"


def test_benchmark_log_exists():
    compile_minibuild()
    if os.path.exists(LOG):
        os.remove(LOG)
    result = subprocess.run([EXE, BUILD_NEW], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, \
        f"minibuild failed on build.new:\nstdout={result.stdout}\nstderr={result.stderr}"

    assert os.path.isfile(LOG), f"File {LOG} does not exist."
    with open(LOG) as f:
        content = f.read()

    # Preserve the original benchmark assertions, now against a freshly generated log.
    for target in ["all", "frontend", "backend", "ui_components", "database"]:
        assert re.search(rf"^{target}\s+\d+ms", content, re.MULTILINE), \
            f"Target {target} not found in benchmark.log"

    entries = read_benchmark()
    by_name = {name: elapsed for name, elapsed in entries}
    assert len(entries) == 5 and set(by_name) == {
        "all", "frontend", "backend", "ui_components", "database"
    }, "benchmark.log must contain exactly one entry for every migrated target"
    assert by_name["frontend"] >= 800, "frontend command timing shows its sleep was not run"
    assert by_name["backend"] >= 1800, "backend command timing shows its sleep was not run"


def test_minibuild_memory_safety():
    assert os.path.isfile(CPP), f"File {CPP} does not exist."
    compile_minibuild()

    # Preserve the original Valgrind execution and make leak failures explicit.
    result = subprocess.run([
        "valgrind", "--leak-check=full", "--show-leak-kinds=all",
        "--errors-for-leak-kinds=all", "--error-exitcode=1", EXE, BUILD_NEW
    ], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, \
        f"Valgrind found memory errors or leaks:\n{result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
