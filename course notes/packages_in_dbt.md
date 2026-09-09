# Packages in dbt

## What they are
A **package** is a standalone dbt project (macros, models, tests) that you can install into your own project and reuse, similar to a library in a general-purpose programming language. Packages let you avoid reinventing common macros (surrogate keys, date spines, extra generic tests) and can also share whole sets of models (e.g., pre-built source models for a SaaS tool).

## How they're written/used in dbt

Declare packages in `packages.yml` at the project root:
```yaml
# packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: 1.3.0
  - package: calogica/dbt_expectations
    version: 0.10.1
  - git: "https://github.com/my-org/internal-macros.git"
    revision: main
```

Install them:
```bash
dbt deps
```

This downloads packages into `dbt_packages/` (git-ignored, not committed). Use a package's macros with the package name as a namespace:
```sql
SELECT
    {{ dbt_utils.generate_surrogate_key(['customer_id', 'order_id']) }} AS order_pk
FROM {{ ref('stg_orders') }}
```

Package-provided generic tests are used the same way as built-ins:
```yaml
columns:
  - name: amount
    tests:
      - dbt_utils.accepted_range:
          min_value: 0
```

## Commonly used packages
| Package | Purpose |
| --- | --- |
| `dbt-labs/dbt_utils` | General-purpose macros (surrogate keys, date spines, pivot, `star()`) and extra generic tests |
| `calogica/dbt_expectations` | Great Expectations-style data tests (ranges, distributions, regex) |
| `dbt-labs/codegen` | Generates boilerplate YAML/SQL (e.g., source YAML from a schema) |
| `dbt-labs/audit_helper` | Compare two relations row-by-row, useful when refactoring a model |

## Best practices
- Pin exact or range-bound versions in `packages.yml` — an unpinned/latest install can silently change behavior on a fresh `dbt deps`.
- Commit `packages.yml` (and `package-lock.yml` if your dbt version generates one) to version control; never commit the `dbt_packages/` directory itself.
- Prefer well-maintained, widely-used packages (dbt Hub / dbt Labs packages) over writing custom macros for common problems.
- Re-run `dbt deps` after cloning the repo or changing `packages.yml` — installed packages aren't part of git history.
- Watch for macro name collisions between packages; namespacing (`dbt_utils.macro_name`) avoids most of these.
- Keep internal, company-specific reusable logic in your own private package (via git) once it's used across multiple dbt projects.

## When to use
- You need a common utility (surrogate key generation, date spine, pivot) — check `dbt_utils` first.
- You want richer data-quality tests than the four built-ins — `dbt_expectations`.
- Your org has multiple dbt projects that share macros/conventions — build an internal package instead of duplicating macros across repos.
- **Not** needed for simple, one-off project-specific macros — just write them locally in `macros/`.
