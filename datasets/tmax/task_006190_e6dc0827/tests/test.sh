#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
import pytest

WORKSPACE_DIR = "/home/user/workspace"
RUSTY_MATH_DIR = os.path.join(WORKSPACE_DIR, "rusty_math")
CI_PIPELINE_SCRIPT = os.path.join(WORKSPACE_DIR, "ci_pipeline.sh")
DEP_COUNT_FILE = os.path.join(WORKSPACE_DIR, "dep_count.txt")
LIB_RS_FILE = os.path.join(RUSTY_MATH_DIR, "src", "lib.rs")


def test_lib_rs_modified():
    assert os.path.isfile(LIB_RS_FILE), f"{LIB_RS_FILE} is missing."
    with open(LIB_RS_FILE, "r") as f:
        content = f.read()

    assert "cfg" in content and "wasm32" in content, \
        "lib.rs does not seem to contain #[cfg(...)] attributes for wasm32."


def test_native_build_succeeds():
    result = subprocess.run(
        ["cargo", "build"],
        cwd=RUSTY_MATH_DIR,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Native cargo build failed:\n{result.stderr}"


def test_wasm_build_succeeds():
    result = subprocess.run(
        ["cargo", "build", "--target", "wasm32-unknown-unknown"],
        cwd=RUSTY_MATH_DIR,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Wasm cargo build failed:\n{result.stderr}"


def test_wasm_selected_implementation_returns_42_without_instant():
    # Build and execute a host-runnable copy in which the wasm32 cfg predicate is
    # mapped to a private verifier cfg. Poisoning the Instant identifier proves
    # that no Instant reference is present in the selected Wasm implementation.
    with tempfile.TemporaryDirectory() as temp_dir:
        project = os.path.join(temp_dir, "rusty_math")
        os.makedirs(os.path.join(project, "src", "bin"))
        shutil.copy2(os.path.join(RUSTY_MATH_DIR, "Cargo.toml"), project)
        lock_file = os.path.join(RUSTY_MATH_DIR, "Cargo.lock")
        if os.path.isfile(lock_file):
            shutil.copy2(lock_file, project)

        source_dir = os.path.join(RUSTY_MATH_DIR, "src")
        for root, _, files in os.walk(source_dir):
            for name in files:
                if not name.endswith(".rs"):
                    continue
                source_path = os.path.join(root, name)
                relative = os.path.relpath(source_path, source_dir)
                destination = os.path.join(project, "src", relative)
                os.makedirs(os.path.dirname(destination), exist_ok=True)
                with open(source_path, "r") as f:
                    source = f.read()
                source = re.sub(r'target_arch\s*=\s*"wasm32"',
                                'verifier_wasm', source)
                source = re.sub(r'\bInstant\b',
                                '__VERIFIER_FORBIDDEN_INSTANT__', source)
                with open(destination, "w") as f:
                    f.write(source)

        runner = os.path.join(project, "src", "bin", "verify_wasm.rs")
        with open(runner, "w") as f:
            f.write(
                'fn main() {\n'
                '    let result = rusty_math::compute_algorithm();\n'
                '    assert_eq!(result, 42, "compute_algorithm must return 42");\n'
                '}\n'
            )

        env = os.environ.copy()
        env["RUSTFLAGS"] = "--cfg verifier_wasm --check-cfg=cfg(verifier_wasm)"
        result = subprocess.run(
            ["cargo", "run", "--offline", "--quiet", "--bin", "verify_wasm"],
            cwd=project,
            env=env,
            capture_output=True,
            text=True,
            timeout=120
        )
        assert result.returncode == 0, (
            "The implementation selected for wasm32 either uses Instant or does "
            f"not return 42:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )


def test_ci_pipeline_script_executable_and_runs_required_commands():
    assert os.path.isfile(CI_PIPELINE_SCRIPT), f"{CI_PIPELINE_SCRIPT} is missing."
    assert os.access(CI_PIPELINE_SCRIPT, os.X_OK), \
        f"{CI_PIPELINE_SCRIPT} is not executable."

    with open(CI_PIPELINE_SCRIPT, "r") as f:
        script_content = f.read()
    commands = "\n".join(
        line for line in script_content.replace("\\\n", " ").splitlines()
        if not line.lstrip().startswith("#")
    )
    cargo_command = r'(?:[^\s;|&]*/)?cargo'
    assert re.search(cargo_command + r'\s+build\b[^\n]*--target(?:\s+|=)wasm32-unknown-unknown', commands), \
        "ci_pipeline.sh does not invoke cargo build for wasm32-unknown-unknown."
    assert re.search(cargo_command + r'\s+tree\b', commands), \
        "ci_pipeline.sh does not use cargo tree to inspect dependencies."

    if os.path.exists(DEP_COUNT_FILE):
        os.remove(DEP_COUNT_FILE)

    real_cargo = shutil.which("cargo")
    assert real_cargo is not None, "cargo is unavailable."
    with tempfile.TemporaryDirectory() as wrapper_dir:
        log_file = os.path.join(wrapper_dir, "cargo_calls")
        wrapper = os.path.join(wrapper_dir, "cargo")
        with open(wrapper, "w") as f:
            f.write(
                "#!/bin/bash\n"
                "printf '%s\\t' \"$@\" >> \"$VERIFIER_CARGO_LOG\"\n"
                "printf '\\n' >> \"$VERIFIER_CARGO_LOG\"\n"
                "exec \"$VERIFIER_REAL_CARGO\" \"$@\"\n"
            )
        os.chmod(wrapper, 0o755)

        env = os.environ.copy()
        env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
        env["VERIFIER_REAL_CARGO"] = real_cargo
        env["VERIFIER_CARGO_LOG"] = log_file
        result = subprocess.run(
            [CI_PIPELINE_SCRIPT],
            cwd=WORKSPACE_DIR,
            env=env,
            capture_output=True,
            text=True,
            timeout=180
        )
        assert result.returncode == 0, (
            f"ci_pipeline.sh failed when executed:\nstdout:\n{result.stdout}"
            f"\nstderr:\n{result.stderr}"
        )

        if os.path.isfile(log_file):
            with open(log_file, "r") as f:
                calls = [line.rstrip("\n").split("\t") for line in f if line.strip()]
            saw_wasm_build = any(
                "build" in call and
                any(arg == "--target=wasm32-unknown-unknown" for arg in call) or
                ("build" in call and "--target" in call and
                 "wasm32-unknown-unknown" in call)
                for call in calls
            )
            saw_tree = any("tree" in call for call in calls)
            assert saw_wasm_build, \
                "Executing ci_pipeline.sh did not invoke the required Wasm cargo build."
            assert saw_tree, \
                "Executing ci_pipeline.sh did not invoke cargo tree."

    assert os.path.isfile(DEP_COUNT_FILE), \
        "ci_pipeline.sh did not generate dep_count.txt when executed."


def test_dep_count_file_correct():
    assert os.path.isfile(DEP_COUNT_FILE), f"{DEP_COUNT_FILE} is missing."

    with open(DEP_COUNT_FILE, "r") as f:
        content = f.read().strip()

    try:
        written_count = int(content)
    except ValueError:
        pytest.fail(f"{DEP_COUNT_FILE} does not contain a valid integer. Found: '{content}'")

    tree_result = subprocess.run(
        ["cargo", "tree", "--prefix", "none"],
        cwd=RUSTY_MATH_DIR,
        capture_output=True,
        text=True
    )
    assert tree_result.returncode == 0, "cargo tree command failed."

    deps = set()
    for line in tree_result.stdout.splitlines():
        line = line.strip()
        if line and not line.startswith("rusty_math"):
            deps.add(line)

    expected_count = len(deps)
    assert written_count == expected_count, \
        f"Expected {expected_count} dependencies in {DEP_COUNT_FILE}, but found {written_count}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
