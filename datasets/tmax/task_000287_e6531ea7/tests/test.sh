#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import shutil
import stat
import subprocess
import tarfile
import uuid
import zipfile

EXTRACTED = "/home/user/extracted"
ORGANIZED = "/home/user/organized"


def test_nested_extraction_and_archive_removal():
    assert os.path.isdir(EXTRACTED), f"Directory {EXTRACTED} does not exist."

    expected_files = [
        "not_elf_program",
        "part1.gcode",
        "part2_noext",
        "readme.txt",
        "changelog.md",
        "system_part_aa.log",
        "system_part_ab.log",
        "system_part_ac.log",
    ]
    for name in expected_files:
        assert os.path.isfile(os.path.join(EXTRACTED, name)), \
            f"Recursively extracted file {name} is missing."

    leftovers = []
    for root, _, files in os.walk(EXTRACTED):
        for name in files:
            path = os.path.join(root, name)
            lower = name.lower()
            is_archive = lower.endswith((".tar", ".tar.gz", ".tgz", ".zip"))
            try:
                is_archive = is_archive or tarfile.is_tarfile(path) or zipfile.is_zipfile(path)
            except (OSError, tarfile.TarError, zipfile.BadZipFile):
                pass
            try:
                with open(path, "rb") as f:
                    is_archive = is_archive or f.read(2) == b"\x1f\x8b"
            except OSError:
                pass
            if is_archive:
                leftovers.append(path)
    assert not leftovers, f"Archive files remain under {EXTRACTED}: {leftovers}"


def test_elf_files_moved():
    bin_dir = "/home/user/organized/bin"
    assert os.path.isdir(bin_dir), f"Directory {bin_dir} does not exist."

    prog_a = os.path.join(bin_dir, "program_a")
    prog_b = os.path.join(bin_dir, "program_b")
    not_elf = os.path.join(bin_dir, "not_elf_program")

    assert os.path.isfile(prog_a), f"ELF file {prog_a} is missing."
    assert os.path.isfile(prog_b), f"ELF file {prog_b} is missing."
    assert not os.path.exists(not_elf), f"Non-ELF file {not_elf} should not be in {bin_dir}."

    expected_a = b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00"
    expected_b = b"\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00"
    with open(prog_a, "rb") as f:
        assert f.read() == expected_a, f"{prog_a} is not the extracted ELF payload."
    with open(prog_b, "rb") as f:
        assert f.read() == expected_b, f"{prog_b} is not the extracted ELF payload."

    for root, _, files in os.walk(EXTRACTED):
        for name in files:
            path = os.path.join(root, name)
            with open(path, "rb") as f:
                assert f.read(4) != b"\x7fELF", f"ELF file was not moved: {path}"

    non_elf = os.path.join(EXTRACTED, "not_elf_program")
    with open(non_elf, "rb") as f:
        assert f.read() == b"MZ\x90\x00\x03\x00\x00\x00", \
            "The extracted non-ELF payload is missing or altered."


def test_gcode_times_report():
    report_path = "/home/user/organized/gcode_times.txt"
    assert os.path.isfile(report_path), f"Report {report_path} is missing."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "part1.gcode: 3600s",
        "part2_noext: 8450s"
    ]
    assert lines == expected_lines, f"Contents of {report_path} are incorrect. Expected {expected_lines}, got {lines}."


def test_log_splitting():
    aa_log = os.path.join(EXTRACTED, "system_part_aa.log")
    ab_log = os.path.join(EXTRACTED, "system_part_ab.log")
    ac_log = os.path.join(EXTRACTED, "system_part_ac.log")
    original_log = os.path.join(EXTRACTED, "system.log")

    assert not os.path.exists(original_log), f"Original log file {original_log} was not deleted."
    assert os.path.isfile(aa_log), f"Split log {aa_log} is missing."
    assert os.path.isfile(ab_log), f"Split log {ab_log} is missing."
    assert os.path.isfile(ac_log), f"Split log {ac_log} is missing."

    with open(aa_log, "r") as f:
        aa = [line.rstrip("\n") for line in f]
    with open(ab_log, "r") as f:
        ab = [line.rstrip("\n") for line in f]
    with open(ac_log, "r") as f:
        ac = [line.rstrip("\n") for line in f]

    assert len(aa) == 500, f"{aa_log} should have exactly 500 lines."
    assert len(ab) == 500, f"{ab_log} should have exactly 500 lines."
    assert len(ac) == 200, f"{ac_log} should have exactly 200 lines."

    expected = ["Log Started"] + [f"Log entry line {i}" for i in range(2, 1201)]
    assert aa + ab + ac == expected, "Split logs do not preserve the original log contents and order."

    logs = []
    for root, _, files in os.walk(EXTRACTED):
        logs.extend(os.path.join(root, n) for n in files if n.endswith(".log"))
    assert sorted(logs) == sorted([aa_log, ab_log, ac_log]), \
        f"Unexpected or incorrectly named log files found: {logs}"


def test_build_index_script():
    script_path = "/home/user/build_index.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "flock" in content, "Script does not contain 'flock'."
    assert "&" in content, "Script does not contain '&' for background jobs."
    assert "wait" in content, "Script does not contain 'wait'."


def test_master_index_contents():
    index_path = "/home/user/organized/master_index.txt"
    assert os.path.isfile(index_path), f"Master index {index_path} is missing."

    with open(index_path, "r") as f:
        lines = sorted([line.strip() for line in f if line.strip()])

    expected_entries = [
        "changelog.md | Changelog for V2",
        "part1.gcode | ; FLAVOR:Marlin",
        "part2_noext | ; FLAVOR:Marlin",
        "readme.txt | Project Alpha Documentation",
        "system_part_aa.log | Log Started",
        "system_part_ab.log | Log entry line 501",
        "system_part_ac.log | Log entry line 1001"
    ]

    for expected in expected_entries:
        assert any(expected in line for line in lines), f"Expected entry '{expected}' not found in {index_path}."


def _plain_text_files():
    result = []
    for root, _, files in os.walk(EXTRACTED):
        for name in files:
            path = os.path.join(root, name)
            mime = subprocess.check_output(
                ["file", "-b", "--mime-type", "--", path], text=True
            ).strip()
            if mime.startswith("text/"):
                result.append(path)
    return sorted(result)


def test_index_script_functionally_with_concurrency_and_locking():
    script_path = "/home/user/build_index.sh"
    index_path = os.path.join(ORGANIZED, "master_index.txt")

    token = uuid.uuid4().hex
    probe_dir = os.path.join(EXTRACTED, "verification_" + token[:12])
    os.makedirs(probe_dir)
    probes = {
        "probe_" + token[:10] + ".txt": "dynamic first " + token,
        "probe_" + token[10:20] + ".md": "another dynamic first " + token[::-1],
    }
    for name, first in probes.items():
        with open(os.path.join(probe_dir, name), "w") as f:
            f.write(first + "\nsecond line\n")

    text_files = _plain_text_files()
    expected = []
    for path in text_files:
        with open(path, "r", errors="strict") as f:
            first_line = f.readline().rstrip("\r\n")
        expected.append(f"{os.path.basename(path)} | {first_line}")

    real_flock = shutil.which("flock")
    assert real_flock and os.path.samefile(real_flock, "/usr/bin/flock"), "System flock utility is unavailable."
    backup = "/usr/bin/flock.verifier-real-" + token
    state_dir = "/tmp/flock-state-" + token
    os.makedirs(state_dir)
    for name in ("active", "maximum", "calls"):
        with open(os.path.join(state_dir, name), "w") as f:
            f.write("0\n")

    wrapper = '''#!/bin/bash
set -e
state="$VERIFIER_FLOCK_STATE"
real="$VERIFIER_REAL_FLOCK"
while ! mkdir "$state/guard" 2>/dev/null; do sleep 0.005; done
active=$(cat "$state/active")
calls=$(cat "$state/calls")
maximum=$(cat "$state/maximum")
active=$((active + 1))
calls=$((calls + 1))
if [ "$active" -gt "$maximum" ]; then maximum=$active; fi
printf '%s\n' "$active" > "$state/active"
printf '%s\n' "$calls" > "$state/calls"
printf '%s\n' "$maximum" > "$state/maximum"
rmdir "$state/guard"
sleep 0.20
while ! mkdir "$state/guard" 2>/dev/null; do sleep 0.005; done
active=$(cat "$state/active")
printf '%s\n' "$((active - 1))" > "$state/active"
rmdir "$state/guard"
exec "$real" "$@"
'''

    os.replace("/usr/bin/flock", backup)
    try:
        with open("/usr/bin/flock", "w") as f:
            f.write(wrapper)
        os.chmod("/usr/bin/flock", 0o755)

        if os.path.exists(index_path):
            os.remove(index_path)
        env = os.environ.copy()
        env["VERIFIER_FLOCK_STATE"] = state_dir
        env["VERIFIER_REAL_FLOCK"] = backup
        completed = subprocess.run(
            ["bash", script_path], env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert completed.returncode == 0, \
            f"build_index.sh failed when executed:\n{completed.stdout}\n{completed.stderr}"
    finally:
        if os.path.exists("/usr/bin/flock"):
            os.remove("/usr/bin/flock")
        if os.path.exists(backup):
            os.replace(backup, "/usr/bin/flock")

    with open(os.path.join(state_dir, "calls")) as f:
        calls = int(f.read().strip())
    with open(os.path.join(state_dir, "maximum")) as f:
        maximum = int(f.read().strip())

    assert calls >= len(text_files), \
        f"flock was invoked {calls} times for {len(text_files)} text files; each background append must be locked."
    assert maximum >= 2, \
        "Indexing jobs did not run concurrently; flock invocations never overlapped."

    assert os.path.isfile(index_path), "Executing build_index.sh did not create master_index.txt."
    with open(index_path, "r") as f:
        actual = [line.rstrip("\r\n") for line in f]

    assert collections.Counter(actual) == collections.Counter(expected), \
        f"Executed index output is not the exact index of all current text files. Expected {sorted(expected)}, got {sorted(actual)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
