"""Run: python3 scripts/test_setup_mobile.py  (checks scripts/setup_mobile.py on sample project files)"""
import pathlib, plistlib, subprocess, sys, tempfile

PLIST = plistlib.dumps({"CFBundleName": "goldentongue", "CFBundleDisplayName": "GoldenTongue"})
MANIFEST = '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="goldentongue"
        android:name="${applicationName}">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
'''
here = pathlib.Path(__file__).parent / "setup_mobile.py"
with tempfile.TemporaryDirectory() as d:
    root = pathlib.Path(d)
    (root / "ios/Runner").mkdir(parents=True)
    (root / "android/app/src/main").mkdir(parents=True)
    (root / "ios/Runner/Info.plist").write_bytes(PLIST)
    manifest = root / "android/app/src/main/AndroidManifest.xml"
    manifest.write_text(MANIFEST)
    for _ in range(2):  # twice: must be idempotent
        subprocess.run([sys.executable, str(here), d], check=True, capture_output=True)
    p = plistlib.loads((root / "ios/Runner/Info.plist").read_bytes())
    assert "NSMicrophoneUsageDescription" in p and "NSSpeechRecognitionUsageDescription" in p
    assert p["ITSAppUsesNonExemptEncryption"] is False
    assert len(p["CFBundleURLTypes"]) == 1 and p["CFBundleURLTypes"][0]["CFBundleURLSchemes"] == ["io.goldentongue"]
    t = manifest.read_text()
    for needle in ["android.permission.INTERNET", "android.permission.RECORD_AUDIO", "android.speech.RecognitionService", 'android:scheme="io.goldentongue"', 'android:label="GoldenTongue"']:
        assert t.count(needle) == 1, (needle, t.count(needle))
    assert t.index("<queries>") < t.index("<application")
    assert t.index("login-callback") < t.index("</activity>")
print("setup_mobile: ok (idempotent, all entries present once)")
