#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess
import time
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:8080/metrics"


def get_metrics():
    response = None
    max_retries = 5
    for i in range(max_retries):
        try:
            response = requests.get(URL, timeout=5)
            if response.status_code == 200:
                break
        except requests.exceptions.RequestException:
            if i == max_retries - 1:
                pytest.fail(f"Failed to connect to the server at {URL}. Is it running?")
            time.sleep(1)

    assert response is not None
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    required_keys = {"wasserstein", "ci_lower", "ci_upper"}
    missing_keys = required_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in JSON response: {missing_keys}"

    values = tuple(float(data[k]) for k in ("wasserstein", "ci_lower", "ci_upper"))
    assert all(math.isfinite(v) for v in values), "Metrics must be finite numbers"
    return values


def test_metrics_endpoint():
    wasserstein, ci_lower, ci_upper = get_metrics()

    # Preserve the original statistical assertions.
    assert 0.45 <= wasserstein <= 0.55, f"Wasserstein distance {wasserstein} is out of expected range [0.45, 0.55]"
    assert 0.40 <= ci_lower <= 0.50, f"CI lower bound {ci_lower} is out of expected range [0.40, 0.50]"
    assert 0.50 <= ci_upper <= 0.60, f"CI upper bound {ci_upper} is out of expected range [0.50, 0.60]"
    assert ci_lower < wasserstein < ci_upper, f"Expected ci_lower < wasserstein < ci_upper, but got {ci_lower} < {wasserstein} < {ci_upper}"

    # Derive the expected center from the supplied image rather than trusting
    # constants reported by the service.
    ocr = subprocess.check_output(
        ["tesseract", "/app/params.png", "stdout"], text=True, stderr=subprocess.DEVNULL
    )
    match = re.search(r"mu\s*=\s*([-+]?\d+(?:\.\d+)?)\s+sigma\s*=\s*([-+]?\d+(?:\.\d+)?)", ocr, re.I)
    assert match, f"Could not extract mu and sigma from params.png; OCR output was {ocr!r}"
    target_mu, target_sigma = map(float, match.groups())
    assert target_sigma > 0
    expected_wasserstein = abs(target_mu - 4.5)  # Equal-sigma Normal distributions.
    assert abs(wasserstein - expected_wasserstein) <= 0.05


def local_files(suffix=None):
    roots = [Path("/app"), Path("/home/user"), Path("/root")]
    result = []
    for root in roots:
        if not root.exists():
            continue
        for base, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".git", "__pycache__", ".cache", "node_modules"}]
            for name in files:
                p = Path(base) / name
                if suffix is None or p.suffix.lower() in suffix:
                    result.append(p)
    return result


def listener_executable():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local, state = fields[1], fields[3]
            if local.rsplit(":", 1)[-1].upper() == "1F90" and state == "0A":
                inodes.add(fields[9])
    for proc in Path("/proc").glob("[0-9]*"):
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                m = re.fullmatch(r"socket:\[(\d+)\]", target)
                if m and m.group(1) in inodes:
                    try:
                        return Path(os.readlink(proc / "exe")).resolve()
                    except OSError:
                        pass
        except OSError:
            pass
    return None


def is_elf(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def output_matches_metrics(text, metrics):
    # Prefer structured/labeled output, but also support a simple whitespace
    # protocol used by Python wrappers around a C++ computation binary.
    try:
        obj = json.loads(text.strip().splitlines()[-1])
        got = [float(obj[k]) for k in ("wasserstein", "ci_lower", "ci_upper")]
        return all(abs(a - b) <= 0.05 for a, b in zip(got, metrics))
    except Exception:
        pass
    nums = [float(x) for x in re.findall(r"(?<![A-Za-z_])[-+]?(?:\d+\.\d+|\d+)(?:[eE][-+]?\d+)?", text)]
    return all(any(abs(value - n) <= 0.05 for n in nums) for value in metrics)


def test_cpp_computation_artifact_exists_and_is_exercised():
    metrics = get_metrics()
    sources = local_files({".cc", ".cpp", ".cxx"})
    assert sources, "No C++ source file was left for the required statistical computation"

    combined = "\n".join(p.read_text(errors="ignore") for p in sources)
    compact = re.sub(r"\s+", "", combined)
    assert "10000" in compact, "C++ source does not implement the required 10,000-sample computation"
    assert "1000" in compact, "C++ source does not implement the required 1,000 bootstrap iterations"
    assert re.search(r"(?:std::)?sort\s*\(", combined), "C++ source does not sort empirical samples"
    assert ("normal_distribution" in combined or
            all(token in combined for token in ("sqrt", "log", "cos"))), \
        "C++ source does not implement Normal sampling"
    assert ("uniform_int_distribution" in combined or
            re.search(r"(?:rng|gen|engine)\s*\(\s*\)\s*%", combined)), \
        "C++ source does not implement bootstrap resampling with replacement"

    # Ensure the submitted C++ is genuine compilable code rather than comments
    # placed beside a constant-only HTTP service.
    include_dirs = sorted({str(p.parent) for p in sources})
    command = ["g++", "-std=c++17", "-fsyntax-only"]
    command += [arg for directory in include_dirs for arg in ("-I", directory)]
    command += [str(p) for p in sources]
    compiled = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    assert compiled.returncode == 0, f"Submitted C++ source does not compile:\n{compiled.stdout}"

    executables = [p for p in local_files() if is_elf(p)]
    serving_exe = listener_executable()
    direct_cpp_server = serving_exe is not None and any(
        serving_exe == p.resolve() for p in executables
    )

    # For a Python wrapper, execute the submitted computation binary and verify
    # that its calculated values agree with those exposed by HTTP. For an
    # all-C++ server, the ELF currently owning the listening socket is already
    # the executed artifact.
    matched_binary = direct_cpp_server
    if not matched_binary:
        for exe in sorted(executables, key=lambda p: p.stat().st_mtime, reverse=True)[:30]:
            try:
                run = subprocess.run(
                    [str(exe)], cwd=str(exe.parent), text=True,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45
                )
            except (OSError, subprocess.TimeoutExpired):
                continue
            if run.returncode == 0 and output_matches_metrics(run.stdout, metrics):
                matched_binary = True
                break

    assert matched_binary, (
        "No submitted C++ executable was actually exercised as the server or "
        "produced the reported Wasserstein and bootstrap-CI metrics"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
