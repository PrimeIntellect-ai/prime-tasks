#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import subprocess
import sys
import tempfile
import pytest

WORKSPACE = "/home/user/mobile_pipeline"
LIB_PATH = os.path.join(WORKSPACE, "libfastsemver.so")
RESOLVED_MANIFEST_PATH = os.path.join(WORKSPACE, "resolved_manifest.json")
RESOLVER_PATH = os.path.join(WORKSPACE, "build_resolver.py")

@pytest.fixture(scope="session", autouse=True)
def rebuild_native_library():
    subprocess.run(["make", "clean"], cwd=WORKSPACE, check=True, timeout=30)
    subprocess.run(["make", "all"], cwd=WORKSPACE, check=True, timeout=30)


def test_libfastsemver_exists():
    assert os.path.isfile(LIB_PATH), "The native extension libfastsemver.so was not built."


def test_native_library_loads_and_handles_long_versions():
    cases = [
        "1.2.3",
        "7.8.9-" + ("prerelease" * 700),
        ("1234567890" * 300) + ".2.3",
    ]
    expected = [value.split("-", 1)[0] for value in cases]

    probe = r'''
import ctypes
import json
import os

lib = ctypes.CDLL(os.environ["LIB_PATH"])
parse = lib.parse_version_core
parse.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
parse.restype = None
results = []
for value in json.loads(os.environ["CASES"]):
    encoded = value.encode("utf-8")
    output = ctypes.create_string_buffer(len(encoded) + 32)
    parse(encoded, output)
    results.append(output.value.decode("utf-8"))
print(json.dumps(results))
'''
    env = os.environ.copy()
    env["LIB_PATH"] = LIB_PATH
    env["CASES"] = json.dumps(cases)
    result = subprocess.run(
        [sys.executable, "-c", probe],
        env=env,
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        "parse_version_core crashed or the shared library could not be loaded.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert json.loads(result.stdout) == expected, (
        "parse_version_core did not safely extract the base version from long inputs."
    )


def test_resolved_manifest_exists():
    assert os.path.isfile(RESOLVED_MANIFEST_PATH), "The resolved_manifest.json file was not generated."


def test_resolved_manifest_content():
    expected_content = {
        "libAnalytics": "3.0.0",
        "libAuth": "1.2.9",
        "libDatabase": "4.2.0",
        "libNetwork": "2.1.10",
        "libUI": "1.15.2"
    }

    with open(RESOLVED_MANIFEST_PATH, 'r') as f:
        try:
            actual_content = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("resolved_manifest.json is not a valid JSON file.")

    assert actual_content == expected_content, (
        f"The resolved manifest content is incorrect.\n"
        f"Expected: {expected_content}\n"
        f"Actual: {actual_content}\n"
        f"Check your semantic version comparison logic."
    )


def test_resolved_manifest_formatting():
    with open(RESOLVED_MANIFEST_PATH, 'r') as f:
        raw_content = f.read()

    content_dict = json.loads(raw_content)
    expected_raw = json.dumps(content_dict, indent=4, sort_keys=True)

    assert raw_content.strip() == expected_raw.strip(), (
        "The resolved_manifest.json is not formatted correctly. "
        "Ensure it uses indent=4 and keys are sorted alphabetically."
    )


def test_resolver_executes_on_unseen_manifests():
    rng = secrets.SystemRandom()
    token = secrets.token_hex(8)
    patch_low = rng.randint(2, 8)
    patch_high = rng.randint(10, 99)
    minor_low = rng.randint(2, 8)
    minor_high = rng.randint(10, 99)

    manifest_a = {
        f"numericPatch_{token}": f"1.4.{patch_low}",
        f"numericMinor_{token}": f"3.{minor_high}.1",
        f"prerelease_{token}": f"5.6.7-alpha.{rng.randint(1000, 9999)}",
        f"onlyA_{token}": "8.0.1",
        f"major_{token}": "9.99.99",
    }
    manifest_b = {
        f"numericPatch_{token}": f"1.4.{patch_high}",
        f"numericMinor_{token}": f"3.{minor_low}.99",
        f"prerelease_{token}": "5.6.6",
        f"onlyB_{token}": "2.3.4",
        f"major_{token}": "10.0.0",
    }

    def base_tuple(version):
        return tuple(int(part) for part in version.split("-", 1)[0].split("."))

    expected = {}
    for key in set(manifest_a) | set(manifest_b):
        if key not in manifest_b:
            expected[key] = manifest_a[key]
        elif key not in manifest_a:
            expected[key] = manifest_b[key]
        elif base_tuple(manifest_a[key]) >= base_tuple(manifest_b[key]):
            expected[key] = manifest_a[key]
        else:
            expected[key] = manifest_b[key]
    expected = {key: expected[key] for key in sorted(expected)}

    with tempfile.TemporaryDirectory() as temp_dir:
        path_a = os.path.join(temp_dir, "manifest_A.json")
        path_b = os.path.join(temp_dir, "manifest_B.json")
        with open(path_a, "w") as f:
            json.dump(manifest_a, f)
        with open(path_b, "w") as f:
            json.dump(manifest_b, f)

        result = subprocess.run(
            [sys.executable, RESOLVER_PATH, path_a, path_b],
            cwd=temp_dir,
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            "build_resolver.py failed on valid unseen manifests.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

        output_path = os.path.join(temp_dir, "resolved_manifest.json")
        assert os.path.isfile(output_path), (
            "build_resolver.py did not generate resolved_manifest.json."
        )
        with open(output_path, "r") as f:
            raw_output = f.read()
        assert json.loads(raw_output) == expected, (
            "build_resolver.py produced an incorrect result for unseen numeric versions."
        )
        assert raw_output.strip() == json.dumps(expected, indent=4, sort_keys=True).strip(), (
            "Dynamically generated resolved_manifest.json is not sorted and formatted with indent=4."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
