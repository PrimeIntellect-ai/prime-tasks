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
import json
import math
import os
import secrets
import subprocess
import textwrap

import pytest
import requests

URL = "http://127.0.0.1:8080/process"
AUTHORIZED = {"Authorization": "Bearer secret_token_999"}


def post(payload, headers=None, timeout=10):
    try:
        return requests.post(URL, json=payload, headers=headers or {}, timeout=timeout)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service or request timed out: {e}")


def parse_success(resp):
    assert resp.status_code == 200, (
        f"Expected status code 200, got {resp.status_code}. Response: {resp.text}"
    )
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")

    assert "cleaned_count" in data, "Response JSON missing 'cleaned_count'"
    assert "mean_ci" in data, "Response JSON missing 'mean_ci'"
    assert isinstance(data["cleaned_count"], int) and not isinstance(data["cleaned_count"], bool)
    mean_ci = data["mean_ci"]
    assert isinstance(mean_ci, list) and len(mean_ci) == 2, "mean_ci must be a list of two floats"
    for value in mean_ci:
        assert isinstance(value, (int, float)) and not isinstance(value, bool), "CI bounds must be numbers"
        assert math.isfinite(value), "CI bounds must be finite"
    return data


def test_vendored_package_fixed_and_behavioral():
    cargo_path = "/app/outlier_detect/Cargo.toml"
    assert os.path.isfile(cargo_path), f"{cargo_path} is missing."
    with open(cargo_path, "r") as f:
        cargo_content = f.read()
    assert "[dependencies]" in cargo_content, "Cargo.toml should have the typo '[dependencis]' fixed to '[dependencies]'."
    assert "[dependencis]" not in cargo_content, "Cargo.toml still contains the typo '[dependencis]'."

    lib_path = "/app/outlier_detect/src/lib.rs"
    assert os.path.isfile(lib_path), f"{lib_path} is missing."
    with open(lib_path, "r") as f:
        lib_content = f.read()

    # Retain the original source-level assertion, then compile and execute the crate.
    assert "sum::<f64>() / data.len() as f64;" in lib_content or "sum::<f64>() / (data.len() as f64);" in lib_content or "as f64;\n" in lib_content, "lib.rs still seems to be missing the semicolon on the variance calculation."

    probe = "/tmp/outlier_probe"
    os.makedirs(os.path.join(probe, "src"), exist_ok=True)
    with open(os.path.join(probe, "Cargo.toml"), "w") as f:
        f.write(textwrap.dedent("""
            [package]
            name = "outlier_probe"
            version = "0.1.0"
            edition = "2021"

            [dependencies]
            outlier_detect = { path = "/app/outlier_detect" }
        """))
    with open(os.path.join(probe, "src", "main.rs"), "w") as f:
        f.write(textwrap.dedent("""
            fn main() {
                assert!(outlier_detect::filter_outliers(&[]).is_empty());
                assert_eq!(
                    outlier_detect::filter_outliers(&[1.0, 2.0, 3.0]),
                    vec![1.0, 2.0, 3.0]
                );
                assert_eq!(
                    outlier_detect::filter_outliers(&[0.0, 0.0, 0.0, 0.0, 0.0, 100.0]),
                    vec![0.0, 0.0, 0.0, 0.0, 0.0]
                );
                assert_eq!(
                    outlier_detect::filter_outliers(&[7.5, 7.5, 7.5]),
                    vec![7.5, 7.5, 7.5]
                );
            }
        """))
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--offline", "--manifest-path", os.path.join(probe, "Cargo.toml")],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
        env={**os.environ, "CARGO_TARGET_DIR": "/tmp/outlier_probe_target"},
    )
    assert result.returncode == 0, f"Vendored crate failed compilation/behavioral probe:\n{result.stdout}"


def test_rust_service_project_compiles_and_uses_vendor():
    manifest = "/home/user/data_service/Cargo.toml"
    assert os.path.isfile(manifest), f"{manifest} is missing"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--offline", "--format-version", "1", "--manifest-path", manifest],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert metadata_result.returncode == 0, f"Cargo metadata failed:\n{metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    root_manifest = os.path.realpath(manifest)
    root_packages = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == root_manifest]
    assert root_packages, "Cargo metadata did not contain the data_service package"
    vendor_path = os.path.realpath("/app/outlier_detect")
    assert any(
        dep.get("name") == "outlier_detect"
        and dep.get("path")
        and os.path.realpath(dep["path"]) == vendor_path
        for dep in root_packages[0]["dependencies"]
    ), "data_service must depend on the vendored /app/outlier_detect crate"

    rust_sources = []
    for root, _, files in os.walk("/home/user/data_service/src"):
        for name in files:
            if name.endswith(".rs"):
                with open(os.path.join(root, name), "r") as f:
                    rust_sources.append(f.read())
    assert rust_sources, "The service has no Rust source files"
    assert any("filter_outliers" in source for source in rust_sources), (
        "The service source does not call filter_outliers"
    )

    check_result = subprocess.run(
        ["cargo", "check", "--offline", "--manifest-path", manifest],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert check_result.returncode == 0, f"Rust service does not compile:\n{check_result.stdout}"


def test_service_unauthorized():
    payload = [{"id": 1, "val": 10.0}]

    resp = post(payload)
    assert resp.status_code == 401, f"Expected 401 Unauthorized for missing header, got {resp.status_code}"

    resp = post(payload, {"Authorization": "Bearer wrong_token"})
    assert resp.status_code == 401, f"Expected 401 Unauthorized for incorrect token, got {resp.status_code}"


def test_service_processing_original_case():
    payload = [
        {"id": 1, "val": 10.0},
        {"id": 2, "val": 12.0},
        {"id": 3, "val": None},
        {"id": 4, "val": 11.0},
        {"id": 5, "val": 1000.0},
        {"id": 6, "val": 9.0},
    ]
    data = parse_success(post(payload, AUTHORIZED))
    assert data["cleaned_count"] == 5, f"Expected cleaned_count to be 5, got {data['cleaned_count']}"

    lower_bound, upper_bound = data["mean_ci"]
    assert 8.0 <= lower_bound <= 50.0, f"Lower bound {lower_bound} is outside the plausible range [8.0, 50.0]"
    assert 50.0 <= upper_bound <= 200.0, f"Upper bound {upper_bound} is outside the plausible range [50.0, 200.0]"
    assert lower_bound < upper_bound, "Lower bound must be less than upper bound"


def test_randomized_imputation_and_constant_bootstrap():
    # The value is selected only after the agent has finished, preventing a fixed response.
    base = float(secrets.randbelow(9000) + 1000)
    payload = [
        {"id": 101, "val": base},
        {"id": 205, "val": None},
        {"id": 309, "val": base},
        {"id": 412, "val": None},
        {"id": 578, "val": base},
    ]
    data = parse_success(post(payload, AUTHORIZED))
    assert data["cleaned_count"] == len(payload)
    lower, upper = data["mean_ci"]
    assert math.isclose(lower, base, rel_tol=0.0, abs_tol=1e-8), (
        f"Constant data with mean-imputed nulls must have lower CI {base}, got {lower}"
    )
    assert math.isclose(upper, base, rel_tol=0.0, abs_tol=1e-8), (
        f"Constant data with mean-imputed nulls must have upper CI {base}, got {upper}"
    )


def test_randomized_outlier_removal():
    base = float(secrets.randbelow(5000) - 2500)
    extreme = base + float(secrets.randbelow(50000) + 50000)
    payload = [{"id": i + 1, "val": base} for i in range(8)]
    payload.append({"id": 999, "val": extreme})
    data = parse_success(post(payload, AUTHORIZED))
    assert data["cleaned_count"] == 8, "A single value more than two standard deviations away was not removed"
    lower, upper = data["mean_ci"]
    assert math.isclose(lower, base, rel_tol=0.0, abs_tol=1e-8)
    assert math.isclose(upper, base, rel_tol=0.0, abs_tol=1e-8)


def test_randomized_bootstrap_distribution():
    low = float(secrets.randbelow(2000) - 1000)
    span = float(secrets.randbelow(900) + 100)
    high = low + span
    values = [low] * 10 + [high] * 10
    payload = [{"id": 7000 + i, "val": value} for i, value in enumerate(values)]
    data = parse_success(post(payload, AUTHORIZED))
    assert data["cleaned_count"] == 20
    lower, upper = data["mean_ci"]

    # For n=20 with ten values at each endpoint, bootstrap sample means follow
    # low + span*Binomial(20, 0.5)/20. These broad bands safely contain the
    # sampled 5th/95th percentiles while rejecting fixed or non-bootstrap CIs.
    assert low + 0.20 * span <= lower <= low + 0.40 * span, (
        f"Unexpected bootstrap lower percentile {lower} for endpoints {low}, {high}"
    )
    assert low + 0.60 * span <= upper <= low + 0.80 * span, (
        f"Unexpected bootstrap upper percentile {upper} for endpoints {low}, {high}"
    )
    assert lower < upper
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
