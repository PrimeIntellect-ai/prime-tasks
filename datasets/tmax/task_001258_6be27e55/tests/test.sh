#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import stat
import sys

import pytest
import requests

URL = "http://127.0.0.1:8888/resolve"
AUTH = {"Authorization": "Bearer test-agent-token-99"}
REGISTRY_PATH = "/home/user/registry.json"


def checksum(resolved):
    entries = sorted(f"{name}=={version}" for name, version in resolved.items())
    return hashlib.sha256("\n".join(entries).encode("utf-8")).hexdigest()


def request_resolution(pkg, req):
    try:
        return requests.get(
            URL,
            params={"pkg": pkg, "req": req},
            headers=AUTH,
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the resolution API at {URL}: {exc}")


def test_resolver_artifact_exists():
    path = "/home/user/resolver.py"
    assert os.path.exists(path), f"Missing required server artifact: {path}"
    mode = os.stat(path).st_mode
    assert stat.S_ISREG(mode), f"Expected {path} to be a regular file"
    assert os.path.getsize(path) > 0, f"Expected {path} to be non-empty"


def test_semantic_version_fixed():
    """Verify the vendored semantic_version constraint bug was fixed."""
    vendored_path = "/app/semantic_version"
    if vendored_path not in sys.path:
        sys.path.insert(0, vendored_path)

    try:
        import semantic_version
    except ImportError:
        pytest.fail(f"Could not import semantic_version from {vendored_path}")

    assert os.path.realpath(semantic_version.__file__).startswith(
        os.path.realpath(vendored_path) + os.sep
    ), "semantic_version was not imported from the required vendored package"

    try:
        spec = semantic_version.SimpleSpec(">=1.5.0")
        ver = semantic_version.Version("1.5.0")
        assert spec.match(ver) is True, "The semantic_version bug is not fixed. '>=1.5.0' should match '1.5.0'."

        cases = [
            (">=1.5.0", "1.4.9", False),
            (">=1.5.0", "1.5.1", True),
            ("<=2.3.4", "2.3.4", True),
            ("<=2.3.4", "2.3.3", True),
            ("<=2.3.4", "2.3.5", False),
            (">1.0.0", "1.0.0", False),
            (">1.0.0", "1.0.1", True),
            ("<2.0.0", "2.0.0", False),
            ("<2.0.0", "1.9.9", True),
            ("==1.2.3", "1.2.3", True),
            ("==1.2.3", "1.2.4", False),
            ("!=1.2.3", "1.2.4", True),
            (">=1.2.0,<2.0.0", "1.8.7", True),
            (">=1.2.0,<2.0.0", "2.0.0", False),
        ]
        for expression, version, expected in cases:
            actual = semantic_version.SimpleSpec(expression).match(
                semantic_version.Version(version)
            )
            assert actual is expected, (
                f"SimpleSpec({expression!r}).match(Version({version!r})) "
                f"returned {actual!r}, expected {expected!r}"
            )
    except Exception as exc:
        pytest.fail(f"Error evaluating semantic_version constraints: {exc}")


def test_api_resolution_success():
    """Verify the API returns the correct resolved versions and checksum."""
    response = request_resolution("frontend", ">=1.0.0")
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "resolved" in data, "Missing 'resolved' key in JSON response."
    assert "checksum" in data, "Missing 'checksum' key in JSON response."

    resolved = data["resolved"]
    expected_resolved = {
        "frontend": "1.2.0",
        "backend": "2.2.0",
        "db": "1.0.1",
    }

    for pkg, expected_ver in expected_resolved.items():
        actual_ver = resolved.get(pkg)
        assert actual_ver == expected_ver, f"Expected resolved package '{pkg}' to be '{expected_ver}', got '{actual_ver}'"

    expected_checksum = checksum(expected_resolved)
    assert data["checksum"] == expected_checksum, f"Checksum mismatch. Expected '{expected_checksum}', got '{data['checksum']}'"


def test_api_uses_registry_and_resolves_dynamic_constraints():
    """Exercise randomized registry data so a fixed response cannot pass."""
    with open(REGISTRY_PATH, "rb") as handle:
        original_bytes = handle.read()
    original_registry = json.loads(original_bytes.decode("utf-8"))

    rng = secrets.SystemRandom()
    token = secrets.token_hex(8)
    target = f"target_{token}"
    dep_a = f"dep_a_{token}"
    dep_b = f"dep_b_{token}"

    target_parts = sorted(rng.sample(range(1, 40), 3))
    a_parts = sorted(rng.sample(range(1, 40), 3))
    b_parts = sorted(rng.sample(range(1, 40), 3))

    target_versions = [f"1.{part}.0" for part in target_parts]
    a_versions = [f"2.{part}.0" for part in a_parts]
    b_versions = [f"3.{part}.0" for part in b_parts]

    registry = dict(original_registry)
    registry[target] = {
        target_versions[0]: {"deps": {}},
        target_versions[1]: {
            "deps": {
                dep_a: f">={a_versions[1]}",
                dep_b: f"<={b_versions[1]}",
            }
        },
        target_versions[2]: {"deps": {dep_b: f">={b_versions[1]}"}},
    }
    registry[dep_a] = {version: {"deps": {}} for version in a_versions}
    registry[dep_b] = {version: {"deps": {}} for version in b_versions}

    temporary = REGISTRY_PATH + ".verifier.tmp"
    try:
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(registry, handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, REGISTRY_PATH)

        expected_upper = {
            target: target_versions[1],
            dep_a: a_versions[2],
            dep_b: b_versions[1],
        }
        response = request_resolution(target, f"<={target_versions[1]}")
        assert response.status_code == 200, response.text
        data = response.json()
        assert data.get("resolved") == expected_upper
        assert data.get("checksum") == checksum(expected_upper)

        expected_lower = {
            target: target_versions[2],
            dep_b: b_versions[2],
        }
        response = request_resolution(target, f">={target_versions[1]}")
        assert response.status_code == 200, response.text
        data = response.json()
        assert data.get("resolved") == expected_lower
        assert data.get("checksum") == checksum(expected_lower)
    finally:
        with open(temporary, "wb") as handle:
            handle.write(original_bytes)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, REGISTRY_PATH)


def test_api_unauthorized():
    """Verify the API rejects requests without the correct Authorization header."""
    params = {"pkg": "frontend", "req": ">=1.0.0"}
    try:
        response = requests.get(URL, params=params, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the resolution API at {URL}: {exc}")
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for missing auth, got {response.status_code}"

    response = requests.get(
        URL,
        params=params,
        headers={"Authorization": "Bearer wrong-token"},
        timeout=5,
    )
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for incorrect auth, got {response.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
