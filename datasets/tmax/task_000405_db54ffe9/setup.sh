#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ valgrind gdb
pip3 install pytest Pillow

mkdir -p /app
cat << 'EOF' > /app/oracle_evaluator.cpp
#include <iostream>
#include <cstdlib>

int main(int argc, char* argv[]) {
    if (argc != 4) return 1;
    long long x = std::atoll(argv[1]);
    long long y = std::atoll(argv[2]);
    long long z = std::atoll(argv[3]);
    long long result = ((x + y) * 5) - (z * y);
    std::cout << result << std::endl;
    return 0;
}
EOF
g++ -O3 /app/oracle_evaluator.cpp -o /app/oracle_evaluator
chmod +x /app/oracle_evaluator

python3 -c '
from PIL import Image, ImageDraw, ImageFont
img = Image.new("RGB", (300, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "INPUTS: X, Y, Z\nN1 = ADD X, Y\nN2 = MUL N1, 5\nN3 = MUL Z, Y\nN4 = SUB N2, N3\nOUT = N4"
d.text((10,10), text, fill=(0,0,0))
img.save("/app/circuit_def.png")
'

useradd -m -s /bin/bash user || true

mkdir -p /home/user/src
cat << 'EOF' > /home/user/src/main.cpp
#include <iostream>
#include <string>
#include <cstdlib>

// AST Node
struct Node {
    virtual ~Node() {}
    virtual long long evaluate() = 0;
};

struct ValueNode : public Node {
    long long val;
    ValueNode(long long v) : val(v) {}
    long long evaluate() override { return val; }
};

struct OpNode : public Node {
    char op;
    Node* left;
    Node* right;

    OpNode(char o, Node* l, Node* r) : op(o), left(l), right(r) {}

    // BUG: Missing destructor to delete left and right children (Memory leak)

    long long evaluate() override {
        // BUG: Segfault risk if left or right is null
        long long lval = left->evaluate();
        long long rval = right->evaluate();
        if (op == '+') return lval + rval;
        if (op == '-') return lval - rval;
        if (op == '*') return lval * rval;
        return 0;
    }
};

int main(int argc, char* argv[]) {
    if (argc != 4) {
        std::cerr << "Usage: " << argv[0] << " <X> <Y> <Z>\n";
        return 1;
    }

    long long X = std::atoll(argv[1]);
    long long Y = std::atoll(argv[2]);
    long long Z = std::atoll(argv[3]);

    // Dummy circuit (Needs to be replaced by the logic from the image)
    Node* root = new OpNode('+', new ValueNode(X), new ValueNode(Y));

    // INTENTIONAL BUG: create a dangling pointer
    Node* dangling = new ValueNode(Z);
    delete dangling;

    // Evaluate with dangling pointer
    Node* bad_root = new OpNode('*', root, dangling);

    std::cout << bad_root->evaluate() << std::endl;

    // Memory leaks galore here
    return 0;
}
EOF

chown -R user:user /home/user/src
chmod -R 777 /home/user
