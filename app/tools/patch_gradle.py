"""Gradle tweaks applied in CI after `flutter create`:
1. force every plugin module to compile against a recent SDK (agora_rtc_engine ships with 31)
2. drop optional Agora extension libraries we do not use, to shrink the APK
   (re-add the video ones here when video rooms are introduced)."""
import os

EXCLUDES = [
    "libagora_segmentation_extension.so",
    "libagora_clear_vision_extension.so",
    "libagora_content_inspect_extension.so",
    "libagora_face_capture_extension.so",
    "libagora_face_detection_extension.so",
    "libagora_lip_sync_extension.so",
    "libagora_screen_capture_extension.so",
    "libagora_spatial_audio_extension.so",
    "libagora_video_av1_encoder_extension.so",
    "libagora_video_av1_decoder_extension.so",
    "libagora_video_quality_analyzer_extension.so",
    "libagora_audio_beauty_extension.so",
    "libagora_pvc_extension.so",
]

KTS_ROOT = """// --- SalliLive: raise compileSdk of plugin modules ---
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.withGroovyBuilder { "compileSdkVersion"(36) }
    }
}
// ---
"""
GROOVY_ROOT = """// --- SalliLive: raise compileSdk of plugin modules ---
subprojects {
    afterEvaluate { p ->
        if (p.hasProperty('android')) { p.android.compileSdkVersion 36 }
    }
}
// ---
"""


def prepend(files, snippet):
    for name in files:
        if os.path.exists(name):
            src = open(name, encoding="utf-8").read()
            if "SalliLive" not in src:
                open(name, "w", encoding="utf-8").write(snippet + "\n" + src)
            print("patched", name)
            return
    raise SystemExit("gradle file not found: " + ", ".join(files))


def append(files, snippet):
    for name in files:
        if os.path.exists(name):
            src = open(name, encoding="utf-8").read()
            if "SalliLive-excludes" not in src:
                open(name, "w", encoding="utf-8").write(src + "\n" + snippet)
            print("patched", name)
            return
    raise SystemExit("gradle file not found: " + ", ".join(files))


prepend(["android/build.gradle.kts", "android/build.gradle"],
        KTS_ROOT if os.path.exists("android/build.gradle.kts") else GROOVY_ROOT)

kts_items = ", ".join(f'"**/{n}"' for n in EXCLUDES)
app_kts = f"""// SalliLive-excludes
android {{
    packaging {{
        jniLibs {{
            excludes += listOf({kts_items})
        }}
    }}
}}
"""
groovy_items = "\n".join(f"        exclude '**/{n}'" for n in EXCLUDES)
app_groovy = f"""// SalliLive-excludes
android {{
    packagingOptions {{
{groovy_items}
    }}
}}
"""
append(["android/app/build.gradle.kts", "android/app/build.gradle"],
       app_kts if os.path.exists("android/app/build.gradle.kts") else app_groovy)
