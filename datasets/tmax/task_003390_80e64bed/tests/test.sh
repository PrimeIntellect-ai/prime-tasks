#!/bin/bash
set -e
mkdir -p /logs/verifier

REAL_VALGRIND="/tmp/verifier-real-valgrind.$$"
VG_MARKER="/tmp/verifier-valgrind-args.$$"
VG_ENV_MARKER="/tmp/verifier-valgrind-env.$$"
VG_MODE="/tmp/verifier-valgrind-mode.$$"

mv /usr/bin/valgrind "$REAL_VALGRIND"
cat > /usr/bin/valgrind <<EOF
#!/bin/bash
printf '%s\\0' "\$@" > "$VG_MARKER"
printf '%s' "\${LD_LIBRARY_PATH-}" > "$VG_ENV_MARKER"
if [ -f "$VG_MODE" ]; then
    code=\$(cat "$VG_MODE")
    exit "\$code"
fi
exec "$REAL_VALGRIND" "\$@"
EOF
chmod 755 /usr/bin/valgrind

cleanup() {
    rm -f /usr/bin/valgrind "$VG_MARKER" "$VG_ENV_MARKER" "$VG_MODE"
    mv "$REAL_VALGRIND" /usr/bin/valgrind 2>/dev/null || true
}
trap cleanup EXIT

export VERIFIER_VG_MARKER="$VG_MARKER"
export VERIFIER_VG_ENV_MARKER="$VG_ENV_MARKER"
export VERIFIER_VG_MODE="$VG_MODE"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import time

PROJECT_DIR = "/home/user/project"
APP = os.path.join(PROJECT_DIR, "app")
LIB = os.path.join(PROJECT_DIR, "libdataparser.so")
SCRIPT = os.path.join(PROJECT_DIR, "run_tests.sh")
OUTPUT = os.path.join(PROJECT_DIR, "output.log")
MARKER = os.environ["VERIFIER_VG_MARKER"]
ENV_MARKER = os.environ["VERIFIER_VG_ENV_MARKER"]
MODE = os.environ["VERIFIER_VG_MODE"]


def run(cmd, **kwargs):
    return subprocess.run(cmd, cwd=PROJECT_DIR, capture_output=True, text=True,
                          timeout=30, **kwargs)


def assert_elf(path, executable=False):
    assert os.path.isfile(path), f"{path} was not built"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF binary"
    if executable:
        assert os.access(path, os.X_OK), f"{path} is not executable"


def marker_args():
    assert os.path.isfile(MARKER), "run_tests.sh did not invoke /usr/bin/valgrind"
    with open(MARKER, "rb") as f:
        return [x.decode() for x in f.read().split(b"\0") if x]


def path_points_to_project(value):
    for entry in value.split(":"):
        if not entry:
            continue
        resolved = os.path.realpath(os.path.join(PROJECT_DIR, entry) if not os.path.isabs(entry) else entry)
        if resolved == os.path.realpath(PROJECT_DIR):
            return True
    return False


def assert_valgrind_command(args, payload):
    assert "--leak-check=full" in args, "Valgrind was not passed --leak-check=full"
    assert "--error-exitcode=1" in args, "Valgrind was not passed --error-exitcode=1"

    command_index = next((i for i, arg in enumerate(args) if not arg.startswith("-")), None)
    assert command_index is not None, "Valgrind was not given a command"
    command = args[command_index]
    ld_from_env_command = None

    if os.path.basename(command) == "env":
        i = command_index + 1
        while i < len(args) and "=" in args[i]:
            name, value = args[i].split("=", 1)
            if name == "LD_LIBRARY_PATH":
                ld_from_env_command = value
            i += 1
        assert i < len(args), "env was not given the app command"
        command_index = i
        command = args[i]

    command_path = command if os.path.isabs(command) else os.path.join(PROJECT_DIR, command)
    assert os.path.realpath(command_path) == os.path.realpath(APP), \
        f"Valgrind ran {command!r} rather than the built app"
    assert command_index + 1 < len(args) and args[command_index + 1] == payload, \
        "The supplied payload was not passed to app under Valgrind"

    with open(ENV_MARKER) as f:
        inherited_ld = f.read()
    assert path_points_to_project(inherited_ld) or (ld_from_env_command and path_points_to_project(ld_from_env_command)), \
        "run_tests.sh did not put the project directory in LD_LIBRARY_PATH"


def test_makefile_builds_successfully_and_builds_real_linked_artifacts():
    subprocess.run(["make", "clean"], cwd=PROJECT_DIR, capture_output=True)
    for path in (APP, LIB):
        if os.path.lexists(path):
            os.remove(path)

    result = run(["make"])
    assert result.returncode == 0, f"Make failed with output:\n{result.stderr}\n{result.stdout}"
    assert_elf(LIB)
    assert_elf(APP, executable=True)

    symbols = run(["nm", "-D", LIB])
    assert symbols.returncode == 0
    assert re.search(r"\bparse_payload$", symbols.stdout, re.M), "shared library lacks parse_payload"
    assert re.search(r"\bfree_parsed_data$", symbols.stdout, re.M), "shared library lacks free_parsed_data"

    dynamic = run(["readelf", "-d", APP])
    assert dynamic.returncode == 0
    assert re.search(r"NEEDED.*\[libdataparser\.so\]", dynamic.stdout), \
        "app is not dynamically linked against libdataparser.so"

    old_lib = os.stat(LIB).st_mtime_ns
    old_app = os.stat(APP).st_mtime_ns
    time.sleep(1.1)
    os.utime(os.path.join(PROJECT_DIR, "libdataparser.c"), None)
    rebuilt = run(["make", "app"])
    assert rebuilt.returncode == 0, f"make app failed after library source changed:\n{rebuilt.stderr}"
    assert os.stat(LIB).st_mtime_ns > old_lib, "library was not rebuilt when its source changed"
    assert os.stat(APP).st_mtime_ns > old_app, "app target does not depend on the shared library"


def test_main_c_memory_leak_fixed_with_real_code():
    with open(os.path.join(PROJECT_DIR, "main.c")) as f:
        content = f.read()
    assert "free_parsed_data(" in content, "main.c does not seem to call free_parsed_data"
    without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", content, flags=re.S)
    assert re.search(r"\bfree_parsed_data\s*\(\s*data\s*\)\s*;", without_comments), \
        "main.c does not execute free_parsed_data(data)"


def test_run_tests_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), "run_tests.sh script is missing"
    assert os.access(SCRIPT, os.X_OK), "run_tests.sh script is not executable"


def test_run_tests_script_behavior_on_derived_payload_under_real_valgrind():
    for path in (OUTPUT, MARKER, ENV_MARKER, MODE):
        if os.path.exists(path):
            os.remove(path)

    pairs = [("k" + secrets.token_hex(4), "v" + secrets.token_hex(6)) for _ in range(4)]
    payload = ",".join(f"{key}:{value}" for key, value in pairs)
    expected = "\n".join(f"Key: {key} | Value: {value}" for key, value in pairs)

    result = run([SCRIPT, payload])
    assert result.returncode == 0, \
        f"run_tests.sh failed under Valgrind. stderr:\n{result.stderr}\nstdout:\n{result.stdout}"
    assert os.path.isfile(OUTPUT), "output.log was not created"
    with open(OUTPUT) as f:
        assert f.read().strip() == expected, "output.log does not contain app's derived expected output"

    assert_valgrind_command(marker_args(), payload)


def test_runner_accepts_exactly_one_argument():
    no_args = run([SCRIPT])
    assert no_args.returncode != 0, "run_tests.sh accepted zero arguments"
    two_args = run([SCRIPT, "a:b", "c:d"])
    assert two_args.returncode != 0, "run_tests.sh accepted more than one argument"


def test_runner_returns_exact_valgrind_exit_code():
    for path in (MARKER, ENV_MARKER):
        if os.path.exists(path):
            os.remove(path)
    with open(MODE, "w") as f:
        f.write("37")
    payload = "forced:status"
    try:
        result = run([SCRIPT, payload])
    finally:
        os.remove(MODE)
    assert result.returncode == 37, \
        f"run_tests.sh returned {result.returncode}, not Valgrind's exact exit code 37"
    assert_valgrind_command(marker_args(), payload)


def test_run_tests_script_contents():
    with open(SCRIPT) as f:
        content = f.read()
    assert "valgrind" in content, "run_tests.sh does not use valgrind"
    assert "--leak-check=full" in content, "run_tests.sh does not use --leak-check=full"
    assert "--error-exitcode=1" in content, "run_tests.sh does not use --error-exitcode=1"
    assert "output.log" in content, "run_tests.sh does not redirect to output.log"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
