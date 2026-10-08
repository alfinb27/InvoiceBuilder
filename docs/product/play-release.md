# Google Play release (Android 1.0)

The Play Console counterpart of `app-store-listing.md`, and the Phase 7c checklist. The name is still the working
name (`naming.md`): replace "InvoiceBuilder" and the application ID before the first upload — **the application ID
can never change once an app is published**, and the billing product ID is derived from it (`spec/billing.md`).

## 1. Identity and signing

| Item | Value / action |
|---|---|
| Application ID | `app.invoicebuilder.invoices` in `android/app/build.gradle.kts` (debug builds add `.debug`). Use the same ID as the iOS bundle ID. |
| In-app product | `<applicationId>.unlimited_invoices`, one-time product, non-consumable; price per country in the console (≈ £1.99 / ₹99, plan §Headline 11) |
| Play App Signing | On (default). Google holds the app signing key. |
| Upload key | `keytool -genkeypair -v -keystore upload.jks -alias upload -keyalg RSA -keysize 4096 -validity 10000`. Keep `upload.jks` and its passwords **outside the repo** and back them up in two places. A lost upload key can be reset through Play support, but it takes days. |
| Gradle signing | read from `~/.gradle/gradle.properties` (`INVOICE_UPLOAD_STORE_FILE`, `…_STORE_PASSWORD`, `…_KEY_ALIAS`, `…_KEY_PASSWORD`) through a `signingConfigs.release` block; never commit them. Until then `assembleRelease` builds an unsigned APK, which CI uses to prove R8 works. |
| Version | `versionCode` +1 for every upload; `versionName` matches iOS (`0.1.0` → `1.0.0` at launch) |
| Bundle | `./gradlew :app:bundleRelease` → `app/build/outputs/bundle/release/app-release.aab` (Play wants an AAB, not an APK) |
| R8 mapping | `app/build/outputs/mapping/release/mapping.txt` — uploaded automatically with the AAB; keep a copy per release (≈ dSYMs) |

## 2. Play Console forms

| Form | Answer |
|---|---|
| App category | Business |
| Contact details | support email (same as iOS) |
| Privacy policy | the hosted `privacy-policy.md` |
| Ads | No ads |
| App access | All functionality available without an account (no login) |
| Content rating (IARC) | Utility/productivity; no violence, no user-generated content shared with others, no gambling → "Everyone" / PEGI 3 |
| Target audience | 18+ (business users); not designed for children |
| News app | No |
| Government app | No |
| **Financial features declaration** | The app does **not** provide financial services (no lending, payments processing, banking, crypto, trading). It creates invoices; the UPI QR only encodes the business's own payment link. |
| Health apps | No |
| **Data safety** | **No data collected, no data shared.** Everything stays on the device; backups are files the user saves where they choose; Google Auto Backup is the platform's own encrypted backup. Purchases go through Google Play. Crash reports (`ApplicationExitInfo`) stay on the device unless the user shares them. Answer "Data is encrypted in transit": not applicable (no transmission). |
| Permissions | `POST_NOTIFICATIONS` (payment reminders), `com.android.vending.BILLING` (merged from the Billing library). No storage permission: SAF and the photo picker are used. |

## 3. Store listing

Reuse the copy in `app-store-listing.md` (UK and India sections), adjusted for Play:

- **Short description (≤ 80):** UK: "VAT invoices & quotes on your phone, even offline. 15 free invoices." ·
  India: "GST invoices with UPI QR, quotes & reminders — offline. 15 free invoices."
- **Full description (≤ 4,000):** the iOS description, with "iPhone and iPad" → "phone and tablet", "iCloud Drive" →
  "Google Drive or your email", and no iCloud sync bullet (Android 1.0 is local-only; moving between devices is
  backup and restore, which also works between iPhone and Android).
- **Graphics:** icon 512 × 512, feature graphic 1024 × 500, and screenshots for **phone, 7" tablet and 10" tablet**
  (the large-screen quality checklist expects tablet shots). Take them from the seeded app (`--es seed IN` / `GB`
  on a debug build): Home, the builder with the live preview (tablet), an issued invoice, the PDF preview, Clients.

## 4. Tracks and rollout

1. **Internal testing** — instant, up to 100 testers. First upload as soon as the app ID is final, so the in-app
   product can be created (Play only allows products on an app with an uploaded bundle).
2. **Closed testing** — on a personal developer account Google requires **at least 12 testers opted in for 14
   continuous days** before production access. Start this at the beginning of 7b so the clock overlaps the work.
3. **Production** — staged rollout 10% → 50% → 100%, watching Android vitals: crash rate < 1%, ANR rate < 0.47%.
   A staged rollout can be halted from the console.

## 5. Pre-launch checks (Phase 7c definition of done)

- [ ] License testers: buy at the limit → unlocked; cancel → back to the limit; a pending (slow test card / UPI)
      purchase → "Payment pending", then unlocked when it completes; refund in the console → free again after the
      next resume; reinstall → unlocked on first launch (and the free counter survives through Block Store).
- [ ] Every purchase is acknowledged (the console shows no auto-refunds after 3 days).
- [ ] Restore a backup made on an iPhone, and restore an Android backup on an iPhone.
- [ ] Low-end phone: a 3-page PDF renders in ≤ 2 s; 30-minute `adb shell monkey` run with no ANR.
- [ ] TalkBack through: onboarding → new invoice → issue → share; font size at 200%.
- [ ] Foldable emulator (folded/unfolded mid-edit) and a freeform window resized across 600 dp and 840 dp.
- [ ] Pre-launch report (Play runs the app on real devices automatically) has no crashes.
