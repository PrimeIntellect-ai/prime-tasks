#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the dataset
    cat << 'EOF' > /home/user/dataset.csv
text,label
free money now,1
hello friend,0
win free cash,1
call me back,0
urgent free prize,1
how are you,0
claim your money,1
good morning,0
win a prize,1
see you tomorrow,0
free gift card,1
lunch at noon,0
urgent money transfer,1
call back later,0
cash prize waiting,1
meeting is canceled,0
claim your gift,1
are you free,0
win big cash,1
hello how are you,0
EOF

    # Create the buggy C++ code
    cat << 'EOF' > /home/user/naive_bayes.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <cmath>

using namespace std;

struct Document {
    string text;
    int label;
    vector<string> tokens;
};

vector<Document> load_data(const string& filename) {
    vector<Document> docs;
    ifstream file(filename);
    string line;
    getline(file, line); // skip header
    while (getline(file, line)) {
        size_t last_comma = line.find_last_of(',');
        if (last_comma != string::npos) {
            string text = line.substr(0, last_comma);
            int label = stoi(line.substr(last_comma + 1));
            docs.push_back({text, label, {}});
        }
    }
    return docs;
}

void tokenize(vector<Document>& docs, unordered_set<string>& vocab) {
    for (auto& doc : docs) {
        stringstream ss(doc.text);
        string word;
        while (ss >> word) {
            doc.tokens.push_back(word);
            vocab.insert(word); // BUG: fitting on all data here
        }
    }
}

int main() {
    auto docs = load_data("/home/user/dataset.csv");
    unordered_set<string> vocab;

    // BUG: Tokenization and vocabulary building on the entire dataset
    tokenize(docs, vocab);

    int split_idx = docs.size() * 0.8;
    vector<Document> train_docs(docs.begin(), docs.begin() + split_idx);
    vector<Document> test_docs(docs.begin() + split_idx, docs.end());

    // Train Naive Bayes (Calculate Frequencies)
    int spam_count = 0, ham_count = 0;
    unordered_map<string, int> spam_word_counts;
    unordered_map<string, int> ham_word_counts;

    for (const auto& doc : train_docs) {
        if (doc.label == 1) spam_count++;
        else ham_count++;

        for (const auto& token : doc.tokens) {
            if (doc.label == 1) spam_word_counts[token]++;
            else ham_word_counts[token]++;
        }
    }

    int total_spam_words = 0, total_ham_words = 0;
    for (auto const& [key, val] : spam_word_counts) total_spam_words += val;
    for (auto const& [key, val] : ham_word_counts) total_ham_words += val;

    double p_spam = log((double)spam_count / train_docs.size());
    double p_ham = log((double)ham_count / train_docs.size());

    // Test
    int correct = 0;
    for (const auto& doc : test_docs) {
        double score_spam = p_spam;
        double score_ham = p_ham;

        for (const auto& token : doc.tokens) {
            // Laplace smoothing using full vocab size (Leakage)
            score_spam += log((spam_word_counts[token] + 1.0) / (total_spam_words + vocab.size()));
            score_ham += log((ham_word_counts[token] + 1.0) / (total_ham_words + vocab.size()));
        }

        int pred = (score_spam > score_ham) ? 1 : 0;
        if (pred == doc.label) correct++;
    }

    cout << "Vocab Size: " << vocab.size() << endl;
    cout << "Test Accuracy: " << (double)correct / test_docs.size() << endl;
    return 0;
}
EOF

    chmod -R 777 /home/user
