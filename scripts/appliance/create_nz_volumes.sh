#!/usr/bin/env bash

set -u

usage() {
    printf 'Usage: %s MGMT_IP COUNT [SIZE_BYTES] [NAME_PREFIX]\n' "$0" >&2
    printf '\nEnvironment:\n' >&2
    printf '  APPLIANCE_USER      API user (default: admin)\n' >&2
    printf '  APPLIANCE_PASSWORD  API password (required)\n' >&2
    printf '  APPLIANCE_ID        Appliance id (default: A1)\n' >&2
}

if [[ $# -lt 2 || $# -gt 4 ]]; then
    usage
    exit 2
fi

MGMT_IP=$1
COUNT=$2
SIZE_BYTES=${3:-268435456000}
NAME_PREFIX=${4:-NZ_volume}
API_USER=${APPLIANCE_USER:-admin}
API_PASSWORD=${APPLIANCE_PASSWORD:-}
APPLIANCE_ID=${APPLIANCE_ID:-A1}
BASE_URL="https://${MGMT_IP}:443/api/rest"

if [[ -z "$API_PASSWORD" ]]; then
    printf 'APPLIANCE_PASSWORD must be set; refusing to run without credentials.\n' >&2
    exit 2
fi

if ! [[ "$COUNT" =~ ^[1-9][0-9]*$ ]]; then
    printf 'COUNT must be a positive integer.\n' >&2
    exit 2
fi

if ! [[ "$SIZE_BYTES" =~ ^[1-9][0-9]*$ ]]; then
    printf 'SIZE_BYTES must be a positive integer.\n' >&2
    exit 2
fi

if ! [[ "$NAME_PREFIX" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    printf 'NAME_PREFIX may contain only letters, numbers, dots, underscores, and hyphens.\n' >&2
    exit 2
fi

if ! command -v curl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    printf 'This script requires curl and python3.\n' >&2
    exit 2
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
AUTH="${API_USER}:${API_PASSWORD}"

get_resource() {
    local endpoint=$1
    local output=$2
    local status

    status=$(curl --silent --show-error --insecure --user "$AUTH" \
        --header 'Content-Type: application/json' \
        --header 'cache-control: nocache' \
        --request GET --output "$output" --write-out '%{http_code}' \
        "${BASE_URL}/${endpoint}") || {
        printf 'Request failed while querying %s.\n' "$endpoint" >&2
        return 1
    }

    if [[ "$status" != 2* ]]; then
        printf 'Query %s returned HTTP %s:\n' "$endpoint" "$status" >&2
        cat "$output" >&2
        return 1
    fi
}

policy_file="$TMP_DIR/policies.json"
host_file="$TMP_DIR/hosts.json"
get_resource 'policy?select=*&limit=2000' "$policy_file" || exit 1
get_resource 'host?select=*&limit=2000' "$host_file" || exit 1

policy_id=$(python3 - "$policy_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)

def objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from objects(child)

matches = []
seen = set()
for item in objects(data):
    if not item.get("id") or item["id"] in seen:
        continue
    text = json.dumps(item, ensure_ascii=False).lower().replace("-", " ").replace("_", " ")
    if "nearzero" in text.replace(" ", "") or "near zero" in text:
        matches.append(item)
        seen.add(item["id"])

if len(matches) != 1:
    if not matches:
        print("No NearZero protection policy is configured.", file=sys.stderr)
    else:
        print("Multiple NearZero protection policies are configured; refusing to guess.", file=sys.stderr)
    sys.exit(1)

print(matches[0]["id"])
PY
) || exit 1

host_id=$(python3 - "$host_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)

def objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from objects(child)

hosts = []
seen = set()
for item in objects(data):
    if item.get("id") and item["id"] not in seen:
        hosts.append(item)
        seen.add(item["id"])

if not hosts:
    print("No configured host was found.", file=sys.stderr)
    sys.exit(1)

if len(hosts) > 1:
    print("Multiple hosts are configured; using the first host returned by the appliance.", file=sys.stderr)

print(hosts[0]["id"])
PY
) || exit 1

printf 'Using NearZero policy %s and host %s.\n' "$policy_id" "$host_id"
printf 'Creating %s volume(s), %s bytes each.\n' "$COUNT" "$SIZE_BYTES"

for ((index=1; index<=COUNT; index++)); do
    name="${NAME_PREFIX}${index}"
    payload=$(printf '{"name":"%s","size":%s,"description":"NearZero volume","host_id":"%s","protection_policy_id":"%s","appliance_id":"%s"}' \
        "$name" "$SIZE_BYTES" "$host_id" "$policy_id" "$APPLIANCE_ID")
    response_file="$TMP_DIR/volume-${index}.json"
    status=$(curl --silent --show-error --insecure --user "$AUTH" \
        --header 'Content-Type: application/json' \
        --header 'cache-control: nocache' \
        --request POST --data "$payload" \
        --output "$response_file" --write-out '%{http_code}' \
        "${BASE_URL}/volume") || {
        printf 'Request failed while creating %s.\n' "$name" >&2
        exit 1
    }

    if [[ "$status" != 2* ]]; then
        printf 'Creating %s returned HTTP %s:\n' "$name" "$status" >&2
        cat "$response_file" >&2
        exit 1
    fi

    volume_id=$(python3 - "$response_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
print(data.get("id", "created"))
PY
) || volume_id=created
    printf '%s: %s\n' "$name" "$volume_id"
done
