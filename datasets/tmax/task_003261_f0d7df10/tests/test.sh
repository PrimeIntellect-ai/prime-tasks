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
import os
import random
import shutil
import subprocess
import tempfile
import time

import pytest
import requests

PROJECT_DIR = "/home/user/policy-service"
SEMVER_RS = os.path.join(PROJECT_DIR, "src/semver.rs")
URL = "http://127.0.0.1:8080/validate"


def post_version(version):
    try:
        response = requests.post(URL, json={"version": version}, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the HTTP service or request failed: {exc}")
    assert response.status_code == 200, f"Expected HTTP 200 for version {version!r}, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response for {version!r} was not JSON: {response.text!r}")
    assert "allowed" in data, f"Response JSON missing 'allowed' key for version {version!r}"
    assert type(data["allowed"]) is bool, f"'allowed' must be a JSON boolean for version {version!r}"
    return data["allowed"]


def test_service_ready_file_exists():
    assert os.path.isfile("/tmp/service_ready"), "/tmp/service_ready file was not created by the service"


def test_http_endpoint_validation_and_dynamic_policy():
    time.sleep(1)

    # Preserve the original verifier's assertions against the supplied policy.
    original_cases = [
        ("1.5.4", True),
        ("2.0.0", False),
        ("1.1.9", False),
    ]
    for version, expected in original_cases:
        assert post_version(version) is expected, f"Expected allowed={expected} for version {version}"

    # Replace the image after the server has started. This checks that the service
    # actually reads/OCRs the current policy rather than hardcoding the three cases
    # or caching the policy at startup.
    policy_path = "/app/policy.png"
    backup_fd, backup_path = tempfile.mkstemp(suffix=".png")
    os.close(backup_fd)
    shutil.copy2(policy_path, backup_path)

    rng = random.SystemRandom()
    low = (rng.randint(3, 8), rng.randint(1, 8), rng.randint(1, 8))
    high = (low[0] + rng.randint(1, 3), rng.randint(1, 8), rng.randint(1, 8))
    policy_text = f">={low[0]}.{low[1]}.{low[2]} <{high[0]}.{high[1]}.{high[2]}"
    generated_path = f"/tmp/policy-{os.getpid()}.png"

    try:
        result = subprocess.run(
            ["convert", "-size", "700x120", "xc:white", "-fill", "black",
             "-pointsize", "32", "-annotate", "+15+65", policy_text, generated_path],
            capture_output=True, text=True,
        )
        assert result.returncode == 0, f"Could not generate policy image: {result.stdout}\n{result.stderr}"
        os.chmod(generated_path, 0o644)
        os.replace(generated_path, policy_path)

        def fmt(v):
            return f"{v[0]}.{v[1]}.{v[2]}"

        cases = {
            low,
            high,
            (low[0], low[1], low[2] + 1),
            (high[0], high[1], max(0, high[2] - 1)),
            (max(0, low[0] - 1), 99, 99),
            (high[0] + 1, 0, 0),
        }
        for _ in range(16):
            cases.add((rng.randint(0, high[0] + 2), rng.randint(0, 15), rng.randint(0, 15)))

        for version_tuple in cases:
            expected = low <= version_tuple < high
            version = fmt(version_tuple)
            assert post_version(version) is expected, (
                f"Policy {policy_text!r} expected allowed={expected} for {version}"
            )

        # Inputs which are not x.y.z semantic versions must not be accepted.
        for invalid in ["", "garbage", "1.2", "1.2.3.4", "-1.2.3", "1.02.3", " 1.2.3", "1.2.3 "]:
            assert post_version(invalid) is False, f"Invalid semantic version {invalid!r} was accepted"
    finally:
        shutil.copy2(backup_path, policy_path)
        os.unlink(backup_path)
        if os.path.exists(generated_path):
            os.unlink(generated_path)


def test_cargo_tests_pass():
    result = subprocess.run(["cargo", "test"], cwd=PROJECT_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"cargo test failed:\n{result.stdout}\n{result.stderr}"


def test_proptest_used():
    assert os.path.isfile(SEMVER_RS), f"{SEMVER_RS} does not exist"
    with open(SEMVER_RS, "r") as source:
        content = source.read()
    assert "proptest" in content, "proptest crate is not used in src/semver.rs"
    assert "proptest!" in content or "#[proptest]" in content, "proptest macro is not used in src/semver.rs"


def test_semver_comparator_and_transitivity_independently():
    # Compile an external harness against the submitted module. This does not
    # trust agent-authored tests and checks both lexicographic ordering and the
    # required transitivity property over independently generated values.
    with tempfile.TemporaryDirectory(prefix="semver-verifier-") as td:
        os.makedirs(os.path.join(td, "src"))
        with open(os.path.join(td, "Cargo.toml"), "w") as cargo:
            cargo.write('''[package]\nname = "semver-verifier"\nversion = "0.1.0"\nedition = "2021"\n\n[dependencies]\nproptest = "1.0"\nserde = { version = "1.0", features = ["derive"] }\nserde_json = "1.0"\ntokio = { version = "1.0", features = ["full"] }\naxum = "0.6"\n''')

        harness = r'''
#[path = "/home/user/policy-service/src/semver.rs"]
mod submitted_semver;

use std::cmp::Ordering;
use submitted_semver::Version;

fn version(t: (u32, u32, u32)) -> Version {
    Version { major: t.0, minor: t.1, patch: t.2 }
}

fn next(state: &mut u64) -> u32 {
    *state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
    (*state >> 32) as u32
}

fn main() {
    let mut values = Vec::new();
    for major in 0..7 {
        for minor in 0..7 {
            for patch in 0..7 {
                values.push((major, minor, patch));
            }
        }
    }

    for &a in &values {
        for &b in &values {
            let expected = a.cmp(&b);
            let actual = version(a).cmp(&version(b));
            assert_eq!(actual, expected, "wrong comparison for {:?} and {:?}", a, b);
        }
    }

    let mut state = 0x91e10da5c79e7b1du64;
    for _ in 0..25000 {
        let make = |state: &mut u64| -> (u32, u32, u32) {
            (next(state) % 1000, next(state) % 1000, next(state) % 1000)
        };
        let a = make(&mut state);
        let b = make(&mut state);
        let c = make(&mut state);
        let va = version(a);
        let vb = version(b);
        let vc = version(c);
        if va > vb && vb > vc {
            assert!(va > vc, "transitivity failed for {:?} > {:?} > {:?}", a, b, c);
        }
        assert_eq!(va.partial_cmp(&vb), Some(a.cmp(&b)));
        assert_eq!(va.cmp(&va), Ordering::Equal);
    }
}
'''
        with open(os.path.join(td, "src", "main.rs"), "w") as main_rs:
            main_rs.write(harness)

        result = subprocess.run(
            ["cargo", "run", "--quiet", "--offline"], cwd=td,
            capture_output=True, text=True, timeout=180,
        )
        assert result.returncode == 0, (
            "Submitted semver comparator failed independent ordering/transitivity checks:\n"
            f"{result.stdout}\n{result.stderr}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
