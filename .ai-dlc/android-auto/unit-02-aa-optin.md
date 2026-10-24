---
title: Android Auto discovery opt-in (manifest + automotive_app_desc)
status: pending
workflow: default
depends_on: [unit-01-test-harness]
quality_gates:
  - name: analyze
    command: flutter analyze
  - name: build
    command: flutter build apk --debug
---

# Unit 02 — Android Auto discovery opt-in

Make the app discoverable as a media app. Today the exported
`com.ryanheise.audioservice.AudioService` is a `MediaBrowserService` but has
no Android Auto opt-in, so no car host (AA or Gearslip) lists the app.
References: `docs/android-media-auto-optin.md`,
`docs/android-media-manifest.md`, `Gearslip docs/BUILDING_APPS.md`
(§Media apps — "Both halves are required").

## Changes

1. **`android/app/src/main/res/xml/automotive_app_desc.xml`** (new):
   ```xml
   <?xml version="1.0" encoding="utf-8"?>
   <automotiveApp>
       <uses name="media" />
   </automotiveApp>
   ```
2. **`android/app/src/main/AndroidManifest.xml`** — inside `<application>`:
   ```xml
   <meta-data
       android:name="com.google.android.gms.car.application"
       android:resource="@xml/automotive_app_desc" />
   ```
3. **Standard browse action.** Per
   `docs/android-media-manifest.md`, the media browser service is declared
   with `<action android:name="android.media.browse.MediaBrowserService"/>`.
   Add that action to the `AudioService` `<service>` intent-filter (keep
   the existing session-command filters; they are harmless. The pre-existing
   `android.media.browse.action.BROWSE` filter is not a real system action —
   note it as a cleanup candidate in the report, do not remove in this unit).
4. **Accent color.** AA styles the in-car UI from the app theme's
   `colorAccent`; the current `NormalTheme` inherits the platform default.
   Add a style (e.g. `AATheme`) carrying `colorAccent` set to the brand
   primary (`#37474F`, per `lib/main.dart` `ColorScheme`), and reference it:
   ```xml
   <meta-data
       android:name="com.google.android.gms.car.application.theme"
       android:resource="@style/AATheme" />
   ```
   (Verify the brand mapping against `lib/main.dart` at build time; use
   `secondary` `#F4511E` instead if that reads better on the car — record
   the choice in the report.)

## Out of scope for this unit

- Attribution icon: the app's launcher icon is used by default, which the
  docs permit. A dedicated monochrome vector attribution icon is a polish
  item — raise it in the report, do not block on it.
- Car launcher icon (`android:icon` on the service): same — default is the
  app icon.

## Completion criteria

### Success cases

- [ ] `adb shell dumpsys package dev.educoder.owntone_sync | grep -A2
      'com.google.android.gms.car.application'` shows the meta-data (harness
      check that the opt-in is actually in the installed APK).
- [ ] On the DHU, **Owntone Player appears in the media section** with the
      correct label and launcher icon. Screenshot saved.
- [ ] Tapping its tile opens the app on the car display (this is the first
      time the Flutter UI renders on the DHU — at this point it will be the
      un-adapted portrait library screen letterboxed; that is expected and is
      exactly the problem unit-05 solves. Screenshot for the record.)
- [ ] `flutter analyze` clean.

### Failure cases

- [ ] If the app does not appear in the DHU media section: check
      (a) meta-data present in installed APK (dumpsys above), (b) developer
      mode enabled (unit-01), (c) `automotive_app_desc` well-formed, (d)
      audio_service `AudioService` still exported after manifest merge
      (merged manifest in `build/app/.../merged_manifest/...`). Record which
      check found the cause.

## Notes for the builder

- The merged-manifest check from the compatibility analysis: today's merged
  manifest has **zero** occurrences of `gms.car` — after this unit it must
  have the meta-data plus the new intent-filter action.
- Do not add `<uses name="notification"/>` (we are not a messaging app) and
  do not add `android:process` or permission restrictions on the service.
