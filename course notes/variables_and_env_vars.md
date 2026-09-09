# Variables and Environment Variables in dbt

## `var()` — project variables

### What it is
A **variable** is a value passed into dbt compilation from `dbt_project.yml` or the command line, used to parameterize model logic (date ranges, feature flags, thresholds) without hardcoding values into SQL.

### How it's written in dbt

Define a default in `dbt_project.yml`:
```yaml
vars:
  days_of_history: 365
  enable_new_logic: false
```

Read it in a model:
```sql
SELECT *
FROM {{ ref('stg_events') }}
WHERE event_date >= DATEADD('day', -{{ var('days_of_history') }}, CURRENT_DATE)
```

`var()` accepts a default as the second argument, used if the variable isn't defined anywhere:
```sql
{{ var('days_of_history', 90) }}
```

Override at runtime from the CLI (highest precedence):
```bash
dbt build --vars '{"days_of_history": 30}'
```

## `env_var()` — environment variables

### What it is
`env_var()` reads an environment variable from the shell/CI environment running dbt. It's the standard way to inject secrets (passwords, keys) and environment-specific config (target schema names, feature flags per environment) without ever writing them into version-controlled files.

### How it's written in dbt

In `profiles.yml`:
```yaml
my_profile:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: "{{ env_var('SNOWFLAKE_ACCOUNT') }}"
      user: "{{ env_var('SNOWFLAKE_USER') }}"
      password: "{{ env_var('SNOWFLAKE_PASSWORD') }}"
      schema: "{{ env_var('DBT_SCHEMA', 'dev') }}"
```

In a model, to branch on environment:
```sql
{% if env_var('DBT_ENV', 'dev') == 'prod' %}
    ...
{% endif %}
```

`env_var()` also takes an optional default as the second argument — without one, dbt raises a compilation error if the variable isn't set, which is usually the behavior you want for required secrets.

## Best practices
- Use `env_var()` for **anything secret or environment-specific** (credentials, account names, target schema) — never hardcode these, and never put real secrets directly in `dbt_project.yml` or `profiles.yml`.
- Use `var()` for **business/logic parameters** that might change per run but aren't secret (a lookback window, a feature flag, a threshold) — not for credentials.
- Always give `var()` a sensible default so a plain `dbt build` still works without requiring `--vars` for every run; reserve required (no-default) variables for values that truly must be explicit.
- Avoid overusing `var()`/`env_var()` to branch model logic heavily — too many conditional branches make a model's compiled SQL hard to predict and test. Prefer separate models or clear config over deeply nested `{% if %}` logic.
- In CI/CD, set environment variables through the CI platform's secret store, not by printing them into logs or committing `.env` files.

## Quick Comparison

| | `var()` | `env_var()` |
| --- | --- | --- |
| Source | `dbt_project.yml` `vars:` block, or `--vars` CLI flag | Shell/CI environment variables |
| Typical use | Business logic parameters (date ranges, flags, thresholds) | Secrets and environment-specific config |
| Committed to git? | Yes (the default value) | No (the value lives outside the repo) |
| Override at runtime | `--vars '{"key": "value"}'` | Set the env var before invoking dbt |
