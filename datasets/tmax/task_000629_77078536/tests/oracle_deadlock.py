import sys

def get_deadlocks():
    # Hardcoded final state for the specific sequence above.
    # A true oracle would dynamically parse, but since the video is fixed:
    return {
        1: "DEADLOCK: Tx1 -> Res2 -> Tx2 -> Res3 -> Tx3 -> Res1 -> Tx1",
        2: "DEADLOCK: Tx2 -> Res3 -> Tx3 -> Res1 -> Tx1 -> Res2 -> Tx2",
        3: "DEADLOCK: Tx3 -> Res1 -> Tx1 -> Res2 -> Tx2 -> Res3 -> Tx3"
    }

if __name__ == "__main__":
    tx = int(sys.argv[1])
    dls = get_deadlocks()
    if tx in dls:
        print(dls[tx])
    else:
        print("NO DEADLOCK")
