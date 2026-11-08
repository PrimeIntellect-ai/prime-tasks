#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import secrets
import subprocess
import tempfile
import time

SCRIPT_PATH = "/home/user/project/build.py"
ARTIFACT_PATH = "/home/user/project/build_artifact.txt"


def load_build_module():
    spec = importlib.util.spec_from_file_location("submitted_build", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None, "Could not load build.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_build_script_exists():
    """Verify that the build script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."


def test_build_script_execution_and_artifact():
    """Run the build script and verify its required artifact."""
    try:
        os.remove(ARTIFACT_PATH)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=10,
    )

    assert result.returncode == 0, (
        f"The script {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"Standard Error:\n{result.stderr}"
    )
    assert os.path.isfile(ARTIFACT_PATH), (
        f"The artifact file {ARTIFACT_PATH} was not created after running the script. "
        "The script might still have a bug causing premature file deletion."
    )

    with open(ARTIFACT_PATH, "r") as f:
        content = f.read().strip()

    expected_content = "SUCCESS: 1.0.42"
    assert content == expected_content, (
        f"The artifact file {ARTIFACT_PATH} does not contain the expected text. "
        f"Expected '{expected_content}', but got '{content}'."
    )


def test_cleanup_uses_timezone_consistent_file_age():
    """Fresh manifests must survive and genuinely old manifests must be removed."""
    module = load_build_module()
    assert callable(getattr(module, "cleanup_old_builds", None)), (
        "build.py must retain and fix the cleanup_old_builds operation"
    )

    old_cwd = os.getcwd()
    old_tz = os.environ.get("TZ")
    original_sleep = module.time.sleep
    module.time.sleep = lambda _seconds: None

    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            os.chdir(tmpdir)
            for timezone in ("America/New_York", "Asia/Tokyo"):
                os.environ["TZ"] = timezone
                time.tzset()

                with open("manifest.tmp", "w") as f:
                    f.write("fresh")
                now = time.time()
                os.utime("manifest.tmp", (now, now))
                module.cleanup_old_builds()
                assert os.path.exists("manifest.tmp"), (
                    f"cleanup deleted a fresh manifest in timezone {timezone}"
                )

                old = time.time() - 7200
                os.utime("manifest.tmp", (old, old))
                module.cleanup_old_builds()
                assert not os.path.exists("manifest.tmp"), (
                    f"cleanup failed to delete a two-hour-old manifest in timezone {timezone}"
                )
    finally:
        module.time.sleep = original_sleep
        os.chdir(old_cwd)
        if old_tz is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = old_tz
        time.tzset()


def test_main_consumes_generated_manifest_instead_of_writing_constant_artifact():
    """Exercise the build with a verifier-selected manifest version."""
    module = load_build_module()
    assert callable(getattr(module, "main", None)), "build.py must provide its build main()"
    assert callable(getattr(module, "generate_manifest", None)), (
        "build.py must retain the manifest generation stage"
    )

    selected_version = "verify-" + secrets.token_hex(12)

    def generated_manifest():
        with open("manifest.tmp", "w") as f:
            json.dump({"version": selected_version, "timestamp": time.time()}, f)

    module.generate_manifest = generated_manifest
    for path in (ARTIFACT_PATH, "/home/user/project/manifest.tmp"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    module.main()

    assert os.path.isfile(ARTIFACT_PATH), "main() did not generate the build artifact"
    with open(ARTIFACT_PATH, "r") as f:
        content = f.read().strip()
    assert content == f"SUCCESS: {selected_version}", (
        "The build artifact was not derived from the generated manifest"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
