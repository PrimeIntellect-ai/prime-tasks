#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/samples/evil /app/samples/clean /app/eval/evil /app/eval/clean

    # Generate the rule image
    convert -size 1200x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -draw 'text 20,100 "Rule: A log is evil if any operation containing the word '\''fit'\'' occurs on a line before the operation '\''train_test_split'\''."' \
        /app/leak_rule.png

    # Populate samples/evil
    cat << 'EOF' > /app/samples/evil/log1.txt
load_data
clean_text
fit_transform_tokenizer
train_test_split
train_model
EOF

    cat << 'EOF' > /app/samples/evil/log2.txt
load_data
fit_scaler
train_test_split
predict
EOF

    # Populate samples/clean
    cat << 'EOF' > /app/samples/clean/log1.txt
load_data
clean_text
train_test_split
fit_transform_tokenizer
train_model
EOF

    cat << 'EOF' > /app/samples/clean/log2.txt
load_data
train_test_split
fit_scaler
predict
EOF

    # Populate eval/evil
    cat << 'EOF' > /app/eval/evil/eval_log1.txt
init
fit_model
train_test_split
eval
EOF

    cat << 'EOF' > /app/eval/evil/eval_log2.txt
load_data
fit_something
train_test_split
evaluate
EOF

    # Populate eval/clean
    cat << 'EOF' > /app/eval/clean/eval_log1.txt
init
train_test_split
fit_model
eval
EOF

    cat << 'EOF' > /app/eval/clean/eval_log2.txt
load_data
train_test_split
evaluate
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
