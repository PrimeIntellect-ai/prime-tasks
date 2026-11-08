#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import importlib.metadata
import os
import random
import struct
import subprocess
import tempfile
import uuid
from decimal import Decimal, localcontext

import pytest
from packaging.requirements import Requirement

SAFEGUARD_SCRIPT = "/home/user/safeguard.py"
REQUIREMENTS_FILE = "/home/user/requirements.txt"
EVIL_CORPUS_DIR = "/app/test_data/evil"
CLEAN_CORPUS_DIR = "/app/test_data/clean"


def run_safeguard(path):
    return subprocess.run(
        ["python3", SAFEGUARD_SCRIPT, path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_safeguard_script_exists():
    assert os.path.isfile(SAFEGUARD_SCRIPT), f"Missing safeguard script at {SAFEGUARD_SCRIPT}"


def test_requirements_are_fixed_and_installed():
    assert os.path.isfile(REQUIREMENTS_FILE), f"Missing requirements file at {REQUIREMENTS_FILE}"

    requirements = []
    with open(REQUIREMENTS_FILE, encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            assert not line.startswith("-"), f"Unsupported or unresolved requirements directive: {line}"
            requirements.append(Requirement(line))

    active = [req for req in requirements if req.marker is None or req.marker.evaluate()]
    names = {req.name.lower().replace("_", "-") for req in active}
    assert {"numpy", "scipy", "pandas"}.issubset(names), \
        "requirements.txt must retain numpy, scipy, and pandas"

    for req in active:
        try:
            installed_version = importlib.metadata.version(req.name)
        except importlib.metadata.PackageNotFoundError:
            pytest.fail(f"Required package is not installed: {req.name}")
        assert not req.url, f"Requirement must resolve to an installed package version: {req}"
        assert not req.specifier or req.specifier.contains(installed_version, prereleases=True), \
            f"Installed {req.name} {installed_version} does not satisfy {req.specifier}"

    for module_name in ("numpy", "scipy", "pandas"):
        importlib.import_module(module_name)


def test_adversarial_corpus_evaluation():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Missing evil corpus directory at {EVIL_CORPUS_DIR}"
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Missing clean corpus directory at {CLEAN_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    assert len(evil_files) > 0, "Evil corpus is empty"
    assert len(clean_files) > 0, "Clean corpus is empty"

    evil_bypassed = []
    for evil_file in evil_files:
        result = run_safeguard(evil_file)
        output = result.stdout.strip()
        if output != "REJECT":
            evil_bypassed.append((os.path.basename(evil_file), output))

    clean_rejected = []
    for clean_file in clean_files:
        result = run_safeguard(clean_file)
        output = result.stdout.strip()
        if output != "ACCEPT":
            clean_rejected.append((os.path.basename(clean_file), output))

    error_messages = []
    if evil_bypassed:
        basenames = [f[0] for f in evil_bypassed]
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(basenames)}")

    if clean_rejected:
        basenames = [f[0] for f in clean_rejected]
        error_messages.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified (rejected): {', '.join(basenames)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def f32(value):
    return struct.unpack("=f", struct.pack("=f", value))[0]


def legacy_variance(lines):
    values = [f32(float(line)) for line in lines]
    total = f32(0.0)
    total_sq = f32(0.0)
    for value in values:
        total = f32(total + value)
        total_sq = f32(total_sq + f32(value * value))
    n_as_float = f32(float(len(values)))
    correction = f32(f32(total * total) / n_as_float)
    return f32(f32(total_sq - correction) / n_as_float)


def accurate_variance(lines):
    with localcontext() as context:
        context.prec = 60
        values = [Decimal(line) for line in lines]
        count = Decimal(len(values))
        mean = sum(values, Decimal(0)) / count
        return sum((value - mean) ** 2 for value in values) / count


def loses_extreme_precision(lines):
    observed = Decimal.from_float(legacy_variance(lines))
    expected = accurate_variance(lines)
    error = abs(observed - expected)
    return error > max(Decimal("0.1"), abs(expected) * Decimal(100))


def make_candidate(rng, cancellation_prone):
    count = rng.randint(80, 140)
    if cancellation_prone:
        magnitude = Decimal(str(rng.choice((100000, 1000000, 10000000, 100000000))))
        if rng.choice((False, True)):
            magnitude = -magnitude
        jitter = Decimal(str(rng.choice(("0.000001", "0.00001", "0.0001", "0.001"))))
        return [format(magnitude + Decimal(rng.randint(-10, 10)) * jitter, "f") for _ in range(count)]

    center = Decimal(str(rng.uniform(-100.0, 100.0)))
    spread = Decimal(str(rng.uniform(2.0, 25.0)))
    return [format(center + Decimal(str(rng.uniform(-1.0, 1.0))) * spread, ".12f") for _ in range(count)]


def test_generated_holdout_uses_content_not_directory_names():
    rng = random.SystemRandom()
    cases = []
    wanted = {"ACCEPT": 16, "REJECT": 16}

    for _ in range(1000):
        candidate = make_candidate(rng, rng.choice((False, True)))
        expected = "REJECT" if loses_extreme_precision(candidate) else "ACCEPT"
        if wanted[expected] > 0:
            cases.append((candidate, expected))
            wanted[expected] -= 1
        if not any(wanted.values()):
            break

    assert not any(wanted.values()), f"Could not construct balanced derived holdout cases: {wanted}"
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="payloads_") as directory:
        failures = []
        for lines, expected in cases:
            path = os.path.join(directory, uuid.uuid4().hex)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("\n".join(lines) + "\n")

            result = run_safeguard(path)
            actual = result.stdout.strip()
            if result.returncode != 0 or actual != expected:
                failures.append((os.path.basename(path), expected, actual, result.returncode))

        assert not failures, f"Safeguard failed generated content-derived holdout cases: {failures}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
