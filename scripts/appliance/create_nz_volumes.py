#!/usr/bin/env python3

import argparse
import base64
import json
import os
import re
import ssl
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

DEFAULT_SIZE_BYTES = 268435456000


class ApiError(Exception):
    pass


def positive_integer(value):
    if not re.fullmatch(r"[1-9][0-9]*", value):
        raise argparse.ArgumentTypeError("must be a positive integer")
    return int(value)


def safe_name_prefix(value):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", value):
        raise argparse.ArgumentTypeError(
            "may contain only letters, numbers, dots, underscores, and hyphens"
        )
    return value


def request_json(mgmt_ip, password, method, endpoint, payload=None):
    url = "https://{}:443/api/rest/{}".format(mgmt_ip, endpoint)
    headers = {
        "Authorization": "Basic {}".format(
            base64.b64encode("admin:{}".format(password).encode()).decode()
        ),
        "Content-Type": "application/json",
        "cache-control": "nocache",
    }
    data = None if payload is None else json.dumps(payload).encode()
    request = Request(url, data=data, headers=headers, method=method)

    try:
        with urlopen(request, context=ssl._create_unverified_context(), timeout=60) as response:
            raw = response.read()
            status = response.getcode()
    except HTTPError as error:
        body = error.read().decode(errors="replace").strip()
        detail = ": {}".format(body) if body else ""
        raise ApiError(
            "{} {} returned HTTP {}{}".format(method, endpoint, error.code, detail)
        )
    except URLError as error:
        raise ApiError("{} {} failed: {}".format(method, endpoint, error.reason))

    if not 200 <= status < 300:
        raise ApiError("{} {} returned HTTP {}".format(method, endpoint, status))

    if not raw:
        return {}
    try:
        return json.loads(raw.decode())
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ApiError("{} {} returned invalid JSON: {}".format(method, endpoint, error))


def objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from objects(child)


def normalized(value):
    return str(value).lower().replace("-", " ").replace("_", " ").strip()


def is_nz_policy(policy):
    name = normalized(policy.get("name", ""))
    compact_name = name.replace(" ", "")
    policy_type = normalized(policy.get("type", ""))
    return (
        name in {"nz", "nearzero", "near zero"}
        or compact_name == "nearzero"
        or (name == "nz" and policy_type == "protection")
    )


def find_nz_policy(data):
    matches = []
    seen = set()
    for item in objects(data):
        item_id = item.get("id")
        if not item_id or item_id in seen or not is_nz_policy(item):
            continue
        matches.append(item)
        seen.add(item_id)

    if not matches:
        raise ApiError("No NearZero/NZ protection policy is configured")
    if len(matches) > 1:
        raise ApiError("Multiple NearZero/NZ protection policies are configured")
    return matches[0]


def find_host(data):
    hosts = []
    seen = set()
    for item in objects(data):
        item_id = item.get("id")
        if item_id and item_id not in seen:
            hosts.append(item)
            seen.add(item_id)

    if not hosts:
        raise ApiError("No configured host was found")
    if len(hosts) > 1:
        print(
            "Multiple hosts are configured; using the first host returned by the appliance.",
            file=sys.stderr,
        )
    return hosts[0]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Create volumes using the appliance's NZ protection policy and host."
    )
    parser.add_argument("mgmt_ip", help="Appliance management IP")
    parser.add_argument(
        "password",
        help="Appliance admin password (visible to local process inspection while running)",
    )
    parser.add_argument("count", type=positive_integer, help="Number of volumes to create")
    parser.add_argument(
        "size_bytes",
        nargs="?",
        type=positive_integer,
        default=DEFAULT_SIZE_BYTES,
        help="Volume size in bytes (default: %(default)s)",
    )
    parser.add_argument(
        "name_prefix",
        nargs="?",
        type=safe_name_prefix,
        default="NZ_volume",
        help="Volume name prefix (default: %(default)s)",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    appliance_id = os.environ.get("APPLIANCE_ID", "A1")

    try:
        policies = request_json(
            args.mgmt_ip, args.password, "GET", "policy?select=*&limit=2000"
        )
        policy = find_nz_policy(policies)
        hosts = request_json(args.mgmt_ip, args.password, "GET", "host?select=*&limit=2000")
        host = find_host(hosts)
    except (ApiError, ValueError, TypeError) as error:
        print("Discovery failed: {}".format(error), file=sys.stderr)
        return 1

    print("Using NZ policy {} and host {}.".format(policy["id"], host["id"]))
    print("Creating {} volume(s), {} bytes each.".format(args.count, args.size_bytes))

    for index in range(1, args.count + 1):
        name = "{}{}".format(args.name_prefix, index)
        payload = {
            "name": name,
            "size": args.size_bytes,
            "description": "NearZero volume",
            "host_id": host["id"],
            "protection_policy_id": policy["id"],
            "appliance_id": appliance_id,
        }
        try:
            response = request_json(
                args.mgmt_ip, args.password, "POST", "volume", payload
            )
        except ApiError as error:
            print("Creating {} failed: {}".format(name, error), file=sys.stderr)
            return 1
        print("{}: {}".format(name, response.get("id", "created")))

    return 0


if __name__ == "__main__":
    sys.exit(main())
