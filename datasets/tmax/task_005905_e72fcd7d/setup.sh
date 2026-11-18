#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/src /home/user/bin /home/user/test

    # Create reference data for regression test
    cat << 'EOF' > /home/user/test/ref_in.txt
10.0
20.0
30.0
40.0
50.0
EOF

    cat << 'EOF' > /home/user/test/ref_out.txt
-1.414214
-0.707107
0.000000
0.707107
1.414214
EOF

    # Create regression test script
    cat << 'EOF' > /home/user/test/regression_test.sh
#!/bin/bash
if [ ! -f /home/user/bin/preprocess ]; then
    echo "Error: Executable /home/user/bin/preprocess not found."
    exit 1
fi

/home/user/bin/preprocess /home/user/test/ref_in.txt /home/user/test/test_out.txt

if diff -q /home/user/test/ref_out.txt /home/user/test/test_out.txt > /dev/null; then
    echo "Regression test PASSED."
else
    echo "Regression test FAILED."
    echo "Expected:"
    cat /home/user/test/ref_out.txt
    echo "Got:"
    cat /home/user/test/test_out.txt
    exit 1
fi
EOF
    chmod +x /home/user/test/regression_test.sh

    # Create the raw training data
    cat << 'EOF' > /home/user/raw_training_data.txt
5.2
7.8
4.5
6.1
9.3
2.1
5.5
8.4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
