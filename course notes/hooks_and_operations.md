# Hooks and Operations in dbt

## What they are
**Hooks** are snippets of SQL that dbt runs at specific points around a model/seed/snapshot build, or around an entire `dbt run`/`dbt build` invocation. **Operations** (run via `dbt run-operation`) let you invoke any macro directly from the CLI, outside the normal model-build lifecycle. Both are used for side-effect SQL that isn't itself a model — granting permissions, logging run metadata, refreshing external tools, vacuuming tables, etc.

## Hook types

| Hook | Scope | Runs |
| --- | --- | --- |
| `pre-hook` | Single model/seed/snapshot | Immediately before that resource is built |
| `post-hook` | Single model/seed/snapshot | Immediately after that resource is built |
| `on-run-start` | Whole invocation | Once, before any resource in the run starts |
| `on-run-end` | Whole invocation | Once, after every resource in the run finishes |

## How they're written in dbt

### Model-level hook
```sql
-- models/marts/fct_orders.sql
{{ config(
    post_hook="GRANT SELECT ON {{ this }} TO ROLE reporting"
) }}

SELECT ...
```

### Project-level hooks (`dbt_project.yml`)
```yaml
on-run-start:
  - "{{ log('Starting dbt run at ' ~ run_started_at, info=True) }}"

on-run-end:
  - "GRANT SELECT ON ALL TABLES IN SCHEMA {{ target.schema }} TO ROLE reporting"

models:
  my_project:
    marts:
      +post-hook:
        - "ANALYZE {{ this }}"
```

Multiple hooks can be listed; they run in order.

### Operations
An **operation** is any macro invoked directly, without touching the DAG:
```sql
-- macros/grant_select.sql
{% macro grant_select(schema_name, role) %}
    GRANT SELECT ON ALL TABLES IN SCHEMA {{ schema_name }} TO ROLE {{ role }}
{% endmacro %}
```
```bash
dbt run-operation grant_select --args '{schema_name: analytics, role: reporting}'
```

## Best practices
- Use hooks for **warehouse housekeeping**, not business logic — grants, vacuuming, refreshing an external cache, writing audit log rows. Business transformation logic belongs in a model, not a hook.
- Keep hook SQL idempotent — hooks can run multiple times across retries/reruns, so avoid statements that fail or duplicate data on a second execution.
- Prefer project-level hooks (`dbt_project.yml`, scoped by folder) over repeating the same `post_hook` in every model — DRY and centrally maintainable.
- Use `run-operation` for one-off maintenance tasks (clearing stale tables, generating docs, custom setup scripts) that shouldn't be tied to a specific model build.
- Log run metadata (`on-run-end`) to a dedicated audit table when you need observability into run history beyond what `dbt` artifacts (`run_results.json`) already provide.

## When to use
- **Hooks**: granting/revoking permissions after a table is (re)built, triggering warehouse-native maintenance (e.g., clustering, vacuum), writing to an audit/logging table, invalidating a downstream cache when a specific model finishes.
- **Operations**: one-off or scheduled maintenance macros — bulk grants across a schema, custom cleanup scripts, generating YAML boilerplate — anything that doesn't correspond to building a specific resource.
