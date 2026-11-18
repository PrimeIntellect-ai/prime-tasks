#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

VIDEO = "/app/build_metrics.mp4"
BLACKLIST = "/home/user/blacklist.txt"
RESOLVER = "/home/user/resolve_artifacts.sh"
SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


def get_truth_blacklist():
    """Extract subtitles from the video to get the truth blacklist."""
    try:
        result = subprocess.run(
            ["ffmpeg", "-i", VIDEO, "-map", "0:1", "-f", "srt", "-"],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Failed to extract subtitles from video using ffmpeg: {exc.stderr}")

    blacklist = []
    for line in result.stdout.strip().splitlines():
        line = line.strip()
        if not line or "-->" in line or line.isdigit():
            continue
        blacklist.append(re.sub(r"<[^>]+>", "", line))
    return blacklist


def test_blacklist_extracted_correctly():
    """Test that the blacklist was correctly extracted from the video."""
    assert os.path.isfile(BLACKLIST), f"Blacklist file missing at {BLACKLIST}"
    with open(BLACKLIST, encoding="utf-8") as handle:
        user_lines = [line.strip() for line in handle if line.strip()]
    assert user_lines == get_truth_blacklist(), (
        "The extracted blacklist does not match the subtitles in the video."
    )


def parse_version(value):
    match = SEMVER_RE.fullmatch(value.strip())
    if not match:
        return None
    return tuple(int(part) for part in match.groups())


def expected_resolution(requested_range, available_versions, blacklist):
    if requested_range.startswith(("^", "~")):
        operator = requested_range[0]
        requested_text = requested_range[1:]
    else:
        operator = "="
        requested_text = requested_range

    requested = parse_version(requested_text)
    if requested is None:
        return "NONE"

    if operator == "^":
        major, minor, patch = requested
        if major != 0:
            upper = (major + 1, 0, 0)
        elif minor != 0:
            upper = (0, minor + 1, 0)
        else:
            upper = (0, 0, patch + 1)
    elif operator == "~":
        major, minor, _ = requested
        upper = (major, minor + 1, 0)
    else:
        upper = None

    matches = []
    for raw_version in available_versions:
        version_text = raw_version.strip()
        if version_text in blacklist:
            continue
        version = parse_version(version_text)
        if version is None:
            continue

        if operator == "=" and version == requested:
            matches.append((version, version_text))
        elif operator in ("^", "~") and requested <= version < upper:
            matches.append((version, version_text))

    return max(matches)[1] if matches else "NONE"


def run_case(requested_range, available_versions, blacklist):
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", delete=False) as handle:
        handle.write("\n".join(available_versions) + "\n")
        path = handle.name

    try:
        expected = expected_resolution(requested_range, available_versions, blacklist)
        try:
            result = subprocess.run(
                ["bash", RESOLVER, requested_range, path],
                capture_output=True,
                text=True,
                timeout=5,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Resolver timed out for range {requested_range}")

        assert result.returncode == 0, (
            f"Resolver exited with {result.returncode} for range {requested_range}.\n"
            f"stderr: {result.stderr}"
        )
        assert result.stdout.strip() == expected, (
            f"Mismatch for range {requested_range}.\n"
            f"Available versions: {available_versions}\n"
            f"Expected: {expected}\n"
            f"Actual stdout: {result.stdout!r}\n"
            f"Agent stderr: {result.stderr}"
        )
    finally:
        os.remove(path)


def test_resolve_artifacts_semantics():
    assert os.path.isfile(RESOLVER), f"Agent script missing at {RESOLVER}"
    assert os.access(RESOLVER, os.X_OK), f"Agent script is not executable: {RESOLVER}"

    blacklist = set(get_truth_blacklist())

    fixed_cases = [
        ("^1.2.3", ["1.2.3", "1.2.4", "1.9.9", "2.0.0", "bad"], "1.9.9"),
        ("^0.2.3", ["0.2.3", "0.2.9", "0.3.0", "1.0.0"], "0.2.9"),
        ("^0.0.3", ["0.0.2", "0.0.3", "0.0.4"], "0.0.3"),
        ("~2.3.4", ["2.3.4", "2.3.20", "2.4.0", "3.0.0"], "2.3.20"),
        ("1.2.3", ["1.2.2", "1.2.3", "1.2.5"], "1.2.3"),
        ("^1.2.0", ["1.2.3", "1.2.4", "2.0.0"], "1.2.3"),
        ("~3.1.0", ["3.1.0", "3.1.1", "3.2.0"], "3.1.1"),
    ]
    for requested, versions, expected in fixed_cases:
        assert expected_resolution(requested, versions, blacklist) == expected
        run_case(requested, versions, blacklist)

    rng = secrets.SystemRandom()
    for _ in range(500):
        major = rng.randint(0, 8)
        minor = rng.randint(0, 12)
        patch = rng.randint(0, 25)
        operator = rng.choice(["^", "~", ""])
        requested = f"{operator}{major}.{minor}.{patch}"

        versions = [
            f"{rng.randint(0, 9)}.{rng.randint(0, 14)}.{rng.randint(0, 30)}"
            for _ in range(rng.randint(20, 80))
        ]
        versions.extend([f"{major}.{minor}.{patch}", "1.2.4", "3.1.0"])

        if operator == "~":
            versions.append(f"{major}.{minor}.{patch + rng.randint(1, 20)}")
            versions.append(f"{major}.{minor + 1}.0")
        elif operator == "^":
            if major > 0:
                versions.append(f"{major}.{minor + rng.randint(1, 5)}.{rng.randint(0, 30)}")
                versions.append(f"{major + 1}.0.0")
            elif minor > 0:
                versions.append(f"0.{minor}.{patch + rng.randint(1, 20)}")
                versions.append(f"0.{minor + 1}.0")
            else:
                versions.append(f"0.0.{patch + 1}")

        if rng.random() < 0.5:
            versions.extend(["1.2", "not-a-version", "2.3.4.5"])
        rng.shuffle(versions)
        run_case(requested, versions, blacklist)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
