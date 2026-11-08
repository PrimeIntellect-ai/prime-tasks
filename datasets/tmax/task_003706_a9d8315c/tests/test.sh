#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import shutil
import subprocess
import tarfile
import uuid
import zipfile

PROGRAM = "/home/user/audit_archives.go"
ARCHIVE_ROOT = "/home/user/uploaded_archives"
LOG_FILE = "/home/user/malicious_archives.log"
SCRIPT_FILE = "/home/user/cleanup.sh"

ORIGINAL_ARCHIVES = [
    "/home/user/uploaded_archives/project_a/clean1.zip",
    "/home/user/uploaded_archives/project_a/malicious1.zip",
    "/home/user/uploaded_archives/project_b/clean2.tar",
    "/home/user/uploaded_archives/project_b/nested/malicious2.tar",
]

ORIGINAL_MALICIOUS = [
    "/home/user/uploaded_archives/project_a/malicious1.zip",
    "/home/user/uploaded_archives/project_b/nested/malicious2.tar",
]


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def run_program():
    env = os.environ.copy()
    env["GO111MODULE"] = "off"
    env["GOPROXY"] = "off"
    result = subprocess.run(
        ["go", "run", PROGRAM],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Go program failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def expected_commands(paths):
    return [f"rm -f '{path}'" for path in sorted(paths)]


def test_go_program_exists():
    assert os.path.isfile(PROGRAM), "The Go program /home/user/audit_archives.go was not found."
    assert os.path.getsize(PROGRAM) > 0, "The Go program is empty."
    remove_path(LOG_FILE)
    remove_path(SCRIPT_FILE)
    run_program()


def test_archives_not_deleted():
    for f in ORIGINAL_ARCHIVES:
        assert os.path.isfile(f), f"Archive file missing, perhaps the cleanup script was executed: {f}"


def test_malicious_archives_log():
    assert os.path.isfile(LOG_FILE), f"Log file missing: {LOG_FILE}"
    lines = read_nonempty_lines(LOG_FILE)
    assert lines == ORIGINAL_MALICIOUS, (
        f"Contents of {LOG_FILE} do not match the expected sorted list of malicious archives. Got: {lines}"
    )


def test_cleanup_script():
    assert os.path.isfile(SCRIPT_FILE), f"Cleanup script missing: {SCRIPT_FILE}"
    lines = read_nonempty_lines(SCRIPT_FILE)
    assert len(lines) >= 3, f"Cleanup script {SCRIPT_FILE} does not have enough lines."
    assert lines[0] == "#!/bin/bash", (
        f"Cleanup script does not start with #!/bin/bash shebang. Got: {lines[0]}"
    )
    commands = expected_commands(ORIGINAL_MALICIOUS)
    assert lines[1:] == commands, f"Cleanup script commands do not match expected output. Got: {lines[1:]}"


def test_program_handles_fresh_recursive_archives_and_atomic_replacement():
    token = uuid.uuid4().hex
    dynamic_root = os.path.join(ARCHIVE_ROOT, f"verification_{token}", "deep", "space dir")
    os.makedirs(dynamic_root, exist_ok=True)

    clean_zip = os.path.join(dynamic_root, f"{uuid.uuid4().hex}.zip")
    traversal_zip = os.path.join(dynamic_root, f"{uuid.uuid4().hex}.zip")
    backslash_zip = os.path.join(dynamic_root, f"{uuid.uuid4().hex}.zip")
    clean_tar = os.path.join(dynamic_root, f"{uuid.uuid4().hex}.tar")
    absolute_tar = os.path.join(dynamic_root, f"{uuid.uuid4().hex}.tar")

    extraction_marker = f"/tmp/audit_archives_must_not_extract_{token}"
    remove_path(extraction_marker)

    with zipfile.ZipFile(clean_zip, "w") as zf:
        zf.writestr("normal/file.txt", "safe")
        zf.writestr("name..txt", "safe")

    with zipfile.ZipFile(traversal_zip, "w") as zf:
        zf.writestr("folder/../escape.txt", "unsafe")

    with zipfile.ZipFile(backslash_zip, "w") as zf:
        zf.writestr(r"folder\..\escape.txt", "unsafe")

    with tarfile.open(clean_tar, "w") as tf:
        info = tarfile.TarInfo("safe/subdirectory/file.txt")
        payload = b"safe"
        info.size = len(payload)
        tf.addfile(info, io.BytesIO(payload))

    with tarfile.open(absolute_tar, "w") as tf:
        info = tarfile.TarInfo(extraction_marker)
        payload = b"must not be extracted"
        info.size = len(payload)
        tf.addfile(info, io.BytesIO(payload))

    expected_malicious = sorted(ORIGINAL_MALICIOUS + [
        traversal_zip,
        backslash_zip,
        absolute_tar,
    ])

    sentinel_dir = f"/tmp/audit_atomic_{token}"
    os.makedirs(sentinel_dir)
    log_sentinel = os.path.join(sentinel_dir, "log_sentinel")
    script_sentinel = os.path.join(sentinel_dir, "script_sentinel")
    with open(log_sentinel, "w") as f:
        f.write("unchanged-log-sentinel")
    with open(script_sentinel, "w") as f:
        f.write("unchanged-script-sentinel")

    remove_path(LOG_FILE)
    remove_path(SCRIPT_FILE)
    os.symlink(log_sentinel, LOG_FILE)
    os.symlink(script_sentinel, SCRIPT_FILE)

    run_program()

    assert not os.path.lexists(extraction_marker), "The program extracted an archive entry to disk."
    for path in ORIGINAL_ARCHIVES + [clean_zip, traversal_zip, backslash_zip, clean_tar, absolute_tar]:
        assert os.path.isfile(path), f"Archive was deleted or modified unexpectedly: {path}"

    assert not os.path.islink(LOG_FILE), "Log output was written through the destination instead of atomically replacing it."
    assert not os.path.islink(SCRIPT_FILE), "Cleanup output was written through the destination instead of atomically replacing it."
    with open(log_sentinel) as f:
        assert f.read() == "unchanged-log-sentinel", "Log destination was written directly rather than atomically replaced."
    with open(script_sentinel) as f:
        assert f.read() == "unchanged-script-sentinel", "Cleanup destination was written directly rather than atomically replaced."

    assert os.path.isfile(LOG_FILE), f"Log file missing after dynamic run: {LOG_FILE}"
    assert read_nonempty_lines(LOG_FILE) == expected_malicious, (
        "The program did not recursively inspect the freshly generated ZIP/TAR headers correctly or did not sort its results."
    )

    assert os.path.isfile(SCRIPT_FILE), f"Cleanup script missing after dynamic run: {SCRIPT_FILE}"
    script_lines = read_nonempty_lines(SCRIPT_FILE)
    assert script_lines[0] == "#!/bin/bash", "Cleanup script has an invalid or missing shebang."
    assert script_lines[1:] == expected_commands(expected_malicious), (
        "Cleanup commands do not exactly match the dynamically discovered malicious archives in sorted order."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
