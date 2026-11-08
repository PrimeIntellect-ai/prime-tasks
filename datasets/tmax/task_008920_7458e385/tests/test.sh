#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile

APP = "/home/user/app"
LIB_RS = os.path.join(APP, "src/lib.rs")


def cargo_env():
    env = os.environ.copy()
    env["PKG_CONFIG_PATH"] = "/home/user/custom_lib/pkgconfig"
    return env


def test_rust_code_fixed_and_test_added():
    assert os.path.exists(LIB_RS), f"File {LIB_RS} does not exist."
    with open(LIB_RS, "r") as f:
        content = f.read()

    # Check if the regression test is present
    assert "test_process_data_regression" in content, "The required test 'test_process_data_regression' is missing in src/lib.rs."


def test_test_output_file():
    output_path = "/home/user/test_output.txt"
    assert os.path.exists(output_path), f"File {output_path} does not exist. Did you redirect the output of cargo test?"
    with open(output_path, "r") as f:
        content = f.read()

    assert "test_process_data_regression" in content, "The test output file does not mention 'test_process_data_regression'."
    assert "ok" in content, "The test output file does not indicate that tests passed (missing 'ok')."


def test_cargo_test_success():
    # Verify that the project actually compiles and tests pass when the correct environment is set
    result = subprocess.run(
        ["cargo", "test"],
        cwd=APP,
        env=cargo_env(),
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"cargo test failed. The borrow checker error might not be fixed correctly, or the test failed. Output:\n{result.stdout}\n{result.stderr}"

    # Cargo test output can go to stdout or stderr depending on the version and flags
    combined_output = result.stdout + "\n" + result.stderr
    assert "test_process_data_regression" in combined_output, "The test 'test_process_data_regression' was not executed by cargo test."


def test_process_data_actual_behavior():
    # Independently exercise the public function instead of trusting agent-authored tests.
    tests_dir = os.path.join(APP, "tests")
    os.makedirs(tests_dir, exist_ok=True)
    verifier_test = os.path.join(tests_dir, "__verifier_process_data.rs")
    try:
        with open(verifier_test, "w") as f:
            f.write(
                "use app::process_data;\n"
                "#[test]\n"
                "fn verifier_process_data_behavior() {\n"
                "    let mut data = vec![10, 20];\n"
                "    process_data(&mut data);\n"
                "    assert_eq!(data, vec![10, 20, 10]);\n"
                "}\n"
            )
        result = subprocess.run(
            ["cargo", "test", "--test", "__verifier_process_data"],
            cwd=APP,
            env=cargo_env(),
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, (
            "process_data does not transform [10, 20] into [10, 20, 10].\n"
            + result.stdout + "\n" + result.stderr
        )
    finally:
        if os.path.exists(verifier_test):
            os.remove(verifier_test)
        if os.path.isdir(tests_dir) and not os.listdir(tests_dir):
            os.rmdir(tests_dir)


def test_regression_test_detects_the_regression():
    # Run the required named test against a deliberately broken copy of process_data.
    # A merely empty test with the right name must not pass this check.
    with tempfile.TemporaryDirectory() as tmp:
        copied_app = os.path.join(tmp, "app")
        shutil.copytree(APP, copied_app, ignore=shutil.ignore_patterns("target"))
        copied_lib = os.path.join(copied_app, "src/lib.rs")
        with open(copied_lib, "r") as f:
            source = f.read()

        signature = "pub fn process_data"
        start = source.find(signature)
        assert start != -1, "pub fn process_data is missing from src/lib.rs"
        body_start = source.find("{", start)
        assert body_start != -1, "Could not locate the body of process_data"

        depth = 0
        body_end = None
        for i in range(body_start, len(source)):
            if source[i] == "{":
                depth += 1
            elif source[i] == "}":
                depth -= 1
                if depth == 0:
                    body_end = i
                    break
        assert body_end is not None, "Could not parse the body of process_data"

        broken = source[:body_start] + "{ data.clear(); }" + source[body_end + 1:]
        with open(copied_lib, "w") as f:
            f.write(broken)

        result = subprocess.run(
            ["cargo", "test", "test_process_data_regression", "--", "--exact"],
            cwd=copied_app,
            env=cargo_env(),
            capture_output=True,
            text=True
        )
        assert result.returncode != 0, (
            "The required test_process_data_regression test passed even when "
            "process_data was changed to produce the wrong result; the test must "
            "call process_data and assert [10, 20, 10]."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
