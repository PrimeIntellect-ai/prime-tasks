#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import textwrap
import pytest

PROJECT_DIR = "/home/user/rusty-dispatcher"
PROCESSOR_RS = f"{PROJECT_DIR}/src/processor.rs"
WORKER_SCRIPT = f"{PROJECT_DIR}/mock_worker.sh"


def test_failed_files_json():
    json_path = "/home/user/diagnostics/failed_files.json"
    assert os.path.isfile(json_path), f"The file {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    assert isinstance(data, list), f"The JSON in {json_path} must be an array."

    expected_files = {
        "/data/inputs/financial summary final.pdf",
        "/data/inputs/user backups/archive.tar.gz",
    }
    actual_files = set(data)
    assert actual_files == expected_files, (
        f"The extracted failed files do not match the expected list.\n"
        f"Expected: {expected_files}\nFound: {actual_files}"
    )


def test_processor_rs_fixed():
    assert os.path.isfile(PROCESSOR_RS), f"{PROCESSOR_RS} does not exist."
    with open(PROCESSOR_RS, "r") as f:
        content = f.read()

    assert "Command::new(\"sh\")" not in content, (
        "The code still uses Command::new(\"sh\"), which is unsafe for this use case."
    )
    assert "arg(\"-c\")" not in content, (
        "The code still passes '-c' to a shell, indicating the bug might not be properly fixed."
    )


def test_regression_test_exists():
    assert os.path.isfile(PROCESSOR_RS), f"{PROCESSOR_RS} does not exist."
    with open(PROCESSOR_RS, "r") as f:
        content = f.read()

    assert "test_filename_with_spaces_regression" in content, (
        "The regression test `test_filename_with_spaces_regression` was not found in processor.rs."
    )

    result = subprocess.run(
        ["cargo", "test", "--", "--list"],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, (
        f"Could not enumerate the Rust tests.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert re.search(
        r"(?m)^.*test_filename_with_spaces_regression: test$", result.stdout
    ), "`test_filename_with_spaces_regression` is not a registered Rust test."


def test_execute_worker_job_passes_special_path_as_one_exact_argument():
    # Install a verifier-controlled worker that records exactly what the submitted
    # implementation passes to it. This prevents a stub returning Ok from passing.
    with open(WORKER_SCRIPT, "w") as f:
        f.write(textwrap.dedent("""\
            #!/bin/bash
            printf '%s' "$#" > /tmp/verifier_worker_argc
            if [ "$#" -ge 1 ]; then
                printf '%s' "$1" > /tmp/verifier_worker_arg
            else
                : > /tmp/verifier_worker_arg
            fi
            [ "$#" -eq 1 ] || exit 41
            [ -f "$1" ] || exit 42
            exit 0
        """))
    os.chmod(WORKER_SCRIPT, 0o755)

    harness_dir = "/tmp/rusty_dispatcher_verifier_harness"
    os.makedirs(f"{harness_dir}/src", exist_ok=True)
    with open(f"{harness_dir}/Cargo.toml", "w") as f:
        f.write(textwrap.dedent("""\
            [package]
            name = "rusty-dispatcher-verifier-harness"
            version = "0.1.0"
            edition = "2021"

            [dependencies]
            rusty-dispatcher = { path = "/home/user/rusty-dispatcher" }
        """))
    with open(f"{harness_dir}/src/main.rs", "w") as f:
        f.write(textwrap.dedent(r'''\
            use std::fs;

            fn main() {
                let dir = std::env::temp_dir().join(format!(
                    "rusty_dispatcher_behavior_{}", std::process::id()
                ));
                fs::create_dir_all(&dir).unwrap();
                let path = dir.join("payload with spaces;dollar$ampersand&brackets[1].txt");
                fs::write(&path, b"verification data").unwrap();

                let _ = fs::remove_file("/tmp/verifier_worker_argc");
                let _ = fs::remove_file("/tmp/verifier_worker_arg");

                let path_string = path.to_str().unwrap().to_owned();
                rusty_dispatcher::processor::execute_worker_job(&path_string)
                    .expect("execute_worker_job returned an error for a valid special-character path");

                let argc = fs::read_to_string("/tmp/verifier_worker_argc")
                    .expect("the worker script was not executed");
                assert_eq!(argc, "1", "worker script did not receive exactly one argument");

                let actual = fs::read("/tmp/verifier_worker_arg").unwrap();
                assert_eq!(actual, path_string.as_bytes(),
                    "worker script did not receive the exact filepath");
            }
        '''))

    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", f"{harness_dir}/Cargo.toml"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, (
        "execute_worker_job failed the verifier-controlled spaced/special-path test.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_cargo_test_passes():
    assert os.path.isdir(PROJECT_DIR), f"Project directory {PROJECT_DIR} does not exist."
    result = subprocess.run(
        ["cargo", "test"],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, (
        f"`cargo test` failed in {PROJECT_DIR}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
