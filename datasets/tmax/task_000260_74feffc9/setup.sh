#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 binutils tar

    pip3 install pytest grpcio grpcio-tools hypothesis

    mkdir -p /home/user/

    cat << 'EOF' > /home/user/deps.proto
syntax = "proto3";
package deps;
service DependencyAnalyzer {
    rpc Analyze (AnalyzeRequest) returns (AnalyzeResponse);
}
message AnalyzeRequest {
    string binary_path = 1;
}
message AnalyzeResponse {
    repeated string shared_libraries = 1;
}
EOF

    cat << 'EOF' > /home/user/verify.py
import os
import subprocess

def test_bundle_list():
    assert os.path.exists('/home/user/bundle_list.txt'), "bundle_list.txt missing"
    with open('/home/user/bundle_list.txt', 'r') as f:
        paths = [line.strip() for line in f if line.strip()]

    assert '/usr/bin/sqlite3' in paths, "Missing main binary in bundle"

    # We expect basic libs like libc, libm
    has_libc = any('libc.so' in p for p in paths)
    has_libm = any('libm.so' in p for p in paths)
    assert has_libc, "Missing libc dependency"
    assert has_libm, "Missing libm dependency"

    # Check sorting
    assert paths == sorted(paths), "bundle_list.txt is not sorted alphabetically"

def test_tar_contents():
    assert os.path.exists('/home/user/minimal_sqlite3.tar'), "Tar archive missing"
    out = subprocess.check_output(['tar', '-tf', '/home/user/minimal_sqlite3.tar']).decode('utf-8').splitlines()

    # tar output might not have leading slash, or might. 
    # normalize paths to check if sqlite3 is present
    has_sqlite = any('usr/bin/sqlite3' in p for p in out)
    assert has_sqlite, "Tar archive missing sqlite3"

def test_pytest_hypothesis():
    assert os.path.exists('/home/user/test_server.py'), "test_server.py missing"
    try:
        subprocess.check_call(['pytest', '/home/user/test_server.py'])
    except subprocess.CalledProcessError:
        assert False, "Hypothesis tests failed"

if __name__ == '__main__':
    test_bundle_list()
    test_tar_contents()
    test_pytest_hypothesis()
    print("ALL CHECKS PASSED")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
