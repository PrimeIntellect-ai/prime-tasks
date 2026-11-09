#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sec_suite

    cat << 'EOF' > /home/user/sec_suite/utils.sh
# Buggy compare_versions
compare_versions() {
    if [[ "$1" == "$2" ]]; then echo 0;
    elif [[ "$1" > "$2" ]]; then echo 1;
    else echo -1; fi
}

# Incomplete generate_fuzz_length
generate_fuzz_length() {
    echo 0
}
EOF

    cat << 'EOF' > /home/user/sec_suite/auth_tests.sh
source /home/user/sec_suite/utils.sh
source /home/user/sec_suite/rest_tests.sh

run_auth_tests() {
    local v=$(compare_versions "2.0.10" "2.0.9")
    if [ "$v" -ne 1 ]; then
        echo "[FAIL] Auth Test: SemVer 2.0.10 should be > 2.0.9"
    else
        echo "[PASS] Auth Test: SemVer check successful"
    fi
}
EOF

    cat << 'EOF' > /home/user/sec_suite/graphql_tests.sh
source /home/user/sec_suite/utils.sh
source /home/user/sec_suite/auth_tests.sh

run_graphql_tests() {
    local fuzz=$(generate_fuzz_length 7)
    if [ "$fuzz" -ne 29 ]; then
        echo "[FAIL] GraphQL Test: Fuzz length L(7) should be 29, got $fuzz"
    else
        echo "[PASS] GraphQL Test: Fuzz length successful"
    fi
}
EOF

    cat << 'EOF' > /home/user/sec_suite/rest_tests.sh
source /home/user/sec_suite/utils.sh
source /home/user/sec_suite/graphql_tests.sh

run_rest_tests() {
    local v=$(compare_versions "1.2.0" "1.2.0")
    if [ "$v" -ne 0 ]; then
        echo "[FAIL] REST Test: SemVer 1.2.0 should be == 1.2.0"
    else
        echo "[PASS] REST Test: SemVer check successful"
    fi
}
EOF

    cat << 'EOF' > /home/user/sec_suite/run_tests.sh
#!/bin/bash
# Entry point
source /home/user/sec_suite/auth_tests.sh
source /home/user/sec_suite/graphql_tests.sh
source /home/user/sec_suite/rest_tests.sh

echo "Starting Security Test Suite..."
run_auth_tests
run_graphql_tests
run_rest_tests
echo "Test Suite Completed."
EOF

    chmod +x /home/user/sec_suite/run_tests.sh
    chown -R user:user /home/user/sec_suite
    chmod -R 777 /home/user
