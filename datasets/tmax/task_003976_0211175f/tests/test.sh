#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import subprocess
import uuid


def test_processed_docs_directory_exists():
    assert os.path.isdir("/home/user/processed_docs"), "The /home/user/processed_docs/ directory does not exist."


def test_module_files_content():
    expected_contents = {
        "module_01.md": "Content of Alpha",
        "module_02.md": "Content of Beta",
        "module_03.md": "Content of Delta",
        "module_04.md": "Content of Gamma"
    }

    for filename, expected_text in expected_contents.items():
        filepath = os.path.join("/home/user/processed_docs", filename)
        assert os.path.isfile(filepath), f"File {filename} is missing in /home/user/processed_docs/."
        with open(filepath, "r") as f:
            content = f.read()
        assert expected_text in content, f"File {filename} does not contain the expected text '{expected_text}'."


def test_symlink_current_module():
    symlink_path = "/home/user/processed_docs/current_module.md"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
    target = os.readlink(symlink_path)
    assert target.endswith("module_04.md"), f"Symlink {symlink_path} does not point to module_04.md. It points to {target}."


def test_index_file_content():
    index_path = "/home/user/processed_docs/index.txt"
    assert os.path.isfile(index_path), f"Index file {index_path} does not exist."

    with open(index_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "module_01.md",
        "module_02.md",
        "module_03.md",
        "module_04.md"
    ]
    assert lines == expected_lines, f"Index file content does not match expected sorted filenames. Got {lines}"


def test_cpp_program_exists_and_uses_rename():
    cpp_path = "/home/user/make_index.cpp"
    assert os.path.isfile(cpp_path), f"C++ program {cpp_path} does not exist."

    with open(cpp_path, "r") as f:
        content = f.read()

    assert "rename(" in content, "The C++ program does not appear to use the POSIX 'rename()' function for atomic writes."


def test_cpp_program_compiles_runs_and_atomically_renames_complete_index():
    docs = pathlib.Path("/home/user/processed_docs")
    cpp_path = pathlib.Path("/home/user/make_index.cpp")
    index_path = docs / "index.txt"
    token = uuid.uuid4().hex
    added_md = [docs / f"probe_{token}_z.md", docs / f"probe_{token}_a.md"]
    added_txt = docs / f"probe_{token}.txt"
    added_link = docs / f"probe_{token}_link.md"
    wrapper_path = pathlib.Path(f"/tmp/rename_wrapper_{token}.cpp")
    executable = pathlib.Path(f"/tmp/make_index_{token}")
    log_path = pathlib.Path(f"/tmp/rename_log_{token}")
    original_index = index_path.read_bytes() if index_path.exists() else None

    wrapper_path.write_text(r'''
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <filesystem>
#include <fstream>
#include <limits.h>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

extern "C" int __real_rename(const char *, const char *);

static std::vector<std::string> lines_of(const std::string &s) {
    std::vector<std::string> result;
    std::istringstream in(s);
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (!line.empty()) result.push_back(line);
    }
    return result;
}

static bool source_is_closed(const struct stat &wanted) {
    DIR *dir = opendir("/proc/self/fd");
    if (!dir) return false;
    bool closed = true;
    struct dirent *entry;
    while ((entry = readdir(dir)) != nullptr) {
        char *end = nullptr;
        long fd = std::strtol(entry->d_name, &end, 10);
        if (!end || *end != '\0' || fd < 0 || fd == dirfd(dir)) continue;
        struct stat current;
        if (fstat(static_cast<int>(fd), &current) == 0 &&
            current.st_dev == wanted.st_dev && current.st_ino == wanted.st_ino) {
            closed = false;
            break;
        }
    }
    closedir(dir);
    return closed;
}

extern "C" int __wrap_rename(const char *oldpath, const char *newpath) {
    bool valid = false;
    char resolved_old[PATH_MAX];
    struct stat source_stat;
    const char *expected_env = std::getenv("EXPECTED_INDEX");

    try {
        std::filesystem::path destination = std::filesystem::absolute(newpath).lexically_normal();
        if (destination == std::filesystem::path("/home/user/processed_docs/index.txt") &&
            realpath(oldpath, resolved_old) != nullptr &&
            lstat(resolved_old, &source_stat) == 0 && S_ISREG(source_stat.st_mode) &&
            std::filesystem::path(resolved_old).parent_path() == std::filesystem::path("/home/user/processed_docs") &&
            std::filesystem::path(resolved_old) != destination && expected_env) {
            std::ifstream input(resolved_old, std::ios::binary);
            std::ostringstream buffer;
            buffer << input.rdbuf();
            input.close();
            valid = lines_of(buffer.str()) == lines_of(expected_env) && source_is_closed(source_stat);
        }
    } catch (...) {
        valid = false;
    }

    int result = __real_rename(oldpath, newpath);
    if (valid && result == 0) {
        const char *log_path = std::getenv("ATOMIC_LOG");
        if (log_path) {
            std::ofstream log(log_path, std::ios::app);
            log << "OK\n";
        }
    }
    return result;
}
''')

    try:
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-O2", str(cpp_path), str(wrapper_path),
             "-Wl,--wrap=rename", "-o", str(executable)],
            text=True, capture_output=True, timeout=30
        )
        assert compile_result.returncode == 0, "C++ program failed to compile:\n" + compile_result.stdout + compile_result.stderr

        added_md[0].write_text("dynamic z\n")
        added_md[1].write_text("dynamic a\n")
        added_txt.write_text("not markdown\n")
        added_link.symlink_to(added_md[0].name)

        expected = sorted(
            entry.name for entry in os.scandir(docs)
            if entry.name.endswith(".md") and entry.is_file(follow_symlinks=False)
        )
        if index_path.exists():
            index_path.unlink()

        env = os.environ.copy()
        env["EXPECTED_INDEX"] = "\n".join(expected)
        env["ATOMIC_LOG"] = str(log_path)
        run_result = subprocess.run(
            [str(executable)], text=True, capture_output=True, timeout=30, env=env
        )
        assert run_result.returncode == 0, "Compiled C++ program failed when run:\n" + run_result.stdout + run_result.stderr
        assert index_path.is_file(), "Compiled C++ program did not create index.txt."
        actual = [line.strip() for line in index_path.read_text().splitlines() if line.strip()]
        assert actual == expected, f"Executed C++ program produced the wrong index. Got {actual}, expected {expected}."
        assert log_path.exists() and "OK" in log_path.read_text().splitlines(), (
            "The executed program did not rename a closed, complete temporary index file from the processed_docs directory to index.txt."
        )
    finally:
        for path in [added_link, *added_md, added_txt, executable, wrapper_path, log_path]:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        if original_index is None:
            try:
                index_path.unlink()
            except FileNotFoundError:
                pass
        else:
            index_path.write_bytes(original_index)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
