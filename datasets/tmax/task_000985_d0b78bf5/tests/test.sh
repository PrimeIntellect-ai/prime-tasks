#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shlex
import shutil
import stat
import subprocess
from pathlib import Path

import numpy as np
import pytest

PROJECT = Path("/home/user/sre_tool")
REPORT = Path("/home/user/report.json")
CONF = Path("/home/user/sre_logrotate.conf")
IMAGE = Path("/app/vnc_crash.png")
METRICS = Path("/app/metrics.log")
TARGET_DIR = Path("/tmp/sre_verify_target")


def run_checked(command, **kwargs):
    return subprocess.run(
        command,
        check=True,
        text=True,
        capture_output=True,
        timeout=120,
        **kwargs,
    )


def reset_network():
    subprocess.run(
        ["ip", "route", "del", "10.55.0.0/24"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        ["ip", "link", "del", "sre-mon"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def build_rust_binary():
    assert PROJECT.is_dir(), f"{PROJECT} does not exist."
    manifest = PROJECT / "Cargo.toml"
    assert manifest.is_file(), f"{manifest} does not exist."

    metadata_result = run_checked([
        "cargo", "metadata", "--format-version", "1", "--no-deps",
        "--manifest-path", str(manifest),
    ])
    metadata = json.loads(metadata_result.stdout)
    manifest_real = manifest.resolve()
    packages = [
        package for package in metadata["packages"]
        if Path(package["manifest_path"]).resolve() == manifest_real
    ]
    assert len(packages) == 1, "Cargo metadata does not contain the sre_tool package."
    package = packages[0]
    bins = [target for target in package["targets"] if "bin" in target.get("kind", [])]
    assert bins, "The Cargo project has no Rust binary target."

    default_run = package.get("default_run")
    if default_run:
        selected = [target for target in bins if target["name"] == default_run]
        assert selected, "Cargo default-run does not name a binary target."
        target = selected[0]
    elif len(bins) == 1:
        target = bins[0]
    else:
        main_targets = [target for target in bins if Path(target["src_path"]).name == "main.rs"]
        assert len(main_targets) == 1, "Multiple binary targets exist without an unambiguous default."
        target = main_targets[0]

    source = Path(target["src_path"])
    assert source.is_file() and source.suffix == ".rs", "The binary target is not backed by Rust source."
    assert PROJECT.resolve() in source.resolve().parents, "The Rust binary source is outside /home/user/sre_tool."

    shutil.rmtree(TARGET_DIR, ignore_errors=True)
    env = os.environ.copy()
    env["CARGO_TARGET_DIR"] = str(TARGET_DIR)
    run_checked([
        "cargo", "build", "--manifest-path", str(manifest),
        "--bin", target["name"],
    ], cwd=str(PROJECT), env=env)

    binary = TARGET_DIR / "debug" / target["name"]
    assert binary.is_file(), f"Cargo did not produce the expected executable {binary}."
    assert os.stat(binary).st_mode & stat.S_IXUSR, f"{binary} is not executable."
    return binary


def execute_binary(binary):
    subprocess.run(
        [str(binary)],
        cwd=str(PROJECT),
        check=True,
        text=True,
        capture_output=True,
        timeout=120,
    )


def assert_network_configured():
    link = subprocess.run(["ip", "link", "show", "sre-mon"], capture_output=True, text=True)
    assert link.returncode == 0, "The executed Rust program did not create interface 'sre-mon'."
    assert "UP" in link.stdout or "state UP" in link.stdout or "state UNKNOWN" in link.stdout, \
        "The executed Rust program did not bring interface 'sre-mon' up."

    routes = run_checked(["ip", "route", "show", "10.55.0.0/24"]).stdout.splitlines()
    assert any(re.search(r"^10\.55\.0\.0/24(?:\s|$)", line) and re.search(r"\bdev\s+sre-mon\b", line)
               for line in routes), "The executed Rust program did not create the required route."


def assert_structured_logrotate_config():
    assert CONF.is_file(), f"{CONF} does not exist."
    raw_lines = CONF.read_text().splitlines()
    lines = []
    for raw in raw_lines:
        lexer = shlex.shlex(raw, posix=True)
        lexer.whitespace_split = True
        lexer.commenters = "#"
        tokens = list(lexer)
        if tokens:
            lines.append(tokens)

    blocks = []
    current_paths = None
    current_rules = None
    for tokens in lines:
        if current_paths is None:
            assert tokens[-1] == "{", f"Invalid logrotate block header: {' '.join(tokens)}"
            assert len(tokens) >= 2, "A logrotate block has no log path."
            current_paths = tokens[:-1]
            current_rules = []
        else:
            if tokens == ["}"]:
                blocks.append((current_paths, current_rules))
                current_paths = None
                current_rules = None
            else:
                assert "{" not in tokens and "}" not in tokens, "Malformed nested logrotate block."
                current_rules.append(tokens)
    assert current_paths is None, "Logrotate configuration has an unterminated block."

    matching = [rules for paths, rules in blocks if "/home/user/sre_tool.log" in paths]
    assert matching, "No active logrotate block targets /home/user/sre_tool.log."

    valid = False
    for rules in matching:
        if (["daily"] in rules and ["rotate", "7"] in rules and
                ["compress"] in rules and ["missingok"] in rules):
            valid = True
            break
    assert valid, "The target logrotate block lacks daily, rotate 7, compress, or missingok semantics."

    logrotate = shutil.which("logrotate")
    if logrotate:
        state = "/tmp/sre_logrotate_test.state"
        result = subprocess.run(
            [logrotate, "--debug", "--state", state, str(CONF)],
            capture_output=True, text=True,
        )
        assert result.returncode == 0, f"logrotate rejected the configuration: {result.stderr}"


def load_report():
    assert REPORT.is_file(), f"{REPORT} does not exist."
    with REPORT.open() as f:
        return json.load(f)


def test_rust_program_builds_and_performs_work_on_derived_inputs():
    binary = build_rust_binary()
    original_image = IMAGE.read_bytes()
    original_metrics = METRICS.read_bytes()

    panic_code = "0x" + "".join(secrets.choice("ABCDEF") for _ in range(8))
    while panic_code == "0xDEADBEEF":
        panic_code = "0x" + "".join(secrets.choice("ABCDEF") for _ in range(8))

    rng = random.SystemRandom()
    successful = [round(rng.uniform(20.0, 450.0), 2) for _ in range(101)]
    expected_p95 = float(np.percentile(successful, 95))
    records = [(value, 200) for value in successful]
    records.extend((round(rng.uniform(500.0, 900.0), 2), 500) for _ in range(17))
    rng.shuffle(records)

    try:
        run_checked([
            "convert", "-size", "800x600", "xc:black",
            "-font", "DejaVu-Sans-Mono", "-pointsize", "24", "-fill", "white",
            "-draw", "text 50,50 'Kernel panic - not syncing: Fatal exception'",
            "-draw", f"text 50,100 'PANIC: {panic_code}'",
            str(IMAGE),
        ])
        with METRICS.open("w") as f:
            for index, (latency, status) in enumerate(records):
                f.write(f"{1700000000000 + index * 100} {latency:.2f} {status}\n")

        REPORT.unlink(missing_ok=True)
        CONF.unlink(missing_ok=True)
        reset_network()
        execute_binary(binary)

        data = load_report()
        assert data.get("panic_code") == panic_code, \
            "The executed Rust program did not OCR the verifier-generated panic code."
        assert "p95_latency" in data, "The executed Rust program omitted p95_latency."
        assert abs(float(data["p95_latency"]) - expected_p95) <= 0.05, \
            "The executed Rust program did not calculate P95 from the verifier-generated metrics."
        assert_network_configured()
        assert_structured_logrotate_config()
    finally:
        IMAGE.write_bytes(original_image)
        METRICS.write_bytes(original_metrics)

    REPORT.unlink(missing_ok=True)
    CONF.unlink(missing_ok=True)
    reset_network()
    execute_binary(binary)


def test_report_json_exists_and_valid():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"{report_path} does not exist."
    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{report_path} does not contain valid JSON.")

    assert "panic_code" in data, "report.json is missing 'panic_code'."
    assert "p95_latency" in data, "report.json is missing 'p95_latency'."


def test_panic_code_extraction():
    report_path = "/home/user/report.json"
    with open(report_path, "r") as f:
        data = json.load(f)

    assert data["panic_code"] == "0xDEADBEEF", f"Expected panic_code '0xDEADBEEF', got '{data['panic_code']}'"


def test_p95_latency_calculation():
    # Calculate true P95 from the log file
    log_path = "/app/metrics.log"
    assert os.path.isfile(log_path), f"{log_path} is missing."

    latencies = []
    with open(log_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 3 and parts[2] == "200":
                latencies.append(float(parts[1]))

    assert len(latencies) > 0, "No status 200 entries found in metrics.log."

    true_p95 = float(np.percentile(latencies, 95))

    report_path = "/home/user/report.json"
    with open(report_path, "r") as f:
        data = json.load(f)

    agent_p95 = float(data["p95_latency"])
    error = abs(agent_p95 - true_p95)

    assert error <= 1.5, f"P95 latency error {error} exceeds threshold 1.5. True P95: {true_p95}, Agent P95: {agent_p95}"


def test_network_interface_sremon():
    result = subprocess.run(["ip", "link", "show", "sre-mon"], capture_output=True, text=True)
    assert result.returncode == 0, "Interface 'sre-mon' does not exist."
    assert "UP" in result.stdout or "state UP" in result.stdout or "state UNKNOWN" in result.stdout, "Interface 'sre-mon' is not brought up."


def test_network_route():
    result = subprocess.run(["ip", "route", "show"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to execute 'ip route show'."

    route_found = False
    for line in result.stdout.splitlines():
        if "10.55.0.0/24" in line and "sre-mon" in line:
            route_found = True
            break

    assert route_found, "Static route for 10.55.0.0/24 via sre-mon is missing."


def test_logrotate_config():
    conf_path = "/home/user/sre_logrotate.conf"
    assert os.path.isfile(conf_path), f"{conf_path} does not exist."

    with open(conf_path, "r") as f:
        content = f.read()

    assert "/home/user/sre_tool.log" in content, "Logrotate config does not target /home/user/sre_tool.log"
    assert "daily" in content, "Logrotate config missing 'daily' rule."
    assert "rotate 7" in content, "Logrotate config missing 'rotate 7' rule."
    assert "compress" in content, "Logrotate config missing 'compress' rule."
    assert "missingok" in content, "Logrotate config missing 'missingok' rule."
    assert_structured_logrotate_config()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
