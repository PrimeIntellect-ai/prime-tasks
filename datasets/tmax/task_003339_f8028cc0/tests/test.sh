#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import uuid


def assert_regular_file(path):
    assert os.path.exists(path), f"{path} does not exist."
    assert stat.S_ISREG(os.lstat(path).st_mode), f"{path} is not a regular file."


def expected_outputs(manifest, platform):
    artifacts = {a["name"]: a for a in manifest["artifacts"]}
    valid = {
        name for name, artifact in artifacts.items()
        if platform in artifact["platforms"]
    }
    memo = {}

    def content(name):
        if name in memo:
            return memo[name]
        deps = sorted(dep for dep in artifacts[name]["deps"] if dep in valid)
        value = name if not deps else f"{name}({','.join(content(dep) for dep in deps)})"
        memo[name] = value
        return value

    return {f"{name}.out": content(name) for name in valid}


def assert_platform_outputs(manifest, platform):
    platform_dir = os.path.join("/home/user/artifacts", platform)
    expected = expected_outputs(manifest, platform)
    assert os.path.isdir(platform_dir), f"Missing platform directory: {platform_dir}"
    actual_names = set(os.listdir(platform_dir))
    assert actual_names == set(expected), (
        f"Wrong output files for {platform}: expected {set(expected)}, got {actual_names}"
    )
    for filename, expected_content in expected.items():
        path = os.path.join(platform_dir, filename)
        assert_regular_file(path)
        with open(path, "r") as f:
            actual = f.read().strip()
        assert actual == expected_content, (
            f"Content mismatch in {path}. Expected '{expected_content}', got '{actual}'"
        )


def make_dynamic_manifest():
    suffix = uuid.uuid4().hex[:10]
    p1 = "plat" + uuid.uuid4().hex[:8]
    p2 = "plat" + uuid.uuid4().hex[:8]
    p3 = "plat" + uuid.uuid4().hex[:8]
    base = "base_" + suffix
    mid = "mid_" + suffix
    only1 = "onlya_" + suffix
    only2 = "onlyb_" + suffix
    top = "top_" + suffix
    third = "third_" + suffix

    # Dependents intentionally precede dependencies, and dependency lists are
    # intentionally not alphabetical.
    manifest = {
        "artifacts": [
            {"name": top, "platforms": [p1, p2], "deps": [only2, mid, only1, base]},
            {"name": third, "platforms": [p3], "deps": [base]},
            {"name": only2, "platforms": [p2], "deps": [base]},
            {"name": mid, "platforms": [p1, p2], "deps": [base]},
            {"name": only1, "platforms": [p1], "deps": [base]},
            {"name": base, "platforms": [p1, p2, p3], "deps": []},
        ]
    }
    return manifest, p1, p2, p3


def test_run_ci_and_verify_outputs():
    artifacts_dir = "/home/user/artifacts"
    if os.path.exists(artifacts_dir):
        subprocess.run(["rm", "-rf", artifacts_dir], check=True)

    ci_script = "/home/user/run_ci.sh"
    assert_regular_file(ci_script)

    commit_msg = "Initial commit [ci:linux] [ci:mac]"
    result = subprocess.run(["bash", ci_script, commit_msg], capture_output=True, text=True)
    assert result.returncode == 0, f"run_ci.sh failed with return code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    expected_files = {
        "linux/base.out": "base",
        "linux/crypto.out": "crypto(base)",
        "linux/gui_x11.out": "gui_x11(base)",
        "linux/app.out": "app(base,crypto(base),gui_x11(base))",
        "mac/base.out": "base",
        "mac/gui_mac.out": "gui_mac(base)",
        "mac/app.out": "app(base,gui_mac(base))"
    }

    for rel_path, expected_content in expected_files.items():
        file_path = os.path.join(artifacts_dir, rel_path)
        assert os.path.exists(file_path), f"Expected output file missing: {file_path}"
        with open(file_path, "r") as f:
            content = f.read().strip()
            assert content == expected_content, f"Content mismatch in {file_path}. Expected '{expected_content}', got '{content}'"


def test_windows_platform_directly():
    build_manager = "/home/user/build_manager.py"
    manifest = "/home/user/manifest.json"
    assert_regular_file(build_manager)

    result = subprocess.run(["python3", build_manager, "--manifest", manifest, "--platform", "windows"], capture_output=True, text=True)
    assert result.returncode == 0, f"build_manager.py failed for windows.\nStderr: {result.stderr}"

    expected_files = {
        "windows/base.out": "base",
        "windows/crypto.out": "crypto(base)",
        "windows/app.out": "app(base,crypto(base))"
    }

    artifacts_dir = "/home/user/artifacts"
    for rel_path, expected_content in expected_files.items():
        file_path = os.path.join(artifacts_dir, rel_path)
        assert os.path.exists(file_path), f"Expected output file missing: {file_path}"
        with open(file_path, "r") as f:
            content = f.read().strip()
            assert content == expected_content, f"Content mismatch in {file_path}. Expected '{expected_content}', got '{content}'"


def test_build_manager_uses_supplied_manifest_and_resolves_dynamic_dag(tmp_path):
    build_manager = "/home/user/build_manager.py"
    assert_regular_file(build_manager)
    manifest, p1, _, _ = make_dynamic_manifest()
    manifest_path = tmp_path / "dynamic_manifest.json"
    manifest_path.write_text(json.dumps(manifest))

    shutil.rmtree("/home/user/artifacts", ignore_errors=True)
    result = subprocess.run(
        ["python3", build_manager, "--manifest", str(manifest_path), "--platform", p1],
        capture_output=True, text=True
    )
    assert result.returncode == 0, (
        f"build_manager.py failed on a supplied manifest.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert set(os.listdir("/home/user/artifacts")) == {p1}
    assert_platform_outputs(manifest, p1)


def test_run_ci_parses_dynamic_multiple_tags_and_uses_prescribed_manifest():
    ci_script = "/home/user/run_ci.sh"
    assert_regular_file(ci_script)
    manifest, p1, p2, p3 = make_dynamic_manifest()
    manifest_path = "/home/user/manifest.json"
    with open(manifest_path, "rb") as f:
        original_manifest = f.read()

    shutil.rmtree("/home/user/artifacts", ignore_errors=True)
    try:
        with open(manifest_path, "w") as f:
            json.dump(manifest, f)
        message = f"Dynamic build request [ci:{p2}] some text [ci:{p1}] mentions {p3} without a tag"
        result = subprocess.run(["bash", ci_script, message], capture_output=True, text=True)
        assert result.returncode == 0, (
            f"run_ci.sh failed on dynamic tags.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        )
        assert os.path.isdir("/home/user/artifacts")
        assert set(os.listdir("/home/user/artifacts")) == {p1, p2}, (
            "CI must build exactly the platforms appearing in [ci:<platform>] tags"
        )
        assert_platform_outputs(manifest, p1)
        assert_platform_outputs(manifest, p2)
        assert not os.path.exists(os.path.join("/home/user/artifacts", p3))
    finally:
        with open(manifest_path, "wb") as f:
            f.write(original_manifest)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
