#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/domain.txt
The neural network achieves state-of-the-art accuracy on the validation set.
Gradient descent minimizes the loss function over several epochs!
Backpropagation computes the gradient of the loss with respect to the weights.
EOF

    cat << 'EOF' > /home/user/generic.txt
The quick brown fox jumps over the lazy dog.
I went to the store to buy some groceries for dinner.
What a beautiful day it is outside today!
EOF

    cat << 'EOF' > /home/user/target.txt
We trained the neural network for ten epochs.
The lazy cat slept outside all day.
I bought some weights at the store.
EOF

    chmod -R 777 /home/user
