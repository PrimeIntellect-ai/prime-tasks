import sys

def process(text):
    reversed_text = text[::-1]
    res = []
    for c in reversed_text:
        res.append(str(ord(c) + 12))
    return "_".join(res)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(process(sys.argv[1]))
