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
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import json
import math
import os
import pathlib
import secrets
import subprocess
import time

import pytest
import requests

URL = "http://127.0.0.1:9090/run_mcmc"
LOG = pathlib.Path("/tmp/verifier_oracle_calls")
TARGET = pathlib.Path("/tmp/verifier_oracle_target")


def install_instrumented_oracle():
    source = r'''
use std::env;
use std::fs::{read_to_string, OpenOptions};
use std::io::Write;

fn main() {
    let arg = env::args().nth(1).unwrap_or_else(|| std::process::exit(1));
    let mu: f64 = arg.parse().unwrap_or_else(|_| std::process::exit(1));
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open("/tmp/verifier_oracle_calls") {
        let _ = writeln!(f, "{:.17}", mu);
    }
    let center: f64 = read_to_string("/tmp/verifier_oracle_target")
        .unwrap_or_else(|_| "1.234".to_string())
        .trim().parse().unwrap();
    let log_lik = -((mu - center) * (mu - center)) / (2.0 * 0.1_f64.powi(2));
    println!("{}", log_lik);
}
'''
    pathlib.Path("/tmp/verifier_score_oracle.rs").write_text(source)
    subprocess.run(
        ["rustc", "-O", "/tmp/verifier_score_oracle.rs", "-o", "/tmp/verifier_score_oracle"],
        check=True,
    )
    os.chmod("/tmp/verifier_score_oracle", 0o755)
    os.replace("/tmp/verifier_score_oracle", "/app/score_oracle")


def reset_oracle(center):
    TARGET.write_text(f"{center:.17g}\n")
    os.chmod(TARGET, 0o644)
    LOG.write_text("")
    os.chmod(LOG, 0o666)


def post(payload, timeout=90):
    response = None
    for _ in range(10):
        try:
            response = requests.post(URL, json=payload, timeout=timeout)
            break
        except requests.exceptions.ConnectionError:
            time.sleep(1)
    assert response is not None, f"Failed to connect to the server at {URL}. Is the server running?"
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, but could not parse it. Response: {response.text}")
    assert "mean" in data, f"Response JSON does not contain 'mean' key. Response: {data}"
    mean_val = data["mean"]
    assert isinstance(mean_val, (int, float)) and not isinstance(mean_val, bool), (
        f"Expected 'mean' to be a number, got {type(mean_val)}"
    )
    assert math.isfinite(mean_val), f"Expected a finite mean, got {mean_val}"
    return float(mean_val)


def oracle_calls():
    values = []
    for line in LOG.read_text().splitlines():
        try:
            value = float(line)
        except ValueError:
            continue
        if math.isfinite(value):
            values.append(value)
    return values


def assert_real_sampling_calls(iterations):
    calls = oracle_calls()
    assert len(calls) >= int(iterations * 0.85), (
        f"Expected the sampler to invoke /app/score_oracle for its proposals; "
        f"observed only {len(calls)} calls for {iterations} iterations"
    )
    rounded = {round(x, 8) for x in calls}
    assert len(rounded) >= min(500, iterations // 3), (
        "Oracle arguments did not contain enough distinct proposal values"
    )
    assert all(-1.0 <= x <= 11.0 for x in calls), "Oracle received implausible proposal values"


def rust_listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            address, port = fields[1].rsplit(":", 1)
            if port.upper() != "2382":
                continue
            if table.endswith("tcp") and address.upper() != "0100007F":
                continue
            inodes.add(fields[9])

    pids = []
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.append(int(proc.name))
                    break
        except OSError:
            continue
    return pids


def assert_rust_implementation():
    manifests = []
    for root in (pathlib.Path("/home/user"), pathlib.Path("/app"), pathlib.Path("/workspace")):
        if root.exists():
            manifests.extend(root.rglob("Cargo.toml"))
    assert manifests, "No Rust Cargo project was found"
    assert any(list(manifest.parent.rglob("*.rs")) for manifest in manifests), (
        "The Cargo project contains no Rust source files"
    )

    pids = rust_listener_pid()
    assert pids, "No process is listening on exactly 127.0.0.1:9090"
    rust_markers = (b"rust_begin_unwind", b"rust_eh_personality", b"/rustc/", b"library/std/src", b"core/src/")
    for pid in pids:
        try:
            exe = pathlib.Path(f"/proc/{pid}/exe").resolve()
            image = exe.read_bytes()
        except OSError:
            continue
        if image.startswith(b"\x7fELF") and any(marker in image for marker in rust_markers):
            return
    pytest.fail("The process listening on port 9090 is not a compiled Rust executable")


def test_mcmc_endpoint():
    install_instrumented_oracle()
    assert_rust_implementation()

    # Preserve the original fixed request and its assertions.
    reset_oracle(1.234)
    iterations = 5000
    mean_val = post({"iterations": iterations, "init_mu": 1.0})
    expected_mean = 1.234
    tolerance = 0.05
    assert abs(mean_val - expected_mean) <= tolerance, (
        f"Calculated mean {mean_val} is not within {tolerance} of expected {expected_mean}."
    )
    assert_real_sampling_calls(iterations)

    # Secret, runtime-selected likelihoods prevent a fixed response from passing.
    rng = secrets.SystemRandom()
    observed_means = []
    for _ in range(2):
        center = rng.uniform(2.0, 8.0)
        init_mu = min(9.0, max(1.0, center + rng.choice((-0.7, 0.7))))
        iterations = 3200
        reset_oracle(center)
        mean_val = post({"iterations": iterations, "init_mu": init_mu})
        assert abs(mean_val - center) <= 0.08, (
            f"Calculated mean {mean_val} did not track the runtime oracle posterior centered at {center}"
        )
        assert_real_sampling_calls(iterations)
        observed_means.append(mean_val)

    assert abs(observed_means[0] - observed_means[1]) > 0.1 or abs(observed_means[0] - 1.234) > 0.5
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
