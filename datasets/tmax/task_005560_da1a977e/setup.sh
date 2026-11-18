#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest nbconvert ipykernel numpy

    mkdir -p /home/user/sim
    mkdir -p /home/user/analysis
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/sim/network_sim.cpp
#include <iostream>
#include <vector>
#include <numeric>
#include <cstdlib>
#include <sys/time.h>

int main() {
    struct timeval time;
    gettimeofday(&time, NULL);
    srand((time.tv_sec * 1000) + (time.tv_usec / 1000));

    // Simulate non-deterministic floating point reduction
    double base_energy = 15234.50;
    double noise = ((double)rand() / RAND_MAX) * 2.0 - 1.0; // [-1.0, 1.0]
    std::cout << base_energy + noise << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/analysis/bootstrap_ci.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import numpy as np\n",
    "import json\n",
    "np.random.seed(42)\n",
    "with open('/home/user/data/results.txt', 'r') as f:\n",
    "    data = [float(line.strip()) for line in f if line.strip()]\n",
    "data = np.array(data)\n",
    "means = [np.mean(np.random.choice(data, size=len(data), replace=True)) for _ in range(1000)]\n",
    "ci_lower = np.percentile(means, 2.5)\n",
    "ci_upper = np.percentile(means, 97.5)\n",
    "res = {'ci_lower': ci_lower, 'ci_upper': ci_upper}\n",
    "with open('/home/user/data/final_ci.json', 'w') as f:\n",
    "    json.dump(res, f)"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/sim /home/user/analysis /home/user/data
    chmod -R 777 /home/user
