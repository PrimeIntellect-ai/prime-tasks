#!/bin/bash
mkdir -p /logs/verifier || true

if (
    set -e

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import tarfile

def test_incremental_archive_exists():
    archive_path = "/home/user/incremental.tar.gz"
    assert os.path.isfile(archive_path), f"The incremental archive was not found at {archive_path}"

def test_incremental_archive_contents():
    archive_path = "/home/user/incremental.tar.gz"
    assert tarfile.is_tarfile(archive_path), f"The file at {archive_path} is not a valid tar archive."

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()

        # Ensure files are not nested in directories
        filenames = [m.name for m in members if m.isfile()]

        # Check expected files
        assert "app.conf" in filenames, "app.conf is missing from the incremental archive."
        assert "cache.conf" in filenames, "cache.conf is missing from the incremental archive."

        # Check unexpected files
        assert "db.conf" not in filenames, "db.conf should not be in the incremental archive (it was unchanged)."
        assert "log.conf" not in filenames, "log.conf should not be in the incremental archive (it was unchanged)."

        # Check that there are exactly 2 files
        assert len(filenames) == 2, f"Expected exactly 2 files in the archive, but found {len(filenames)}: {filenames}"

        # Verify contents
        app_conf_member = tar.getmember("app.conf")
        app_conf_f = tar.extractfile(app_conf_member)
        assert app_conf_f is not None, "Failed to extract app.conf"
        app_content = app_conf_f.read().decode("utf-8")
        assert app_content == "theme=light\n", f"Incorrect content in app.conf. Expected 'theme=light\\n', got {app_content!r}"

        cache_conf_member = tar.getmember("cache.conf")
        cache_conf_f = tar.extractfile(cache_conf_member)
        assert cache_conf_f is not None, "Failed to extract cache.conf"
        cache_content = cache_conf_f.read().decode("utf-8")
        assert cache_content == "size=1024\n", f"Incorrect content in cache.conf. Expected 'size=1024\\n', got {cache_content!r}"
TEST_EOF

    # Preserve all checks against the archive produced by the agent.
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

    # Require a real Rust source file and compile it from a clean target directory.
    test -f /home/user/config_manager/src/main.rs
    test -s /home/user/config_manager/src/main.rs
    cd /home/user/config_manager
    cargo clean
    cargo build
    test -x /home/user/config_manager/target/debug/config_manager

    # Generate unpredictable fixtures after compilation, execute the compiled
    # artifact, and derive the expected differential archive from those inputs.
    python3 << 'DYNAMIC_EOF'
import io
import os
import secrets
import shutil
import subprocess
import tarfile

base_path = "/home/user/base_config.tar.gz"
config_dir = "/home/user/configs"
output_path = "/home/user/incremental.tar.gz"
binary = "/home/user/config_manager/target/debug/config_manager"

token = secrets.token_hex(8)
names = {
    "unchanged": f"unchanged_{token}.conf",
    "modified": f"modified_{token}.conf",
    "new": f"new_{token}.conf",
    "base_only": f"base_only_{token}.conf",
}
base_files = {
    names["unchanged"]: f"same-{token}\n".encode(),
    names["modified"]: f"old-{token}\n".encode(),
    names["base_only"]: f"base-only-{token}\n".encode(),
}
config_files = {
    names["unchanged"]: base_files[names["unchanged"]],
    names["modified"]: f"changed-{token}\n".encode(),
    names["new"]: f"new-content-{token}\n".encode(),
}

shutil.rmtree(config_dir, ignore_errors=True)
os.makedirs(config_dir)
for name, data in config_files.items():
    with open(os.path.join(config_dir, name), "wb") as f:
        f.write(data)

with tarfile.open(base_path, "w:gz") as tar:
    for name, data in base_files.items():
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mode = 0o644
        tar.addfile(info, io.BytesIO(data))

expected = {
    name: data
    for name, data in config_files.items()
    if name not in base_files or base_files[name] != data
}

if os.path.lexists(output_path):
    os.remove(output_path)
subprocess.run([binary], cwd="/home/user/config_manager", check=True, timeout=30)

assert os.path.isfile(output_path), "The compiled program did not create incremental.tar.gz"
with tarfile.open(output_path, "r:gz") as tar:
    members = tar.getmembers()
    assert all(m.isfile() for m in members), "The incremental archive contains non-file entries"
    names_in_archive = [m.name for m in members]
    assert all("/" not in name and name not in (".", "..") for name in names_in_archive), \
        f"Archive entries must not be nested: {names_in_archive}"
    assert sorted(names_in_archive) == sorted(expected), \
        f"Expected exactly {sorted(expected)}, found {sorted(names_in_archive)}"
    for member in members:
        extracted = tar.extractfile(member)
        assert extracted is not None, f"Could not extract {member.name}"
        actual = extracted.read()
        assert actual == expected[member.name], \
            f"Incorrect bytes for {member.name}: expected {expected[member.name]!r}, got {actual!r}"

# Ensure the program did not obtain a passing result by changing its inputs.
for name, data in config_files.items():
    with open(os.path.join(config_dir, name), "rb") as f:
        assert f.read() == data, f"The program modified input file {name}"
DYNAMIC_EOF
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
