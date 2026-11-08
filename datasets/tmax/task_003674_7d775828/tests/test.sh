#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import signal
import subprocess
import time
import urllib.error
import urllib.request

import pytest


def parse_semver(version_str):
    """Helper to parse semantic version string into a tuple of integers."""
    return tuple(int(part) for part in version_str.split('.'))


def test_updates_json_correct():
    current_path = "/home/user/api-version-resolver/current.json"
    wanted_path = "/home/user/api-version-resolver/wanted.json"
    updates_path = "/home/user/updates.json"

    assert os.path.exists(current_path), f"File {current_path} is missing."
    assert os.path.exists(wanted_path), f"File {wanted_path} is missing."
    assert os.path.exists(updates_path), f"File {updates_path} is missing. Did you save the curl output?"

    with open(current_path, "r") as f:
        current_data = json.load(f)

    with open(wanted_path, "r") as f:
        wanted_data = json.load(f)

    # Dynamically compute expected updates based on SemVer rules
    expected_updates = []
    for pkg, curr_ver in current_data.items():
        if pkg in wanted_data:
            want_ver = wanted_data[pkg]
            if parse_semver(want_ver) > parse_semver(curr_ver):
                expected_updates.append({
                    "package": pkg,
                    "from": curr_ver,
                    "to": want_ver
                })

    # The output MUST be sorted alphabetically by package name
    expected_updates.sort(key=lambda x: x["package"])

    with open(updates_path, "r") as f:
        try:
            actual_updates = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {updates_path} does not contain valid JSON.")

    assert isinstance(actual_updates, list), f"The JSON in {updates_path} must be an array."
    assert actual_updates == expected_updates, (
        f"The contents of {updates_path} do not match the expected updates. "
        f"Expected: {expected_updates}, Actual: {actual_updates}"
    )


def stop_existing_port_8080():
    """Stop a server left on the required port so the submitted binary is exercised."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for fd in glob.glob("/proc/[0-9]*/fd/*"):
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        if target.startswith("socket:[") and target[8:-1] in inodes:
            victims.add(int(fd.split("/")[2]))

    for pid in victims:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    if victims:
        time.sleep(0.4)


def expected_updates(current, wanted):
    result = []
    for package, current_version in current.items():
        wanted_version = wanted.get(package)
        if wanted_version is not None and parse_semver(wanted_version) > parse_semver(current_version):
            result.append({"package": package, "from": current_version, "to": wanted_version})
    return sorted(result, key=lambda item: item["package"])


def fetch_updates(process):
    last_error = None
    for _ in range(50):
        assert process.poll() is None, "The compiled Go server exited before serving /updates."
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/updates", timeout=1) as response:
                assert response.status == 200
                assert response.headers.get_content_type() == "application/json"
                return json.loads(response.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail(f"The compiled server did not become available on port 8080: {last_error}")


def test_main_go_compiles_and_serves_dynamic_inputs():
    project = "/home/user/api-version-resolver"
    source = os.path.join(project, "main.go")
    current_path = os.path.join(project, "current.json")
    wanted_path = os.path.join(project, "wanted.json")
    binary = "/tmp/api-version-resolver-submission"

    assert os.path.isfile(source), f"File {source} is missing."

    build = subprocess.run(
        ["go", "build", "-o", binary, source],
        cwd=project,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert build.returncode == 0, f"main.go does not compile:\n{build.stdout}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK)

    with open(current_path, "rb") as f:
        original_current = f.read()
    with open(wanted_path, "rb") as f:
        original_wanted = f.read()

    suffix = "%08x" % random.SystemRandom().getrandbits(32)
    current = {
        f"zeta-{suffix}": "1.2.0",
        f"alpha-{suffix}": "0.9.9",
        f"beta-{suffix}": "2.10.1",
        f"equal-{suffix}": "4.5.6",
        f"current-only-{suffix}": "0.0.1",
    }
    wanted = {
        f"zeta-{suffix}": "1.10.0",
        f"alpha-{suffix}": "1.0.0",
        f"beta-{suffix}": "2.9.9",
        f"equal-{suffix}": "4.5.6",
        f"wanted-only-{suffix}": "9.0.0",
    }

    process = None
    try:
        with open(current_path, "w") as f:
            json.dump(current, f)
        with open(wanted_path, "w") as f:
            json.dump(wanted, f)

        stop_existing_port_8080()
        process = subprocess.Popen(
            [binary],
            cwd=project,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        actual = fetch_updates(process)
        assert isinstance(actual, list), "The /updates response must be a JSON array."
        assert actual == expected_updates(current, wanted)

        # Exercise another request with changed files, including the required empty-array case.
        current2 = {f"numeric-{suffix}": "10.0.0", f"same-{suffix}": "1.1.1"}
        wanted2 = {f"numeric-{suffix}": "9.99.99", f"same-{suffix}": "1.1.1"}
        with open(current_path, "w") as f:
            json.dump(current2, f)
        with open(wanted_path, "w") as f:
            json.dump(wanted2, f)

        actual2 = fetch_updates(process)
        assert isinstance(actual2, list), "An empty update result must be encoded as [], not null."
        assert actual2 == expected_updates(current2, wanted2)
    finally:
        with open(current_path, "wb") as f:
            f.write(original_current)
        with open(wanted_path, "wb") as f:
            f.write(original_wanted)
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
