#!/usr/bin/env python3
"""Injecte les permissions et reglages Android dans les fichiers generes par
`flutter create`. Execute automatiquement par GitHub Actions avant le build APK.
Le script est idempotent : on peut le relancer sans risque.
"""

import os
import re
import sys

MANIFEST = os.path.join("android", "app", "src", "main", "AndroidManifest.xml")

GROOVY_SNIPPET = """
// Force chaque module de plugin a compiler contre le SDK 36 (ajout automatique)
subprojects {
    afterEvaluate { sub ->
        if (sub.hasProperty('android')) {
            sub.android.compileSdkVersion 36
        }
    }
}
"""

KOTLIN_SNIPPET = """
subprojects {
    val forceSdk = {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                androidExt.javaClass
                    .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    .invoke(androidExt, 36)
            } catch (e: Exception) {
            }
        }
    }
    if (state.executed) {
        forceSdk()
    } else {
        afterEvaluate { forceSdk() }
    }
}
// ajout automatique
"""

PERMISSIONS = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
"""


def patch_manifest():
    if not os.path.exists(MANIFEST):
        print("Manifeste introuvable :", MANIFEST)
        return False

    with open(MANIFEST, "r", encoding="utf-8") as f:
        content = f.read()

    if "MANAGE_EXTERNAL_STORAGE" not in content:
        content = content.replace("    <application", PERMISSIONS + "    <application", 1)

    if "requestLegacyExternalStorage" not in content:
        content = content.replace(
            "    <application",
            '    <application\n        android:requestLegacyExternalStorage="true"',
            1,
        )

    content = re.sub(
        r'android:label="[^"]*"', 'android:label="Anime Organizer"', content, count=1
    )

    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(content)
    print("Manifeste mis a jour.")
    return True


def patch_gradle():
    for name in ("build.gradle", "build.gradle.kts"):
        path = os.path.join("android", "app", name)
        if not os.path.exists(path):
            continue
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        # minSdk : requis par media_kit
        content = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", content)
        content = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", content)
        content = re.sub(r"minSdk\s+flutter\.minSdkVersion", "minSdk 23", content)

        # compileSdk : file_picker et flutter_plugin_android_lifecycle exigent 36
        content = re.sub(r"compileSdkVersion\s+flutter\.compileSdkVersion", "compileSdkVersion 36", content)
        content = re.sub(r"compileSdk\s*=\s*flutter\.compileSdkVersion", "compileSdk = 36", content)
        content = re.sub(r"compileSdk\s+flutter\.compileSdkVersion", "compileSdk 36", content)
        content = re.sub(r"compileSdk\s*=\s*3[0-5]\b", "compileSdk = 36", content)

        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print("Gradle mis a jour :", path)
    return True




MARKER = "ajout automatique"


def patch_root_gradle():
    """Certains plugins se compilent contre un SDK trop ancien.
    On impose le SDK 36 a tous les sous-projets depuis le build racine."""
    for name, snippet in (
        ("build.gradle", GROOVY_SNIPPET),
        ("build.gradle.kts", KOTLIN_SNIPPET),
    ):
        path = os.path.join("android", name)
        if not os.path.exists(path):
            continue
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        if MARKER in content:
            print("Build racine deja patche :", path)
            continue
        with open(path, "a", encoding="utf-8") as f:
            f.write(snippet)
        print("Build racine mis a jour :", path)
    return True


if __name__ == "__main__":
    ok = patch_manifest()
    patch_gradle()
    patch_root_gradle()
    sys.exit(0 if ok else 1)
