#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make time
    pip3 install pytest

    mkdir -p /app/finance-aggregator-1.0/src

    cat << 'EOF' > "/app/finance-aggregator-1.0/src/trade record.cpp"
#include <string>
class TradeRecord {
public:
    std::string data;
    TradeRecord(std::string d) : data(d) {}
};
EOF

    cat << 'EOF' > "/app/finance-aggregator-1.0/src/main.cpp"
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <thread>
#include <dirent.h>

class TradeRecord {
public:
    std::string data;
    TradeRecord(std::string d) : data(d) {}
};

double global_total = 0.0;

void process_file(const std::string& filepath) {
    std::ifstream file(filepath);
    std::string line;
    while (std::getline(file, line)) {
        TradeRecord* tr = new TradeRecord(line);
        size_t pos = line.find(',');
        if (pos != std::string::npos) {
            try {
                double val = std::stod(line.substr(pos + 1));
                global_total += val;
            } catch (...) {}
        }
    }
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <data_dir>\n";
        return 1;
    }
    std::string dir = argv[1];
    DIR* dp = opendir(dir.c_str());
    if (!dp) return 1;
    struct dirent* ep;
    std::vector<std::thread> threads;
    while ((ep = readdir(dp)) != NULL) {
        std::string fname = ep->d_name;
        if (fname == "." || fname == "..") continue;
        threads.emplace_back(process_file, dir + "/" + fname);
    }
    closedir(dp);
    for (auto& t : threads) {
        t.join();
    }
    std::cout << global_total << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > "/app/finance-aggregator-1.0/build.sh"
#!/bin/bash
mkdir -p build
rm -f build/*.o
for file in $(ls src/*.cpp); do
    filename=$(basename $file .cpp)
    g++ -std=c++11 -pthread -c $file -o build/${filename}.o
done
g++ -pthread build/*.o -o finance-aggregator
EOF
    chmod +x "/app/finance-aggregator-1.0/build.sh"

    mkdir -p /home/user/mock_data
    echo "T,100.50" > "/home/user/mock_data/data 1.csv"
    echo "T,200.25" > "/home/user/mock_data/data 2.csv"
    echo "T,300.00" > "/home/user/mock_data/data 3.csv"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
