import sys
import json

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    data = json.loads(sys.argv[1])
    pipeline = []

    pipeline.append({"$match": {"status": data.get("match_status")}})

    pipeline.append({
        "$lookup": {
            "from": data.get("join_collection"),
            "localField": data.get("join_local_field"),
            "foreignField": data.get("join_foreign_field"),
            "as": data.get("join_as")
        }
    })

    fields = data.get("fields", [])
    proj = {f: 1 for f in fields}
    pipeline.append({"$project": proj})

    print(json.dumps(pipeline))

if __name__ == "__main__":
    main()
