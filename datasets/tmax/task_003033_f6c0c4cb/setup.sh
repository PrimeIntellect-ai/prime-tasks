#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/loc_filter.cpp
#include <iostream>
#include <string>
#include <regex>
#include <algorithm>
#include <vector>

int levenshtein(const std::string& s1, const std::string& s2) {
    int m = s1.length(), n = s2.length();
    std::vector<std::vector<int>> dp(m + 1, std::vector<int>(n + 1));
    for (int i = 0; i <= m; i++) dp[i][0] = i;
    for (int j = 0; j <= n; j++) dp[0][j] = j;
    for (int i = 1; i <= m; i++) {
        for (int j = 1; j <= n; j++) {
            if (s1[i - 1] == s2[j - 1])
                dp[i][j] = dp[i - 1][j - 1];
            else
                dp[i][j] = 1 + std::min({dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]});
        }
    }
    return dp[m][n];
}

int main() {
    std::string line;
    std::regex email_regex("([a-zA-Z0-9._]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})");
    std::string prev_text = "";

    while (std::getline(std::cin, line)) {
        size_t comma_pos = line.find(',');
        if (comma_pos == std::string::npos) {
            continue; // Silently drops lines without a comma
        }

        std::string id = line.substr(0, comma_pos);
        std::string text = line.substr(comma_pos + 1);

        // Mask emails
        text = std::regex_replace(text, email_regex, "<EMAIL>");

        int dist = levenshtein(text, prev_text);
        prev_text = text;

        std::cout << id << "|" << dist << "|" << text << "\n";
    }
    return 0;
}
EOF

    g++ -O3 /tmp/loc_filter.cpp -o /app/loc_filter
    strip /app/loc_filter
    rm /tmp/loc_filter.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
