# KhataFlow

<p align="center">
  <img src="assets/brand/khataflow-icon.png" alt="KhataFlow app icon" width="120">
</p>

<p align="center">
  <strong>A simple, offline-first way to keep track of your money.</strong><br>
  Record income and expenses, see your wallet balance, and understand how each week went.
</p>

<p align="center">
  <a href="https://github.com/bijaykumarceh-dev/expencehistory/releases">
    <img alt="Latest Android APK" src="https://img.shields.io/badge/Android-Download%20APK-16845B?logo=android&logoColor=white">
  </a>
  <img alt="Flutter" src="https://img.shields.io/badge/Built%20with-Flutter-02569B?logo=flutter&logoColor=white">
</p>

## Download for Android

**[Download KhataFlow for Android (arm64)](https://github.com/bijaykumarceh-dev/expencehistory/raw/refs/heads/main/releases/KhataFlow-1.1.0-android-arm64.apk?download=1)**

This APK is built for most modern Android phones (64-bit ARM). Download it to
your phone, open the APK, and allow installation from this source if Android
asks. This is a direct-install build, not a Play Store release.

## What it does

- **Balance dashboard** — total balance across wallets, calculated from opening
  balances, income, and expenses.
- **Wallets** — keep separate Cash, Bank, UPI, or custom accounts with opening
  balances.
- **Transactions** — add, edit, and delete income and expenses with category,
  wallet, date, time, and an optional note.
- **Weekly view** — Monday–Sunday income, expenses, net result, profit/loss
  status, category breakdown, and closing balance.
- **Weekly PDF reports** — share the selected week's balance summary, category
  totals, and transaction list as a PDF.
- **Receipts** — take a photo or choose one from the gallery and attach it to an
  entry. Images over 1 MB are rejected.
- **UPI QR scanning** — scan a payment QR to prefill supported amount and payee
  details; review everything before saving.
- **Optional app PIN** — protect the app when it is opened or returns from the
  background.
- **Offline-first storage** — your entries are kept on the device and remain
  available without an internet connection.

## Screens

| Dashboard | Transactions | Weekly history |
|---|---|---|
| Balance and weekly spending | Filter and manage entries | Profit/loss and closing balance |

## Install from a computer

With Android Platform Tools installed and USB debugging enabled:

```sh
adb install -r releases/KhataFlow-1.1.0-android-arm64.apk
```

Or copy the APK to your phone and open it there.

## Run from source

Requirements: Flutter and Dart versions allowed by `pubspec.yaml`, plus an
Android SDK for Android builds.

```sh
flutter pub get
flutter run
```

Run checks:

```sh
flutter analyze
flutter test
```

Build an Android APK for a modern 64-bit ARM phone:

```sh
flutter build apk --release --target-platform android-arm64
```

## Data and privacy

- Transactions, wallet details, and receipt images are stored locally on this
  device using app preferences.
- The optional PIN is stored as a salted SHA-256 hash. It is not a substitute
  for Android's secure lock screen or encrypted financial storage.
- Removing the app or clearing its storage can remove locally saved data.
- This project is **not configured with Firebase**. There is no account
  sign-in, cloud sync, cloud receipt storage, or remote backup.
- Review a scanned QR's details before saving or making any payment. KhataFlow
  records transactions; it does not initiate UPI payments.

## Current limitations

Cloud login and sync, encrypted database storage, automatic backup, CSV export,
biometric unlock, and multi-currency support are not implemented yet.
The Android APK is currently signed with a development signing key and is for
testing/personal installation, not store distribution.

## Technology

- Flutter / Dart
- `shared_preferences` for on-device persistence
- `image_picker` for receipt photos
- `mobile_scanner` for QR scanning
