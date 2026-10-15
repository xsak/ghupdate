#!/bin/sh
# End-to-end test: install the example tools into a temporary directory,
# then run each binary.
#
#   sh tests/run-test.sh             # all tools from config.example.json
#   sh tests/run-test.sh lazydocker  # a subset
#
# Exits non-zero on any failure; the temp directory is always removed.
set -eu

cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
cp config.example.json "$tmp/config.json"
python3 - "$tmp/config.json" "$tmp/bin" <<'PY'
import json, sys

path, bindir = sys.argv[1], sys.argv[2]
config = json.load(open(path))
config["bin_dir"] = bindir
json.dump(config, open(path, "w"), indent=2)
PY

# Tools to test: the explicit arguments, or all tools in the example config.
if [ "$#" -gt 0 ]; then
    tools="$*"
else
    tools="$(python3 -c "import json; print(' '.join(json.load(open('$tmp/config.json'))['tools']))")"
fi

echo "=== update: $tools"
# $tools is intentionally unquoted: word-split tool names are wanted.
python3 ghupdate --config "$tmp/config.json" --state "$tmp/state.json" update $tools

echo "=== verify"
python3 - "$tmp" "$tools" <<'PY'
import json, os, subprocess, sys

tmp, tools = sys.argv[1], sys.argv[2].split()
bin_dir = os.path.join(tmp, "bin")
config = json.load(open(os.path.join(tmp, "config.json")))
state = json.load(open(os.path.join(tmp, "state.json")))

unknown = [t for t in tools if t not in config["tools"]]
if unknown:
    sys.exit(f"unknown tools in config: {', '.join(unknown)}")

for tool in tools:
    path = os.path.join(bin_dir, tool)
    assert os.access(path, os.X_OK), f"{tool}: binary missing or not executable"
    # Tools disagree on the flag: helm uses the `version` subcommand.
    for args in ((path, "--version"), (path, "version")):
        result = subprocess.run(args, capture_output=True, timeout=10)
        if result.returncode == 0:
            break
    else:
        sys.exit(f"{tool}: version probe failed: {result.stderr.decode().strip()}")
    assert state["versions"][tool], f"{tool}: not recorded in state file"
    print(f"  {tool}  {state['versions'][tool]}  ok")

print("all ok")
PY

echo "=== update again with the state file removed (regression: no reinstalls)"
# Binaries are already the latest but have no state entries; update must
# probe them and report "up to date" instead of re-downloading everything.
rm "$tmp/state.json"
out="$(python3 ghupdate --config "$tmp/config.json" --state "$tmp/state.json" update $tools)"
printf '%s\n' "$out"
if printf '%s\n' "$out" | grep -qv 'up to date'; then
    echo "FAIL: up-to-date tools were reinstalled without a state file" >&2
    exit 1
fi
if ls "$tmp/bin"/*.old >/dev/null 2>&1; then
    echo "FAIL: .old backups found, so binaries were replaced" >&2
    exit 1
fi

echo "=== state was backfilled from the probed versions"
python3 - "$tmp/state.json" "$tools" <<'PY'
import json, sys

state = json.load(open(sys.argv[1]))["versions"]
missing = [t for t in sys.argv[2].split() if not state.get(t)]
if missing:
    sys.exit(f"FAIL: state not backfilled for: {', '.join(missing)}")
print("  all tools recorded")
PY

echo "all ok"
