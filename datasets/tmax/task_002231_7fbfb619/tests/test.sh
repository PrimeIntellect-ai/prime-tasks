#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

CONFIG_DIR = Path("/home/user/qemu_configs")
REPORT_FILE = Path("/home/user/hardening_report.json")
SCRIPT_FILE = Path("/home/user/harden_vms.py")

EXPECTED_CONTENTS = {
    "vm_web.sh": "#!/bin/bash\nqemu-system-x86_64 -m 1024 -drive file=web.img,format=qcow2 -vnc 0.0.0.0:1,password=on -monitor stdio\n",
    "vm_db.sh": "#!/bin/bash\nqemu-system-x86_64 -m 2048 -drive file=db.img,format=qcow2 -vnc 127.0.0.1:2,password=on -daemonize\n",
    "vm_test.sh": "#!/bin/bash\nqemu-system-x86_64 -m 512 -drive file=test.img,format=qcow2 -vnc :3,password=on -net nic\n",
    "vm_safe.sh": "#!/bin/bash\nqemu-system-x86_64 -m 512 -drive file=safe.img,format=qcow2 -vnc :4,password=on\n",
}


def test_script_exists():
    assert SCRIPT_FILE.exists(), f"Automation script {SCRIPT_FILE} is missing."
    assert SCRIPT_FILE.is_file(), f"{SCRIPT_FILE} is not a regular file."
    assert not SCRIPT_FILE.is_symlink(), f"{SCRIPT_FILE} must be an actual Python script, not a symlink."


def test_vnc_password_fixed():
    """Check that password=off was replaced with password=on in the relevant files."""
    vnc_files = ["vm_web.sh", "vm_test.sh"]
    for filename in vnc_files:
        filepath = CONFIG_DIR / filename
        assert filepath.is_file(), f"File {filepath} is missing."
        content = filepath.read_text()
        assert "password=on" in content, f"File {filepath} does not contain 'password=on'."
        assert "password=off" not in content, f"File {filepath} still contains 'password=off'."
        assert content == EXPECTED_CONTENTS[filename], f"File {filepath} had arguments or its VNC binding altered."


def test_permissions_fixed():
    """Check that world-writable files were changed to 750."""
    fixed_files = ["vm_web.sh", "vm_test.sh", "vm_safe.sh"]
    for filename in fixed_files:
        filepath = CONFIG_DIR / filename
        assert filepath.is_file(), f"File {filepath} is missing."
        actual_perms = stat.S_IMODE(filepath.stat().st_mode)
        assert actual_perms == 0o750, f"File {filepath} has permissions {oct(actual_perms)}, expected 0o750."


def test_unaffected_files():
    """Check that files not needing fixes were left unchanged."""
    filepath = CONFIG_DIR / "vm_db.sh"
    assert filepath.is_file(), f"File {filepath} is missing."
    actual_perms = stat.S_IMODE(filepath.stat().st_mode)
    assert actual_perms == 0o644, f"File {filepath} has permissions {oct(actual_perms)}, expected 0o644."
    content = filepath.read_text()
    assert "password=on" in content, f"File {filepath} does not contain 'password=on'."
    assert "password=off" not in content, f"File {filepath} contains 'password=off'."
    assert content == EXPECTED_CONTENTS["vm_db.sh"], f"File {filepath} was otherwise altered."

    safe = CONFIG_DIR / "vm_safe.sh"
    assert safe.read_text() == EXPECTED_CONTENTS["vm_safe.sh"], f"File {safe} was otherwise altered."


def test_hardening_report():
    """Check that the hardening report is generated correctly."""
    assert REPORT_FILE.is_file(), f"Report file {REPORT_FILE} was not generated."
    try:
        report = json.loads(REPORT_FILE.read_text())
    except json.JSONDecodeError:
        pytest.fail(f"Report file {REPORT_FILE} is not valid JSON.")

    assert "vnc_fixed" in report, "Report is missing 'vnc_fixed' key."
    assert "permissions_fixed" in report, "Report is missing 'permissions_fixed' key."
    expected_vnc_fixed = ["vm_test.sh", "vm_web.sh"]
    expected_perms_fixed = ["vm_safe.sh", "vm_test.sh", "vm_web.sh"]
    assert sorted(report["vnc_fixed"]) == expected_vnc_fixed, \
        f"Expected vnc_fixed to be {expected_vnc_fixed}, got {report['vnc_fixed']}."
    assert sorted(report["permissions_fixed"]) == expected_perms_fixed, \
        f"Expected permissions_fixed to be {expected_perms_fixed}, got {report['permissions_fixed']}."


def remediate_vnc(content):
    """Derive the required result by changing password=off only in -vnc arguments."""
    pattern = re.compile(r"(-vnc[ \t]+)([^ \t\r\n]+)")

    def replace_argument(match):
        return match.group(1) + match.group(2).replace("password=off", "password=on")

    return pattern.sub(replace_argument, content)


def test_script_performs_remediation_on_fresh_inputs():
    """Execute the submitted automation against unpredictable fresh fixtures."""
    token = uuid.uuid4().hex[:10]
    fixtures = {
        f"alpha_{token}.sh": (
            "#!/bin/bash\nqemu-system-x86_64 -name alpha -m 1536 "
            "-vnc 10.23.45.67:8,password=off,share=force-shared -monitor none\n",
            0o777,
        ),
        f"beta_{token}.sh": (
            "#!/bin/bash\nqemu-system-x86_64 -name beta -vnc 127.0.0.1:9,password=on -daemonize\n",
            0o640,
        ),
        f"gamma_{token}.sh": (
            "#!/bin/bash\necho password=off\nqemu-system-x86_64 -name gamma -vnc :10,password=on -net nic\n",
            0o777,
        ),
        f"delta_{token}.sh": (
            "#!/bin/bash\nqemu-system-x86_64 -name delta -drive file=disk.img,format=qcow2 "
            "-vnc 192.0.2.44:11,password=off -serial stdio\n",
            0o750,
        ),
    }
    non_script_name = f"ignore_{token}.txt"
    non_script_content = "-vnc :99,password=off\n"

    expected_contents = {name: remediate_vnc(content) for name, (content, _) in fixtures.items()}
    expected_vnc = sorted(
        name for name, (content, _) in fixtures.items() if expected_contents[name] != content
    )
    expected_permissions = sorted(
        name for name, (_, mode) in fixtures.items() if mode & stat.S_IWOTH
    )

    backup_root = Path(tempfile.mkdtemp(prefix="hardening-verifier-"))
    backup_configs = backup_root / "qemu_configs"
    backup_report = backup_root / "hardening_report.json"
    shutil.copytree(CONFIG_DIR, backup_configs, copy_function=shutil.copy2)
    report_existed = REPORT_FILE.exists()
    if report_existed:
        shutil.copy2(REPORT_FILE, backup_report)

    try:
        shutil.rmtree(CONFIG_DIR)
        CONFIG_DIR.mkdir(mode=0o777)
        os.chmod(CONFIG_DIR, 0o777)

        for name, (content, mode) in fixtures.items():
            path = CONFIG_DIR / name
            path.write_text(content)
            os.chmod(path, mode)
        ignored = CONFIG_DIR / non_script_name
        ignored.write_text(non_script_content)
        os.chmod(ignored, 0o666)

        if REPORT_FILE.exists():
            REPORT_FILE.unlink()

        result = subprocess.run(
            ["python3", str(SCRIPT_FILE)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Automation script exited with {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        for name, (_, original_mode) in fixtures.items():
            path = CONFIG_DIR / name
            assert path.is_file(), f"Automation removed expected file {path}."
            assert path.read_text() == expected_contents[name], (
                f"{name} was not remediated exactly, or unrelated arguments/bindings were altered."
            )
            expected_mode = 0o750 if original_mode & stat.S_IWOTH else original_mode
            actual_mode = stat.S_IMODE(path.stat().st_mode)
            assert actual_mode == expected_mode, (
                f"{name} has permissions {oct(actual_mode)}, expected {oct(expected_mode)}."
            )

        assert ignored.read_text() == non_script_content, "The automation altered a non-.sh file."
        assert stat.S_IMODE(ignored.stat().st_mode) == 0o666, "The automation changed permissions on a non-.sh file."

        assert REPORT_FILE.is_file(), "The executed script did not generate hardening_report.json."
        try:
            report = json.loads(REPORT_FILE.read_text())
        except json.JSONDecodeError as exc:
            pytest.fail(f"Generated report is not valid JSON: {exc}")
        assert report == {
            "vnc_fixed": expected_vnc,
            "permissions_fixed": expected_permissions,
        }, f"Generated report does not precisely describe the fresh remediations: {report!r}"
    finally:
        if CONFIG_DIR.exists():
            shutil.rmtree(CONFIG_DIR)
        shutil.copytree(backup_configs, CONFIG_DIR, copy_function=shutil.copy2)
        if REPORT_FILE.exists():
            REPORT_FILE.unlink()
        if report_existed:
            shutil.copy2(backup_report, REPORT_FILE)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
