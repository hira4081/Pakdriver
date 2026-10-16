#!/usr/bin/env python3
"""Run once after `flutter create` (see README). Idempotent.

Adds to the generated Android project:
  - INTERNET + location permissions
  - app label "PakDrive"
  - <queries> so url_launcher can open the dialer / maps
  - cleartext HTTP in the *debug* manifest only (so the emulator can reach http://10.0.2.2:8080)
"""
import pathlib
import re
import sys

base = pathlib.Path(__file__).resolve().parent.parent / "android" / "app" / "src"
main = base / "main" / "AndroidManifest.xml"
debug = base / "debug" / "AndroidManifest.xml"

if not main.exists():
    sys.exit("android/ not found. Run: flutter create --org com.pakdrive --project-name pakdrive --platforms=android .")

s = main.read_text()

perms = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
]
add = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in s)
if add:
    s = s.replace("<application", add + "    <application", 1)

s = re.sub(r'android:label="[^"]*"', 'android:label="PakDrive"', s, count=1)

if "<queries>" not in s:
    queries = """    <queries>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
        <intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>
    </queries>
"""
    s = s.replace("</manifest>", queries + "</manifest>")

main.write_text(s)

if debug.exists():
    d = debug.read_text()
    if "usesCleartextTraffic" not in d:
        d = d.replace("<manifest", "<manifest", 1)
        if "<application" in d:
            d = d.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
        else:
            d = d.replace("</manifest>", '    <application android:usesCleartextTraffic="true"/>\n</manifest>')
        debug.write_text(d)

print("Android manifest patched.")
