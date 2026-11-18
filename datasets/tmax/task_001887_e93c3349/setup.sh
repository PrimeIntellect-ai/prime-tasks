#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl bc
    pip3 install pytest

    # Set up directories
    mkdir -p /app/corpus/clean /app/corpus/evil /app/bats-core-1.11.0

    # Download and vendor bats-core
    curl -sL https://github.com/bats-core/bats-core/archive/refs/tags/v1.11.0.tar.gz | tar -xz -C /app/bats-core-1.11.0 --strip-components=1

    # Inject the perturbation
    sed -i '/source/s/BATS_TEST_FILENAME/BATS_TEST_FILENAME_BROKEN/g' /app/bats-core-1.11.0/libexec/bats-core/bats-exec-test
    # Fallback if the above didn't match anything (e.g. if source is not used)
    if ! grep -q BATS_TEST_FILENAME_BROKEN /app/bats-core-1.11.0/libexec/bats-core/bats-exec-test; then
        sed -i 's/BATS_TEST_FILENAME/BATS_TEST_FILENAME_BROKEN/g' /app/bats-core-1.11.0/libexec/bats-core/bats-exec-test
    fi

    # Create the clean corpus
    cat << 'EOF' > /app/corpus/clean/basic.bats
#!/usr/bin/env bats

@test "addition using bc" {
  result="$(echo 2+2 | bc)"
  [ "$result" -eq 4 ]
}
EOF

    cat << 'EOF' > /app/corpus/clean/no_eval_here.bats
#!/usr/bin/env bats

@test "string match" {
  string="evaluate the situation"
  [[ "$string" =~ "evaluate" ]]
}
EOF

    # Create the evil corpus
    cat << 'EOF' > /app/corpus/evil/bad_shebang.bats
#!/bin/bash
# Should be rejected because it lacks the bats shebang

@test "fake" {
  true
}
EOF

    cat << 'EOF' > /app/corpus/evil/has_eval.bats
#!/usr/bin/env bats

@test "eval injection" {
  eval "echo $UNSAFE_VAR"
}
EOF

    cat << 'EOF' > /app/corpus/evil/comment_eval.bats
#!/usr/bin/env bats

# Let's eval this
@test "comment eval" {
  true
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
