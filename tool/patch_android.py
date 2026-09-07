#!/usr/bin/env python3
"""Injecte les permissions et reglages Android dans les fichiers generes par
`flutter create`. Execute automatiquement par GitHub Actions avant le build APK.
Le script est idempotent : on peut le relancer sans risque.
"""

import os
import re
import sys

MANIFEST = os.path.join("android", "app", "src", "main", "AndroidManifest.xml")

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

        content = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", content)
        content = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", content)
        content = re.sub(r"minSdk\s+flutter\.minSdkVersion", "minSdk 23", content)

        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print("Gradle mis a jour :", path)
    return True


if __name__ == "__main__":
    ok = patch_manifest()
    patch_gradle()
    sys.exit(0 if ok else 1)
