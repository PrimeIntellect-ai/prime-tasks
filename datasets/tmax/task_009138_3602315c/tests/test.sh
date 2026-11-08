#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import shutil
import subprocess
import sys
import uuid


def test_symlinks_created_correctly():
    build_dir = "/home/user/project/build"
    assert os.path.isdir(build_dir), f"Build directory {build_dir} was not created."

    alpha_link = os.path.join(build_dir, "libAlpha")
    beta_link = os.path.join(build_dir, "libBeta")

    assert os.path.islink(alpha_link), f"{alpha_link} is not a symlink."
    assert os.path.islink(beta_link), f"{beta_link} is not a symlink."

    alpha_target = os.readlink(alpha_link)
    beta_target = os.readlink(beta_link)

    expected_alpha_target = "/home/user/libs/libAlpha-1.2.5"
    expected_beta_target = "/home/user/libs/libBeta-1.1.2"

    assert alpha_target == expected_alpha_target, f"libAlpha symlink points to {alpha_target}, expected {expected_alpha_target}"
    assert beta_target == expected_beta_target, f"libBeta symlink points to {beta_target}, expected {expected_beta_target}"


def test_linker_exists_and_semver_comparisons_work():
    linker_file = "/home/user/project/linker.py"
    assert os.path.isfile(linker_file), f"Linker script {linker_file} does not exist."

    spec = importlib.util.spec_from_file_location("submitted_linker", linker_file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)

    assert hasattr(module, "SemVer"), "linker.py does not define SemVer."
    SemVer = module.SemVer
    assert SemVer.__module__ == module.__name__, "SemVer must be defined in linker.py."

    low = SemVer("1.2.3")
    same = SemVer("1.2.3")
    high = SemVer("1.10.0")
    top = SemVer("2.0.0")

    assert low == same
    assert low <= same and low >= same
    assert low < high < top
    assert low <= high and high <= top
    assert top > high > low
    assert top >= high and high >= low
    assert not (low > high)
    assert not (top < high)
    assert low < high and high < top and low < top


def test_linker_executes_and_resolves_unseen_fixture():
    project = "/home/user/project"
    libs = "/home/user/libs"
    linker_file = os.path.join(project, "linker.py")
    config_file = os.path.join(project, "link_config.txt")
    build_dir = os.path.join(project, "build")
    assert os.path.isfile(linker_file), f"Linker script {linker_file} does not exist."

    token = uuid.uuid4().hex
    name_a = "verifyA" + token
    name_b = "verifyB" + token
    fixtures = {
        name_a: ["1.0.7", "1.3.1", "1.8.4", "2.0.0"],
        name_b: ["0.9.9", "1.0.0", "1.4.2", "1.7.0"],
    }
    expected = {
        name_a: os.path.join(libs, f"{name_a}-1.8.4"),
        name_b: os.path.join(libs, f"{name_b}-1.4.2"),
    }

    old_config = open(config_file, "rb").read()
    saved_build = os.path.join(project, ".build-verifier-" + token)
    created = []
    if os.path.lexists(build_dir):
        os.rename(build_dir, saved_build)

    try:
        for name, versions in fixtures.items():
            for version in versions:
                path = os.path.join(libs, f"{name}-{version}")
                os.mkdir(path)
                created.append(path)

        with open(config_file, "w", encoding="utf-8") as config:
            config.write(f"{name_a} >=1.1.0,<2.0.0\n")
            config.write(f"{name_b} >=1.0.0,<1.5.0\n")

        result = subprocess.run(
            [sys.executable, linker_file],
            cwd=project,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"linker.py failed on an unseen fixture:\n{result.stdout}\n{result.stderr}"
        )
        assert os.path.isdir(build_dir), "linker.py did not create the build directory."

        for name, target in expected.items():
            link = os.path.join(build_dir, name)
            assert os.path.islink(link), f"linker.py did not create symlink {link}."
            assert os.readlink(link) == target, (
                f"{link} points to {os.readlink(link)}, expected {target}"
            )
    finally:
        with open(config_file, "wb") as config:
            config.write(old_config)
        if os.path.lexists(build_dir):
            if os.path.islink(build_dir) or not os.path.isdir(build_dir):
                os.unlink(build_dir)
            else:
                shutil.rmtree(build_dir)
        if os.path.lexists(saved_build):
            os.rename(saved_build, build_dir)
        for path in created:
            if os.path.isdir(path):
                shutil.rmtree(path)


def _decorator_is_given(decorator):
    target = decorator.func if isinstance(decorator, ast.Call) else decorator
    return (
        isinstance(target, ast.Name) and target.id == "given"
    ) or (
        isinstance(target, ast.Attribute) and target.attr == "given"
    )


def _lt_pairs(tree):
    pairs = set()
    for node in ast.walk(tree):
        if not isinstance(node, ast.Compare):
            continue
        values = [node.left] + list(node.comparators)
        for index, operator in enumerate(node.ops):
            if isinstance(operator, ast.Lt):
                pairs.add((ast.dump(values[index]), ast.dump(values[index + 1])))
    return pairs


def test_test_linker_exists_and_uses_hypothesis():
    test_file = "/home/user/project/test_linker.py"
    assert os.path.isfile(test_file), f"Test file {test_file} does not exist."

    with open(test_file, "r") as f:
        content = f.read()

    assert "hypothesis" in content, "The test file does not appear to import or use 'hypothesis'."
    assert "@given" in content, "The test file does not appear to use the '@given' decorator from hypothesis."

    tree = ast.parse(content, filename=test_file)
    imports_semver = any(
        isinstance(node, ast.ImportFrom)
        and node.module == "linker"
        and any(alias.name == "SemVer" for alias in node.names)
        for node in ast.walk(tree)
    )
    assert imports_semver, "test_linker.py must import SemVer from linker.py."

    given_tests = [
        node for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name.startswith("test")
        and any(_decorator_is_given(d) for d in node.decorator_list)
    ]
    assert given_tests, "No pytest test function is actually decorated with Hypothesis @given."

    verifies_transitivity = False
    for function in given_tests:
        all_pairs = _lt_pairs(function)
        asserted_pairs = set()
        for assertion in (n for n in ast.walk(function) if isinstance(n, ast.Assert)):
            asserted_pairs.update(_lt_pairs(assertion.test))
        for a, c in asserted_pairs:
            if a != c and any(x == a and y != a and y != c and (y, c) in all_pairs
                              for x, y in all_pairs):
                verifies_transitivity = True
                break
        if verifies_transitivity:
            break
    assert verifies_transitivity, (
        "A @given test must assert the transitive relation a < c from comparisons "
        "a < b and b < c."
    )


def test_pytest_runs_successfully():
    test_file = "/home/user/project/test_linker.py"
    env = os.environ.copy()
    env["PYTHONPATH"] = "/home/user/project"

    result = subprocess.run(
        ["pytest", test_file],
        env=env,
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"pytest failed on {test_file}:\n{result.stdout}\n{result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
