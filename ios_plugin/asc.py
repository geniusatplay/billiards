#!/usr/bin/env python3
"""Fetches the App Store signing files from Apple for the TestFlight build (26 Nov 2026).

  python3 ios_plugin/asc.py fetch <folder>

Needs the environment variables ASC_KEY_ID, ASC_ISSUER_ID (the App Store Connect API key's ids) and the key itself in
~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8, plus <folder>/dist.key (the Apple Distribution certificate's
private key). Writes into <folder>:
  dist.cer              the Apple Distribution certificate whose public key matches dist.key (DER)
  app.mobileprovision   the active App Store profile "Emerald 8 Ball Pool App Store" (or $IOS_PROFILE_NAME)
Nothing secret is printed. Needs the Python packages PyJWT and cryptography."""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import serialization

API = "https://api.appstoreconnect.apple.com/v1/"
PROFILE_NAME = os.environ.get("IOS_PROFILE_NAME", "Emerald 8 Ball Pool App Store")
BUNDLE_ID = "com.emeraldvortexgames.emeraldbreak"


def token() -> str:
    kid = os.environ["ASC_KEY_ID"]
    p8 = open(os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_%s.p8" % kid), "rb").read()
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                      p8, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})


def get(path: str, params: dict) -> dict:
    url = API + path + ("?" + urllib.parse.urlencode(params) if params else "")
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:600]
        raise SystemExit("App Store Connect API %s: HTTP %d %s" % (path, e.code, body))


def spki(pub) -> bytes:
    return pub.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)


def fetch(folder: str) -> None:
    key = serialization.load_pem_private_key(open(os.path.join(folder, "dist.key"), "rb").read(), password=None)
    mine = spki(key.public_key())
    certs = get("certificates", {"filter[certificateType]": "DISTRIBUTION,IOS_DISTRIBUTION", "limit": "200"})["data"]
    der = None
    for c in certs:
        raw = base64.b64decode(c["attributes"]["certificateContent"])
        if spki(x509.load_der_x509_certificate(raw).public_key()) == mine:
            der = raw
            print("certificate: %s (%s), expires %s" % (c["id"], c["attributes"].get("name", ""),
                                                        c["attributes"].get("expirationDate", "")))
            break
    if der is None:
        raise SystemExit("no Apple Distribution certificate matches the private key (%d certificates looked at)" % len(certs))
    open(os.path.join(folder, "dist.cer"), "wb").write(der)
    profs = get("profiles", {"filter[name]": PROFILE_NAME, "filter[profileType]": "IOS_APP_STORE", "limit": "20"})["data"]
    active = [p for p in profs if p["attributes"].get("profileState") == "ACTIVE"]
    if not active:
        raise SystemExit("no active App Store profile named %r (found %d): regenerate it in Certificates, Identifiers "
                         "& Profiles" % (PROFILE_NAME, len(profs)))
    p = active[0]
    open(os.path.join(folder, "app.mobileprovision"), "wb").write(base64.b64decode(p["attributes"]["profileContent"]))
    print("profile: %s (%s), expires %s" % (p["id"], PROFILE_NAME, p["attributes"].get("expirationDate", "")))


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "fetch":
        raise SystemExit(__doc__)
    fetch(sys.argv[2])
