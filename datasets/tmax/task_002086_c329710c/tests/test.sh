#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile

import pytest

WORKSPACE_DIR = "/home/user/workspace"
PACKAGES_PATH = os.path.join(WORKSPACE_DIR, "packages.json")
INSTALL_PLAN_PATH = os.path.join(WORKSPACE_DIR, "install_plan.json")
GO_MOD_PATH = os.path.join(WORKSPACE_DIR, "go.mod")
SOLVER_GO_PATH = os.path.join(WORKSPACE_DIR, "solver.go")
SOLVER_TEST_GO_PATH = os.path.join(WORKSPACE_DIR, "solver_test.go")

CANONICAL_PACKAGES = {
    "core-app": {"size": 30, "depends_on": ["libA"], "conflicts_with": []},
    "libA": {"size": 20, "depends_on": [], "conflicts_with": ["libB"]},
    "libB": {"size": 40, "depends_on": [], "conflicts_with": ["libA"]},
    "plugin1": {"size": 50, "depends_on": ["core-app"], "conflicts_with": []},
    "plugin2": {"size": 60, "depends_on": ["core-app"], "conflicts_with": ["plugin1"]},
    "util": {"size": 10, "depends_on": [], "conflicts_with": []},
}
CANONICAL_PLAN = ["core-app", "libA", "plugin2", "util"]


def test_go_module_initialized():
    assert os.path.isfile(GO_MOD_PATH), f"go.mod file is missing at {GO_MOD_PATH}"
    with open(GO_MOD_PATH, "r", encoding="utf-8") as f:
        content = f.read()
    assert "module mathpack" in content, "go.mod does not declare the 'mathpack' module."


def test_go_files_exist():
    assert os.path.isfile(SOLVER_GO_PATH), f"solver.go is missing at {SOLVER_GO_PATH}"
    assert os.path.isfile(SOLVER_TEST_GO_PATH), f"solver_test.go is missing at {SOLVER_TEST_GO_PATH}"


def test_go_tests_pass():
    try:
        result = subprocess.run(
            ["go", "test"],
            cwd=WORKSPACE_DIR,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except FileNotFoundError:
        pytest.fail("The 'go' command is not available. Go might not be installed or in PATH.")
    except subprocess.TimeoutExpired:
        pytest.fail("'go test' timed out.")
    assert result.returncode == 0, f"'go test' failed with output:\n{result.stdout}\n{result.stderr}"


def optimal_objective(packages):
    names = list(packages)
    assert "core-app" in packages
    best = None
    for mask in range(1 << len(names)):
        chosen = {names[i] for i in range(len(names)) if mask & (1 << i)}
        if "core-app" not in chosen:
            continue
        valid = True
        total = 0
        for name in chosen:
            info = packages[name]
            total += info["size"]
            if any(dep not in chosen for dep in info["depends_on"]):
                valid = False
                break
            if any(conflict in chosen for conflict in info["conflicts_with"]):
                valid = False
                break
        if not valid or total > 120:
            continue
        objective = (len(chosen), total)
        if best is None or objective > best:
            best = objective
    assert best is not None, "Verifier generated an infeasible dataset"
    return best


def validate_plan(packages, plan):
    assert isinstance(plan, list), "install_plan.json should contain a JSON array."
    assert all(type(name) is str for name in plan), "Every plan entry must be a package name string."
    assert plan == sorted(plan), "Package names in install_plan.json are not sorted alphabetically."
    assert len(plan) == len(set(plan)), "install_plan.json contains duplicate package names."
    assert all(name in packages for name in plan), "install_plan.json contains an unknown package."
    assert "core-app" in plan, "The plan does not include core-app."

    chosen = set(plan)
    total = sum(packages[name]["size"] for name in chosen)
    assert total <= 120, f"Plan size {total} exceeds 120."
    for name in chosen:
        info = packages[name]
        missing = [dep for dep in info["depends_on"] if dep not in chosen]
        conflicts = [other for other in info["conflicts_with"] if other in chosen]
        assert not missing, f"{name} has missing dependencies: {missing}"
        assert not conflicts, f"{name} conflicts with installed packages: {conflicts}"

    assert (len(chosen), total) == optimal_objective(packages), (
        f"Plan is not optimal: got objective {(len(chosen), total)}, "
        f"expected {optimal_objective(packages)}"
    )


def random_dataset(rng):
    count = rng.randrange(8, 12)
    names = ["core-app"] + [f"pkg-{i:02d}-{rng.randrange(1000, 10000)}" for i in range(count - 1)]
    packages = {
        "core-app": {"size": rng.randrange(5, 26), "depends_on": [], "conflicts_with": []}
    }
    for i in range(1, count):
        previous = names[:i]
        dep_count = rng.randrange(0, min(2, len(previous)) + 1)
        dependencies = rng.sample(previous, dep_count)
        conflicts = [other for other in names if other != names[i] and rng.random() < 0.13]
        packages[names[i]] = {
            "size": rng.randrange(5, 56),
            "depends_on": dependencies,
            "conflicts_with": conflicts,
        }
    return packages


def run_solver(binary, packages):
    with open(PACKAGES_PATH, "w", encoding="utf-8") as f:
        json.dump(packages, f)
    if os.path.lexists(INSTALL_PLAN_PATH):
        os.unlink(INSTALL_PLAN_PATH)

    try:
        result = subprocess.run(
            [binary],
            cwd=WORKSPACE_DIR,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The compiled solver timed out.")
    assert result.returncode == 0, f"Solver failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(INSTALL_PLAN_PATH), f"install_plan.json is missing at {INSTALL_PLAN_PATH}"
    try:
        with open(INSTALL_PLAN_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"{INSTALL_PLAN_PATH} does not contain valid JSON: {exc}")


def test_install_plan_json_and_solver_behavior():
    binary = os.path.join(tempfile.mkdtemp(prefix="mathpack-verifier-"), "solver")
    build = subprocess.run(
        ["go", "build", "-o", binary, "."],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"Solver does not compile:\n{build.stdout}\n{build.stderr}"

    count_priority = {
        "core-app": {"size": 10, "depends_on": [], "conflicts_with": []},
        "jumbo": {"size": 110, "depends_on": [], "conflicts_with": []},
        "small-a": {"size": 35, "depends_on": [], "conflicts_with": []},
        "small-b": {"size": 35, "depends_on": [], "conflicts_with": []},
        "small-c": {"size": 35, "depends_on": [], "conflicts_with": []},
    }
    transitive = {
        "core-app": {"size": 12, "depends_on": ["base"], "conflicts_with": []},
        "base": {"size": 13, "depends_on": ["runtime"], "conflicts_with": []},
        "runtime": {"size": 14, "depends_on": [], "conflicts_with": []},
        "feature": {"size": 31, "depends_on": ["base"], "conflicts_with": ["alternate"]},
        "alternate": {"size": 45, "depends_on": ["runtime"], "conflicts_with": []},
        "tool-a": {"size": 17, "depends_on": [], "conflicts_with": []},
        "tool-b": {"size": 18, "depends_on": ["tool-a"], "conflicts_with": []},
    }

    rng = secrets.SystemRandom()
    cases = [CANONICAL_PACKAGES, count_priority, transitive]
    cases.extend(random_dataset(rng) for _ in range(5))

    try:
        for index, packages in enumerate(cases):
            plan = run_solver(binary, packages)
            validate_plan(packages, plan)
            if index == 0:
                assert plan == CANONICAL_PLAN, (
                    f"install_plan.json does not match the expected output. "
                    f"Got {plan}, expected {CANONICAL_PLAN}."
                )
    finally:
        with open(PACKAGES_PATH, "w", encoding="utf-8") as f:
            json.dump(CANONICAL_PACKAGES, f, indent=2)
            f.write("\n")
        if os.path.isfile(binary):
            subprocess.run([binary], cwd=WORKSPACE_DIR, capture_output=True, text=True, timeout=10)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
