#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_curate_artifacts.py
import io
import os
import secrets
import shutil
import subprocess
import tarfile

SCRIPT = "/home/user/curate_artifacts.sh"
INCOMING = "/home/user/incoming"
REPO = "/home/user/repo"
LOG = "/home/user/curation.log"


def add_file(tar, arcname, source):
    with open(source, "rb") as f:
        data = f.read()
    info = tarfile.TarInfo(arcname)
    info.size = len(data)
    info.mode = 0o755
    tar.addfile(info, io.BytesIO(data))


def add_data(tar, arcname, data=b"marker\n"):
    info = tarfile.TarInfo(arcname)
    info.size = len(data)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))


def reset_paths():
    shutil.rmtree(INCOMING, ignore_errors=True)
    shutil.rmtree(REPO, ignore_errors=True)
    os.makedirs(INCOMING, mode=0o777)
    os.makedirs(REPO, mode=0o777)
    if os.path.lexists(LOG):
        os.remove(LOG)


def run_script():
    assert os.path.isfile(SCRIPT), f"Required Bash script {SCRIPT} is missing or is not a regular file."
    result = subprocess.run(
        ["bash", SCRIPT], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def make_original_archives():
    reset_paths()
    with tarfile.open(os.path.join(INCOMING, "1_base.tar"), "w") as t:
        add_file(t, "bin/app1", "/bin/ls")
        add_file(t, "bin/app2", "/bin/pwd")
    with tarfile.open(os.path.join(INCOMING, "2_inc.tar"), "w") as t:
        add_file(t, "bin/app3", "/bin/echo")
        add_data(t, "../evil.sh")
    with tarfile.open(os.path.join(INCOMING, "3_inc.tar"), "w") as t:
        add_file(t, "bin/app4", "/bin/cat")
    with tarfile.open(os.path.join(INCOMING, "4_inc.tar"), "w") as t:
        add_file(t, "/etc/shadow_overwrite", "/bin/cat")


def check_original_curation_log():
    assert os.path.isfile(LOG), f"Log file {LOG} is missing."
    with open(LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected = [
        "ACCEPTED: 1_base.tar",
        "REJECTED: 2_inc.tar",
        "ACCEPTED: 3_inc.tar",
        "REJECTED: 4_inc.tar"
    ]
    assert lines == expected, f"Log content mismatch. Expected {expected}, got {lines}"


def check_original_malicious_files_not_extracted():
    for root, _, files in os.walk(REPO):
        for f in files:
            assert not f.startswith("app3"), f"Malicious archive 2_inc.tar was extracted! Found {f}"
            assert "evil.sh" not in f, f"Malicious file evil.sh was extracted into {root}!"
            assert "shadow_overwrite" not in f, f"Malicious file shadow_overwrite was extracted into {root}!"


def architecture_suffix(path):
    out = subprocess.check_output(["file", path], text=True)
    if "x86-64" in out:
        return "_x86_64"
    if "aarch64" in out:
        return "_aarch64"
    if "ARM" in out:
        return "_arm"
    if "386" in out:
        return "_i386"
    return ""


def check_original_safe_files_extracted_and_renamed():
    repo_bin = os.path.join(REPO, "bin")
    assert os.path.isdir(repo_bin), f"Directory {repo_bin} does not exist. Safe archives were not extracted correctly."
    files = os.listdir(repo_bin)
    found_bases = set()
    for f in files:
        filepath = os.path.join(repo_bin, f)
        if not os.path.isfile(filepath):
            continue
        out = subprocess.check_output(["file", filepath], text=True)
        expected_suffix = ""
        if "x86-64" in out:
            expected_suffix = "_x86_64"
        elif "aarch64" in out:
            expected_suffix = "_aarch64"
        elif "ARM" in out:
            expected_suffix = "_arm"
        elif "386" in out:
            expected_suffix = "_i386"
        assert expected_suffix != "", f"Could not determine expected architecture suffix for {f}. `file` output: {out}"
        assert f.endswith(expected_suffix), f"File '{f}' does not have the expected suffix '{expected_suffix}' for its architecture."
        found_bases.add(f[:-len(expected_suffix)])
    assert found_bases == {"app1", "app2", "app4"}, f"Expected extracted binaries app1, app2, app4. Found: {found_bases}"


def dynamic_behavior_check():
    token = secrets.token_hex(8)
    reset_paths()

    base_name = "base_" + token
    deep_name = "deep_" + token
    overwrite_name = "overwrite_" + token
    rejected_name = "rejected_" + token
    absolute_name = "absolute_" + token
    text_name = "note_" + token + ".txt"
    escape_path = "/home/user/escape_" + token
    absolute_path = "/tmp/absolute_" + token
    for path in (escape_path, absolute_path):
        if os.path.lexists(path):
            os.remove(path)

    archive_names = [
        "10_" + token + "_base.tar",
        "20_" + token + "_traversal.tar",
        "30_" + token + "_incremental.tar",
        "40_" + token + "_absolute.tar",
    ]

    with tarfile.open(os.path.join(INCOMING, archive_names[0]), "w") as t:
        add_file(t, "bin/" + base_name, "/bin/ls")
        add_file(t, "nested/tools/" + deep_name, "/bin/pwd")
        add_file(t, "bin/" + overwrite_name, "/bin/echo")
        add_data(t, "docs/" + text_name, b"not an ELF file\n")

    with tarfile.open(os.path.join(INCOMING, archive_names[1]), "w") as t:
        add_file(t, "bin/" + rejected_name, "/bin/echo")
        add_data(t, "../escape_" + token, b"must not escape\n")

    with tarfile.open(os.path.join(INCOMING, archive_names[2]), "w") as t:
        add_file(t, "bin/" + overwrite_name, "/bin/cat")

    with tarfile.open(os.path.join(INCOMING, archive_names[3]), "w") as t:
        add_file(t, absolute_path, "/bin/echo")
        add_file(t, "bin/" + absolute_name, "/bin/echo")

    run_script()

    with open(LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_log = [
        "ACCEPTED: " + archive_names[0],
        "REJECTED: " + archive_names[1],
        "ACCEPTED: " + archive_names[2],
        "REJECTED: " + archive_names[3],
    ]
    assert lines == expected_log, f"Dynamic log mismatch. Expected {expected_log}, got {lines}"

    expected_sources = {
        os.path.join("bin", base_name): "/bin/ls",
        os.path.join("nested", "tools", deep_name): "/bin/pwd",
        os.path.join("bin", overwrite_name): "/bin/cat",
    }
    expected_files = set()
    for relative_base, source in expected_sources.items():
        suffix = architecture_suffix(source)
        assert suffix, f"Could not derive architecture for test binary {source}"
        relative_result = relative_base + suffix
        expected_files.add(relative_result)
        result_path = os.path.join(REPO, relative_result)
        assert os.path.isfile(result_path), f"Expected renamed ELF binary is missing: {result_path}"
        with open(result_path, "rb") as actual, open(source, "rb") as wanted:
            assert actual.read() == wanted.read(), f"Wrong archive version was retained for {relative_base}"

    expected_files.add(os.path.join("docs", text_name))
    actual_files = set()
    for root, _, files in os.walk(REPO):
        for name in files:
            actual_files.add(os.path.relpath(os.path.join(root, name), REPO))
    assert actual_files == expected_files, f"Unexpected repository contents: expected {expected_files}, got {actual_files}"
    assert not os.path.exists(escape_path), "A traversal member was extracted outside the repository"
    assert not os.path.exists(absolute_path), "An absolute-path member was extracted"
    assert not any(rejected_name in p or absolute_name in p for p in actual_files), "A malicious archive was partially extracted"


def test_complete_script_behavior():
    make_original_archives()
    run_script()
    check_original_curation_log()
    check_original_malicious_files_not_extracted()
    check_original_safe_files_extracted_and_renamed()
    dynamic_behavior_check()
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_curate_artifacts.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
