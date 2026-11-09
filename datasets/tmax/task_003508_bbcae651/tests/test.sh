#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

SCRIPT = Path("/home/user/deploy_update.sh")
SOURCE = Path("/home/user/release_v2")
PRODUCTION = Path("/home/user/production")
AUDIT = Path("/home/user/audit.log")

ORIGINAL = {
    "api/server.py": {"perms": "750", "acl_user": "www-data", "acl_perms": "r-x"},
    "config/db.conf": {"perms": "600", "acl_user": "www-data", "acl_perms": "r--"},
    "static/style.css": {"perms": "644", "acl_user": "daemon", "acl_perms": "r--"},
}


def acl_output(path):
    result = subprocess.run(["getfacl", "-p", str(path)], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to run getfacl on {path}: {result.stderr}"
    return result.stdout


def test_deploy_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Deployment script missing: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Deployment script is not executable: {SCRIPT}"


def test_deployed_files_and_permissions():
    for rel_path, expected in ORIGINAL.items():
        full_path = PRODUCTION / rel_path
        source_path = SOURCE / rel_path
        assert os.path.isfile(full_path), f"Deployed file missing: {full_path}"

        # The deployed artifact must actually be the release artifact.
        assert full_path.read_bytes() == source_path.read_bytes(), \
            f"Deployed content differs from release_v2 for {rel_path}"

        actual_mode = format(stat.S_IMODE(full_path.stat().st_mode), "03o")
        assert actual_mode == expected["perms"], \
            f"Wrong mode for {full_path}: expected {expected['perms']}, got {actual_mode}"

        output = acl_output(full_path)
        acl_line = f"user:{expected['acl_user']}:{expected['acl_perms']}"
        assert acl_line in output, \
            f"ACL rule '{acl_line}' not found in getfacl output for {full_path}:\n{output}"


def test_audit_log_content():
    assert os.path.isfile(AUDIT), f"Audit log missing: {AUDIT}"
    expected_lines = [
        "FILE: api/server.py - PERMS: 750 - ACL: www-data:r-x",
        "FILE: config/db.conf - PERMS: 600 - ACL: www-data:r--",
        "FILE: static/style.css - PERMS: 644 - ACL: daemon:r--",
    ]
    content = AUDIT.read_text().strip().split("\n")
    assert len(content) == len(expected_lines), \
        f"Audit log should have exactly {len(expected_lines)} lines, found {len(content)}."
    for expected in expected_lines:
        assert expected in content, f"Missing expected audit log line: '{expected}'"
    assert content == expected_lines, "Audit log entries are not sorted alphabetically by file path"


def install_tool_wrapper(tool, marker, saved):
    resolved = Path(os.path.realpath(subprocess.check_output(["sh", "-c", f"command -v {tool}"], text=True).strip()))
    backup = resolved.with_name(resolved.name + ".verifier-real")
    assert not backup.exists(), f"Unexpected verifier backup already exists: {backup}"
    os.replace(resolved, backup)
    resolved.write_text(
        "#!/bin/sh\n"
        f"printf '%s\\n' '{tool}' >> '{marker}'\n"
        f"exec '{backup}' \"$@\"\n"
    )
    resolved.chmod(0o755)
    saved.append((resolved, backup))


def restore_tool_wrappers(saved):
    for resolved, backup in reversed(saved):
        try:
            if resolved.exists() or resolved.is_symlink():
                resolved.unlink()
        finally:
            if backup.exists():
                os.replace(backup, resolved)


def test_script_processes_supplied_manifest_and_real_inputs():
    token = uuid.uuid4().hex
    cases = {
        f"verify_{token}/zeta.txt": ("640", "www-data", "r--", b"zeta dynamic payload\n"),
        f"verify_{token}/alpha.txt": ("750", "daemon", "r-x", b"alpha dynamic payload\n"),
        f"verify_{token}/nested/middle.bin": ("660", "www-data", "rw-", os.urandom(73)),
    }

    for rel, (_, _, _, payload) in cases.items():
        source = SOURCE / rel
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_bytes(payload)
        target = PRODUCTION / rel
        if target.exists():
            target.unlink()

    with tempfile.TemporaryDirectory(prefix="deploy-verifier-") as temp_dir:
        temp = Path(temp_dir)
        manifest = temp / "supplied-manifest.txt"
        marker = temp / "tools-used.log"
        marker.touch()

        # Deliberately unsorted, with whitespace and an empty line.
        order = list(cases.keys())
        manifest.write_text(
            f" {order[0]} | {cases[order[0]][0]} | {cases[order[0]][1]} | {cases[order[0]][2]} \n"
            "\n"
            f"{order[2]}|{cases[order[2]][0]}|{cases[order[2]][1]}|{cases[order[2]][2]}\n"
            f" {order[1]} | {cases[order[1]][0]} | {cases[order[1]][1]} | {cases[order[1]][2]}\n"
        )

        saved = []
        try:
            install_tool_wrapper("awk", marker, saved)
            install_tool_wrapper("getfacl", marker, saved)
            result = subprocess.run(
                [str(SCRIPT), str(manifest)],
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=30,
            )
        finally:
            restore_tool_wrappers(saved)

        assert result.returncode == 0, \
            f"Script failed on supplied manifest. stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        tools_used = marker.read_text().splitlines()
        assert "awk" in tools_used, "The deployment script did not execute awk"
        assert "getfacl" in tools_used, "The deployment script did not execute getfacl"

    expected_log = []
    for rel in sorted(cases):
        expected_mode, acl_user, acl_perms, payload = cases[rel]
        target = PRODUCTION / rel
        assert target.is_file(), f"Script did not deploy manifest entry {rel}"
        assert target.read_bytes() == payload, f"Script did not copy release content for {rel}"

        actual_mode = format(stat.S_IMODE(target.stat().st_mode), "03o")
        assert actual_mode == expected_mode, \
            f"Wrong mode for dynamic entry {rel}: expected {expected_mode}, got {actual_mode}"

        output = acl_output(target)
        acl_line = f"user:{acl_user}:{acl_perms}"
        assert acl_line in output, f"Missing ACL {acl_line} on dynamic entry {rel}:\n{output}"
        expected_log.append(
            f"FILE: {rel} - PERMS: {actual_mode} - ACL: {acl_user}:{acl_perms}"
        )

    assert AUDIT.is_file(), "Script did not create the audit log for the supplied manifest"
    actual_log = AUDIT.read_text().splitlines()
    assert actual_log == expected_log, \
        f"Audit log must contain exactly the deployed files in alphabetical order.\nExpected: {expected_log}\nActual: {actual_log}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
