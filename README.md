# Secure Vault

Flutter app for storing supported local files as authenticated, encrypted blobs. Native targets are Android, Windows, and macOS; the web target stores the vault locally in the browser.

## Web app

Live web app: [Secure Vault](https://ashishthakur-sudo.github.io/secure-vault-web/).

Build the browser version with:

```powershell
flutter pub get
flutter build web --release
```

To test it locally, run `flutter run -d chrome` or serve the `build\web` folder over HTTPS or `localhost`. The browser version uses browser-native IndexedDB and secure browser storage; encrypted files stay in that browser profile and origin. It has no server-side database or account sync, and its data is separate from the Windows/Android vaults and other browsers/devices. Clearing browser data can permanently erase the local vault. Browser media playback depends on supported codecs.

Serve the app only over HTTPS or localhost: secure browser storage requires a secure context. A static host can serve the frontend, but does not receive or store vault files.

## Shared folder (cloud)

The **Shared** folder button in the vault opens a cloud folder that different users can access with the same four-digit password. Unlike the private local vault, shared files are uploaded to a Supabase Storage bucket so other users can list and download them. Cloud files are not end-to-end encrypted; the project owner/Supabase administrators can access them. Do not use it for sensitive files. A four-digit password is weak; the Edge Function limits incorrect attempts to five per IP per 15-minute window, but this is not equivalent to strong account authentication.

To enable Shared, create a Supabase project, install the Supabase CLI, then from this repository run:

```powershell
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
supabase functions deploy shared-vault --no-verify-jwt
supabase secrets set SHARED_FOLDER_PIN=1234
```

Replace `1234` with your chosen four-digit password. Supabase supplies the project URL and service-role secret to the Edge Function; never put a service-role key in this app or publish it. In Secure Vault, each user opens **Shared → Configure shared folder** and enters the same Supabase project URL and its public anon/publishable key from **Project Settings → API**. The public key is intended for client use; the service-role secret is not. Rebuild and deploy the web app after code changes using the existing GitHub Pages deployment process. Shared uploads are currently limited to 4 MB each. Native app downloads are saved under `Documents\SecureVaultShared`; browser downloads use the browser's download location.

## Use the app on a Windows laptop

The Android APK does not run on Windows. Build the Windows desktop app instead:

1. Install Flutter stable and add its `bin` directory to your `PATH`.
2. Install **Visual Studio 2022** or **Visual Studio Build Tools 2022** with the **Desktop development with C++** workload. Include the recommended MSVC C++ build tools, CMake tools, and Windows 10/11 SDK.
3. Open this project folder in VS Code and choose **Terminal → New Terminal**. Check that Flutter recognizes the Windows compiler:

   ```powershell
   flutter doctor -v
   ```

   Resolve any Visual Studio or Windows desktop toolchain error before building. If Flutter reports that plugin symlinks are unavailable, enable Windows Developer Mode in **Settings → System → For developers**, then reopen VS Code.

4. Fetch dependencies and prepare the Windows PDF viewer:

   ```powershell
   flutter pub get
   dart run pdfx:install_windows
   ```

5. Run the app on the laptop:

   ```powershell
   flutter run -d windows
   ```

   Or build an optimized desktop release:

   ```powershell
   flutter build windows --release
   ```

6. Launch `build\windows\x64\runner\Release\secure_vault.exe`. Keep the entire `Release` folder together: the executable needs the neighboring DLLs and `data` folder. To move the app to another Windows laptop, copy or zip the whole folder, not just the `.exe`.

On first launch, create a master password. Your encrypted vault is stored in your Windows Documents directory under `.SecureVault`; unlock it with that password on later launches. Use the eye button in the password field to reveal or hide your password before unlocking.

To open the app from a browser address bar on this Windows account, register the local URL protocol once:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tooling\register_secure_vault_protocol.ps1
```

Then enter `securevault://open` in the browser address bar and approve the browser's prompt to open Secure Vault. This is a Windows-only link to the installed local app, not a public website; register it again if you move the app folder or use another Windows account.

## App icon

The Android launcher and Windows executable share the Secure Vault shield-and-lock icon. To regenerate the Android density icons and Windows `.ico` after changing the icon artwork in `tooling\generate_app_icons.ps1`, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tooling\generate_app_icons.ps1
```

Rebuild with `flutter build apk --release` for Android and `flutter build windows --release` for Windows to include the updated icon in each app.

## Security behavior

- A first-run master password is bcrypt-hashed and stored with `flutter_secure_storage`. The vault encryption key is separately derived from the password and a random per-install salt using PBKDF2-HMAC-SHA256.
- Files and vault metadata are encrypted using AES-256-CBC with encrypt-then-MAC HMAC-SHA256. A local SQLite database (`.vault-metadata.db`) stores only random file IDs and encrypted metadata; original filenames are not stored in plaintext. Existing encrypted JSON indexes are migrated to SQLite on the next successful unlock.
- Images render from `Image.memory`; PDFs use `PdfDocument.openData`. Audio/video are decrypted into a Dart memory buffer and streamed by a short-lived HTTP server bound only to `127.0.0.1`; no decrypted media file is written to storage.
- The optional decoy PIN opens a read-only empty view. It does not store a second vault.
- Imported inputs are read into memory before encryption. The app cannot erase or protect the original source file.

This protects vault contents at rest while the device is locked. It does not protect against a compromised/unlocked operating system, screenshots, memory inspection, backups of source files, or a weak password. Dart cannot guarantee immediate zeroization of every copy of a key or plaintext buffer.

SQLite is local storage, not a remote/shared database. The database is created automatically inside `.SecureVault` on first use; back up the entire vault folder while the app is locked, and keep the master password because the encrypted files and metadata cannot be recovered without it.

## Generate platform scaffolding

Install Flutter stable and the relevant platform toolchains. In VS Code, open this folder, open **Terminal → New Terminal**, and run:

```powershell
flutter create --project-name secure_vault --platforms=android,windows,macos .
flutter pub get
dart run pdfx:install_windows
```

The Windows PDF setup command updates generated CMake configuration. The Android manifest in `android/app/src/main/AndroidManifest.xml` and `android/app/src/main/res/xml/network_security_config.xml` include the loopback playback permission/configuration; keep them when generating or merge those entries if Flutter recreates platform files. Android uses the generated Flutter Gradle/Kotlin project files. Set the Android `minSdk` to 23 or higher when required by plugin Gradle configuration. Passwords are limited to 72 UTF-8 bytes because bcrypt truncates/rejects longer inputs.

Run on a connected Android device/emulator:

```powershell
flutter run
```

Run as a Windows desktop app (requires Visual Studio 2022 or Build Tools 2022 with the Desktop development with C++ workload):

```powershell
flutter run -d windows
```

Run as a macOS desktop app (the build must run on macOS with Xcode installed):

```bash
flutter run -d macos
```

## Build the Android release APK in VS Code

1. Open the project folder in VS Code and choose **Terminal → New Terminal**.
2. Confirm Flutter is on `PATH` with `flutter doctor`.
3. Fetch dependencies:

   ```powershell
   flutter pub get
   ```

4. Build the release APK:

   ```powershell
   flutter build apk --release
   ```

5. Find the generated APK at:

   ```text
   build\app\outputs\flutter-apk\app-release.apk
   ```

The current release build uses the Android debug signing key for local testing. It can be installed on a device, but it is not suitable for Play Store distribution. To install it on a USB-connected Android device with USB debugging enabled:

```powershell
adb devices
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

For a distributable release, configure a private upload keystore and replace the debug signing configuration in `android/app/build.gradle.kts`.

For macOS desktop, run `flutter build macos --release` on a Mac. For Windows desktop, run `flutter build windows --release` on Windows with the required Visual Studio workload.

## Android launcher alias and icon

For a normal branded app, change `android:label` in the `<application>` element and replace the generated `mipmap` launcher resources (prefer the `flutter_launcher_icons` package for all densities). Android launcher aliases can provide a different launcher label/icon, but an alias is only a launcher presentation mechanism; it does not hide the package from Android settings or provide a security boundary.

To use an alias, remove the `MAIN`/`LAUNCHER` intent filter from `.MainActivity` and add a sibling `<activity-alias>` inside `<application>` targeting `.MainActivity`, with `android:label="Calculator"` and an existing icon resource such as `@mipmap/ic_launcher`. Keep the alias exported and enabled. Use an icon you own or are licensed to use, and do not represent the app as an unrelated third-party service.

Example alias (add the launcher intent filter here, not on `.MainActivity`):

```xml
<activity-alias
    android:name=".CalculatorAlias"
    android:targetActivity=".MainActivity"
    android:label="Calculator"
    android:icon="@mipmap/ic_launcher"
    android:enabled="true"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
    </intent-filter>
</activity-alias>
```
