#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import os
import random
import shlex
import subprocess
import uuid

PROJECT_DIR = "/home/user/project"
RUNNER_SCRIPT = os.path.join(PROJECT_DIR, "ci_runner.sh")
REPORT_FILE = os.path.join(PROJECT_DIR, "ci_report.txt")
APP = os.path.join(PROJECT_DIR, "app")


def run_runner(executable, timeout=60):
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    return subprocess.run(
        [RUNNER_SCRIPT, executable],
        cwd="/tmp",
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


@contextlib.contextmanager
def instrument_tool(name):
    tool = os.path.join("/usr/bin", name)
    real = tool + ".verifier-real-" + uuid.uuid4().hex
    log = os.path.join("/tmp", name + "-" + uuid.uuid4().hex + ".log")
    os.replace(tool, real)
    wrapper = f'''#!/bin/bash
printf '%s\\n' "$PWD" > {shlex.quote(log)}
printf '%s\\n' "${{LD_LIBRARY_PATH-}}" >> {shlex.quote(log)}
printf '%s\\n' "$@" >> {shlex.quote(log)}
exec {shlex.quote(real)} "$@"
'''
    try:
        with open(tool, "w") as f:
            f.write(wrapper)
        os.chmod(tool, 0o755)
        yield log
    finally:
        try:
            os.remove(tool)
        except FileNotFoundError:
            pass
        os.replace(real, tool)
        try:
            os.remove(log)
        except FileNotFoundError:
            pass


def read_tool_log(path):
    assert os.path.isfile(path), f"Expected instrumented tool to be invoked; no log at {path}"
    with open(path) as f:
        return f.read().splitlines()


def assert_project_on_library_path(cwd, value):
    entries = value.split(":")
    resolved = [os.path.abspath(os.path.join(cwd, entry or ".")) for entry in entries]
    assert PROJECT_DIR in resolved, (
        f"LD_LIBRARY_PATH did not contain the project directory: {value!r} (cwd={cwd!r})"
    )


def report_lines():
    assert os.path.isfile(REPORT_FILE), f"The report file {REPORT_FILE} does not exist."
    with open(REPORT_FILE, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_runner_script_exists_and_executable():
    assert os.path.isfile(RUNNER_SCRIPT), f"The script {RUNNER_SCRIPT} does not exist."
    assert os.access(RUNNER_SCRIPT, os.X_OK), f"The script {RUNNER_SCRIPT} is not executable."


def test_runner_script_no_args_exit_code():
    result = subprocess.run([RUNNER_SCRIPT], capture_output=True)
    assert result.returncode == 1, f"Expected exit code 1 when no arguments are provided, got {result.returncode}."


def test_runner_script_invalid_executable_exit_code():
    dummy_file = os.path.join(PROJECT_DIR, "dummy.txt")
    with open(dummy_file, "w") as f:
        f.write("test")
    try:
        result = subprocess.run([RUNNER_SCRIPT, dummy_file], capture_output=True)
        assert result.returncode == 1, f"Expected exit code 1 when argument is not executable, got {result.returncode}."
    finally:
        os.remove(dummy_file)


def test_runner_script_rejects_extra_arguments():
    result = subprocess.run([RUNNER_SCRIPT, APP, APP], capture_output=True)
    assert result.returncode == 1, f"Expected exit code 1 when more than one argument is provided, got {result.returncode}."


def test_runner_executes_real_app_with_make_valgrind_and_linking_environment():
    try:
        os.remove(REPORT_FILE)
    except FileNotFoundError:
        pass

    with instrument_tool("make") as make_log, instrument_tool("valgrind") as valgrind_log:
        result = run_runner(APP)
        assert result.returncode == 0, (
            f"Runner failed for app with status {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        make_data = read_tool_log(make_log)
        assert make_data and os.path.abspath(make_data[0]) == PROJECT_DIR, (
            f"make was not run in {PROJECT_DIR}; recorded cwd was {make_data[0] if make_data else None!r}"
        )

        valgrind_data = read_tool_log(valgrind_log)
        assert len(valgrind_data) >= 3, "Valgrind invocation log was incomplete."
        vg_cwd, vg_library_path, *vg_args = valgrind_data
        assert "--leak-check=full" in vg_args, (
            f"Valgrind was not invoked with --leak-check=full; arguments were {vg_args!r}"
        )
        assert_project_on_library_path(vg_cwd, vg_library_path)

    assert report_lines() == ["LINKING: SUCCESS", "LEAKED_BYTES: 128"]


def test_ci_report_content():
    assert os.path.isfile(REPORT_FILE), f"The report file {REPORT_FILE} does not exist."

    with open(REPORT_FILE, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {REPORT_FILE}, got {len(lines)}."
    assert lines[0] == "LINKING: SUCCESS", f"Expected first line to be 'LINKING: SUCCESS', got '{lines[0]}'."
    assert lines[1] == "LEAKED_BYTES: 128", f"Expected second line to be 'LEAKED_BYTES: 128', got '{lines[1]}'."


def test_report_is_parsed_for_the_provided_executable():
    token = uuid.uuid4().hex
    stem = "probe_" + token
    lib_source = os.path.join("/tmp", stem + ".c")
    app_source = os.path.join("/tmp", stem + "_main.c")
    library = os.path.join(PROJECT_DIR, "lib" + stem + ".so")
    executable = os.path.join(PROJECT_DIR, stem)
    leaked = random.SystemRandom().randint(257, 733)

    with open(lib_source, "w") as f:
        f.write(
            "#include <stdlib.h>\n"
            "void verifier_leak(void) {\n"
            f"    void *p = malloc({leaked});\n"
            "    __asm__ __volatile__(\"\" : : \"r\"(p) : \"memory\");\n"
            "}\n"
        )
    with open(app_source, "w") as f:
        f.write("void verifier_leak(void);\nint main(void) { verifier_leak(); return 0; }\n")

    try:
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", library, lib_source],
            check=True,
            capture_output=True,
            text=True,
        )
        subprocess.run(
            ["gcc", "-o", executable, app_source, "-L" + PROJECT_DIR, "-l" + stem],
            check=True,
            capture_output=True,
            text=True,
        )

        try:
            os.remove(REPORT_FILE)
        except FileNotFoundError:
            pass

        with instrument_tool("make") as make_log, instrument_tool("valgrind") as valgrind_log:
            result = run_runner(executable)
            assert result.returncode == 0, (
                f"Runner failed for generated executable with status {result.returncode}.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            make_data = read_tool_log(make_log)
            assert make_data and os.path.abspath(make_data[0]) == PROJECT_DIR
            valgrind_data = read_tool_log(valgrind_log)
            assert len(valgrind_data) >= 3
            vg_cwd, vg_library_path, *vg_args = valgrind_data
            assert "--leak-check=full" in vg_args
            assert_project_on_library_path(vg_cwd, vg_library_path)

        assert report_lines() == ["LINKING: SUCCESS", f"LEAKED_BYTES: {leaked}"], (
            "The report was not regenerated from Valgrind output for the provided executable."
        )
    finally:
        for path in (lib_source, app_source, library, executable):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
