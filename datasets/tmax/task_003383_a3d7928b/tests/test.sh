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
import os
import re
import secrets
import subprocess
from pathlib import Path

import requests
import pytest
import numpy as np
from scipy import stats


def parse_b_factors(filepath):
    b_factors = []
    with open(filepath, 'r') as f:
        for line in f:
            if line.startswith("ATOM"):
                atom_name = line[12:16].strip()
                if atom_name == "CA":
                    b_factor = float(line[60:66].strip())
                    b_factors.append(b_factor)
    return np.array(b_factors)


def listening_pid():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            port = int(local_address.rsplit(":", 1)[1], 16)
            if port == 8080 and state == "0A":
                socket_inodes.add(fields[9])

    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    return int(proc.name)
        except (OSError, PermissionError):
            continue
    raise AssertionError("Could not identify the process listening on port 8080")


def server_source(pid):
    proc = Path(f"/proc/{pid}")
    cmdline = (proc / "cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "ignore")
    cwd = Path(os.readlink(proc / "cwd"))
    chunks = [cmdline]

    raw_args = (proc / "cmdline").read_bytes().split(b"\0")
    for raw in raw_args:
        if not raw:
            continue
        arg = raw.decode("utf-8", "ignore")
        candidate = Path(arg)
        if not candidate.is_absolute():
            candidate = cwd / candidate
        if candidate.is_file() and candidate.suffix == ".py":
            try:
                chunks.append(candidate.read_text(errors="ignore"))
            except OSError:
                pass

    # Also cover servers launched with `python -m module` or a relative launcher.
    if cwd.is_dir():
        try:
            for candidate in cwd.rglob("*.py"):
                text_path = str(candidate)
                if any(part in text_path for part in ("/venv/", "/site-packages/", "/vendored_bio_struct_parser/", "/__pycache__/")):
                    continue
                try:
                    chunks.append(candidate.read_text(errors="ignore"))
                except OSError:
                    pass
        except OSError:
            pass
    return "\n".join(chunks)


@pytest.fixture(scope="module", autouse=True)
def verify_package_setup_and_usage():
    makefile = Path("/app/vendored_bio_struct_parser/Makefile")
    assert makefile.is_file(), "Vendored package Makefile is missing"
    make_text = makefile.read_text()
    assert re.search(r"(?m)^install\s*:", make_text), "Makefile has no install target"
    assert "insatll" not in make_text, "The deliberate Makefile typo was not fixed"
    assert re.search(r"/app/venv/bin/pip\s+install(?:\s|$)", make_text), \
        "The install target must install with /app/venv/bin/pip"

    install = subprocess.run(
        ["make", "-C", "/app/vendored_bio_struct_parser", "install"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert install.returncode == 0, f"The repaired Makefile install target failed:\n{install.stdout}"

    probe = subprocess.run(
        ["/app/venv/bin/python", "-c",
         "import json, bio_struct_parser; "
         "a=bio_struct_parser.parse_pdb('/app/data/proteinA.pdb'); "
         "print(json.dumps({'file': bio_struct_parser.__file__, 'count': len(a), "
         "'ca': sum(x['atom_name']=='CA' for x in a)}))"],
        cwd="/tmp", stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert probe.returncode == 0, f"bio_struct_parser is not installed in /app/venv: {probe.stderr}"
    package_info = json.loads(probe.stdout.strip().splitlines()[-1])
    assert "site-packages" in package_info["file"], \
        f"bio_struct_parser did not import from the virtualenv installation: {package_info['file']}"
    assert package_info["count"] == 400 and package_info["ca"] == 200, \
        "The installed bio_struct_parser does not correctly parse the supplied PDB"

    source = server_source(listening_pid())
    assert re.search(r"(?:from\s+bio_struct_parser\s+import|import\s+bio_struct_parser)", source), \
        "The running server does not import bio_struct_parser"
    assert "parse_pdb" in source, "The running server does not use bio_struct_parser.parse_pdb"


@pytest.fixture(scope="module")
def truth_data():
    b_factors_A = parse_b_factors("/app/data/proteinA.pdb")
    b_factors_B = parse_b_factors("/app/data/proteinB.pdb")

    ks_stat, ks_pvalue = stats.ks_2samp(b_factors_A, b_factors_B)

    kde_A = stats.gaussian_kde(b_factors_A)
    kde_B = stats.gaussian_kde(b_factors_B)

    density_A_25 = kde_A.evaluate(25.0)[0]
    density_B_30 = kde_B.evaluate(30.0)[0]

    return {
        "ks_stat": ks_stat,
        "ks_pvalue": ks_pvalue,
        "density_A_25": density_A_25,
        "density_B_30": density_B_30,
        "kde_A": kde_A,
        "kde_B": kde_B,
    }


def test_ks_test_endpoint(truth_data):
    url = "http://127.0.0.1:8080/ks_test"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    data = response.json()
    assert "stat" in data, f"Missing 'stat' in response: {data}"
    assert "pvalue" in data, f"Missing 'pvalue' in response: {data}"

    assert data["stat"] == pytest.approx(truth_data["ks_stat"], rel=1e-3), f"Expected stat ~ {truth_data['ks_stat']}, got {data['stat']}"
    assert data["pvalue"] == pytest.approx(truth_data["ks_pvalue"], rel=1e-3), f"Expected pvalue ~ {truth_data['ks_pvalue']}, got {data['pvalue']}"


def test_density_proteinA_endpoint(truth_data):
    url = "http://127.0.0.1:8080/density/proteinA/25.0"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    data = response.json()
    assert "density" in data, f"Missing 'density' in response: {data}"

    assert data["density"] == pytest.approx(truth_data["density_A_25"], rel=1e-3), f"Expected density ~ {truth_data['density_A_25']}, got {data['density']}"


def test_density_proteinB_endpoint(truth_data):
    url = "http://127.0.0.1:8080/density/proteinB/30.0"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    data = response.json()
    assert "density" in data, f"Missing 'density' in response: {data}"

    assert data["density"] == pytest.approx(truth_data["density_B_30"], rel=1e-3), f"Expected density ~ {truth_data['density_B_30']}, got {data['density']}"


@pytest.mark.parametrize("protein,key", [("proteinA", "kde_A"), ("proteinB", "kde_B")])
def test_density_at_unpredictable_b_factors(truth_data, protein, key):
    # Values are selected only after the agent's server is running, preventing a
    # fixed table of the three originally tested answers from passing.
    values = [8.0 + secrets.randbelow(3_400_001) / 100_000.0 for _ in range(7)]
    for value in values:
        url = f"http://127.0.0.1:8080/density/{protein}/{value:.5f}"
        try:
            response = requests.get(url, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to {url}: {e}")
        assert response.status_code == 200, \
            f"Expected status code 200 for {url}, got {response.status_code}. Response: {response.text}"
        data = response.json()
        assert "density" in data, f"Missing 'density' in response from {url}: {data}"
        expected = truth_data[key].evaluate(value)[0]
        assert data["density"] == pytest.approx(expected, rel=1e-3, abs=1e-10), \
            f"Expected density ~ {expected} for {protein} at {value}, got {data['density']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
