#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
import uuid
import pytest


def test_build_pipeline_exists_and_builds_from_source():
    script_path = "/home/user/build_pipeline.sh"
    source_path = "/home/user/src/video_processor/main.cpp"
    assert os.path.isfile(script_path), f"Build script not found: {script_path}"

    with open(script_path, "r") as f:
        script_text = f.read()
    uncommented = "\n".join(
        line for line in script_text.splitlines()
        if not line.lstrip().startswith("#")
    )
    assert re.search(r"(^|[\n;|&])\s*(?:/usr/bin/)?cmake\b", uncommented), \
        "build_pipeline.sh does not invoke CMake"

    with open(source_path, "r") as f:
        original_source = f.read()

    marker = "BuildProbe_" + uuid.uuid4().hex
    probe_source = f'''#include <iostream>
extern int apply_filter(int x);
int main() {{
    std::cout << "{marker}:" << apply_filter(42) << std::endl;
    return 0;
}}
'''

    try:
        with open(source_path, "w") as f:
            f.write(probe_source)

        # Remove previously produced copies so the script must produce a fresh binary.
        for root, dirs, files in os.walk("/home/user"):
            for name in files:
                if name == "vproc_bin":
                    os.remove(os.path.join(root, name))

        try:
            result = subprocess.run(
                ["bash", script_path], text=True, capture_output=True, timeout=120
            )
        except subprocess.TimeoutExpired:
            pytest.fail("build_pipeline.sh timed out")

        assert result.returncode == 0, (
            "build_pipeline.sh failed:\n"
            + result.stdout + "\n" + result.stderr
        )

        bin_path = "/home/user/deploy/bin/vproc_bin"
        assert os.path.isfile(bin_path), f"Build script did not create {bin_path}"
        assert os.access(bin_path, os.X_OK), f"Built binary is not executable: {bin_path}"
        run = subprocess.run([bin_path], text=True, capture_output=True, timeout=10)
        assert run.returncode == 0, f"Freshly built vproc_bin failed: {run.stderr}"
        assert f"{marker}:84" in run.stdout, \
            "Deployed binary was not compiled from the current CMake project source"
    finally:
        with open(source_path, "w") as f:
            f.write(original_source)


def test_vproc_bin_compiled_and_linked():
    bin_path = "/home/user/deploy/bin/vproc_bin"
    assert os.path.isfile(bin_path), f"Binary not found: {bin_path}"
    assert os.access(bin_path, os.X_OK), f"Binary is not executable: {bin_path}"

    try:
        ldd_output = subprocess.check_output(["ldd", bin_path], text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run ldd on {bin_path}: {e}")

    assert "libcustom_filter.so" in ldd_output, "vproc_bin is not dynamically linked to libcustom_filter.so"
    assert "not found" not in ldd_output, "vproc_bin has missing dynamic libraries (rpath might be missing)"


def test_video_result():
    result_path = "/home/user/deploy/video_result.txt"
    assert os.path.isfile(result_path), f"Video result file not found: {result_path}"

    with open(result_path, "r") as f:
        content = f.read().strip()

    assert content == "27", f"Expected video result to be '27', but got '{content}'"


def test_run_integration_exists_and_exercises_entire_corpus():
    script_path = "/home/user/run_integration.sh"
    deploy_script = "/home/user/deploy/run_integration.sh"
    validator = "/home/user/deploy/validate_routes.sh"

    assert os.path.isfile(script_path), f"Integration test script not found: {script_path}"
    assert os.path.isfile(deploy_script), f"Deployed integration script not found: {deploy_script}"

    with open(script_path, "r") as f:
        text = f.read()
    uncommented = "\n".join(
        line for line in text.splitlines()
        if not line.lstrip().startswith("#")
    )
    assert re.search(r"(^|[\n;|&])\s*(?:/usr/bin/)?time\b", uncommented), \
        "run_integration.sh does not benchmark with time"
    assert re.search(r"(^|[\n;|&])\s*(?:/usr/bin/)?diff\b", uncommented), \
        "run_integration.sh does not produce a diff"

    expected = set()
    for corpus_dir in ("/app/corpus/clean", "/app/corpus/evil"):
        for name in os.listdir(corpus_dir):
            path = os.path.join(corpus_dir, name)
            if os.path.isfile(path):
                expected.add(os.path.realpath(path))

    assert os.path.isfile(validator), f"Validator script not found: {validator}"
    with tempfile.TemporaryDirectory(prefix="integration_probe_") as td:
        original = os.path.join(td, "validate_routes.original")
        calls = os.path.join(td, "calls.log")
        shutil.copy2(validator, original)
        wrapper = f'''#!/bin/bash
p=$(readlink -f -- "$1")
printf '%s\\n' "$p" >> {calls!r}
exec {original!r} "$@"
'''
        try:
            with open(validator, "w") as f:
                f.write(wrapper)
            os.chmod(validator, 0o755)
            try:
                subprocess.run(
                    ["bash", script_path],
                    text=True,
                    capture_output=True,
                    timeout=60,
                    cwd="/home/user",
                )
            except subprocess.TimeoutExpired:
                pytest.fail("run_integration.sh timed out")
        finally:
            shutil.copy2(original, validator)

        seen = set()
        if os.path.isfile(calls):
            with open(calls, "r") as f:
                seen = {line.strip() for line in f if line.strip()}

        missing = sorted(expected - seen)
        assert not missing, (
            f"run_integration.sh did not validate all corpus files; missing {len(missing)}: "
            + ", ".join(missing[:10])
        )


def test_validate_routes_adversarial_corpus():
    script_path = "/home/user/deploy/validate_routes.sh"
    assert os.path.isfile(script_path), f"Validator script not found: {script_path}"
    assert os.access(script_path, os.X_OK), f"Validator script is not executable: {script_path}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    for fpath in clean_files:
        res = subprocess.run([script_path, fpath], capture_output=True)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(fpath))

    evil_bypassed = []
    for fpath in evil_files:
        res = subprocess.run([script_path, fpath], capture_output=True)
        if res.returncode != 1:
            evil_bypassed.append(os.path.basename(fpath))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean files rejected (expected exit code 0): {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil files bypassed (expected exit code 1): {', '.join(evil_bypassed)}")

    if errors:
        pytest.fail("Adversarial corpus validation failed:\n" + "\n".join(errors))

    # Random names and a mixed directory prevent classification by the shipped paths.
    cases = [
        (0, '''server {
  listen 80;
  location /ordinary { proxy_pass http://backend/service; }
}
'''),
        (0, '''server {
  listen 8080;
  proxy_set_header Authorization $http_authorization;
  location /authorized { proxy_pass http://backend/service; }
}
'''),
        (0, '''server {
  listen 80;
  # proxy_pass http://backend/../commented-out;
  location /literal { proxy_pass http://backend/normal; }
}
'''),
        (1, '''server {
  listen 80;
  location /x { proxy_pass http://backend/a/../private; }
}
'''),
        (1, '''server {
  listen 8080;
  location /x { proxy_pass http://backend/service; }
}
'''),
        (1, '''server {
  listen 8080;
  # proxy_set_header Authorization $http_authorization;
  location /x { proxy_pass http://backend/service; }
}
'''),
    ]

    with tempfile.TemporaryDirectory(prefix="route_probe_" + uuid.uuid4().hex + "_") as td:
        generated = []
        for expected_code, content in cases:
            path = os.path.join(td, uuid.uuid4().hex + ".data")
            with open(path, "w") as f:
                f.write(content)
            generated.append((path, expected_code))

        failures = []
        for path, expected_code in generated:
            result = subprocess.run([script_path, path], capture_output=True)
            if result.returncode != expected_code:
                failures.append(
                    f"{os.path.basename(path)} expected {expected_code}, got {result.returncode}"
                )
        assert not failures, "Generated route validation failed:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
