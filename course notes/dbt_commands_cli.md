# dbt CLI Commands Overview

## What this covers
dbt's command-line interface is how you invoke every action — parsing the project, building models, running tests, generating docs, and managing packages. This note is a fundamentals-level reference for the commands you'll use daily, since prior notes reference many of them individually without listing them together.

## Core build commands

| Command | What it does |
| --- | --- |
| `dbt run` | Executes model SQL and builds views/tables (does not run tests or seeds) |
| `dbt seed` | Loads CSV files from `seeds/` into the warehouse |
| `dbt snapshot` | Runs snapshot definitions to capture historical row versions |
| `dbt test` | Runs generic, singular, and unit tests |
| `dbt build` | Runs seeds, snapshots, models, and tests together, in correct DAG order, stopping downstream builds if an upstream test fails |

**`dbt build` is the recommended default** for most workflows (local dev, CI, scheduled jobs) because it respects dependency order across resource types — a failing test on a staging model prevents a mart built on top of it from running with bad data.

## Inspection and validation commands

| Command | What it does |
| --- | --- |
| `dbt parse` | Validates project/YAML/Jinja syntax and builds the manifest, without hitting the warehouse |
| `dbt compile` | Renders Jinja/SQL to plain SQL (written to `target/compiled/`) without executing it |
| `dbt debug` | Validates `profiles.yml` connection settings and confirms dbt can reach the warehouse |
| `dbt ls` (or `dbt list`) | Lists resources matching a selector, without running anything — great for previewing a `--select` before executing it |
| `dbt show --select <model>` | Compiles and runs a model's SQL, previewing sample output rows, without materializing it |

## Documentation and dependency commands

| Command | What it does |
| --- | --- |
| `dbt docs generate` | Builds the documentation site's metadata (`catalog.json`, `manifest.json`) |
| `dbt docs serve` | Serves the generated documentation site locally |
| `dbt deps` | Installs packages listed in `packages.yml` into `dbt_packages/` |
| `dbt clean` | Deletes generated directories (`target/`, `dbt_packages/` by default, per `clean-targets`) |
| `dbt source freshness` | Checks configured sources against their `warn_after`/`error_after` freshness thresholds |
| `dbt run-operation <macro>` | Invokes a macro directly from the CLI, outside the model DAG |

## Useful flags (combine with most commands above)

| Flag | Purpose |
| --- | --- |
| `--select` / `-s` | Restrict to a subset of resources (see model selection syntax) |
| `--exclude` | Remove a subset from the selection |
| `--full-refresh` | Force a full rebuild (drops/rebuilds incremental models and seeds from scratch) |
| `--target` | Choose which `profiles.yml` output/environment to run against |
| `--vars` | Pass variable overrides for this invocation |
| `--fail-fast` | Stop the run as soon as any resource fails, instead of continuing |
| `--threads` | Override the number of concurrent threads used to build the DAG |

## Best practices
- Default to `dbt build` locally and in CI rather than chaining `dbt run && dbt test` — it respects cross-resource-type dependency order and fails fast on bad data.
- Run `dbt parse` or `dbt compile` as a cheap first check after editing YAML/Jinja — catches syntax errors before spending time/compute on a real warehouse run.
- Run `dbt debug` first when setting up a new environment or troubleshooting connection issues — it isolates "can dbt reach the warehouse at all" from "is my project logic broken."
- Use `dbt show --select model_name` during development to preview a model's output without materializing it — faster feedback than a full build.
- Reserve `--full-refresh` for when incremental logic or schema has changed — running it unnecessarily on very large tables can be expensive.

## When to use which
- **Iterating on one model's SQL**: `dbt compile` / `dbt show` for fast feedback, then `dbt build --select model_name`.
- **Before opening a PR**: `dbt build --select state:modified+` to build only what changed and its dependents.
- **Setting up a new machine/environment**: `dbt deps`, then `dbt debug`, then `dbt build`.
- **Scheduled production job**: `dbt source freshness` → `dbt build` → `dbt docs generate`, in that order.
