# Types of Materialization in dbt

Materialization defines **how dbt builds a model's result in the data warehouse** — i.e., what SQL object dbt creates (or doesn't create) when it runs a model. Every dbt model gets materialized using one of the strategies below.

You set the materialization either:

- **Per model**, using a config block at the top of the `.sql` file:
  ```sql
  {{ config(materialized='table') }}
  ```
- **Per directory/project**, in `dbt_project.yml`:
  ```yaml
  models:
    my_project:
      staging:
        +materialized: view
      marts:
        +materialized: table
  ```

dbt supports **five built-in materializations**: `view`, `table`, `incremental`, `ephemeral`, and `materialized_view`. You can also write **custom materializations** as macros.

---

## 1. View

### What it is
dbt creates a **SQL `VIEW`** in the database. No data is physically stored — the underlying query runs every time someone queries the view.

### How it's written in dbt
```sql
-- models/staging/stg_customers.sql
{{ config(materialized='view') }}

SELECT
    id AS customer_id,
    first_name,
    last_name,
    email
FROM {{ source('raw', 'customers') }}
```

`view` is dbt's **default materialization** — if you don't specify one, dbt uses `view`.

### Best practices
- Use for **staging models** (light cleaning: renaming, casting, filtering) since they're cheap to keep in sync with source data.
- Avoid views on top of **large, complex joins/aggregations** — every query re-runs the full logic, so performance degrades as query volume or data size grows.
- Views keep storage cost near zero, which is valuable when you have many staging models but don't want to pay storage for each.

### When to use
- Small-to-medium datasets.
- Logic that needs to always reflect the *freshest* underlying data (no build lag).
- Early layers of your DAG (staging/intermediate) where query cost per view hit is low.

---

## 2. Table

### What it is
dbt creates a **physical `TABLE`**. On every `dbt run`, dbt drops (or replaces) the existing table and rebuilds it from scratch by running the full `SELECT` statement.

### How it's written in dbt
```sql
-- models/marts/fct_orders.sql
{{ config(materialized='table') }}

SELECT
    o.order_id,
    o.customer_id,
    o.order_date,
    SUM(oi.quantity * oi.unit_price) AS order_total
FROM {{ ref('stg_orders') }} AS o
JOIN {{ ref('stg_order_items') }} AS oi
    ON o.order_id = oi.order_id
GROUP BY 1, 2, 3
```

### Best practices
- Use for models that are **queried often** or have **expensive transformations** (heavy joins/aggregations) — paying the compute cost once at build time is cheaper than recomputing on every query.
- Because tables are fully rebuilt each run, watch build time on very large tables — consider `incremental` instead once builds get slow.
- Combine with `dbt build` and proper `tags`/`selectors` so expensive tables aren't rebuilt unnecessarily on every CI run.

### When to use
- Mart/reporting layer models consumed by BI tools (fast reads matter more than build cost).
- Moderate-sized datasets where a full rebuild is still fast (seconds to a few minutes).
- Any model where downstream query performance matters more than "freshness lag."

---

## 3. Incremental

### What it is
dbt creates a **physical table**, but instead of rebuilding it from scratch every run, dbt only processes **new or changed rows** on subsequent runs and inserts/merges them into the existing table. The first run (or a `--full-refresh`) builds the whole table.

### How it's written in dbt
```sql
-- models/marts/fct_events.sql
{{ config(
    materialized='incremental',
    unique_key='event_id',
    incremental_strategy='merge'
) }}

SELECT
    event_id,
    user_id,
    event_type,
    event_timestamp
FROM {{ source('raw', 'events') }}

{% if is_incremental() %}
  WHERE event_timestamp > (SELECT MAX(event_timestamp) FROM {{ this }})
{% endif %}
```

Key pieces:
- `is_incremental()` — a Jinja function that's `True` only when: the model already exists as a table, it's not a `--full-refresh` run, and the model is configured as `incremental`. This lets you write the "filter to new rows" logic only for subsequent runs.
- `{{ this }}` — refers to the current model's existing database relation, letting you compare against what's already been loaded.
- `unique_key` — tells dbt how to identify a row for update/merge purposes (avoids duplicates when a row is reprocessed).
- `incremental_strategy` — how dbt applies new data: common strategies are `append`, `merge`, `delete+insert`, and `insert_overwrite` (adapter-dependent).

### Best practices
- Always define a `unique_key` when rows can be updated (not just appended), otherwise you risk duplicate rows.
- Filter using a reliable, monotonically increasing column (e.g., `updated_at`, `event_timestamp`, `_loaded_at`) — an unreliable filter column can silently skip or duplicate data.
- Add a small **look-back window** (e.g., `WHERE event_timestamp > (SELECT MAX(event_timestamp) FROM {{ this }}) - interval '3 days'`) to catch late-arriving data.
- Periodically run `dbt run --full-refresh` (or automate it) when: the model's schema changes, the incremental logic changes, or you suspect drift/missed rows.
- Test incremental logic carefully — bugs are harder to spot because most runs only touch a small slice of data.

### When to use
- Very large tables (millions+ rows) where a full rebuild is too slow or expensive.
- Event/log/transaction data that mostly appends and rarely needs full historical reprocessing.
- Any table where compute cost of a full rebuild significantly outweighs the cost of incremental complexity.

---

## 4. Ephemeral

### What it is
dbt does **not create any database object** for this model. Instead, dbt inlines the model's SQL as a **CTE (Common Table Expression)** into any downstream model that references it via `ref()`.

### How it's written in dbt
```sql
-- models/staging/stg_clean_emails.sql
{{ config(materialized='ephemeral') }}

SELECT
    customer_id,
    LOWER(TRIM(email)) AS email_clean
FROM {{ ref('stg_customers') }}
```

Used downstream:
```sql
-- models/marts/dim_customers.sql
{{ config(materialized='table') }}

SELECT
    c.customer_id,
    e.email_clean
FROM {{ ref('stg_customers') }} AS c
JOIN {{ ref('stg_clean_emails') }} AS e
    ON c.customer_id = e.customer_id
```

At compile time, `stg_clean_emails` doesn't appear as a table/view in the warehouse — its SQL is injected as a CTE inside `dim_customers`'s compiled query.

### Best practices
- Use sparingly — ephemeral models **can't be queried directly** (no relation exists), which makes debugging and ad hoc inspection harder.
- Avoid chaining many ephemeral models together or reusing one ephemeral model across many downstream models — each reference re-injects the same CTE, which can bloat compiled SQL and hurt query planning/performance.
- Good for small, single-purpose logic (a rename, a light filter) that doesn't need independent testing or querying.

### When to use
- Lightweight, reusable SQL snippets that don't warrant their own table/view (e.g., a one-off column cleanup step).
- Intermediate logic used by only one or two downstream models where creating a full relation is unnecessary overhead.
- Not recommended for models that need their own tests, need to be queried independently, or are reused across many downstream models.

---

## 5. Materialized View

### What it is
dbt creates a **warehouse-native materialized view** — an object that stores query results physically (like a table) but which the warehouse itself knows how to refresh (fully or incrementally), rather than dbt controlling the rebuild logic. Support and refresh behavior depend on the adapter (e.g., Postgres, Snowflake, Redshift, Databricks each implement this differently).

### How it's written in dbt
```sql
-- models/marts/mv_daily_active_users.sql
{{ config(
    materialized='materialized_view',
    on_configuration_change='apply'
) }}

SELECT
    DATE(event_timestamp) AS activity_date,
    COUNT(DISTINCT user_id) AS daily_active_users
FROM {{ ref('stg_events') }}
GROUP BY 1
```

Adapter-specific refresh options (example, Snowflake/Postgres-style — check your adapter's docs):
```sql
{{ config(
    materialized='materialized_view'
) }}
```

### Best practices
- Confirm your adapter supports `materialized_view` before relying on it — not all adapters do, and refresh behavior (auto vs. manual, full vs. incremental refresh) varies significantly.
- Use `on_configuration_change` to control what happens when the materialized view's config changes between runs (`apply`, `continue`, or `fail`, depending on adapter support).
- Don't use this as a replacement for `incremental` unless the warehouse's native refresh mechanism is well understood and monitored — visibility into refresh failures can be less obvious than with dbt-controlled incremental models.

### When to use
- You want warehouse-managed, automatic refresh of a query result (e.g., near-real-time dashboards) without managing refresh logic in dbt.
- The underlying warehouse feature (e.g., Snowflake dynamic tables mapped to this materialization, Postgres materialized views) fits your latency/cost tradeoff better than a dbt-scheduled `table`/`incremental` rebuild.

---

## 6. Custom Materializations

### What it is
A **macro-defined materialization** that implements custom logic for how a model is built. Used when the built-in materializations don't fit a specific warehouse feature or organizational pattern (e.g., a "snapshot-like" table, a custom merge strategy, or a specialized Python model execution path).

### How it's written in dbt
```sql
-- macros/materializations/my_custom_materialization.sql
{% materialization my_custom, default %}

  {%- set target_relation = this -%}

  {{ run_hooks(pre_hooks) }}

  -- custom build logic here
  {% call statement('main') %}
    CREATE OR REPLACE TABLE {{ target_relation }} AS (
      {{ sql }}
    )
  {% endcall %}

  {{ run_hooks(post_hooks) }}

  {{ return({'relations': [target_relation]}) }}

{% endmaterialization %}
```

Used in a model:
```sql
{{ config(materialized='my_custom') }}

SELECT * FROM {{ ref('stg_customers') }}
```

### Best practices
- Only build a custom materialization when built-ins genuinely don't fit — they add maintenance burden and are harder for new team members to understand.
- Check dbt package hub / community packages first (e.g., `dbt_utils`, adapter-specific packages) — someone may have already solved the same problem.
- Document custom materializations clearly since they aren't self-explanatory the way built-ins are.

### When to use
- Rare, advanced cases: specialized warehouse features, non-standard load patterns, or organization-wide standardized build logic that must be reused across many models.

---

## Quick Comparison

| Materialization | Database object created | Rebuild behavior | Storage cost | Query speed |
| --- | --- | --- | --- | --- |
| `view` | View | Recompiled on every query | Minimal | Slower (recomputed each query) |
| `table` | Table | Full rebuild every run | Full table storage | Fast (precomputed) |
| `incremental` | Table | Only new/changed rows processed | Full table storage | Fast (precomputed) |
| `ephemeral` | None (inlined CTE) | N/A — recompiled wherever referenced | None | Depends on downstream model |
| `materialized_view` | Warehouse-managed materialized view | Warehouse handles refresh | Full storage (warehouse-managed) | Fast (precomputed, refresh cadence varies) |
| Custom | Depends on macro logic | Depends on macro logic | Depends on macro logic | Depends on macro logic |

## General Decision Guide

1. **Start with `view`** for staging models — cheap, always fresh.
2. **Move to `table`** once a model is queried frequently or its transformation is expensive to recompute.
3. **Move to `incremental`** once a table becomes too large/slow to fully rebuild on every run.
4. **Use `ephemeral`** only for small, single-purpose, lightly-reused SQL snippets.
5. **Use `materialized_view`** when the warehouse's native refresh mechanism is a better fit than dbt-scheduled rebuilds.
6. **Write a custom materialization** only as a last resort, when none of the above fit your requirement.
