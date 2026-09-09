# Snapshots in dbt

## What they are
A **snapshot** captures the historical state of a mutable source table over time, using Slowly Changing Dimension (Type 2) logic. Many source systems overwrite rows in place (e.g., a `customers` table where `status` is updated directly), losing history. A snapshot preserves every version of a row, along with the time range each version was valid, so you can answer questions like "what was this customer's plan on March 1st?"

## How they're written in dbt

```sql
-- snapshots/customers_snapshot.sql
{% snapshot customers_snapshot %}

{{ config(
    target_schema='snapshots',
    unique_key='customer_id',
    strategy='timestamp',
    updated_at='updated_at'
) }}

SELECT
    customer_id,
    plan_name,
    status,
    updated_at
FROM {{ source('raw', 'customers') }}

{% endsnapshot %}
```

Run it with:
```bash
dbt snapshot
dbt snapshot --select customers_snapshot
```

Every run compares the current source data against the latest snapshot table state and inserts a new row version whenever a tracked value changes.

### Snapshot strategies

**`timestamp` strategy** — compares an `updated_at` column. A new version is recorded when the timestamp advances.
```sql
strategy='timestamp',
updated_at='updated_at'
```
Preferred when the source system reliably bumps a timestamp on every change.

**`check` strategy** — compares a specific list of columns and creates a new version if any of them differ.
```sql
strategy='check',
check_cols=['plan_name', 'status']
```
Use when there's no trustworthy `updated_at` column. `check_cols='all'` compares every column, but this is more expensive and more sensitive to irrelevant column changes (e.g., a `last_login` column you don't actually care about).

### Metadata columns added by dbt
| Column | Purpose |
| --- | --- |
| `dbt_scd_id` | Unique surrogate key for the row version |
| `dbt_updated_at` | The value of the compare column at the time of the snapshot |
| `dbt_valid_from` | When this row version became active |
| `dbt_valid_to` | When this row version was superseded (`NULL` if it's the current version) |

Query only the current version of every row with `WHERE dbt_valid_to IS NULL`.

## Best practices
- Prefer `timestamp` strategy over `check` whenever a reliable `updated_at` exists — it's cheaper and less ambiguous.
- Snapshot from a `source()`, not from another dbt model — snapshotting a transformed model captures dbt's transformation history, not the actual source system's history, and can produce confusing results if upstream logic changes.
- Choose `unique_key` carefully — it must uniquely identify a row in the source at any point in time.
- Snapshot on a schedule frequent enough to catch changes — if a row changes twice between snapshot runs, the intermediate version is lost forever.
- Don't snapshot everything "just in case" — snapshots grow indefinitely and add storage/compute cost; only snapshot tables where historical tracking is a real business requirement.
- Keep snapshot definitions in `snapshots/`, not `models/` — dbt requires this separation and it keeps intent clear.

## When to use
- Source tables that get updated/overwritten in place, where the business needs point-in-time history (subscription status, pricing tiers, customer attributes).
- Auditing or compliance requirements where you must reconstruct "what did the data look like at time X."
- **Not** for: append-only event/log data (nothing is being overwritten, so there's no history to lose) — use a normal `table` or `incremental` model instead.

## Snapshots vs. Incremental Models

| | Snapshot | Incremental model |
| --- | --- | --- |
| Purpose | Preserve every historical version of a row | Efficiently keep the *latest* transformed data |
| Row count over time | Grows as changes occur (keeps old + new versions) | Roughly stable, reflects current state |
| Source | Must be a `source()` (raw, mutable data) | Any `ref()`/`source()` |
| Use case | "What did this look like on date X?" | "Give me an efficient, up-to-date table" |
