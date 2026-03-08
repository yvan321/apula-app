# APULA Deployment Runbook

This guide is an Android-first production deployment checklist for this repository.

## Scope

- Flutter mobile app (Android release)
- Firebase project configuration
- Firebase Cloud Functions deployment (`functions/`)

## 0. Prerequisites (One-Time)

Run from project root:

```powershell
flutter --version
dart --version
node --version
npm --version
firebase --version
```

Install missing tools:

```powershell
npm i -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
```

## 1. Release Branch + Quality Gate

```powershell
git checkout -b release/vX.Y.Z
flutter clean
flutter pub get
flutter analyze
flutter test
```

Update app version in `pubspec.yaml`:

- Example: `version: 1.0.1+2`

Commit:

```powershell
git add .
git commit -m "chore: prepare vX.Y.Z release"
```

## 2. Configure Production Firebase

Use a dedicated production Firebase project.

```powershell
flutterfire configure
```

Verify generated and platform files:

- `lib/firebase_options.dart` points to prod project IDs
- `android/app/google-services.json` is for prod

In Firebase Console, validate:

- Authentication providers enabled
- Firestore rules/indexes published
- Realtime Database rules published
- Storage rules published
- Cloud Messaging configured

## 3. Functions Environment Setup

This repo uses environment variables (via `.env.<project-id>` in `functions/`):
  - `APULA_EMAIL_ENABLED`
  - `EMAIL_COOLDOWN_SECONDS`
  - `SMTP_HOST`
  - `SMTP_PORT`
  - `SMTP_USER`
  - `SMTP_PASS`
  - `EMAIL_FROM`
  - `SMTP_SECURE` (optional, `true` or `false`)

Create or update `functions/.env.<YOUR_PROJECT_ID>`:

```env
# Email controls
APULA_EMAIL_ENABLED=true
EMAIL_COOLDOWN_SECONDS=180

# SMTP
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=your_smtp_username
SMTP_PASS=your_smtp_password
EMAIL_FROM=alerts@example.com
SMTP_SECURE=false

```

Important:

- Do not commit real credentials.
- Keep production secrets only in protected environment config.

## 4. Deploy Cloud Functions

```powershell
cd functions
npm install
cd ..
firebase use <YOUR_PROD_PROJECT_ID>
firebase deploy --only functions
```

Post-deploy smoke check:

- Confirm functions appear in Firebase Console
- Trigger a test alert and verify:
  - FCM push is sent
  - Email is sent (if enabled)

## 5. Build Android Release Artifact

Build the Play Store artifact:

```powershell
flutter build appbundle --release
```

Output:

- `build/app/outputs/bundle/release/app-release.aab`

Upload `app-release.aab` to Google Play Console.

## 6. Play Store Submission Checklist

- Release signing is configured for Android
- App metadata (description, screenshots, icon) updated
- Privacy Policy URL is valid
- Data Safety form completed
- Permissions justified (camera, location, notifications, background execution)
- Roll out to internal testing first, then production

## 7. Project-Specific Compliance Note

Current app startup (`lib/main.dart`) auto-starts:

- `BackgroundAIManager.startForegroundService();`
- `BackgroundAIManager.startPeriodicTask();`

For Play review and battery policy compliance, prefer user-controlled opt-in (toggle in settings) instead of unconditional auto-start at launch.

## 8. Rollback Plan

If release issues appear:

1. Halt Play rollout (or unpublish latest release).
2. Re-deploy previous stable Cloud Functions revision.
3. Rebuild app from previous stable git tag.
4. Validate alert flow (FCM, email) before re-rollout.

## 9. Quick Command Block (Copy/Paste)

```powershell
git checkout -b release/vX.Y.Z
flutter clean
flutter pub get
flutter analyze
flutter test

flutterfire configure

cd functions
npm install
cd ..
firebase use <YOUR_PROD_PROJECT_ID>
firebase deploy --only functions

flutter build appbundle --release
```
