#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip r-base bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/simulate.py
import random
# Mean around 1.552, with small uniform noise simulating thread-reduction jitter
val = 1.552 + random.uniform(-0.02, 0.02)
print(f"{val:.6f}")
EOF

    echo "1.552500" > /home/user/baseline_mean.txt

    cat << 'EOF' > /home/user/bootstrap_ci.R
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Input file required")
}
data <- as.numeric(readLines(args[1]))
set.seed(42)
B <- 1000
means <- numeric(B)
for(i in 1:B) {
  means[i] <- mean(sample(data, replace=TRUE))
}
lower <- quantile(means, 0.025)
upper <- quantile(means, 0.975)
cat(sprintf("%.6f %.6f\n", lower, upper))
EOF

    chmod 755 /home/user/simulate.py
    chmod 755 /home/user/bootstrap_ci.R

    chmod -R 777 /home/user
