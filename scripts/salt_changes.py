"""Read salt-call --out=json from stdin. Print the number of states that changed, exit 1 on any failure."""
import json
import sys

raw = sys.stdin.read()
data = json.loads(raw[raw.index("{"):])["local"]
failed = [k for k, v in data.items() if v.get("result") is not True]
changed = [k for k, v in data.items() if v.get("changes")]
for k in failed:
    print("FAILED:", k, data[k].get("comment"), file=sys.stderr)
print(len(changed))
sys.exit(1 if failed else 0)
