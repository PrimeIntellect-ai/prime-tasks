#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import shutil
import stat
import subprocess
import tarfile
import tempfile

CPP = "/home/user/provisioner.cpp"
SCRIPT = "/home/user/ci_pipeline.sh"
BINARY = "/home/user/provisioner"
TARGET = "/home/user/target_env"
TARBALL = "/home/user/release.tar.gz"


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def clean_pipeline_outputs():
    for path in (BINARY, TARGET, TARBALL):
        if os.path.lexists(path):
            remove_path(path)


def run_pipeline(command):
    env = os.environ.copy()
    env.pop("PROVISION_TARGET_DIR", None)
    return subprocess.run(
        command,
        cwd="/home/user",
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )


def test_provisioner_cpp_exists():
    assert os.path.isfile(CPP), f"{CPP} does not exist"


def test_provisioner_cpp_logic():
    compile_result = subprocess.run(
        ["g++", CPP, "-o", "/tmp/test_prov"],
        capture_output=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, f"Compilation failed: {compile_result.stderr.decode()}"

    env = os.environ.copy()
    env.pop("PROVISION_TARGET_DIR", None)
    run_no_env = subprocess.run(["/tmp/test_prov"], env=env, capture_output=True, timeout=10)
    assert run_no_env.returncode != 0, "Program should exit with non-zero code when PROVISION_TARGET_DIR is not set"

    test_dir = tempfile.mkdtemp(prefix="provisioner-target-")
    env["PROVISION_TARGET_DIR"] = test_dir
    run_with_env = subprocess.run(["/tmp/test_prov"], env=env, capture_output=True, timeout=10)
    assert run_with_env.returncode == 0, "Program should exit with 0 when PROVISION_TARGET_DIR is set"

    status_file = os.path.join(test_dir, "status.txt")
    assert os.path.isfile(status_file), "status.txt was not created in the target directory"
    with open(status_file, "r") as f:
        content = f.read()
    assert content == "SUCCESS\n", f"status.txt content is incorrect. Expected 'SUCCESS\\n', got {content!r}"


def test_ci_pipeline_script_and_execution():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist"
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SCRIPT} is not executable"

    # Execute the submitted script itself from a clean state, with no inherited
    # provisioning variable, so pre-fabricated artifacts cannot satisfy the test.
    clean_pipeline_outputs()
    direct = run_pipeline([SCRIPT])
    assert direct.returncode == 0, f"Pipeline failed when executed directly:\nstdout:\n{direct.stdout}\nstderr:\n{direct.stderr}"

    for path in (BINARY, TARGET, TARBALL):
        assert os.path.exists(path), f"Pipeline did not generate {path}"

    # Run cleanly under bash tracing as well, and verify that the requested build
    # operations were actually executed in their required order.
    clean_pipeline_outputs()
    traced = run_pipeline(["bash", "-x", SCRIPT])
    assert traced.returncode == 0, f"Pipeline failed under tracing:\nstdout:\n{traced.stdout}\nstderr:\n{traced.stderr}"

    commands = []
    for line in traced.stderr.splitlines():
        stripped = line.lstrip("+ ")
        if not stripped:
            continue
        try:
            commands.append(shlex.split(stripped))
        except ValueError:
            continue

    def command_name(tokens):
        return os.path.basename(tokens[0]) if tokens else ""

    def first_index(predicate, description):
        for i, tokens in enumerate(commands):
            if predicate(tokens):
                return i
        raise AssertionError(f"Pipeline trace did not show the required {description}")

    compile_i = first_index(
        lambda t: command_name(t) == "g++" and CPP in t and any(
            arg == BINARY or arg == "-o" + BINARY for arg in t
        ) and ("-o" in t or any(arg == "-o" + BINARY for arg in t)),
        "g++ compilation of provisioner.cpp to /home/user/provisioner",
    )
    mkdir_i = first_index(
        lambda t: command_name(t) == "mkdir" and TARGET in t,
        "creation of /home/user/target_env",
    )
    export_i = first_index(
        lambda t: command_name(t) == "export" and any(
            arg == "PROVISION_TARGET_DIR=/home/user/target_env" for arg in t[1:]
        ),
        "export of PROVISION_TARGET_DIR=/home/user/target_env",
    )
    execute_i = first_index(
        lambda t: bool(t) and t[0] == BINARY,
        "execution of /home/user/provisioner",
    )
    tar_i = first_index(
        lambda t: command_name(t) == "tar"
        and any(os.path.basename(arg) == "release.tar.gz" for arg in t[1:])
        and any(os.path.basename(arg.rstrip("/")) == "provisioner" for arg in t[1:]),
        "creation of release.tar.gz from provisioner",
    )
    assert compile_i < mkdir_i < export_i < execute_i < tar_i, (
        "Pipeline steps were not executed in the required order: compile, mkdir, "
        "export, execute, tar"
    )


def test_pipeline_results():
    assert os.path.isfile(BINARY), f"{BINARY} executable does not exist"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable"
    assert os.path.isdir(TARGET), f"{TARGET} directory does not exist"

    status_path = os.path.join(TARGET, "status.txt")
    assert os.path.isfile(status_path), f"{status_path} does not exist"
    with open(status_path, "r") as f:
        assert f.read() == "SUCCESS\n", f"{status_path} does not contain exactly 'SUCCESS\\n'"

    # Exercise the binary generated by the pipeline on a verifier-chosen target.
    fresh_target = tempfile.mkdtemp(prefix="pipeline-binary-target-")
    env = os.environ.copy()
    env["PROVISION_TARGET_DIR"] = fresh_target
    result = subprocess.run([BINARY], env=env, capture_output=True, timeout=10)
    assert result.returncode == 0, "Pipeline-generated provisioner failed on a fresh target"
    with open(os.path.join(fresh_target, "status.txt"), "rb") as f:
        assert f.read() == b"SUCCESS\n"


def test_release_tarball():
    assert os.path.isfile(TARBALL), f"{TARBALL} does not exist"
    with tarfile.open(TARBALL, "r:gz") as tar:
        members = tar.getmembers()
        names = tar.getnames()
        assert len(names) == 1, f"Tarball should contain exactly 1 file, found {len(names)}: {names}"
        assert names[0] in ["provisioner", "./provisioner"], f"Tarball contains incorrect file: {names[0]}"
        assert members[0].isfile(), "The sole tarball member must be a regular file"
        archived = tar.extractfile(members[0])
        assert archived is not None
        archived_bytes = archived.read()
    with open(BINARY, "rb") as f:
        binary_bytes = f.read()
    assert archived_bytes == binary_bytes, "Tarball's provisioner does not match /home/user/provisioner"


def test_bashrc_configuration():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist"
    with open(bashrc_path, "r") as f:
        lines = f.read().splitlines()
    assert lines and lines[-1] == "export PROVISION_ENV_MODE=production", (
        "/home/user/.bashrc must end with the exact line "
        "'export PROVISION_ENV_MODE=production'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
