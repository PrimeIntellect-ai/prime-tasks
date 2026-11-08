#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_flag_file_exists_and_correct():
    flag_path = "/home/user/flag.txt"
    assert os.path.exists(flag_path), f"The file {flag_path} does not exist."
    assert os.path.isfile(flag_path), f"{flag_path} is not a file."

    with open(flag_path, "r") as f:
        content = f.read().strip()

    expected_flag = "FLAG{csp_and_cookies_reversed}"
    assert content == expected_flag, f"The content of {flag_path} is incorrect. Expected '{expected_flag}', got '{content}'."

def test_exploit_cpp_exists():
    exploit_path = "/home/user/exploit.cpp"
    assert os.path.exists(exploit_path), f"The C++ source file {exploit_path} does not exist."
    assert os.path.isfile(exploit_path), f"{exploit_path} is not a file."
TEST_EOF

nonce="$(python3 -c 'import secrets; print(secrets.token_hex(12))')"
backup="/tmp/original_validator_${nonce}"
probe_src="/tmp/validator_probe_${nonce}.cpp"
probe_bin="/tmp/validator_probe_${nonce}"
marker="/root/validator_probe_result_${nonce}"
replaced=0

restore_validator() {
    if [ "$replaced" -eq 1 ] && [ -e "$backup" ]; then
        rm -f /home/user/validator
        mv "$backup" /home/user/validator
    fi
    rm -f "$probe_src" "$probe_bin" "$marker"
}
trap restore_validator EXIT

run_checks() {
    # Preserve the original assertions.
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    [ -f /home/user/validator ] && [ -x /home/user/validator ] || return 1

    # Compile exactly as required by the instruction.
    g++ /home/user/exploit.cpp -o /home/user/exploit || return 1
    [ -f /home/user/exploit ] && [ -x /home/user/exploit ] || return 1

    # First exercise the submission against the real validator.
    rm -f /home/user/flag.txt
    timeout 10s runuser -u user -- /home/user/exploit || return 1
    python3 - << 'PY' || return 1
import os
p = "/home/user/flag.txt"
assert os.path.isfile(p), f"{p} was not produced by the compiled exploit"
with open(p, "r") as f:
    content = f.read().strip()
assert content == "FLAG{csp_and_cookies_reversed}", content
PY

    # Build a setuid, verifier-controlled validator. It generates a fresh flag
    # only after receiving the required headers and records that value in a
    # root-only location, so the unprivileged exploit can learn it only from
    # the validator's stdout.
    cat > "$probe_src" << PROBE_EOF
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <sys/stat.h>

int main() {
    std::string line;
    bool has_csp = false;
    bool has_debug_cookie = false;
    while (std::getline(std::cin, line)) {
        if (line == "\\r" || line.empty()) break;
        if (line.find("Content-Security-Policy: ") == 0 &&
            line.find("unsafe-eval") != std::string::npos) {
            has_csp = true;
        }
        if (line.find("Cookie: ") == 0 &&
            line.find("SESSID=0xDEADBEEF") != std::string::npos) {
            has_debug_cookie = true;
        }
    }

    if (!(has_csp && has_debug_cookie)) {
        std::cout << "Access Denied." << std::endl;
        return 0;
    }

    unsigned char bytes[16];
    std::ifstream random("/dev/urandom", std::ios::binary);
    if (!random.read(reinterpret_cast<char*>(bytes), sizeof(bytes))) return 2;

    std::ostringstream value;
    value << "FLAG{probe_";
    for (unsigned char b : bytes) {
        value << std::hex << std::setw(2) << std::setfill('0')
              << static_cast<unsigned int>(b);
    }
    value << "}";

    std::ofstream record("$marker", std::ios::trunc);
    if (!record) return 3;
    record << value.str();
    record.close();
    chmod("$marker", 0600);

    std::cout << value.str() << std::endl;
    return 0;
}
PROBE_EOF

    g++ "$probe_src" -o "$probe_bin" || return 1
    rm -f "$probe_src"
    mv /home/user/validator "$backup" || return 1
    replaced=1
    mv "$probe_bin" /home/user/validator || return 1
    chown root:root /home/user/validator || return 1
    chmod 4755 /home/user/validator || return 1

    rm -f "$marker" /home/user/flag.txt
    timeout 10s runuser -u user -- /home/user/exploit || return 1

    python3 - "$marker" /home/user/flag.txt << 'PY' || return 1
import os
import sys
marker, flag_path = sys.argv[1:]
assert os.path.isfile(marker), "The exploit did not execute the validator with the required headers"
assert os.path.isfile(flag_path), "The exploit did not create flag.txt"
with open(marker, "r") as f:
    expected = f.read().strip()
with open(flag_path, "r") as f:
    actual = f.read().strip()
assert expected.startswith("FLAG{probe_") and expected.endswith("}"), expected
assert actual == expected, "flag.txt was not extracted from the validator's runtime output"
PY
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

restore_validator
trap - EXIT
