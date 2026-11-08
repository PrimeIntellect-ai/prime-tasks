#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import shutil
import subprocess


def test_script_exists_and_executable():
    script_path = "/home/user/check_migration.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_report_exists():
    report_path = "/home/user/migration_report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} was not generated."


def test_report_content():
    report_path = "/home/user/migration_report.txt"
    if not os.path.isfile(report_path):
        return # Handled by previous test

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = """UPGRADES:
pandas 0.24.0
requests 2.20.0
six 1.11.0
urllib3 1.24.2

FAILURES:
legacy.py
old.py
utils.py"""

    assert content == expected_content, (
        f"The content of {report_path} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\nGot:\n{content}"
    )


def test_script_is_bash_and_processes_fresh_inputs_recursively():
    script_path = "/home/user/check_migration.sh"
    with open(script_path, "r", errors="replace") as f:
        first_line = f.readline().strip()
    assert first_line.startswith("#!") and "bash" in first_line, (
        "check_migration.sh must be a Bash script with a Bash shebang."
    )

    syntax_check = subprocess.run(
        ["bash", "-n", script_path], capture_output=True, text=True, timeout=10
    )
    assert syntax_check.returncode == 0, syntax_check.stderr

    token = secrets.token_hex(6)
    equal_pkg = f"aa{token}"
    greater_pkg = f"bb{token}"
    patch_low_pkg = f"cc{token}"
    minor_low_pkg = f"dd{token}"
    missing_pkg = f"ee{token}"

    with open("/home/user/deps.current", "w") as f:
        f.write(
            f"{minor_low_pkg}=1.9.9\n"
            f"{equal_pkg}=2.3.4\n"
            f"unrelated{token}=9.9.9\n"
            f"{patch_low_pkg}=1.2.9\n"
            f"{greater_pkg}=3.0.0\n"
        )

    with open("/home/user/deps.required", "w") as f:
        f.write(
            f"{missing_pkg}>=4.5.6\n"
            f"{greater_pkg}>=2.9.9\n"
            f"{minor_low_pkg}>=1.10.0\n"
            f"{equal_pkg}>=2.3.4\n"
            f"{patch_low_pkg}>=1.2.10\n"
        )

    src = "/home/user/src"
    shutil.rmtree(src, ignore_errors=True)
    os.makedirs(os.path.join(src, "level1", "level2"))

    top_failure = f"ztopbad{token}.py"
    nested_failure = f"anestedbad{token}.py"
    with open(os.path.join(src, "valid.py"), "w") as f:
        f.write("value = 42\nprint(value)\n")
    with open(os.path.join(src, top_failure), "w") as f:
        f.write('print "python two"\n')
    with open(os.path.join(src, "level1", "also_valid.py"), "w") as f:
        f.write("def ok():\n    return True\n")
    with open(os.path.join(src, "level1", "level2", nested_failure), "w") as f:
        f.write("number = 100L\n")

    report_path = "/home/user/migration_report.txt"
    if os.path.exists(report_path):
        os.remove(report_path)

    env = os.environ.copy()
    env["LC_ALL"] = "C"
    result = subprocess.run(
        [script_path], capture_output=True, text=True, timeout=20, env=env
    )
    assert result.returncode == 0, (
        f"Script exited with {result.returncode}.\nstdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(report_path), "Script did not generate migration_report.txt."

    upgrades = sorted([
        (patch_low_pkg, "1.2.10"),
        (minor_low_pkg, "1.10.0"),
        (missing_pkg, "4.5.6"),
    ])
    failures = sorted([top_failure, nested_failure])
    expected = (
        "UPGRADES:\n"
        + "\n".join(f"{name} {version}" for name, version in upgrades)
        + "\n\nFAILURES:\n"
        + "\n".join(failures)
    )

    with open(report_path, "r") as f:
        actual = f.read().strip()
    assert actual == expected, (
        "Script did not correctly process fresh dependency and recursive syntax inputs.\n"
        f"Expected:\n{expected}\n\nGot:\n{actual}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
