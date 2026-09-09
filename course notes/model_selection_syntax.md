# Model Selection Syntax in dbt

## What it is
dbt's **node selection syntax** lets you run, test, or list a specific subset of resources (models, seeds, snapshots, tests, sources) instead of the entire project — using the `--select` / `-s` and `--exclude` flags with `dbt run`, `dbt test`, `dbt build`, and `dbt ls`. This is essential once a project grows beyond a handful of models, since rebuilding everything on every change is slow and wasteful.

## How it's written in dbt

### Basic selection
```bash
dbt build --select dim_customers          # exactly one model
dbt build --select staging.stg_orders     # by path
dbt build --select tag:nightly            # by tag
dbt build --select config.materialized:table   # by config value
```

### Graph operators
```bash
dbt build --select dim_customers+     # dim_customers and everything downstream
dbt build --select +dim_customers     # dim_customers and everything upstream
dbt build --select +dim_customers+    # both directions
dbt build --select dim_customers+2    # downstream, limited to 2 levels
```

### Set operations
```bash
dbt build --select stg_orders stg_customers        # union (space-separated = OR)
dbt build --select tag:nightly,config.materialized:table   # intersection (comma = AND)
dbt build --select staging --exclude stg_legacy_orders     # exclude a subset
```

### Selecting by resource type / state
```bash
dbt build --select resource_type:test
dbt build --select source:raw_jaffle_shop+
dbt build --select result:error         # rerun what failed last run (needs --state or retry)
dbt build --select state:modified+      # only models changed vs. a prior manifest, and downstream — used in CI ("slim CI")
```

### Tags
```yaml
# models/schema.yml
models:
  - name: fct_orders
    config:
      tags: ['nightly', 'finance']
```
```bash
dbt build --select tag:finance
```

## Best practices
- Use `state:modified+` in CI pipelines ("slim CI") to only build/test models that changed in a PR plus their downstream dependents — much faster than a full rebuild on every PR.
- Tag models by domain/team/frequency (`finance`, `nightly`, `hourly`) so orchestration jobs can select cleanly without hardcoding model lists.
- Prefer `+model_name+` over manually listing every related model — it stays correct automatically as the DAG changes.
- Use `dbt ls --select <selector>` to preview exactly what a selection would touch, before running it — especially before an `--exclude` in production.
- Save frequently-used selections as **YAML selectors** (`selectors.yml`) instead of repeating long CLI strings:
  ```yaml
  # selectors.yml
  selectors:
    - name: nightly_finance
      definition:
        method: tag
        value: nightly
  ```
  ```bash
  dbt build --selector nightly_finance
  ```

## When to use
- Local development: build only the model you're working on and its parents (`dbt build --select +my_model`).
- CI: build only what changed (`state:modified+`) to keep pipelines fast.
- Scheduled production jobs: select by tag to run domain-specific subsets (e.g., `tag:finance` on an hourly job, everything else nightly).
- Incident response: `--select result:error` to retry just what failed, or `--exclude` a broken model while you fix it.
