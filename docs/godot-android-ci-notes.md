# Godot 4.6 → Android APK in GitHub Actions — what we learned

Built `ball-connect` end-to-end in CI in **9 workflow runs**. Most of those
were spent fighting Godot's headless mode, which **silently swallows
validation errors** during Android export. Future projects: copy this
workflow and `export_presets.cfg`, skip the pain.

## TL;DR — what to do (and what NOT to do)

### Do

- Pin **Godot 4.6.2** (or whatever stable version you use locally) and pull
  the matching headless binary + export templates from the official GitHub
  releases. The `gh api repos/godotengine/godot/releases` query gives you
  the exact filenames.
- Set `rendering/textures/vram_compression/import_etc2_astc=true` in
  `project.godot`. **This is mandatory for Android, even with the GL
  Compatibility renderer.** Without it, headless export prints just
  `Cannot export project with preset "Android" due to configuration errors:`
  with **nothing after the colon** — the reason is silently dropped.
- Use **Gradle build** path (`gradle_build/use_gradle_build=true`). The
  prebuilt-APK path is technically supported but had its own silent
  validation failures in 4.6 that I never debugged.
- In CI, "install" the build template by extracting `android_source.zip`
  from the export-templates `.tpz` into `<project>/android/build/`,
  **plus** writing two marker files:
  - `<project>/android/build/.gdignore` (tells Godot not to import as game
    assets)
  - `<project>/android/.build_version` containing `X.Y.Z.stable` (this is
    the file Godot's gradle-build version check actually reads — NOT
    `version.txt` in the build dir).
- Editor settings file lives at `~/.config/godot/editor_settings-X.Y.tres`
  (minor-versioned). Godot 4.6 reads `editor_settings-4.6.tres`, **not**
  `editor_settings-4.tres`.
- Generate a fresh PKCS12 debug keystore in CI. JKS works too but PKCS12
  is the modern default and `keytool` ships with the JDK already.
- Use `softprops/action-gh-release@v2` with `tag_name: latest` +
  `prerelease: true` for a rolling pre-release; tag-pushed `vX.Y.Z` makes
  permanent releases. Both can coexist.

### Don't

- **Don't trust headless mode error messages.** When Godot prints
  `due to configuration errors:` followed by nothing, *something is wrong*
  but the actual reason was dropped to `/dev/null`. Open the editor's
  Project → Export → Add → Android dialog locally — that's where the real
  red-text error list lives.
- **Don't write `editor_settings-4.tres`** in Godot 4.6. Godot will create
  its own `editor_settings-4.6.tres` with empty defaults and silently
  ignore yours. Your SDK paths and keystore config never apply.
- **Don't write `version.txt` with the full `X.Y.Z.stable.official.<hash>`
  string from `godot --version`.** Godot wants `X.Y.Z.stable` only.
  Anything longer triggers a "build version mismatch" error.
- **Don't write `version.txt` without also writing `.build_version`.**
  Godot's check fires on `.build_version`; if it's missing you get
  `no version info for it exists`. The `version.txt` is for the editor's
  benefit, not the version validation.
- **Don't set `export/android/debug_keystore_user`** in editor settings on
  Godot 4.6. The property was removed and Godot drops it on first save —
  set the keystore path + password only.
- **Don't use the prebuilt-APK template path** (`use_gradle_build=false`)
  unless you're committing to debug it. Gradle is the default direction.
- **Don't try to "fix" the empty `Cannot export... configuration errors:`
  message by adding `--verbose`.** It's empty by design. Open the editor.

## The two real fixes that unblocked the build

After 9 runs, **two changes** stood between failure and a working APK:

**Fix #1 — `project.godot`:**
```ini
[rendering]
textures/vram_compression/import_etc2_astc=true
```

**Fix #2 — CI workflow, after extracting `android_source.zip`:**
```bash
echo -n "${GODOT_VERSION}.stable" > android/.build_version
echo -n "${GODOT_VERSION}.stable" > android/build/version.txt
touch android/build/.gdignore
```

Where `GODOT_VERSION="4.6.2"` and the resulting content is `4.6.2.stable`
(no `.official.<hash>` suffix). Both `.build_version` and `version.txt`
should match.

## Workflow-shaped reusable template

The full workflow is `.github/workflows/build-android.yml` in this repo.
Key shape, in order:

1. `actions/checkout@v4`
2. `actions/setup-java@v4` with `java-version: '17'` distribution `temurin`
3. `android-actions/setup-android@v3` with `packages: 'platform-tools'` (the
   default `tools platform-tools` fails because Google removed the legacy
   `tools` package), then `sdkmanager` for `platform-tools`,
   `platforms;android-34`, `build-tools;34.0.0`
4. `wget` Godot Linux headless from
   `https://github.com/godotengine/godot/releases/download/${VERSION}-stable/Godot_v${VERSION}-stable_linux.x86_64.zip`,
   `chmod +x`
5. `wget` export templates `.tpz` from same release, unzip to
   `~/.local/share/godot/export_templates/${VERSION}.stable/`
6. `keytool -genkeypair` (PKCS12) → `debug.keystore`
7. Write `~/.config/godot/editor_settings-${MAJOR.MINOR}.tres` with java
   path, android path, debug keystore path, debug keystore pass
8. `unzip android_source.zip -d android/build`, then write `.gdignore` +
   `version.txt` + `../.build_version`
9. `./godot --headless --import .` (twice — first run sometimes errors)
10. `./godot --headless --verbose --export-debug "Android" out.apk`
11. `actions/upload-artifact@v4` for the APK
12. Conditional `softprops/action-gh-release@v2` for `latest` rolling
    pre-release on main pushes, separate for `vX.Y.Z` tags

## `export_presets.cfg` — what actually matters

The hand-written `export_presets.cfg` at the repo root has ~200 lines of
permission flags etc. Most of those don't matter; Godot fills defaults.
The lines that matter for an APK build:

```ini
[preset.0]
name="Android"
platform="Android"
runnable=true
export_path="ball-connect.apk"

[preset.0.options]
gradle_build/use_gradle_build=true
architectures/arm64-v8a=true
architectures/armeabi-v7a=false   # 32-bit ARM, ancient phones
architectures/x86=false           # emulator only
architectures/x86_64=false        # emulator only
package/unique_name="com.matswm.ballconnect"
package/name="Ball Connect"
package/signed=true
```

Everything else is permission flags (all `false`), screen support flags,
keystore paths (we wire those via editor settings instead), etc.

## Debugging method that actually worked

When CI fails with the empty `configuration errors:` message:

1. Open the project locally in the same Godot version.
2. Project → Export → Add… → Android.
3. Scroll to the bottom of the dialog. There's a **red text block** listing
   exactly what's missing, in plain English ("Java SDK path not configured",
   "Build template not installed", "Target platform requires ETC2/ASTC
   texture compression", etc).
4. Each of those reds becomes a fix in CI (project setting, editor settings
   value, marker file, etc).

This is **dramatically** faster than iterating CI runs and reading the
silent stub messages. ~5 minutes of clicking in the editor unblocked us
after ~30 minutes of CI guessing.

## Misc

- The `cannot connect to daemon at tcp:5037: Connection refused` warning
  spam in CI logs is `adb` trying to talk to a phone that isn't there.
  **Ignore it** — it's not an error.
- Java 17 is what Godot 4.6 wants for the Gradle build. Java 21 *might*
  work but I haven't tested.
- This repo uses a **stable debug keystore** stored as the
  `ANDROID_DEBUG_KEYSTORE_BASE64` GitHub secret (base64-encoded PKCS12,
  password `android`, alias `androiddebugkey`). The local copy lives at
  `~/.local/share/godot/keystores/debug.keystore` (the path Godot's
  editor settings already point at). Workflow decodes the secret to
  `$GITHUB_WORKSPACE/debug.keystore` per run; signature stays constant
  so reinstalling a newer APK over an older one doesn't require
  uninstall first. Workflow falls back to ephemeral keystore generation
  if the secret is unset, so forks still produce a (single-use) APK.
- To set up the stable keystore in a new repo:
  ```bash
  keytool -genkeypair -v \
    -keystore ~/.local/share/godot/keystores/debug.keystore \
    -alias androiddebugkey -storepass android -keypass android \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" -storetype PKCS12
  base64 -w 0 ~/.local/share/godot/keystores/debug.keystore | \
    gh secret set ANDROID_DEBUG_KEYSTORE_BASE64 -R OWNER/REPO
  ```

## Stack pick rationale (for reference)

For a small 2D puzzle game from a Python-experienced solo dev:

- **Godot 4 + GDScript** ✓ — fastest path, Python-adjacent syntax, hot
  reload, native Android export. Worked.
- Flutter + Flame — would also work, but smaller game-dev ecosystem.
- libGDX, Unity, Rork, Replit Agent — all eliminated for various reasons
  (verbosity, licensing fiasco, CRUD-focused, not a real game tool).

If next game is also a 2D puzzle/casual: **stay on Godot 4 + GDScript +
this CI workflow**. If it's 3D or needs heavy physics: revisit.
