#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

HOME = "/home/user"
PDB = os.path.join(HOME, "protein.pdb")
STATS = os.path.join(HOME, "posterior_stats.txt")


def parse_stats():
    assert os.path.isfile(STATS), f"File missing: {STATS}"
    with open(STATS, "r") as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 2, f"Expected exactly 2 lines in {STATS}, found {len(lines)}"
    mu_match = re.match(r"^mu:\s*([0-9.]+)$", lines[0])
    sigma_match = re.match(r"^sigma:\s*([0-9.]+)$", lines[1])
    assert mu_match, "First line must be formatted as 'mu: <value>'"
    assert sigma_match, "Second line must be formatted as 'sigma: <value>'"
    assert len(mu_match.group(1).split('.')[-1]) == 1, "mu value must be rounded to exactly one decimal place"
    assert len(sigma_match.group(1).split('.')[-1]) == 1, "sigma value must be rounded to exactly one decimal place"
    return float(mu_match.group(1)), float(sigma_match.group(1))


def command_for(path, text):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".py":
        return ["python3", path]
    if ext == ".pl":
        return ["perl", path]
    if ext == ".awk":
        return ["awk", "-f", path]
    if ext in (".sh", ".bash"):
        return ["bash", path]
    first = text.splitlines()[0] if text.splitlines() else ""
    if first.startswith("#!"):
        if "python" in first:
            return ["python3", path]
        if "perl" in first:
            return ["perl", path]
        if "awk" in first:
            return ["awk", "-f", path]
        if "sh" in first or "bash" in first:
            return ["bash", path]
    if os.access(path, os.X_OK):
        return [path]
    return None


def has_mcmc_parameters(text):
    normalized = text.replace("_", "").lower()
    if "20000" not in normalized or "5000" not in normalized:
        return False
    numbers = []
    for token in re.findall(r"(?<![A-Za-z_])(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", normalized):
        try:
            numbers.append(float(token))
        except ValueError:
            pass
    required = (100.0, 30.0, 0.1)
    if not all(any(abs(x - wanted) < 1e-12 for x in numbers) for wanted in required):
        return False
    return ("mu" in normalized and "sigma" in normalized and
            re.search(r"\b(for|while|until|range)\b", normalized) is not None and
            re.search(r"random|rand\s*\(|urandom|secrets", normalized) is not None and
            re.search(r"\b(log|exp)\b", normalized) is not None and
            re.search(r"likelihood|posterior|logp|log_prob", normalized) is not None)


def candidates():
    found = []
    excluded = {os.path.realpath(PDB), os.path.realpath(STATS)}
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {".cache", "__pycache__"}]
        for name in files:
            path = os.path.join(root, name)
            if os.path.realpath(path) in excluded:
                continue
            try:
                if os.path.getsize(path) > 1000000:
                    continue
                with open(path, "r", errors="ignore") as f:
                    text = f.read()
            except OSError:
                continue
            cmd = command_for(path, text)
            if cmd and has_mcmc_parameters(text):
                found.append((path, cmd))
    return found


def write_synthetic_pdb():
    values = [20.0, 22.0, 24.0]
    with open(PDB, "w") as f:
        serial = 1
        for residue, value in enumerate(values, 1):
            f.write(f"ATOM  {serial:5d}  CA  ALA A{residue:4d}    {0.0:8.3f}{0.0:8.3f}{0.0:8.3f}  1.00{value:6.2f}           C  \n")
            serial += 1
            f.write(f"ATOM  {serial:5d}  CB  ALA A{residue:4d}    {1.0:8.3f}{1.0:8.3f}{1.0:8.3f}  1.00{90.0:6.2f}           C  \n")
            serial += 1


def expected_synthetic_sigma():
    # Numerically integrate the requested posterior after analytically
    # integrating mu over its uniform [0,100] prior.
    data = [20.0, 22.0, 24.0]
    n = len(data)
    mean = sum(data) / n
    sse = sum((x - mean) ** 2 for x in data)
    steps = 20000
    width = (30.0 - 0.1) / steps
    total = 0.0
    sigma_total = 0.0
    for i in range(steps):
        sigma = 0.1 + (i + 0.5) * width
        scale = math.sqrt(n) / (math.sqrt(2.0) * sigma)
        mu_integral = (math.sqrt(math.pi / 2.0) * sigma / math.sqrt(n) *
                       (math.erf((100.0 - mean) * scale) - math.erf((0.0 - mean) * scale)))
        weight = sigma ** (-n) * math.exp(-sse / (2.0 * sigma * sigma)) * mu_integral
        total += weight
        sigma_total += sigma * weight
    return sigma_total / total


def run(cmd):
    if os.path.exists(STATS):
        os.remove(STATS)
    subprocess.run(cmd, cwd=HOME, timeout=60, check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return parse_stats()


def test_mcmc_artifact_and_posterior_stats_file():
    assert os.path.isfile(PDB), f"File missing: {PDB}"
    with open(PDB, "rb") as f:
        original_pdb = f.read()

    usable = None
    errors = []
    try:
        for path, cmd in candidates():
            try:
                write_synthetic_pdb()
                mu_val, sigma_val = run(cmd)
                expected_sigma = expected_synthetic_sigma()
                assert abs(mu_val - 22.0) <= 1.0, "synthetic posterior mu is incorrect"
                assert abs(sigma_val - expected_sigma) <= 1.5, "synthetic posterior sigma is inconsistent with the requested posterior"
                usable = (path, cmd)
                break
            except Exception as exc:
                errors.append(f"{path}: {exc}")
    finally:
        with open(PDB, "wb") as f:
            f.write(original_pdb)

    assert usable is not None, "No executable custom Metropolis-Hastings script passed verification. " + "; ".join(errors)

    # Execute the submitted artifact on the real input; do not trust a
    # pre-created posterior_stats.txt.
    mu_val, sigma_val = run(usable[1])

    with open(STATS, "r") as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 2, f"Expected exactly 2 lines in {STATS}, found {len(lines)}"
    mu_match = re.match(r"^mu:\s*([0-9.]+)$", lines[0])
    sigma_match = re.match(r"^sigma:\s*([0-9.]+)$", lines[1])
    assert mu_match, "First line must be formatted as 'mu: <value>'"
    assert sigma_match, "Second line must be formatted as 'sigma: <value>'"

    ca_b_factors = []
    with open(PDB, "r") as f:
        for line in f:
            if line.startswith("ATOM"):
                atom_name = line[12:16]
                if atom_name == " CA ":
                    b_factor = float(line[60:66].strip())
                    ca_b_factors.append(b_factor)
    assert len(ca_b_factors) > 0, "No CA atoms found in the PDB file."

    n = len(ca_b_factors)
    sample_mean = sum(ca_b_factors) / n
    variance = sum((x - sample_mean) ** 2 for x in ca_b_factors) / n
    sample_sigma = math.sqrt(variance)
    assert abs(mu_val - sample_mean) <= 0.3, f"Estimated mu ({mu_val}) is not within 0.3 of the sample mean ({sample_mean:.2f})"
    assert abs(sigma_val - sample_sigma) <= 0.3, f"Estimated sigma ({sigma_val}) is not within 0.3 of the sample standard deviation ({sample_sigma:.2f})"
    assert len(mu_match.group(1).split('.')[-1]) == 1, "mu value must be rounded to exactly one decimal place"
    assert len(sigma_match.group(1).split('.')[-1]) == 1, "sigma value must be rounded to exactly one decimal place"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
