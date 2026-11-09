#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shutil
import stat
import subprocess
import tempfile

import pytest

ROOT = "/home/user/artifact_manager"
BINARY = os.path.join(ROOT, "version_bumper")
PROPERTY = os.path.join(ROOT, "test_property.sh")
PIPELINE = os.path.join(ROOT, "ci_pipeline.sh")
REPORT = os.path.join(ROOT, "pipeline_report.txt")


def run(args, timeout=30, **kwargs):
    return subprocess.run(
        args,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        **kwargs,
    )


def test_makefile_really_builds_working_c_program():
    clean = run(["make", "clean"])
    assert clean.returncode == 0, clean.stdout + clean.stderr
    assert not os.path.exists(BINARY), "make clean did not remove version_bumper"

    built = run(["make"])
    assert built.returncode == 0, built.stdout + built.stderr
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} does not exist. Did you fix the Makefile and run make?"
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "version_bumper must be a compiled native binary"

    cases = {
        ("0.0.0", "patch"): "0.0.1",
        ("7.12.99", "patch"): "7.12.100",
        ("3.9.8", "minor"): "3.10.0",
        ("99.98.97", "major"): "100.0.0",
    }
    for (version, operation), expected in cases.items():
        result = run([BINARY, version, operation])
        assert result.returncode == 0, result.stdout + result.stderr
        assert result.stdout == expected + "\n", (version, operation, result.stdout)

    for args in ([BINARY], [BINARY, "1.2.3", "unknown"], [BINARY, "not-a-version", "patch"]):
        result = run(args)
        assert result.returncode != 0, f"Invalid invocation unexpectedly succeeded: {args}"


def test_scripts_executable_and_property_source_is_bash():
    for script in (PROPERTY, PIPELINE):
        assert os.path.isfile(script), f"Script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."

    source = open(PROPERTY, encoding="utf-8").read()
    assert source.startswith("#!/bin/bash") or source.startswith("#!/usr/bin/env bash"), "test_property.sh must be a Bash script"
    assert re.search(r"\bRANDOM\b|/dev/(?:u)?random|\bshuf\b", source), "The property test must generate random inputs"
    assert not re.search(r"\b(?:python(?:3)?|perl|ruby|node)\b|sort\s+-V|dpkg\s+--compare-versions", source), "Semantic-version comparison must be implemented in Bash, not delegated to another language or version-comparison utility"


def test_property_script_runs_exactly_50_random_valid_patch_cases_and_detects_failure(tmp_path):
    real_binary = tmp_path / "version_bumper.real"
    shutil.copy2(BINARY, real_binary)
    log = tmp_path / "calls.log"

    forwarding_wrapper = f'''#!/bin/bash
printf '%s|%s\\n' "$1" "$2" >> {str(log)!r}
exec {str(real_binary)!r} "$@"
'''
    try:
        with open(BINARY, "w", encoding="utf-8") as f:
            f.write(forwarding_wrapper)
        os.chmod(BINARY, 0o755)

        result = run([PROPERTY], timeout=45)
        assert result.returncode == 0, result.stdout + result.stderr
        assert "All tests passed" in result.stdout, result.stdout

        calls = log.read_text(encoding="utf-8").splitlines()
        assert len(calls) == 50, f"Expected exactly 50 version_bumper calls, got {len(calls)}"
        versions = []
        for call in calls:
            version, separator, operation = call.partition("|")
            assert separator and operation == "patch", f"Unexpected invocation: {call}"
            match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", version)
            assert match, f"Generated version is not X.Y.Z: {version}"
            values = tuple(map(int, match.groups()))
            assert all(0 <= value <= 99 for value in values), f"Generated component outside 0..99: {version}"
            versions.append(version)
        assert len(set(versions)) > 1, "Random generation produced the same version for all 50 tests"

        failing_wrapper = '''#!/bin/bash
# Return the original version unchanged, violating strict greater-than.
printf '%s\\n' "$1"
exit 0
'''
        with open(BINARY, "w", encoding="utf-8") as f:
            f.write(failing_wrapper)
        os.chmod(BINARY, 0o755)
        failed = run([PROPERTY], timeout=45)
        assert failed.returncode == 1, "test_property.sh must exit 1 when the returned version is not strictly greater"
        output = failed.stdout + failed.stderr
        assert output.strip(), "test_property.sh must print an error when a property fails"
        assert "All tests passed" not in failed.stdout
    finally:
        shutil.copy2(real_binary, BINARY)
        os.chmod(BINARY, 0o755)


def test_ci_pipeline_builds_tests_and_propagates_failures(tmp_path):
    source_path = os.path.join(ROOT, "version_bumper.c")
    original_source = open(source_path, "rb").read()
    original_test = open(PROPERTY, "rb").read()
    original_mode = stat.S_IMODE(os.stat(PROPERTY).st_mode)

    try:
        # A compilation error must make the pipeline fail; an old binary must not mask it.
        with open(source_path, "w", encoding="utf-8") as f:
            f.write("this is deliberately invalid C\n")
        compile_failure = run([PIPELINE], timeout=45)
        assert compile_failure.returncode == 1, "ci_pipeline.sh must exit 1 when compilation fails"

        with open(source_path, "wb") as f:
            f.write(original_source)
        rebuilt = run(["make", "clean"])
        assert rebuilt.returncode == 0, rebuilt.stdout + rebuilt.stderr
        rebuilt = run(["make"])
        assert rebuilt.returncode == 0, rebuilt.stdout + rebuilt.stderr

        # A failing property test must also be executed and propagated.
        with open(PROPERTY, "w", encoding="utf-8") as f:
            f.write("#!/bin/bash\necho deliberate-test-failure >&2\nexit 1\n")
        os.chmod(PROPERTY, 0o755)
        test_failure = run([PIPELINE], timeout=45)
        assert test_failure.returncode == 1, "ci_pipeline.sh must exit 1 when test_property.sh fails"
        assert "deliberate-test-failure" in test_failure.stderr, "ci_pipeline.sh did not run test_property.sh"
    finally:
        with open(source_path, "wb") as f:
            f.write(original_source)
        with open(PROPERTY, "wb") as f:
            f.write(original_test)
        os.chmod(PROPERTY, original_mode)

    # Leave the workspace in the required final state by running the submitted pipeline.
    success = run([PIPELINE], timeout=60)
    assert success.returncode == 0, success.stdout + success.stderr
    assert "All tests passed" in success.stdout, "Successful pipeline did not run the property test"


def test_version_bumper_compiled():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} does not exist. Did you fix the Makefile and run make?"
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."


def test_scripts_executable():
    for script in (PROPERTY, PIPELINE):
        assert os.path.isfile(script), f"Script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."


def test_pipeline_report():
    assert os.path.isfile(REPORT), f"Report {REPORT} does not exist. Did you run the CI pipeline script?"
    with open(REPORT, "r", encoding="utf-8") as f:
        raw_content = f.read()
    content = raw_content.strip()
    match = re.match(r"^SUCCESS:\s*([a-f0-9]{64})$", content)
    assert match, f"Report content '{content}' does not match the expected format 'SUCCESS: <sha256_hash>'."
    reported_hash = match.group(1)
    with open(BINARY, "rb") as f:
        actual_hash = hashlib.sha256(f.read()).hexdigest()
    assert reported_hash == actual_hash, f"Reported hash {reported_hash} does not match actual hash of the binary {actual_hash}."
    assert raw_content in (f"SUCCESS: {actual_hash}", f"SUCCESS: {actual_hash}\n"), "Report must contain exactly 'SUCCESS: <sha256_hash>'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
