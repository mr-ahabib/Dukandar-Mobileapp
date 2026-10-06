# Money rules (হিসাবের নিয়ম)

Single source of truth: **the `transactions` table**. Every balance and every
daily / monthly figure is derived from stored rows; nothing is kept as a
separately-maintained counter.

## Memo (ক্যাশ মেমো)

| term | formula | note |
|---|---|---|
| উপমোট (subtotal) | Σ qty × unit price | |
| ডিসকাউন্ট | clamped to `0 … subtotal` | |
| সর্বমোট (grand total) | subtotal − discount | stored in `grand_total` |
| নগদ (cash kept) | `min(paid, grand total)` | `paid` is clamped on save |
| বাকি (due) | `max(0, grand total − paid)` | 300 of 1000 paid → due 700 |
| ফেরত (change) | `max(0, paid − grand total)` | shown before save, never revenue |

* "পুরো টাকা" sets paid = grand total → due 0.
* With a customer and **বাকি খাতায় লিখুন**: **only the due** is inserted as a
  `gave` transaction with `memo_id = memo.id`. The paid part never creates a
  `got` row, so memo cash and ledger collections cannot double count.
* Deleting a memo deletes every transaction with that `memo_id`, restores stock
  and recomputes the customer's balance (all in one SQLite transaction).

## Ledger (বাকি খাতা)

```
customer balance = Σ gave − Σ got     (+ they owe us, − advance / জমা বেশি)
supplier balance = Σ got  − Σ gave    (+ we owe them, − we prepaid)
```

* `AppDatabase.recomputeBalance(id)` is called after every insert / update /
  delete of a transaction, on memo post / delete, and when a contact is created.
  An opening balance is itself a transaction (`tx_init_<id>`).
* A profile edit never writes `current_balance`.
* Owes 1000, pays 400 → 600; pays 700 more → **−100 = অগ্রিম জমা** (shown, not hidden).
* মোট পাওনা = Σ positive customer balances; মোট দেনা = Σ positive supplier
  balances. Overdue list = customers with balance > 0 and no payment in 7 days.
* Balances are rounded to 2 decimals so "settled" is exact (0, not 1e-17).

## Day figures (হোম / ক্যাশ বাক্স)

| label | definition |
|---|---|
| আজ বিক্রি | Σ `grand_total` of today's memos |
| নগদ বিক্রি | Σ `min(paid, grand_total)` of today's memos |
| বাকিতে বিক্রি | Σ due of today's memos |
| আজ জমা / বাকি আদায় | Σ ledger `got` on **customers** today |
| মহাজনকে দেওয়া | Σ ledger `gave` on **suppliers** today |
| আজ খরচ | Σ expenses today |
| আজকের নগদ | নগদ বিক্রি + বাকি আদায় − খরচ − মহাজনকে দেওয়া |

## Reports (monthly)

`collected` = customer `got`; `credited` = customer `gave` (includes memo
dues posted to the ledger); `sales` = Σ `grand_total`; `expenses` = Σ expenses.

## Statement PDF

Rows are ordered oldest → newest (date, then id); the running balance uses
the same sign convention as above and its last value equals
`customer.current_balance`.
