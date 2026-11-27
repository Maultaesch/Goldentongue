#!/usr/bin/env python3
"""Prepares the generated ios/ and android/ projects for the stores. Safe to run more than once.
Usage (after `flutter create --platforms=ios,android .`):  python3 scripts/setup_mobile.py [project_dir]
Adds: microphone and speech recognition texts, the login deep link, internet and microphone permissions,
the speech recognition query, the app name and the export-compliance flag (standard HTTPS only)."""
import pathlib, plistlib, re, sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
SCHEME = "io.goldentongue"
NAME = "GoldenTongue"


def ios():
    path = root / "ios/Runner/Info.plist"
    if not path.exists():
        print("skip iOS (no ios/Runner/Info.plist)")
        return
    with open(path, "rb") as f:
        p = plistlib.load(f)
    p["CFBundleDisplayName"] = NAME
    p["NSMicrophoneUsageDescription"] = "The microphone is used to record your voice for the voice analysis and the voice call practice."
    p["NSSpeechRecognitionUsageDescription"] = "Speech recognition turns what you say into text during voice call practice."
    p["ITSAppUsesNonExemptEncryption"] = False
    urls = p.setdefault("CFBundleURLTypes", [])
    if not any(SCHEME in u.get("CFBundleURLSchemes", []) for u in urls):
        urls.append({"CFBundleURLName": SCHEME, "CFBundleURLSchemes": [SCHEME]})
    with open(path, "wb") as f:
        plistlib.dump(p, f)
    print("iOS Info.plist ready")


def android():
    path = root / "android/app/src/main/AndroidManifest.xml"
    if not path.exists():
        print("skip Android (no AndroidManifest.xml)")
        return
    t = path.read_text(encoding="utf-8")
    perms = ["android.permission.INTERNET", "android.permission.RECORD_AUDIO"]
    for perm in perms:
        if perm not in t:
            t = re.sub(r"(<manifest[^>]*>)", r'\1\n    <uses-permission android:name="%s"/>' % perm, t, count=1)
    if "android.speech.RecognitionService" not in t:
        q = '\n    <queries>\n        <intent>\n            <action android:name="android.speech.RecognitionService"/>\n        </intent>\n    </queries>'
        t = t.replace("<application", q.strip("\n") + "\n    <application", 1)
    if f'android:scheme="{SCHEME}"' not in t:
        f = ('            <intent-filter>\n'
             '                <action android:name="android.intent.action.VIEW"/>\n'
             '                <category android:name="android.intent.category.DEFAULT"/>\n'
             '                <category android:name="android.intent.category.BROWSABLE"/>\n'
             f'                <data android:scheme="{SCHEME}" android:host="login-callback"/>\n'
             '            </intent-filter>\n')
        t = t.replace("</activity>", f + "        </activity>", 1)
    t = re.sub(r'android:label="[^"]*"', f'android:label="{NAME}"', t, count=1)
    path.write_text(t, encoding="utf-8")
    print("Android manifest ready")


ios()
android()
