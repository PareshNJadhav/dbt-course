# Sources and Source Freshness in dbt

## What a source is
A **source** is a declaration in YAML that tells dbt about raw data already loaded into your warehouse by an external process (an ETL/EL tool, a data engineering pipeline, a direct load) — data dbt itself did **not** create. Declaring sources lets you reference raw tables with `source()` instead of hardcoding schema/table names, and gives dbt a place to attach tests, descriptions, and freshness checks to raw data.

## How it's written in dbt

```yaml
# models/staging/sources.yml
version: 2

sources:
  - name: raw_jaffle_shop
    database: analytics
    schema: raw
    tables:
      - name: customers
      - name: orders
        description: Raw orders loaded nightly from the production database.
```

Reference a source from a model:
```sql
-- models/staging/stg_customers.sql
SELECT
    id AS customer_id,
    first_name,
    last_name
FROM {{ source('raw_jaffle_shop', 'customers') }}
```

`source('raw_jaffle_shop', 'customers')` resolves to the fully-qualified relation (e.g., `analytics.raw.customers`) and — just like `ref()` — registers a dependency edge in dbt's DAG, so lineage and selection (`dbt build --select source:raw_jaffle_shop+`) work correctly.

## Source Freshness

**Freshness** checks whether a source table has been updated recently enough to be trusted — it answers "is this raw data stale?" before you build anything on top of it.

```yaml
sources:
  - name: raw_jaffle_shop
    schema: raw
    tables:
      - name: orders
        loaded_at_field: _loaded_at
        freshness:
          warn_after: {count: 12, period: hour}
          error_after: {count: 24, period: hour}
```

Run a freshness check:
```bash
dbt source freshness
```

dbt compares `MAX(loaded_at_field)` against the current time. If it's older than `warn_after`, the check warns; older than `error_after`, it fails. This is commonly run as the first step in a scheduled job, before `dbt build`, so a stale upstream load doesn't silently produce misleading "fresh-looking" transformed data.

### Tests and docs on sources
Sources support the same generic tests and descriptions as models:
```yaml
tables:
  - name: customers
    columns:
      - name: id
        tests:
          - unique
          - not_null
```

## Best practices
- Declare **every** raw table used by any model as a source — never hardcode a raw schema/table name directly in model SQL.
- Group sources by the system/pipeline that loads them (e.g., `raw_stripe`, `raw_salesforce`), not by how they'll be used downstream.
- Set `loaded_at_field` and freshness thresholds for any source that's expected to load on a schedule — freshness failures are often the earliest signal that an upstream pipeline broke.
- Add `not_null`/`unique` tests on source primary keys to catch upstream data quality issues before they propagate into staging models.
- Keep one `sources.yml` per source system (or per staging subfolder) rather than one giant file, so it's easy to find and maintain.

## When to use
- Any time a model reads data that wasn't built by dbt (raw loaded tables from an EL tool, a data warehouse export, a manually loaded table).
- Freshness checks specifically: whenever downstream consumers (dashboards, alerts) need a guarantee that "data as of today" actually is recent, not stale from a broken load job.

## `source()` vs. `ref()`

| | `source()` | `ref()` |
| --- | --- | --- |
| Points to | Externally-loaded raw table | A dbt-built model, seed, or snapshot |
| Declared in | YAML (`sources:`) | Discovered automatically from the model file itself |
| Supports freshness checks | Yes | No |
| Creates DAG dependency | Yes | Yes |
