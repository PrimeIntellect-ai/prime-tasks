#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import shutil
import subprocess
import sys


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, timeout=120, **kwargs)


def test_setup_py_fixed():
    setup_path = "/home/user/data_processor/setup.py"
    assert os.path.isfile(setup_path), f"Missing file: {setup_path}"
    with open(setup_path, "r") as f:
        content = f.read()
    assert "data_processor/fast_hash.c" in content, "setup.py was not updated to point to the correct C source file."


def test_c_extension_built_and_works():
    project = "/home/user/data_processor"
    ext_dir = os.path.join(project, "data_processor")
    assert os.path.isdir(ext_dir), f"Directory not found: {ext_dir}"

    # Preserve the original assertion that the requested in-place build was done.
    so_files = glob.glob(os.path.join(ext_dir, "fast_hash*.so"))
    assert len(so_files) > 0, "C-extension .so file not found in /home/user/data_processor/data_processor/. Did you build it in-place?"

    # Remove submitted artifacts and prove setup.py conditionally performs a real build.
    for path in so_files:
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    shutil.rmtree(os.path.join(project, "build"), ignore_errors=True)

    env = os.environ.copy()
    env.pop("USE_C_EXT", None)
    without_ext = run([sys.executable, "setup.py", "build_ext", "--inplace"], cwd=project, env=env)
    assert without_ext.returncode == 0, without_ext.stdout + "\n" + without_ext.stderr
    assert not glob.glob(os.path.join(ext_dir, "fast_hash*.so")), \
        "The C extension was built even though USE_C_EXT was not set to 1."

    env["USE_C_EXT"] = "1"
    with_ext = run([sys.executable, "setup.py", "build_ext", "--inplace"], cwd=project, env=env)
    assert with_ext.returncode == 0, with_ext.stdout + "\n" + with_ext.stderr

    built = glob.glob(os.path.join(ext_dir, "fast_hash*.so"))
    assert built, "USE_C_EXT=1 did not build fast_hash in-place."
    for path in built:
        assert os.path.isfile(path) and not os.path.islink(path), f"Not a real extension file: {path}"
        with open(path, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"Built artifact is not an ELF shared object: {path}"

    probe = run(
        [sys.executable, "-c",
         "from data_processor import fast_hash; "
         "assert fast_hash.__file__.endswith('.so'); "
         "assert fast_hash.compute('probe') == 'fast_hash_probe'; "
         "print(fast_hash.__file__)"],
        cwd=project,
        env=env,
    )
    assert probe.returncode == 0, "The built extension cannot be imported or executed:\n" + probe.stdout + probe.stderr
    assert os.path.realpath(probe.stdout.strip()).startswith(os.path.realpath(ext_dir) + os.sep)


def test_download_fixtures_script():
    script_path = "/home/user/data_processor/scripts/download_fixtures.sh"
    assert os.path.isfile(script_path), f"Missing file: {script_path}"
    script_dir = os.path.dirname(script_path)

    # Preserve the original success-case assertion.
    result = run(["bash", script_path], cwd=script_dir)
    assert result.returncode == 0, \
        f"Script failed with exit code {result.returncode}. Output: {result.stdout}\n{result.stderr}"

    # BASH_ENV installs a DEBUG trap which corrupts the provided checksum after
    # the script creates it but before its next command. A correct verifier must
    # detect this mismatch and exit with the specifically requested status 1.
    bash_env = "/tmp/checksum_mismatch_env.sh"
    with open(bash_env, "w") as f:
        f.write(r'''_force_bad_fixture_checksum() {
    if [[ -f fixture.dat.sha256 ]]; then
        printf '%064d  fixture.dat\n' 0 > fixture.dat.sha256
    fi
}
trap _force_bad_fixture_checksum DEBUG
''')
    env = os.environ.copy()
    env["BASH_ENV"] = bash_env
    mismatch = run(["bash", script_path], cwd=script_dir, env=env)
    assert mismatch.returncode == 1, \
        "The checksum script did not exit 1 when fixture.dat.sha256 was made incorrect. " \
        f"Exit: {mismatch.returncode}\nOutput: {mismatch.stdout}\n{mismatch.stderr}"


def test_utils_refactored():
    utils_path = "/home/user/data_processor/data_processor/utils.py"
    assert os.path.isfile(utils_path), f"Missing file: {utils_path}"
    with open(utils_path, "r") as f:
        content = f.read()

    assert "def get_mode" in content, "utils.py does not define a get_mode() function."
    assert "MODE =" not in content, "utils.py still contains the module-level MODE constant."

    project = "/home/user/data_processor"
    probe = run(
        [sys.executable, "-c", r'''
from data_processor import config
config.SETTINGS["mode"] = "local"
from data_processor import utils
assert callable(utils.get_mode)
assert utils.get_mode() == "local"
config.init_ci()
assert utils.get_mode() == "ci"
config.SETTINGS["mode"] = "local"
assert utils.get_mode() == "local"
'''],
        cwd=project,
    )
    assert probe.returncode == 0, \
        "get_mode() does not read the current configuration dynamically:\n" + probe.stdout + probe.stderr


def test_test_processing_refactored():
    test_path = "/home/user/data_processor/tests/test_processing.py"
    assert os.path.isfile(test_path), f"Missing file: {test_path}"
    with open(test_path, "r") as f:
        content = f.read()

    assert "get_mode" in content, "test_processing.py does not call get_mode()."
    assert "pytest.fixture" in content or "fixture" in content, \
        "test_processing.py does not use a pytest fixture as requested."


def test_test_results_log_and_real_suite():
    log_path = "/home/user/test_results.txt"
    assert os.path.isfile(log_path), f"Missing file: {log_path}. Did you run pytest and save the output?"
    with open(log_path, "r") as f:
        content = f.read()

    # Preserve the original log assertions.
    assert re.search(r'\bpassed\b', content.lower()), "test_results.txt does not indicate that tests passed."
    assert "failed" not in content.lower() or "0 failed" in content.lower(), \
        "test_results.txt indicates there are test failures."

    # Do not trust the submitted log: execute the requested suite now.
    result = run(
        [sys.executable, "-m", "pytest", "/home/user/data_processor/tests/"],
        cwd="/home/user/data_processor",
    )
    assert result.returncode == 0, \
        "The actual project test suite fails:\n" + result.stdout + "\n" + result.stderr
    assert re.search(r'\bpassed\b', (result.stdout + result.stderr).lower()), \
        "Pytest did not report any passing tests."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
