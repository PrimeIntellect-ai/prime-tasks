#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import difflib
import os
import random
import re
import signal
import stat
import string
import subprocess
import sys
import tarfile
import time

import pytest

TAR_PATH = "/home/user/backups/history.tar"
TRACKER_PATH = "/home/user/config_tracker.py"
SIMULATION_PATH = "/home/user/simulate_changes.sh"


def test_history_tar_exists():
    """Check that the history.tar file exists."""
    assert os.path.isfile(TAR_PATH), f"Backup archive {TAR_PATH} does not exist."


def test_history_tar_valid_and_contains_diffs():
    """Check that history.tar is a valid tar file and contains the expected diffs."""
    assert tarfile.is_tarfile(TAR_PATH), f"{TAR_PATH} is not a valid tar archive."

    with tarfile.open(TAR_PATH, "r") as tar:
        names = tar.getnames()

    network_diffs = [n for n in names if "network.ini" in n and n.endswith(".diff")]
    assert len(network_diffs) >= 2, f"Expected at least 2 diff files for network.ini, found {len(network_diffs)}: {network_diffs}"


def test_diff_contents():
    """Extract the diffs and verify their contents are correct and in UTF-8."""
    with tarfile.open(TAR_PATH, "r") as tar:
        names = tar.getnames()
        network_diffs = [n for n in names if "network.ini" in n and n.endswith(".diff")]

        # Sort to get them in chronological order based on timestamp in filename
        network_diffs.sort()

        # Read the first two diffs
        try:
            diff1 = tar.extractfile(network_diffs[0]).read().decode('utf-8')
        except UnicodeDecodeError:
            pytest.fail("First diff is not valid UTF-8.")

        try:
            diff2 = tar.extractfile(network_diffs[1]).read().decode('utf-8')
        except UnicodeDecodeError:
            pytest.fail("Second diff is not valid UTF-8.")

    # Verify first diff (creation)
    assert "+server=192.168.1.1" in diff1, "First diff is missing the addition of 'server=192.168.1.1'."
    assert "+port=8080" in diff1, "First diff is missing the addition of 'port=8080'."

    # Verify second diff (modification)
    assert "+enable_ssl=true" in diff2, "Second diff is missing the addition of 'enable_ssl=true'."
    assert "server=192.168.1.1" in diff2, "Second diff is missing the context line 'server=192.168.1.1'."
    assert "port=8080" in diff2, "Second diff is missing the context line 'port=8080'."


def _resolved_calls(tree):
    aliases = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                aliases[item.asname or item.name.split('.')[0]] = item.name
        elif isinstance(node, ast.ImportFrom) and node.module:
            for item in node.names:
                aliases[item.asname or item.name] = node.module + "." + item.name

    def resolve(node):
        if isinstance(node, ast.Name):
            return aliases.get(node.id, node.id)
        if isinstance(node, ast.Attribute):
            return resolve(node.value) + "." + node.attr
        return ""

    return [resolve(node.func) for node in ast.walk(tree) if isinstance(node, ast.Call)]


def test_required_artifacts_and_apis_exist():
    assert os.path.isfile(TRACKER_PATH), f"Missing tracker script {TRACKER_PATH}"
    with open(TRACKER_PATH, "r", encoding="utf-8") as fh:
        source = fh.read()
    tree = ast.parse(source, filename=TRACKER_PATH)
    calls = _resolved_calls(tree)

    assert any(name == "mmap.mmap" for name in calls), "Tracker does not call mmap.mmap"
    assert any(name == "difflib.unified_diff" for name in calls), "Tracker does not call difflib.unified_diff"
    assert any(name.startswith("watchdog.") and name.endswith("Observer") for name in calls), \
        "Tracker does not create a watchdog Observer"

    assert os.path.isfile(SIMULATION_PATH), f"Missing simulation script {SIMULATION_PATH}"
    mode = os.stat(SIMULATION_PATH).st_mode
    assert mode & stat.S_IXUSR, f"{SIMULATION_PATH} is not executable"
    with open(SIMULATION_PATH, "r", encoding="utf-8") as fh:
        simulation = fh.read()
    assert "network.ini" in simulation
    assert "iconv -f UTF-8 -t ISO-8859-1" in simulation
    assert "enable_ssl=true" in simulation


def _tar_entries(path):
    if not os.path.isfile(path):
        return []
    try:
        with tarfile.open(path, "r") as archive:
            result = []
            for member in archive.getmembers():
                if not member.isfile():
                    continue
                extracted = archive.extractfile(member)
                if extracted is not None:
                    result.append((member.name, extracted.read()))
            return result
    except (tarfile.TarError, OSError, EOFError):
        return []


def _wait_for_entry(path, expected, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        for name, data in _tar_entries(path):
            if data == expected:
                return name
        time.sleep(0.15)
    observed = [(name, data[:200]) for name, data in _tar_entries(path)]
    pytest.fail(f"Timed out waiting for expected generated diff. Entries: {observed}")


def test_tracker_executes_on_fresh_unpredictable_inputs(tmp_path):
    watch_dir = tmp_path / "watched"
    backup_dir = tmp_path / "backups"
    hook_dir = tmp_path / "hook"
    watch_dir.mkdir()
    backup_dir.mkdir()
    hook_dir.mkdir()
    archive_path = backup_dir / "dynamic-history.tar"
    mmap_log = tmp_path / "mmap.log"

    # Instrument mmap in the submitted process and record the path corresponding
    # to the mapped descriptor. This confirms mmap is actually used on the INI.
    (hook_dir / "sitecustomize.py").write_text(
        "import mmap as _mmap, os as _os\n"
        "_real_mmap = _mmap.mmap\n"
        "def _tracked_mmap(*args, **kwargs):\n"
        "    try:\n"
        "        p = _os.readlink('/proc/%d/fd/%d' % (_os.getpid(), args[0]))\n"
        "        with open(_os.environ['TRACKER_MMAP_LOG'], 'a') as f: f.write(p + '\\n')\n"
        "    except Exception:\n"
        "        pass\n"
        "    return _real_mmap(*args, **kwargs)\n"
        "_mmap.mmap = _tracked_mmap\n",
        encoding="utf-8",
    )

    env = os.environ.copy()
    env["PYTHONPATH"] = str(hook_dir) + os.pathsep + env.get("PYTHONPATH", "")
    env["TRACKER_MMAP_LOG"] = str(mmap_log)
    proc = subprocess.Popen(
        [sys.executable, TRACKER_PATH, str(watch_dir), str(archive_path)],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )

    try:
        time.sleep(1.5)
        assert proc.poll() is None, f"Tracker exited during startup: {proc.stderr.read()}"

        # A non-INI event must not be archived.
        (watch_dir / "ignored.txt").write_text("not a configuration file\n", encoding="utf-8")
        time.sleep(0.6)
        assert not any("ignored.txt" in name for name, _ in _tar_entries(archive_path))

        token = ''.join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(18))
        extra = ''.join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(12))
        filename = f"probe_{token[:8]}.ini"
        ini_path = watch_dir / filename
        old_text = f"clé={token}\nmode=ancien\n"
        new_text = f"clé={token}\nmode=nouveau\najout={extra}\n"

        ini_path.write_bytes(old_text.encode("iso-8859-1"))
        expected_creation = ''.join(difflib.unified_diff(
            [], old_text.splitlines(keepends=True), fromfile=filename, tofile=filename
        )).encode("utf-8")
        first_name = _wait_for_entry(archive_path, expected_creation)
        assert re.fullmatch(re.escape(filename) + r"_[0-9]+\.diff", first_name), first_name

        # Keep the two required timestamps distinct, as in the supplied simulation.
        time.sleep(2.1)
        ini_path.write_bytes(new_text.encode("iso-8859-1"))
        expected_modification = ''.join(difflib.unified_diff(
            old_text.splitlines(keepends=True),
            new_text.splitlines(keepends=True),
            fromfile=filename,
            tofile=filename,
        )).encode("utf-8")
        second_name = _wait_for_entry(archive_path, expected_modification)
        assert re.fullmatch(re.escape(filename) + r"_[0-9]+\.diff", second_name), second_name
        assert first_name != second_name

        assert mmap_log.is_file(), "No mmap use was recorded"
        mapped_paths = mmap_log.read_text(encoding="utf-8").splitlines()
        assert str(ini_path) in mapped_paths, f"The changed INI was not read with mmap: {mapped_paths}"
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
