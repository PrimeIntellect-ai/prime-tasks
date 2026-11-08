#!/bin/bash
set +e
mkdir -p /logs/verifier

prep_status=0
if ! python3 -c 'import yaml' >/dev/null 2>&1; then
    apt-get update >/dev/null 2>&1 && apt-get install -y python3-yaml >/dev/null 2>&1 || prep_status=1
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import yaml

PROJECT = "/home/user/sec-payload-verifier"


def test_build_rs_fixed():
    path = os.path.join(PROJECT, "build.rs")
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "cc::Build::new()" in content or "cc::Build" in content, "build.rs does not appear to use the cc crate to build the C file."
    assert "src/fast_chk.c" in content, "build.rs does not reference 'src/fast_chk.c'."
    assert "compile" in content, "build.rs does not call compile()."
    assert re.search(r'\.compile\s*\(\s*"fast_chk"\s*\)', content), "build.rs does not compile the static library as 'fast_chk'."


def test_github_actions_workflow():
    path = os.path.join(PROJECT, ".github/workflows/ci.yml")
    assert os.path.isfile(path), f"GitHub Actions workflow file {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "cargo test" in content, "Workflow file does not contain 'cargo test'."
    assert "ubuntu-latest" in content, "Workflow file does not contain 'ubuntu-latest'."
    assert "push" in content, "Workflow file does not trigger on 'push'."

    workflow = yaml.safe_load(content)
    assert isinstance(workflow, dict), "Workflow is not a YAML mapping."

    # PyYAML 1.1 may parse the unquoted key `on` as boolean True.
    triggers = workflow.get("on", workflow.get(True))
    has_push = (
        triggers == "push"
        or isinstance(triggers, list) and "push" in triggers
        or isinstance(triggers, dict) and "push" in triggers
    )
    assert has_push, "Workflow does not semantically trigger on push."

    jobs = workflow.get("jobs")
    assert isinstance(jobs, dict) and jobs, "Workflow has no jobs."
    valid_job = False
    for job in jobs.values():
        if not isinstance(job, dict) or job.get("runs-on") != "ubuntu-latest":
            continue
        steps = job.get("steps")
        if not isinstance(steps, list):
            continue
        for step in steps:
            if not isinstance(step, dict) or not isinstance(step.get("run"), str):
                continue
            command = step["run"]
            if re.search(r'(?:^|[\n;&|])\s*cargo\s+test(?:\s|$)', command):
                valid_job = True
                break
        if valid_job:
            break
    assert valid_job, "No ubuntu-latest job contains a step that executes cargo test."


def test_results_log():
    path = "/home/user/test_results.log"
    assert os.path.isfile(path), f"Test results log file {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "test result: ok" in content.lower(), "Test results log does not indicate a successful test run ('test result: ok')."
    assert "test_ffi_checksum_matches_rust" in content, "Test results log does not show the property test being run."


def test_project_really_builds_and_tests():
    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["CARGO_HOME"] = "/home/user/.cargo"

    clean = subprocess.run(
        ["/usr/bin/cargo", "clean"],
        cwd=PROJECT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}"

    result = subprocess.run(
        ["/usr/bin/cargo", "test", "--", "--nocapture"],
        cwd=PROJECT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=300,
    )
    assert result.returncode == 0, f"cargo test failed:\n{result.stdout}"
    assert "test_ffi_checksum_matches_rust" in result.stdout, (
        "The actual cargo test run did not execute the required property test.\n"
        + result.stdout
    )
    assert "test result: ok" in result.stdout.lower(), (
        "The actual cargo test output does not report success.\n" + result.stdout
    )
TEST_EOF

if [ "$prep_status" -eq 0 ]; then
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
    status=$?
else
    echo "Unable to install the YAML parser required by the verifier." >&2
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
