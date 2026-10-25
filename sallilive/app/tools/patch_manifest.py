"""Adds permissions + app label to the generated Android manifest (run in CI after flutter create)."""
import re

p = "android/app/src/main/AndroidManifest.xml"
x = open(p, encoding="utf-8").read()
perms = "".join(
    f'    <uses-permission android:name="android.permission.{n}"/>\n'
    for n in ["INTERNET", "ACCESS_NETWORK_STATE", "RECORD_AUDIO", "MODIFY_AUDIO_SETTINGS", "BLUETOOTH", "BLUETOOTH_CONNECT", "WAKE_LOCK"]
)
if "RECORD_AUDIO" not in x:
    x = x.replace("<application", perms + "    <application", 1)
x = re.sub(r'android:label="[^"]*"', 'android:label="SalliLive"', x, count=1)
open(p, "w", encoding="utf-8").write(x)
print("manifest ok")
