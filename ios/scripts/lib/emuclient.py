#!/usr/bin/env python3
"""ios/scripts/lib/emuclient.py — the host half of the headless drive.

`xcrun simctl` can boot, install, grant privacy, push a notification, move the device
and read the log stream. It cannot talk to Firebase. This is the piece that does:
phone sign-in over the Auth emulator's REST API, callables over the Functions
emulator, and reads over the Firestore emulator's REST API (with the emulator's
`Bearer owner` admin credential, so a read here is never confused with a read the
security rules allowed the app).

It is the iOS lane's own copy of the wire format documented in
functions/README.md §2 and functions/scripts/lib/emuClient.js. Deliberately duplicated
rather than imported: `functions/` is the backend's lane, and a shell script in
ios/scripts must not break when the backend refactors its test helpers.

Zero dependencies — stdlib only, Python 3.9+.

Subcommands (every one prints JSON on stdout and exits non-zero on failure):

  signin <e164>                      -> {"idToken": "...", "uid": "..."}
  call <name> <idToken> <jsonData>   -> the callable's `result`
  get <docPath>                      -> the decoded document, or null
  list <collPath>                    -> [{"id": ..., ...fields}]
  find-pending-pair <uid>            -> {"id":..., "inviteCode":...} or null
  active-trip <pairId>               -> the decoded trip, or null
  trip-summary <tripId>              -> state / cadence / etaSec coverage, or null
"""

import json
import sys
import time
import urllib.error
import urllib.request

PROJECT = "fin-e8358"
HOST = "127.0.0.1"
AUTH = f"http://{HOST}:9099"
FUNCTIONS = f"http://{HOST}:5001/{PROJECT}/us-central1"
FIRESTORE = f"http://{HOST}:8080/v1/projects/{PROJECT}/databases/(default)/documents"
# The Auth emulator accepts this literal string in place of a Web API key.
FAKE_KEY = "fake-api-key"


def _request(url, payload=None, headers=None, method=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            return e.code, json.loads(body or "{}")
        except json.JSONDecodeError:
            return e.code, {"raw": body}


# ── auth ────────────────────────────────────────────────────────────────────

def signin(e164):
    """sendVerificationCode -> read the code the emulator "sent" -> signInWithPhoneNumber."""
    status, body = _request(
        f"{AUTH}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key={FAKE_KEY}",
        {"phoneNumber": e164},
    )
    if status != 200:
        raise SystemExit(f"sendVerificationCode failed: {status} {body}")
    session = body["sessionInfo"]

    code = None
    for _ in range(20):
        _, codes = _request(f"{AUTH}/emulator/v1/projects/{PROJECT}/verificationCodes")
        mine = [c for c in codes.get("verificationCodes", []) if c.get("phoneNumber") == e164]
        if mine:
            code = mine[-1]["code"]
            break
        time.sleep(0.25)
    if not code:
        raise SystemExit(f"no verification code for {e164}")

    status, body = _request(
        f"{AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key={FAKE_KEY}",
        {"sessionInfo": session, "code": code},
    )
    if status != 200:
        raise SystemExit(f"signInWithPhoneNumber failed: {status} {body}")
    return {"idToken": body["idToken"], "uid": body["localId"]}


# ── callables ───────────────────────────────────────────────────────────────

def call(name, id_token, data):
    """The standard envelope: POST {"data":{...}} -> 200 {"result":{...}}.

    The contract's error CODES arrive as `error.message`, not as the status — clients
    switch on the message, and so does this.
    """
    status, body = _request(
        f"{FUNCTIONS}/{name}",
        {"data": data},
        headers={"Authorization": f"Bearer {id_token}"},
    )
    if status != 200 or "error" in body:
        message = (body.get("error") or {}).get("message", body)
        raise SystemExit(f"callable {name} failed: {status} {message}")
    return body.get("result")


# ── firestore reads ─────────────────────────────────────────────────────────

def _decode(value):
    if "nullValue" in value:
        return None
    if "stringValue" in value:
        return value["stringValue"]
    if "integerValue" in value:
        return int(value["integerValue"])
    if "doubleValue" in value:
        return float(value["doubleValue"])
    if "booleanValue" in value:
        return value["booleanValue"]
    if "timestampValue" in value:
        return value["timestampValue"]
    if "mapValue" in value:
        return {k: _decode(v) for k, v in (value["mapValue"].get("fields") or {}).items()}
    if "arrayValue" in value:
        return [_decode(v) for v in (value["arrayValue"].get("values") or [])]
    return value


def _fields(doc):
    out = {k: _decode(v) for k, v in (doc.get("fields") or {}).items()}
    out["id"] = doc["name"].rsplit("/", 1)[-1]
    return out


def get(path):
    status, body = _request(f"{FIRESTORE}/{path}", headers={"Authorization": "Bearer owner"})
    if status == 404:
        return None
    if status != 200:
        raise SystemExit(f"firestore get {path} failed: {status} {body}")
    return _fields(body)


def list_(path, page_size=1000):
    status, body = _request(
        f"{FIRESTORE}/{path}?pageSize={page_size}",
        headers={"Authorization": "Bearer owner"},
    )
    if status == 404:
        return []
    if status != 200:
        raise SystemExit(f"firestore list {path} failed: {status} {body}")
    return [_fields(d) for d in body.get("documents", [])]


def find_pending_pair(uid):
    for pair in list_("pairs"):
        if pair.get("status") == "pending" and pair.get("createdBy") == uid:
            return pair
    return None


def active_trip(pair_id):
    live = [
        t
        for t in list_("trips")
        if t.get("pairId") == pair_id and t.get("state") in ("armed", "driving")
    ]
    live.sort(key=lambda t: t.get("createdAt") or 0)
    return live[-1] if live else None


def haversine(a_lat, a_lng, b_lat, b_lng):
    import math

    r = 6371000.0
    d_lat = math.radians(b_lat - a_lat)
    d_lng = math.radians(b_lng - a_lng)
    s = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(a_lat)) * math.cos(math.radians(b_lat)) * math.sin(d_lng / 2) ** 2
    )
    return 2 * r * math.asin(min(1.0, math.sqrt(s)))


def trip_summary(trip_id):
    """Everything ios/scripts/e2e-drive.sh asserts about a trip, in one read.

    `farGapSec` / `nearGapSec` are the MEDIAN seconds between consecutive position
    documents on each side of `bands.near`. The contract's cadence rows are
    "30 s / 200 m" in far and "5 s / 10 m" in near, whichever comes first — at 12 m/s
    the 200 m displacement wins in far (~17 s) and the 10 m one wins in near (~1 s),
    so the assertion is that the cadence TIGHTENS, not that it equals 30 and 5.
    """
    trip = get(f"trips/{trip_id}")
    if trip is None:
        return None
    spot = trip.get("spot") or {}
    near_band = ((trip.get("bands") or {}).get("near")) or 0
    positions = sorted(list_(f"trips/{trip_id}/positions"), key=lambda p: p.get("ts") or 0)
    far, near = [], []
    for p in positions:
        d = haversine(p["lat"], p["lng"], spot["lat"], spot["lng"])
        (near if d <= near_band else far).append(p)

    def median_gap(rows):
        gaps = [
            (rows[i]["ts"] - rows[i - 1]["ts"]) / 1000.0
            for i in range(1, len(rows))
        ]
        if not gaps:
            return None
        gaps.sort()
        return round(gaps[len(gaps) // 2], 2)

    last = trip.get("lastPos")
    return {
        "id": trip_id,
        "state": trip.get("state"),
        "phaseHint": trip.get("phaseHint"),
        "routingCalls": trip.get("routingCalls"),
        "hasRoutePolyline": "routePolyline" in trip,
        "bandsNear": near_band,
        "positions": len(positions),
        "withEtaSec": sum(1 for p in positions if "etaSec" in p),
        "extraKeys": sorted(
            {
                k
                for p in positions
                for k in p.keys()
                if k
                not in ("lat", "lng", "accuracyM", "speedMps", "ts", "expireAt", "etaSec", "id")
            }
        ),
        "farPositions": len(far),
        "nearPositions": len(near),
        "farGapSec": median_gap(far),
        "nearGapSec": median_gap(near),
        "lastPosDistM": (
            round(haversine(last["lat"], last["lng"], spot["lat"], spot["lng"]), 1)
            if last
            else None
        ),
        "alerts": trip.get("alerts"),
    }


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)
    cmd = argv[1]
    if cmd == "signin":
        out = signin(argv[2])
    elif cmd == "call":
        out = call(argv[2], argv[3], json.loads(argv[4]))
    elif cmd == "get":
        out = get(argv[2])
    elif cmd == "list":
        out = list_(argv[2])
    elif cmd == "find-pending-pair":
        out = find_pending_pair(argv[2])
    elif cmd == "active-trip":
        out = active_trip(argv[2])
    elif cmd == "trip-summary":
        out = trip_summary(argv[2])
    else:
        raise SystemExit(f"unknown command {cmd}")
    print(json.dumps(out))


if __name__ == "__main__":
    main(sys.argv)
