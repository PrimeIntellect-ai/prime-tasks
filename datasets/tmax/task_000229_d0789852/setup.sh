#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make g++ binutils
    pip3 install --no-cache-dir pytest nbconvert ipykernel numpy scipy pandas scikit-learn

    mkdir -p /app/signal_gen_src
    mkdir -p /home/user

    # Create legacy feature extractor source
    cat << 'EOF' > /tmp/legacy.cpp
#include <iostream>
#include <string>
#include <cmath>
#include <iomanip>

int main() {
    double y = 0.0;
    std::string line;
    std::cout << std::fixed << std::setprecision(6);
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        try {
            double x = std::stod(line);
            y = 0.85 * y + 0.15 * x;
            double z = std::tanh(1.5 * y);
            std::cout << z << "\n";
        } catch (...) {}
    }
    return 0;
}
EOF
    g++ -O3 -o /app/legacy_feature_extractor /tmp/legacy.cpp
    strip /app/legacy_feature_extractor
    rm /tmp/legacy.cpp

    # Create signal generator source
    cat << 'EOF' > /app/signal_gen_src/signal_gen.cpp
#include <iostream>
#include <random>
#include <iomanip>

int main() {
    std::mt19937 gen(42);
    std::uniform_real_distribution<double> dist(-100.0, 100.0);
    std::cout << std::fixed << std::setprecision(6);
    for (int i=0; i<10000; ++i) {
        std::cout << dist(gen) << "\n";
    }
    return 0;
}
EOF

    # Create Makefile
    cat << 'EOF' > /app/signal_gen_src/Makefile
all:
	g++ -O3 -o signal_gen signal_gen.cpp
EOF

    # Create Jupyter notebook template
    cat << 'EOF' > /home/user/analyze_transform.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Load raw_signals.txt and legacy_features.txt to find alpha and beta\n",
    "import numpy as np\n",
    "import pandas as pd\n",
    "from scipy.optimize import curve_fit\n"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "3.10.6"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
