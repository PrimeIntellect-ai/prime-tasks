#!/bin/bash
set -u
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import uuid

import pytest
from elftools.elf.elffile import ELFFile
from elftools.elf.sections import SymbolTableSection

BIN_DIR = "/home/user/binaries"
REPORT_PATH = "/home/user/audit_report.json"
NAMES = {}


def analyze_file(path):
    try:
        with open(path, "rb") as f:
            elf = ELFFile(f)
            if elf.header["e_type"] not in ("ET_EXEC", "ET_DYN"):
                return False
            for section in elf.iter_sections():
                if isinstance(section, SymbolTableSection):
                    for symbol in section.iter_symbols():
                        if symbol.name.split("@", 1)[0] == "gets":
                            return True
            return False
    except Exception:
        return False


@pytest.fixture(scope="session", autouse=True)
def create_unpredictable_inputs_and_run_submission():
    assert os.path.isfile("/home/user/audit.py"), "Required Python script /home/user/audit.py does not exist."

    suffix = uuid.uuid4().hex
    NAMES.update({
        "vulnerable": f"probe_vulnerable_{suffix}",
        "safe": f"probe_safe_{suffix}",
        "nonelf": f"probe_nonelf_{suffix}",
    })

    vulnerable_path = os.path.join(BIN_DIR, NAMES["vulnerable"])
    safe_path = os.path.join(BIN_DIR, NAMES["safe"])
    nonelf_path = os.path.join(BIN_DIR, NAMES["nonelf"])

    vulnerable_source = f"/tmp/{NAMES['vulnerable']}.c"
    safe_source = f"/tmp/{NAMES['safe']}.c"

    with open(vulnerable_source, "w") as f:
        f.write(r'''
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
extern char *gets(char *);
int main(int argc, char **argv) {
    char buffer[8];
    struct rlimit limit;
    if (argc == 9999) gets(buffer);
    if (getrlimit(RLIMIT_CORE, &limit) != 0) return 7;
    printf("clean=%d core=%llu argc=%d\n",
           getenv("LEAK_MARKER") == NULL,
           (unsigned long long)limit.rlim_cur,
           argc - 1);
    for (int i = 1; i < argc; i++) printf("[%s]\n", argv[i]);
    return 0;
}
''')

    with open(safe_source, "w") as f:
        f.write(r'''
#include <stdio.h>
int main(void) {
    puts("The word gets in ordinary data is not a symbol reference.");
    return 0;
}
''')

    subprocess.run(["gcc", "-w", vulnerable_source, "-o", vulnerable_path], check=True, timeout=20)
    subprocess.run(["gcc", safe_source, "-o", safe_path], check=True, timeout=20)
    with open(nonelf_path, "w") as f:
        f.write("#!/bin/sh\necho not-an-elf\n")
    os.chmod(nonelf_path, 0o755)

    for name in NAMES.values():
        wrapper = f"/home/user/sandbox_{name}.sh"
        if os.path.lexists(wrapper):
            os.unlink(wrapper)

    completed = subprocess.run(
        ["python3", "/home/user/audit.py"],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"audit.py failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def load_report():
    assert os.path.isfile(REPORT_PATH), f"Audit report not found at {REPORT_PATH}"
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")


def expected_results():
    results = {}
    for entry in os.scandir(BIN_DIR):
        if entry.is_file():
            results[entry.name] = analyze_file(entry.path)
    return results


def test_audit_report_exists_and_valid():
    report_data = load_report()
    assert isinstance(report_data, list), "Audit report must be a JSON array."

    filenames = [item.get("filename") for item in report_data]
    assert filenames == sorted(filenames), "Audit report must be sorted alphabetically by filename."

    original_expected_results = {
        "app1": False,
        "app2": True,
        "app3": False,
    }

    found_files = {}
    for item in report_data:
        assert "filename" in item, "Missing 'filename' key in report item."
        assert "uses_insecure_gets" in item, "Missing 'uses_insecure_gets' key in report item."
        assert set(item.keys()) == {"filename", "uses_insecure_gets"}, "Report items must have exactly the required keys."
        assert isinstance(item["filename"], str), "filename must be a string."
        assert type(item["uses_insecure_gets"]) is bool, "uses_insecure_gets must be a boolean."
        assert item["filename"] not in found_files, f"Duplicate report entry for {item['filename']}"
        found_files[item["filename"]] = item["uses_insecure_gets"]

    for filename, expected_flag in original_expected_results.items():
        assert filename in found_files, f"File {filename} missing from audit report."
        assert found_files[filename] is expected_flag, (
            f"Expected uses_insecure_gets for {filename} to be {expected_flag}, "
            f"got {found_files[filename]}"
        )

    dynamic_expected = expected_results()
    assert found_files == dynamic_expected, "The report must cover every current file and derive flags from ELF symbols."


def test_sandbox_script_app2_exists_and_executable():
    script_path = "/home/user/sandbox_app2.sh"
    assert os.path.isfile(script_path), f"Sandbox script not found at {script_path}"

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Sandbox script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "ulimit -c 0" in content, f"Sandbox script {script_path} must contain 'ulimit -c 0'."
    assert "env -i" in content, f"Sandbox script {script_path} must use 'env -i' to clear the environment."
    assert "app2" in content, f"Sandbox script {script_path} must execute the app2 binary."
    assert "$@" in content or "$*" in content, f"Sandbox script {script_path} must pass arguments to the binary."


def test_sandbox_scripts_not_created_for_safe_binaries():
    safe_scripts = [
        "/home/user/sandbox_app1.sh",
        "/home/user/sandbox_app3.sh",
        f"/home/user/sandbox_{NAMES['safe']}.sh",
        f"/home/user/sandbox_{NAMES['nonelf']}.sh",
    ]
    for script_path in safe_scripts:
        assert not os.path.exists(script_path), f"Sandbox script {script_path} should not exist for a safe binary."


def test_generated_wrapper_is_executable_and_enforces_required_behavior():
    script_path = f"/home/user/sandbox_{NAMES['vulnerable']}.sh"
    target_path = os.path.join(BIN_DIR, NAMES["vulnerable"])

    assert os.path.isfile(script_path), f"Sandbox script not found at {script_path}"
    assert os.stat(script_path).st_mode & stat.S_IXUSR, f"Sandbox script {script_path} is not executable."

    args = ["argument with spaces", "literal-*.?", "final"]
    completed = subprocess.run(
        [script_path] + args,
        cwd="/tmp",
        env={"LEAK_MARKER": "must-not-reach-target", "PATH": os.environ.get("PATH", "")},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"Generated wrapper failed. stdout={completed.stdout!r}, stderr={completed.stderr!r}"
    )
    expected_output = "clean=1 core=0 argc=3\n" + "".join(f"[{arg}]\n" for arg in args)
    assert completed.stdout == expected_output, (
        "Wrapper must execute the correct binary, clear the environment, disable core dumps, "
        "and preserve each argument exactly."
    )

    with open(script_path, "r") as f:
        content = f.read()
    assert "ulimit -c 0" in content
    assert "env -i" in content
    assert NAMES["vulnerable"] in content
    assert "$@" in content or "$*" in content
    assert target_path in content, "Wrapper must target the vulnerable binary in /home/user/binaries."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
