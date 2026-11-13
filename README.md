# KhataFlow

A Flutter expense and balance tracker with offline-first storage.

## Run locally

```sh
flutter pub get
flutter run
```

## Included

- Dashboard with wallet balance, this week's income/expenses, and a spending chart
- Multiple wallets with opening balances
- Add, edit, and delete income/expense transactions
- Custom categories, dates, notes, receipt photos, and UPI QR scanning
- Weekly income/expense/net summaries, category breakdown, profit/loss status,
  transaction detail, and closing balance
- Optional PIN gate when the app is opened
- Local persistence on the current device

Receipt images are resized by the picker and limited to 1 MB before saving.
The PIN is stored as a salted hash in local app preferences; it is not backed by
hardware security or a dedicated encrypted vault.

## Not configured yet

This workspace has no Firebase project configuration. Email/Google
authentication, cloud sync, cloud receipt storage, and remote backup are not
enabled. Add the project's Firebase app configuration and security rules before
using real accounts or syncing financial data across devices.

CSV/PDF export, biometric unlock, and automated cloud backup are not included in
this first local build.
