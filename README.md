# PlantGuard

Smart care for healthier plants - a Flutter app that reads from IoT sensors
and reports the conditions around your plants.

Mobile client built with Flutter, authentication and data on Firebase,
signup email verification through EmailJS.

## Status

The authentication flow is built and working: animated splash, login, signup,
emailed 6-digit verification code, password reset, and the Terms and Privacy
screens. The dashboard is next.

## Getting it running after a clone

Two files are deliberately not in this repo because they hold credentials.
A fresh clone will not compile until you create them.

**1. Install dependencies**

```bash
flutter pub get
```

**2. Firebase config**

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Select the PlantGuard Firebase project and Android as a platform. This writes
`lib/firebase_options.dart` and `android/app/google-services.json`.

In the Firebase console you also need:

- **Authentication** -> Sign-in method -> **Email/Password** enabled
- **Firestore Database** created (the app queries `users` for the
  username-to-email lookup at sign-in)

**3. EmailJS credentials**

```bash
copy lib\otp_config.dart.example lib\otp_config.dart
```

Then fill in the four values from your EmailJS dashboard. All four are
required, `privateKey` included - EmailJS treats Flutter as a non-browser
caller and rejects requests without it.

These are compile-time constants, so after editing do a **full restart**, not
a hot reload. Hot reload will not pick them up and the app will keep saying
the email service is not set up.

**4. Run**

```bash
flutter run
```

## Project layout

```
lib/
  main.dart                  entry point; initialises Firebase before runApp
  splashscreen.dart          rolling-logo animation into the hero screen
  login_screen.dart          greeting changes if an account exists on-device
  signup_screen.dart         form, consent line, hands off to OTP
  otp_screen.dart            6-digit entry, auto-advance, resend countdown
  reset_password_screen.dart
  verification_screen.dart   success and failure states
  legal_screen.dart          Terms and Conditions, Privacy Policy
  auth_service.dart          Firebase Auth + Firestore profile wrapper
  otp_service.dart           generates and emails the code via EmailJS
  app_ui.dart                shared widgets, metrics, colours, dialogs
  app_sound.dart             sound effects and ambient loop
assets/
  images/   background, logo
  sounds/   taps, whooshes, chime, ambient loop
fonts/      Inter, four weights
```

## Notes on the design

**Signup is two steps on purpose.** The Firebase account is not created when
the form is submitted - only after the emailed code is verified. Creating it
first meant abandoning the OTP screen left an unverified account behind
forever, and deleting it on Cancel did not help because a force-quit skips
that path entirely.

**Every Firestore call has a 15-second timeout.** Firestore is offline-first:
when it cannot reach the server it does not throw, it queues the operation and
waits. Without a timeout an unreachable database makes signup hang silently
with the button spinning and no error.

**Availability checks use `Source.server`.** The default cache-then-server
read returns an empty result when offline, which would read as "username
free" and let a duplicate through.

**Auth error messages are deliberately vague.** Firebase returns
`invalid-credential` for both a wrong password and an unknown email so that
nobody can probe which addresses have accounts. The messages stay general for
the same reason - this is not a rough edge to polish.

**Password reset uses Firebase's emailed link, not our OTP.** The Firebase
client SDK cannot change a signed-out user's password; `updatePassword()`
only ever acts on the currently signed-in user. A custom code flow cannot
work around that without the Admin SDK in a Cloud Function.

## Known limitations

- The EmailJS private key ships inside the APK, so anyone who decompiles the
  app can extract it and send mail through the account up to its quota. An
  accepted trade-off here; production would keep it server-side and have the
  app call that instead.
- The username-to-email lookup at sign-in needs a public `list` rule on the
  `users` collection, which lets an anonymous client test whether a username
  exists.

## Licences

Inter is used under the SIL Open Font License 1.1.
