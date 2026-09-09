# Seeds in dbt

## What they are
A **seed** is a CSV file, checked into your dbt project's version control, that dbt loads into the warehouse as a table via the `dbt seed` command. Seeds are meant for small, static, rarely-changing reference data that your team owns — not for loading real operational or production data.

## How they're written in dbt

Place the CSV under the configured seeds directory (default `seeds/`):

```csv
# seeds/country_codes.csv
country_code,country_name,region
US,United States,North America
IN,India,Asia
DE,Germany,Europe
```

Load it into the warehouse:
```bash
dbt seed
dbt seed --select country_codes
dbt seed --full-refresh
```

Reference it from a model exactly like a model, using `ref()`:
```sql
SELECT
    o.order_id,
    o.country_code,
    c.country_name
FROM {{ ref('stg_orders') }} AS o
LEFT JOIN {{ ref('country_codes') }} AS c
    ON o.country_code = c.country_code
```

### Configuring a seed
```yaml
# seeds/schema.yml
version: 2

seeds:
  - name: country_codes
    description: Static mapping of ISO country codes to country name and region.
    config:
      column_types:
        country_code: varchar(2)
        country_name: varchar(100)
      quote_columns: false
```

Common seed configs:
- `column_types` — explicitly set warehouse column types (dbt otherwise infers types from the CSV, which can guess wrong for things like leading-zero codes).
- `delimiter` — use something other than a comma.
- `quote_columns` — whether CSV column names should be quoted in the generated DDL (adapter-dependent default).
- `schema` / `database` / `alias` — control where the seed table is created.

## Best practices
- Only use seeds for data **you control and version** — country codes, status/category mappings, business-defined thresholds, test fixtures.
- Keep seed files small. Seeds are not meant for large or frequently-changing datasets; large CSVs bloat the git repo and slow down `dbt seed`.
- Set `column_types` explicitly for any column where dbt's type inference could be wrong (e.g., zip codes, IDs with leading zeros, currency codes).
- Never use seeds as a substitute for a proper data ingestion/EL pipeline (Fivetran, Airbyte, custom loaders) — that data doesn't belong in version control.
- Document seed columns and add tests just like a model (`unique`, `not_null`, `accepted_values`), especially since seeds are often join keys.

## When to use
- Small, stable lookup/reference tables maintained by the analytics team (e.g., mapping raw status codes to friendly names).
- Fixed business rules encoded as data (e.g., tax rate by state, fiscal calendar mapping).
- **Not** for: large operational datasets, frequently changing data, or anything that should come from a real source system — use a proper ingestion tool and a `source()` instead.

## Quick Reference

| Aspect | Detail |
| --- | --- |
| File type | CSV |
| Directory | `seed-paths` in `dbt_project.yml` (default `seeds/`) |
| Load command | `dbt seed` |
| Referenced with | `ref('seed_name')` |
| Typical size | Small (a few rows to a few thousand) |
| Ownership | Analytics/data team, version-controlled |
