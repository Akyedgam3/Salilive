"""Forces every Android plugin module to compile against a recent SDK (agora_rtc_engine ships with 31).
Run in CI after `flutter create`."""
import os

KTS = """// --- SalliLive: raise compileSdk of plugin modules ---
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.withGroovyBuilder { "compileSdkVersion"(36) }
    }
}
// ---
"""
GROOVY = """// --- SalliLive: raise compileSdk of plugin modules ---
subprojects {
    afterEvaluate { p ->
        if (p.hasProperty('android')) { p.android.compileSdkVersion 36 }
    }
}
// ---
"""

for name, snippet in (("android/build.gradle.kts", KTS), ("android/build.gradle", GROOVY)):
    if os.path.exists(name):
        src = open(name, encoding="utf-8").read()
        if "SalliLive" not in src:
            open(name, "w", encoding="utf-8").write(snippet + "\n" + src)
        print("patched", name)
        break
else:
    raise SystemExit("no root gradle file found")
