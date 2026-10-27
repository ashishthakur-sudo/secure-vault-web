# Secure Vault

Flutter app for storing supported files as authenticated, encrypted blobs. Encrypted file contents remain on the device; encrypted metadata is synchronized through Supabase PostgreSQL. Native targets are Android, Windows, and macOS; the web target stores encrypted file contents in that browser's IndexedDB.

## Web app

Live web app: [Secure Vault](https://ashishthakur-sudo.github.io/secure-vault-web/).

Build the browser version with:

```powershell
flutter pub get
dart run pdfx:install_web
flutter build web --release
```

Copy `.env.example` to `.env` and configure `SUPABASE_URL` and `SUPABASE_ANON_KEY` before building or running. Apply the Supabase migrations with `supabase db push`. Run locally with `flutter run -d chrome` or serve the `build\web` folder over HTTPS or `localhost`. Create or sign in with an email and password, then unlock the vault with its master password. Supabase email confirmation must be disabled for signup to immediately create a session; no SMS or WhatsApp provider is required. The browser stores encrypted file contents in IndexedDB; metadata is synchronized under the signed-in user's PostgreSQL account. Files themselves are not transferred, so another device can show metadata but cannot open a file that was not imported on that device. Clearing browser data can permanently erase that device's encrypted files. Browser media playback depends on supported codecs.

Serve the app only over HTTPS or localhost: secure browser storage requires a secure context. A static host can serve the frontend, but does not receive or store vault files.

## Shared folder (cloud)

The **Shared** folder button in the vault opens a cloud folder that different users can access with the same four-digit password. Unlike the private local vault, shared files are uploaded to a Supabase Storage bucket so other users can list and download them. Cloud files are not end-to-end encrypted; the project owner/Supabase administrators can access them. Do not use it for sensitive files. A four-digit password is weak; the Edge Function limits incorrect attempts to five per IP per 15-minute window, but this is not equivalent to strong account authentication.

For local development, copy `.env.example` to `.env` and fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY`. `.env` is ignored by Git and loaded by `flutter_dotenv`; do not commit it. Values bundled in a Flutter app are still extractable by users: the Supabase URL and anon/publishable key are public client configuration, not secrets. Never put a service-role key, admin reset key, or other privileged secret in `.env` or Dart code. Keep privileged keys in Supabase Edge Function secrets. The Shared configuration screen can also store a project URL and public key in platform secure storage.

To enable Shared, create a Supabase project, install the Supabase CLI, then from this repository run:

```powershell
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
supabase secrets set SHARED_FOLDER_ADMIN_KEY=YOUR_LONG_RANDOM_ADMIN_KEY
supabase functions deploy shared-vault --no-verify-jwt
```

Set `SHARED_FOLDER_ADMIN_KEY` to a long, random secret and keep it private; it authorizes changing the shared-folder password. No initial `SHARED_FOLDER_PIN` secret is required: after deployment, use **Admin sign in** in the app with this key and set the initial four-digit password. The reset control is then available to admins for future changes. The key is kept only in memory for that app session. Passwords set in the app are stored as salted hashes in the database. A legacy `SHARED_FOLDER_PIN` secret, if configured, is used only until an admin sets a password in the app.

The vault unlock screen also offers **Forgot password or PIN?**. It sends a one-time code to the signed-in account's email and requires the code to be verified for that same account before resetting. A confirmed reset permanently deletes that account's encrypted metadata, KDF salt, and associated local encrypted files, then lets the user create an empty vault. It cannot recover files encrypted with the forgotten password. This is separate from the Shared-folder admin PIN reset.

Supabase supplies the project URL and service-role secret to the Edge Function; never put a service-role key in this app or publish it. The public key is intended for client use; the service-role secret is not. In **Shared**, uploads are restricted to PDF, PNG, JPG, MP4, and MP3 files up to 20 MiB each. The app and Edge Function validate the extension, file signature, and size; the Storage bucket also limits file size and MIME types. The `secure_shared_uploads` migration keeps the shared bucket private, enables/reasserts RLS, and blocks direct table and bucket access for `anon` and `authenticated`; the app accesses files only through the PIN-checked Edge Function, which uses the server-side service role. That shared PIN authorizes access to the entire shared folder; it is not per-user ownership or account-level authorization. Every shared file has a **View** option: images, PDFs, videos, audio, text, and DOCX files preview in the app without saving to Downloads. DOCX previews extract readable text and may not preserve Word formatting or embedded images; unsupported formats show a message explaining that they must be downloaded to open. Use **Download** when you want a local copy. Move files to **Trash** to remove them from the shared list; open Trash and choose **Restore** to bring them back. Trash is shared and recoverable by anyone with the folder password; files are not permanently deleted. Native app downloads are saved under `Documents\SecureVaultShared`; browser downloads use the browser's download location.

## PostgreSQL vault metadata

The local SQLite/IndexedDB metadata store has been replaced by Supabase PostgreSQL tables accessed through Supabase Auth and Row Level Security. On first unlock after signing in, existing SQLite or IndexedDB metadata is migrated to the signed-in account; encrypted files remain at their existing local paths. Do not delete the local vault folder or browser data until the migration has completed and verified. The metadata remains encrypted with the vault master password before it is sent to PostgreSQL. A first-time device must use the same master password to decrypt an existing account's metadata.

The current project URL and publishable key are in the ignored local `.env`. To build or deploy from a clean checkout, copy `.env.example` to `.env`, supply the project URL and public anon/publishable key, then run `flutter pub get`, `supabase link --project-ref YOUR_PROJECT_REF`, and `supabase db push`. In Supabase **Authentication → Sign In / Providers**, leave Email enabled and turn off **Confirm email** to allow password signup without a verification email. Phone authentication is not used and no SMS/WhatsApp credentials are required. In Supabase **Authentication → URL Configuration**, the deployed app URL is `https://ashishthakur-sudo.github.io/secure-vault-web/`. Keep service-role keys and database passwords out of Flutter and `.env`. Every shared file has a **View** option: images, PDFs, videos, audio, text, and DOCX files preview in the app without saving to Downloads. DOCX previews extract readable text and may not preserve Word formatting or embedded images; unsupported formats show a message explaining that they must be downloaded to open. Use **Download** when you want a local copy. Move files to **Trash** to remove them from the shared list; open Trash and choose **Restore** to bring them back. Trash is shared and recoverable by anyone with the folder password; files are not permanently deleted. Native app downloads are saved under `Documents\SecureVaultShared`; browser downloads use the browser's download location.

If **Open Shared** reports **“Failed to fetch”**, the browser could not reach the Edge Function; the PIN has not yet been checked. Check that the function is deployed to the same project configured in the app, the database migration has been applied, and `SHARED_FOLDER_ADMIN_KEY` has been set. Never share or enter the service-role key in the app.

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

On first launch, create or sign in to a Supabase email/password account, then create a master password for the encrypted vault. Email confirmation is disabled for signup; vault resets still require a one-time email code. Encrypted files are stored in your Windows Documents directory under `.SecureVault`; unlock the vault with the master password on later launches. Use **Sign out** to switch cloud accounts. Use the eye button in the password field to reveal or hide your password before unlocking.

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

- A first-run master password is bcrypt-hashed and stored with `flutter_secure_storage`. The vault encryption key is separately derived from the password and a per-account random salt using PBKDF2-HMAC-SHA256.
- On Android and Apple platforms, `flutter_secure_storage` uses platform-backed secure storage (Android Keystore and Keychain). Raw master passwords are not persisted; only the bcrypt hash is stored. Flutter web does not have the same hardware-backed security guarantees.
- The Supabase auth session is persisted through `flutter_secure_storage` instead of plain shared preferences on native platforms.
- Files and vault metadata are encrypted using AES-256-CBC with encrypt-then-MAC HMAC-SHA256. Supabase PostgreSQL stores only the per-user random KDF salt and encrypted metadata; the metadata table is protected by RLS policies tied to `auth.uid()`. Encrypted file blobs remain in local device storage. Existing SQLite or IndexedDB metadata is copied to PostgreSQL on first successful unlock and removed from the legacy metadata store only after the server confirms the copy.
- Images render from `Image.memory`; PDFs use `PdfDocument.openData`. Audio/video are decrypted into a Dart memory buffer and streamed by a short-lived HTTP server bound only to `127.0.0.1`; no decrypted media file is written to storage.
- The Music screen organizes encrypted MP3s into a playlist with playback, seek, shuffle, next/previous, and download controls. Downloads create a normal unencrypted file in the browser's download location or the native app's `Documents\SecureVaultShared` folder.
- The optional decoy PIN opens a read-only empty view. It does not store a second vault.
- Imported inputs are read into memory before encryption. The app cannot erase or protect the original source file.

This protects vault contents at rest while the device is locked. It does not protect against a compromised/unlocked operating system, screenshots, memory inspection, backups of source files, or a weak password. Dart cannot guarantee immediate zeroization of every copy of a key or plaintext buffer.

Encrypted file blobs are local, while metadata is account-scoped PostgreSQL data. Back up the entire local `.SecureVault` folder (or keep browser data intact) and keep the master password; the cloud metadata alone cannot restore encrypted file contents.

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
