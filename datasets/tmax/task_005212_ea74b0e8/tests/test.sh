#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess

import pytest

ROOT = "/home/user/rust_app"
CI = os.path.join(ROOT, "ci_pipeline.sh")


def run_ci(timeout=120):
    return subprocess.run(
        [CI], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=timeout
    )


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


@pytest.fixture(scope="session", autouse=True)
def build_from_clean_artifacts():
    for path in [
        os.path.join(ROOT, "generator"),
        os.path.join(ROOT, "src/generated_config.rs"),
        os.path.join(ROOT, "config_diff.txt"),
    ]:
        if os.path.lexists(path):
            os.remove(path)
    shutil.rmtree(os.path.join(ROOT, "target"), ignore_errors=True)

    result = run_ci()
    assert result.returncode == 0, f"ci_pipeline.sh failed:\n{result.stdout}"


def test_generator_cpp_exists():
    path = "/home/user/rust_app/generator.cpp"
    assert os.path.isfile(path), f"C++ source file {path} is missing."


def test_ci_pipeline_sh_exists_and_executable():
    path = "/home/user/rust_app/ci_pipeline.sh"
    assert os.path.isfile(path), f"Bash script {path} is missing."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Bash script {path} is not executable."


def test_generator_executable_exists():
    path = "/home/user/rust_app/generator"
    assert os.path.isfile(path), f"Compiled C++ executable {path} is missing."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Compiled file {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled file {path} is not an ELF executable."


def test_generated_config_rs_content():
    path = "/home/user/rust_app/src/generated_config.rs"
    assert os.path.isfile(path), f"Generated Rust config file {path} is missing."

    lines = read_nonempty_lines(path)
    expected_lines = [
        "pub const BUFFER_SIZE: i32 = 1024;",
        "pub const MAX_RETRIES: i32 = 18;",
        "pub const TIMEOUT: i32 = 10;",
        "pub const WORKERS: i32 = 5;"
    ]
    assert lines == expected_lines, f"Contents of {path} do not match the expected sorted output. Got: {lines}"


def test_config_diff_txt_content():
    path = "/home/user/rust_app/config_diff.txt"
    assert os.path.isfile(path), f"Diff file {path} is missing."

    lines = read_nonempty_lines(path)
    expected_lines = [
        "~ BUFFER_SIZE=512->1024",
        "+ TIMEOUT=10",
        "+ WORKERS=5"
    ]
    assert lines == expected_lines, f"Contents of {path} do not match the expected sorted diff. Got: {lines}"


def test_rust_app_compiled():
    path = "/home/user/rust_app/target/debug/rust_app"
    assert os.path.isfile(path), f"Rust application executable {path} is missing. Did 'cargo build' succeed?"


def make_scenario():
    unit = 30 + secrets.randbelow(70)
    factor = 3 + secrets.randbelow(6)
    offset = 2 + secrets.randbelow(12)
    delta = 1 + secrets.randbelow(9)
    buffer_size = unit * 4
    max_retries = factor * (offset + 3)
    timeout = max_retries - delta
    workers = buffer_size // unit + 1

    expr = (
        f"DEF MAX_RETRIES = {factor} * ({offset} + 3)\n"
        f"DEF TIMEOUT = MAX_RETRIES - {delta}\n"
        f"DEF BUFFER_SIZE = {unit} * (2 + 2)\n"
        f"DEF WORKERS = BUFFER_SIZE / {unit} + 1\n"
    )
    previous = (
        f"TIMEOUT={timeout + 2}\n"
        f"MAX_RETRIES={max_retries}\n"
        "OLD_VAR=999\n"
        f"BUFFER_SIZE={buffer_size - 4}\n"
    )
    generated = [
        f"pub const BUFFER_SIZE: i32 = {buffer_size};",
        f"pub const MAX_RETRIES: i32 = {max_retries};",
        f"pub const TIMEOUT: i32 = {timeout};",
        f"pub const WORKERS: i32 = {workers};",
    ]
    diff = [
        f"~ BUFFER_SIZE={buffer_size - 4}->{buffer_size}",
        f"~ TIMEOUT={timeout + 2}->{timeout}",
        f"+ WORKERS={workers}",
    ]
    main = f'''pub mod generated_config;
fn main() {{
    assert_eq!(generated_config::BUFFER_SIZE, {buffer_size});
    assert_eq!(generated_config::MAX_RETRIES, {max_retries});
    assert_eq!(generated_config::TIMEOUT, {timeout});
    assert_eq!(generated_config::WORKERS, {workers});
}}
'''
    return expr, previous, generated, diff, main


def install_scenario(scenario):
    expr, previous, _, _, main = scenario
    with open(os.path.join(ROOT, "config.expr"), "w") as f:
        f.write(expr)
    with open(os.path.join(ROOT, "previous_config.txt"), "w") as f:
        f.write(previous)
    with open(os.path.join(ROOT, "src/main.rs"), "w") as f:
        f.write(main)


def assert_scenario_outputs(scenario):
    _, _, generated, diff, _ = scenario
    assert read_nonempty_lines(os.path.join(ROOT, "src/generated_config.rs")) == generated
    assert read_nonempty_lines(os.path.join(ROOT, "config_diff.txt")) == diff


def test_generator_and_ci_pipeline_behavior():
    paths = [
        os.path.join(ROOT, "generator.cpp"),
        os.path.join(ROOT, "config.expr"),
        os.path.join(ROOT, "previous_config.txt"),
        os.path.join(ROOT, "src/main.rs"),
    ]
    originals = {path: open(path, "rb").read() for path in paths}

    try:
        # A clean pipeline run must compile generator.cpp, execute the resulting
        # generator on unpredictable data, and build the corresponding Rust app.
        scenario = make_scenario()
        install_scenario(scenario)
        for path in [
            os.path.join(ROOT, "generator"),
            os.path.join(ROOT, "src/generated_config.rs"),
            os.path.join(ROOT, "config_diff.txt"),
        ]:
            if os.path.lexists(path):
                os.remove(path)
        shutil.rmtree(os.path.join(ROOT, "target"), ignore_errors=True)

        result = run_ci()
        assert result.returncode == 0, f"Pipeline failed on valid dynamic input:\n{result.stdout}"
        assert_scenario_outputs(scenario)
        generator = os.path.join(ROOT, "generator")
        assert os.path.isfile(generator) and os.access(generator, os.X_OK)
        with open(generator, "rb") as f:
            assert f.read(4) == b"\x7fELF"
        rust_binary = os.path.join(ROOT, "target/debug/rust_app")
        assert os.path.isfile(rust_binary) and os.access(rust_binary, os.X_OK)
        app_result = subprocess.run([rust_binary], cwd=ROOT, timeout=30)
        assert app_result.returncode == 0

        # Exercise the compiled generator itself on a second unpredictable input.
        second = make_scenario()
        install_scenario(second)
        for path in [os.path.join(ROOT, "src/generated_config.rs"), os.path.join(ROOT, "config_diff.txt")]:
            if os.path.lexists(path):
                os.remove(path)
        gen_result = subprocess.run(
            [generator], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=30
        )
        assert gen_result.returncode == 0, f"Generator failed on dynamic input:\n{gen_result.stdout}"
        assert_scenario_outputs(second)

        # Compilation failures must make the pipeline fail.
        with open(os.path.join(ROOT, "generator.cpp"), "w") as f:
            f.write("this is not valid C++17 source\n")
        result = run_ci()
        assert result.returncode != 0, "Pipeline returned success when C++ compilation failed."

        # A successfully compiled generator that fails at runtime must also fail CI.
        with open(os.path.join(ROOT, "generator.cpp"), "w") as f:
            f.write("int main() { return 9; }\n")
        result = run_ci()
        assert result.returncode != 0, "Pipeline returned success when the generator failed."

        # Cargo build failures must propagate too.
        with open(os.path.join(ROOT, "generator.cpp"), "wb") as f:
            f.write(originals[os.path.join(ROOT, "generator.cpp")])
        with open(os.path.join(ROOT, "config.expr"), "wb") as f:
            f.write(originals[os.path.join(ROOT, "config.expr")])
        with open(os.path.join(ROOT, "previous_config.txt"), "wb") as f:
            f.write(originals[os.path.join(ROOT, "previous_config.txt")])
        with open(os.path.join(ROOT, "src/main.rs"), "w") as f:
            f.write("fn main() { this is invalid rust }\n")
        result = run_ci()
        assert result.returncode != 0, "Pipeline returned success when cargo build failed."
    finally:
        for path, data in originals.items():
            with open(path, "wb") as f:
                f.write(data)

        # Leave the requested baseline artifacts in their correct final state.
        result = run_ci()
        assert result.returncode == 0, f"Could not restore final baseline build:\n{result.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
