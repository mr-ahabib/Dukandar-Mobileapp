# দোকানদার (Dukandar)

Offline-first shop ledger (বাকি খাতা), cash memo and daily cash drawer app for small shops in Bangladesh. Flutter 3.47, Android.

## Design

Clean, minimal, professional green identity — see `lib/core/theme/app_theme.dart`.

| Token | Value | Use |
|---|---|---|
| `navy` / `primaryDeep` | `#14532D` | hero headers (home, login), dark cards |
| `indigo` / `primary` | `#166534` | primary buttons, selected states |
| `accentEmerald` | `#10B981` | accent / check badge |
| `indigoSoft` / `emeraldSoft` | `#ECFDF5` | mint tint for icon circles & tonal buttons |
| `cream` / `background` | `#F7FAF8` | scaffold background |
| `hairline` | `#E5EBE7` | 1px card borders |
| `ink` / `inkMuted` | `#0F1F17` / `#5B6B62` | text |
| `emerald` | `#059669` | money in |
| `coral` | `#DC2626` | money out / due (sparingly) |
| `saffron` | `#D97706` | amber — small badges only |

Constant *names* are kept from the earlier palette so screens compile unchanged; only the values changed.
Only the home header and login header use a gradient; everything else is flat white cards with a hairline border.

Regenerate the launcher icon and splash:

```sh
python3 tool/gen_brand_assets.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Build

Release APKs should be split per ABI (≈60% smaller downloads than a fat APK). Icon tree-shaking is on by default in release.

```sh
flutter build apk --release --split-per-abi
# or a single fat APK:
flutter build apk --release
# Play Store:
flutter build appbundle --release
```

`android/app/build.gradle.kts` already enables `minifyEnabled` / `shrinkResources`.

Optional: obfuscate Dart symbols and keep the symbol map out of the APK (smaller binary, harder to reverse). Keep the `symbols/` folder per release so crash stack traces can be de-obfuscated with `flutter symbolize`:

```sh
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
```

Pass the API base URL at build time:

```sh
flutter build apk --release --split-per-abi --dart-define=DUKANDAR_API=https://api.example.com/api/v1
```

## Performance notes

- `main()` is light: notifications and security checks are deferred to after the first frame. Provider constructors do **no I/O**; `lib/core/app_bootstrap.dart` opens SQLite once (single-flight) after the first frame and then loads ledger / memos / cash drawer / products concurrently. Screens render their empty state instantly meanwhile.
- SQLite opens with `journal_mode=WAL`, `synchronous=NORMAL`, `foreign_keys=ON`. Schema v5 adds `transactions(customer_id,type,date)`, `transactions(type,date)` and `customers(type,updated_at)` on top of the v3 composite indexes and the stored `cash_memos.grand_total`, so every dashboard/report figure is a `SUM`/`GROUP BY` in SQL. Migration steps are individually guarded and idempotent.
- Ledger writes (record / edit / delete transaction, new contact with opening balance) run as one SQLite transaction together with the balance recompute.
- Memo rows are **lazy**: `items_json` is decoded only when a memo's items are actually read (detail / PDF); list totals come from the stored column.
- Providers cache every derived value (totals, counts, filtered + sorted lists, day groups, low-stock list) and recompute them once per data change, never in `build()`. Models carry a pre-lowercased `searchKey`; `SearchField` debounces 250ms and the home tab uses `context.select` so a search keystroke in another tab does not rebuild it.
- PDF: the two Bengali TTFs are parsed once per process (`PdfKit`), the logo is cached by mtime, and the memo screen shows a spinner / ignores repeat taps while a PDF builds.
- `PhotoHelper.exists()` memoises `existsSync()` so list rows never stat files during build; avatars decode at `cacheWidth: 120`; charts and hero cards sit in `RepaintBoundary`.
- Debug-only timings: `lib/core/utils/perf.dart` prints `[perf] db.open 8ms`, `[perf] ledger.load 24ms · 2000 contacts`, `[perf] first-frame @ 412ms`, `[perf] bootstrap.total 31ms` style lines; `Perf.last` keeps the numbers for tests.
- `test/perf_test.dart` seeds 2,000 contacts / 20,000 transactions / 1,000 memos in-memory and asserts load budgets (ledger < 300ms, dashboard aggregates < 100ms, …). Measured on a dev laptop: ledger 24ms, dashboard 1ms, reports 10ms, billing 2ms.

## Verify

```sh
flutter analyze
flutter test
```
