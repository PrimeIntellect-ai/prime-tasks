#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import textwrap

PROJECT = "/home/user/project"
BUILD = PROJECT + "/build"
RUN_SH = "/home/user/run.sh"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 120)
    return subprocess.run(cmd, **kwargs)


def test_01_run_sh_exists_and_executable():
    assert os.path.isfile(RUN_SH), f"{RUN_SH} does not exist."
    assert os.access(RUN_SH, os.X_OK), f"{RUN_SH} is not executable."


def test_02_run_sh_really_builds_and_runs_project():
    # A clean build directory ensures run.sh cannot rely on a prebuilt artifact.
    subprocess.run(["rm", "-rf", BUILD], check=True)
    result = run(["su", "-", "user", "-c", RUN_SH])
    assert result.returncode == 0, (
        f"run.sh failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert "All tests passed." in result.stdout, (
        "The output did not contain 'All tests passed.' indicating the test didn't succeed."
    )

    binary = BUILD + "/migrator_test"
    assert os.path.isfile(BUILD + "/CMakeCache.txt"), "run.sh did not configure the clean build directory with CMake."
    assert os.path.isfile(binary), "run.sh did not produce build/migrator_test."
    assert os.access(binary, os.X_OK), "build/migrator_test is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "build/migrator_test is not an ELF executable."

    dynamic = run(["readelf", "-d", binary])
    assert dynamic.returncode == 0, dynamic.stderr
    assert re.search(r"Shared library: \[libencoder\.so(?:\.[^]]*)?\]", dynamic.stdout), (
        "migrator_test does not have a dynamic dependency on libencoder.so."
    )

    ldd = run(["ldd", binary])
    assert ldd.returncode == 0, ldd.stderr
    encoder_lines = [line for line in ldd.stdout.splitlines() if "libencoder.so" in line]
    assert encoder_lines and "not found" not in encoder_lines[0], "libencoder.so cannot be resolved at runtime."
    assert PROJECT in encoder_lines[0], "libencoder.so is not being resolved from within the project."

    # Run the actual freshly built binary directly, from build, without an
    # LD_LIBRARY_PATH supplied by the verifier or run.sh.
    direct = run(
        ["env", "-u", "LD_LIBRARY_PATH", "./migrator_test"],
        cwd=BUILD,
    )
    assert direct.returncode == 0, (
        f"The actual migrator_test failed when run directly from build.\n"
        f"Stdout: {direct.stdout}\nStderr: {direct.stderr}"
    )
    assert 'Migrated: {"id":42,"name":"Test"}' in direct.stdout
    assert "All tests passed." in direct.stdout


def test_03_cmake_lists_fixed():
    cmake_path = PROJECT + "/CMakeLists.txt"
    assert os.path.isfile(cmake_path), f"{cmake_path} is missing."
    with open(cmake_path, "r") as f:
        content = f.read()
    assert "target_link_libraries(" in content and "migrator_test" in content and "encoder" in content, \
        "CMakeLists.txt does not appear to link migrator_test to the encoder library."


def test_04_memory_safety_bug_fixed():
    migrator_cpp_path = PROJECT + "/src/migrator.cpp"
    assert os.path.isfile(migrator_cpp_path), f"{migrator_cpp_path} is missing."
    with open(migrator_cpp_path, "r") as f:
        content = f.read()
    bad_allocation = "new char[record.name_len];"
    assert bad_allocation not in content.replace(" ", ""), \
        "The out-of-bounds memory allocation bug is still present in migrator.cpp."


def test_05_mock_data_fixed():
    test_migrator_path = PROJECT + "/test/test_migrator.cpp"
    assert os.path.isfile(test_migrator_path), f"{test_migrator_path} is missing."
    with open(test_migrator_path, "r") as f:
        content = f.read()
    assert 'T' in content and 'e' in content and 's' in content and 't' in content, \
        "test_migrator.cpp does not appear to initialize the mock data with the string 'Test'."


def test_06_fixture_and_migrator_behavior_under_asan():
    # Compile an independent harness around the submitted fixture and production
    # sources. ASan makes the original one-byte out-of-bounds write deterministic.
    harness = "/tmp/migrator_verifier.cpp"
    with open(harness, "w") as f:
        f.write(textwrap.dedent(r'''
            #define main submitted_test_main
            #include "/home/user/project/test/test_migrator.cpp"
            #undef main
            #include <cstdint>
            #include <iostream>
            #include <string>
            #include <vector>

            static std::string expected(uint32_t id, const std::vector<uint16_t>& name) {
                std::string ascii;
                for (uint16_t c : name) ascii.push_back(static_cast<char>(c & 0xff));
                return "{\"id\":" + std::to_string(id) + ",\"name\":\"" + ascii + "\"}";
            }

            int main() {
                const std::vector<uint16_t> fixture = setup_mock_data();
                const std::vector<uint16_t> required = {0x0054, 0x0065, 0x0073, 0x0074};
                if (fixture != required) {
                    std::cerr << "setup_mock_data did not return UTF-16 LE code units for Test\n";
                    return 10;
                }

                const std::vector<std::vector<uint16_t>> names = {
                    {}, {0x0041}, {0x0053, 0x0063, 0x0068, 0x0065, 0x006d, 0x0061},
                    {0x0078, 0x0079, 0x007a, 0x0031, 0x0032, 0x0033}
                };
                uint32_t id = 137;
                for (const auto& name : names) {
                    LegacyRecord rec{id, static_cast<uint16_t>(name.size()), name.data()};
                    const std::string actual = migrate_record(rec);
                    const std::string want = expected(id, name);
                    if (actual != want) {
                        std::cerr << "wrong migration: " << actual << " expected " << want << "\n";
                        return 11;
                    }
                    id = id * 7 + 3;
                }
                return 0;
            }
        '''))

    output = "/tmp/migrator_verifier"
    compile_result = run([
        "g++", "-std=c++17", "-O0", "-g",
        "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
        "-I" + PROJECT + "/include",
        harness, PROJECT + "/src/migrator.cpp", PROJECT + "/src/encoder.cpp",
        "-o", output,
    ])
    assert compile_result.returncode == 0, (
        f"Independent safety harness failed to compile.\n"
        f"Stdout: {compile_result.stdout}\nStderr: {compile_result.stderr}"
    )
    checked = run(
        [output],
        env={**os.environ, "ASAN_OPTIONS": "halt_on_error=1:abort_on_error=1:detect_leaks=1"},
    )
    assert checked.returncode == 0, (
        f"Fixture or migrate_record failed independent behavioral/safety checks.\n"
        f"Stdout: {checked.stdout}\nStderr: {checked.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
