#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/simulation.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": 1,
   "metadata": {},
   "outputs": [],
   "source": [
    "import numpy as np\n",
    "import math\n",
    "\n",
    "# Prototype Monte Carlo Simulation\n",
    "def run_simulation(dt):\n",
    "    np.random.seed(42)\n",
    "    N = 10000\n",
    "    T = 2.0\n",
    "    steps = int(T / dt)\n",
    "    \n",
    "    # Slow initialization\n",
    "    X = [np.random.randn() for _ in range(N)]\n",
    "    \n",
    "    # Slow nested loops\n",
    "    for step in range(steps):\n",
    "        for i in range(N):\n",
    "            Z = np.random.randn()\n",
    "            # Equation: X_{t+dt} = X_t + (-X_t^3 + 2X_t)dt + sqrt(dt)*Z\n",
    "            X[i] = X[i] + (-X[i]**3 + 2*X[i])*dt + math.sqrt(dt) * Z\n",
    "            \n",
    "    return X\n"
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

    chmod -R 777 /home/user
