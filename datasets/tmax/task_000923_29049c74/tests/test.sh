#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import tempfile
import pytest

TOOL_DIR = "/home/user/web_sec_tool"
LIB_DIR = "/home/user/libwebcrypto"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 180)
    return subprocess.run(cmd, **kwargs)


def runtime_env(extra_library_dir=None):
    env = os.environ.copy()
    paths = []
    if extra_library_dir:
        paths.append(extra_library_dir)
    paths.append(LIB_DIR)
    if env.get("LD_LIBRARY_PATH"):
        paths.append(env["LD_LIBRARY_PATH"])
    env["LD_LIBRARY_PATH"] = ":".join(paths)
    return env


def cargo_metadata():
    result = run(
        ["cargo", "metadata", "--format-version", "1", "--locked"],
        cwd=TOOL_DIR,
    )
    assert result.returncode == 0, (
        "cargo metadata --locked failed.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    return json.loads(result.stdout)


def version_tuple(text):
    match = re.fullmatch(r"(\d+)\.(\d+)(?:\.(\d+))?", text)
    assert match, f"Unsupported version component in regex requirement: {text}"
    return tuple(int(x or 0) for x in match.groups())


def requirement_is_within_allowed_range(req):
    req = req.strip()
    if "-" in req or "+" in req or "||" in req:
        return False

    match = re.fullmatch(r"~\s*(\d+)\.(\d+)(?:\.(\d+))?", req)
    if match:
        major, minor, patch = (int(x or 0) for x in match.groups())
        return (major, minor, patch) >= (1, 9, 0) and (major, minor + 1, 0) <= (1, 10, 0)

    match = re.fullmatch(r"(\d+)\.(\d+)\.(?:\*|x|X)", req)
    if match:
        return (int(match.group(1)), int(match.group(2))) == (1, 9)

    match = re.fullmatch(r"=\s*(\d+\.\d+\.\d+)", req)
    if match:
        value = version_tuple(match.group(1))
        return (1, 9, 0) <= value < (1, 10, 0)

    lower_is_safe = False
    upper_is_safe = False
    for item in req.split(","):
        match = re.fullmatch(r"\s*(>=|>|<=|<|=)\s*(\d+\.\d+(?:\.\d+)?)\s*", item)
        if not match:
            return False
        op, raw_version = match.groups()
        value = version_tuple(raw_version)
        if op in (">=", ">") and value >= (1, 9, 0):
            lower_is_safe = True
        elif op == "<" and value <= (1, 10, 0):
            upper_is_safe = True
        elif op == "<=" and value < (1, 10, 0):
            upper_is_safe = True
        elif op == "=" and (1, 9, 0) <= value < (1, 10, 0):
            lower_is_safe = True
            upper_is_safe = True
    return lower_is_safe and upper_is_safe


def resolved_regex_details():
    metadata = cargo_metadata()
    root_id = metadata["resolve"]["root"]
    root_package = next(p for p in metadata["packages"] if p["id"] == root_id)

    declared = [
        dep for dep in root_package["dependencies"]
        if dep["name"] == "regex" and dep.get("kind") is None and dep.get("rename") is None
    ]
    assert len(declared) == 1, "Cargo.toml must contain one direct, normal dependency on the real regex crate."
    dependency = declared[0]
    assert dependency.get("source") == "registry+https://github.com/rust-lang/crates.io-index", (
        "The regex dependency must come from crates.io, not a local or substituted package."
    )
    assert requirement_is_within_allowed_range(dependency["req"]), (
        f"Cargo.toml regex requirement {dependency['req']!r} does not guarantee "
        "a version >= 1.9.0 and < 1.10.0."
    )

    root_node = next(node for node in metadata["resolve"]["nodes"] if node["id"] == root_id)
    direct_regex = [dep for dep in root_node["deps"] if dep["name"] == "regex"]
    assert len(direct_regex) == 1, "The root package did not resolve one direct regex dependency."
    regex_id = direct_regex[0]["pkg"]
    regex_package = next(p for p in metadata["packages"] if p["id"] == regex_id)
    assert regex_package["name"] == "regex"
    assert regex_package.get("source") == "registry+https://github.com/rust-lang/crates.io-index", (
        "The resolved regex package is not the crates.io regex crate."
    )
    parts = tuple(int(x) for x in regex_package["version"].split("-")[0].split("."))
    assert len(parts) == 3 and (1, 9, 0) <= parts < (1, 10, 0), (
        f"Resolved regex version is outside the required range: {regex_package['version']}"
    )
    return regex_package["version"]


def test_symlink_correct():
    symlink_path = "/home/user/libwebcrypto/libwebcrypto.so"
    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symlink, but it is not."

    target = os.readlink(symlink_path)
    expected_targets = ("libwebcrypto.so.1.3.5", "/home/user/libwebcrypto/libwebcrypto.so.1.3.5")
    assert target in expected_targets, f"Symlink points to incorrect target: {target}. Expected one of {expected_targets}."


def test_deployment_json():
    json_path = "/home/user/deployment.json"
    assert os.path.isfile(json_path), f"File {json_path} is missing."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} is not valid JSON.")

    assert set(data) == {"regex_version", "libwebcrypto_version"}, (
        "deployment.json must contain exactly regex_version and libwebcrypto_version."
    )
    assert data["libwebcrypto_version"] == "1.3.5", f"Incorrect libwebcrypto_version: {data['libwebcrypto_version']}. Expected '1.3.5'."

    regex_ver = data["regex_version"]
    assert regex_ver.startswith("1.9."), f"Incorrect regex_version in JSON: {regex_ver}. Expected a 1.9.x version."
    assert regex_ver == resolved_regex_details(), (
        "deployment.json regex_version does not equal the exact version resolved in Cargo.lock."
    )


def test_cargo_build_and_run():
    clean = run(["cargo", "clean"], cwd=TOOL_DIR)
    assert clean.returncode == 0, f"cargo clean failed: {clean.stderr}"

    build = run(
        ["cargo", "build", "--locked", "--message-format=json"],
        cwd=TOOL_DIR,
        env=runtime_env(),
    )
    assert build.returncode == 0, (
        f"cargo build --locked failed.\nSTDOUT:\n{build.stdout}\nSTDERR:\n{build.stderr}"
    )

    executable = None
    for line in build.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("reason") == "compiler-artifact" and message.get("target", {}).get("name") == "web_sec_tool" and message.get("executable"):
            executable = message["executable"]
    assert executable and os.path.isfile(executable), "Could not locate the built web_sec_tool executable."

    dynamic = run(["readelf", "-d", executable])
    assert dynamic.returncode == 0, f"Could not inspect the built executable: {dynamic.stderr}"
    assert re.search(r"NEEDED.*libwebcrypto\.so", dynamic.stdout), (
        "The executable does not have a dynamic dependency on libwebcrypto.so."
    )

    result = run(["cargo", "run", "--locked"], cwd=TOOL_DIR, env=runtime_env())
    assert result.returncode == 0, f"'cargo run' failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert "Encrypted value: 42" in result.stdout, "Expected output 'Encrypted value: 42' not found in cargo run output."

    injected_value = 100000 + secrets.randbelow(800000)
    with tempfile.TemporaryDirectory() as temp_dir:
        source = os.path.join(temp_dir, "webcrypto_probe.c")
        library = os.path.join(temp_dir, "libwebcrypto.so")
        with open(source, "w") as f:
            f.write(f"int encrypt(void) {{ return {injected_value}; }}\n")
        compile_result = run([
            "gcc", "-shared", "-fPIC", "-Wl,-soname,libwebcrypto.so",
            "-o", library, source,
        ])
        assert compile_result.returncode == 0, f"Failed to build verifier probe library: {compile_result.stderr}"

        probe = run(["cargo", "run", "--quiet", "--locked"], cwd=TOOL_DIR, env=runtime_env(temp_dir))
        assert probe.returncode == 0, (
            f"cargo run with the probe library failed.\nSTDOUT:\n{probe.stdout}\nSTDERR:\n{probe.stderr}"
        )
        assert probe.stdout.strip() == f"Encrypted value: {injected_value}", (
            "The program did not obtain its encrypted value from the dynamically linked "
            "libwebcrypto encrypt() function."
        )


def test_cargo_lock_regex_version():
    lock_path = "/home/user/web_sec_tool/Cargo.lock"
    assert os.path.isfile(lock_path), f"{lock_path} is missing. Did you run 'cargo build'?"

    result = run(["cargo", "pkgid", "regex"], cwd=TOOL_DIR)
    assert result.returncode == 0, f"Could not determine regex version from cargo.\nSTDERR: {result.stderr}"
    output = result.stdout.strip()
    assert "1.9." in output, f"Resolved regex version in Cargo does not match 1.9.x. Cargo pkgid output: {output}"

    resolved = resolved_regex_details()
    with open(lock_path, "r") as f:
        lock_text = f.read()
    matching_blocks = []
    for block in lock_text.split("[[package]]")[1:]:
        if re.search(r'^name\s*=\s*"regex"\s*$', block, re.MULTILINE):
            matching_blocks.append(block)
    assert matching_blocks, "Cargo.lock has no package entry for regex."
    assert any(
        re.search(rf'^version\s*=\s*"{re.escape(resolved)}"\s*$', block, re.MULTILINE)
        and re.search(r'^source\s*=\s*"registry\+https://github.com/rust-lang/crates.io-index"\s*$', block, re.MULTILINE)
        for block in matching_blocks
    ), "Cargo.lock does not contain the resolved crates.io regex version."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
