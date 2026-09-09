# `dbt_project.yml` and `profiles.yml`

dbt uses two important YAML files for different responsibilities:

| File | Main responsibility | Usually stored |
| --- | --- | --- |
| `dbt_project.yml` | Defines the dbt project and project/model configuration | In the project root and committed to Git |
| `profiles.yml` | Defines connection details and deployment targets | In the user's dbt profiles directory, normally not committed |

Think of the distinction as:

```text
dbt_project.yml  = How this dbt project is organized and configured
profiles.yml     = Where and how dbt connects to the warehouse
```

## `dbt_project.yml`

`dbt_project.yml` is required in the root of a dbt project. It tells dbt the project name, which profile to use, where resources live, and which defaults apply to models, seeds, snapshots, and tests.

Example from this project:

```yaml
name: airbnb
version: '1.0.0'
profile: airbnb

model-paths: [models]
analysis-paths: [analyses]
test-paths: [tests]
seed-paths: [seeds]
macro-paths: [macros]
snapshot-paths: [snapshots]

models:
	airbnb:
		staging:
			+materialized: view
		marts:
			+materialized: table
```

Important fields:

- `name`: the project/package name. It is used in node IDs such as `model.airbnb.customer_orders`.
- `profile`: the name of the profile key that dbt looks up in `profiles.yml`.
- `*-paths`: directories where dbt discovers models, tests, seeds, macros, snapshots, and analyses.
- `models`: project-level model configurations. The `+` prefix makes it clear that the value is a config.
- `clean-targets`: generated directories removed by `dbt clean`, commonly `target` and `dbt_packages`.

The project file should not contain passwords, private keys, or warehouse credentials.

## `profiles.yml`

`profiles.yml` maps the project `profile:` name to one or more connection outputs. It commonly lives at `~/.dbt/profiles.yml` on macOS/Linux or `%USERPROFILE%\\.dbt\\profiles.yml` on Windows. A project can also use a custom location with the `DBT_PROFILES_DIR` environment variable.

Example shape for the Snowflake profile used by this course:

```yaml
airbnb:
	target: dev
	outputs:
		dev:
			type: snowflake
			account: <account>
			user: <user>
			role: TRANSFORM
			database: AIRBNB
			schema: DEV
			warehouse: COMPUTE_WH
			threads: 1
			authenticator: <authentication method>
```

`target: dev` selects the output named `dev`. You can select another output for a run with:

```bash
dbt debug --target dev
dbt build --target prod
```

The exact fields depend on the adapter. For Snowflake they can include `account`, `user`, `private_key`, `private_key_passphrase`, `database`, `schema`, `warehouse`, `role`, and `threads`. Keep secrets outside Git and prefer environment variables or a secret manager:

```yaml
user: "{{ env_var('DBT_USER') }}"
private_key_passphrase: "{{ env_var('DBT_PRIVATE_KEY_PASSPHRASE') }}"
```

Run this to check both the profile and the connection:

```bash
dbt debug
```

## Project configuration versus connection configuration

These files work together, but they do not replace each other:

```text
dbt_project.yml  -> discovers resources and sets dbt behavior/configuration
profiles.yml     -> selects an adapter, target database/schema, credentials, and threads
model SQL/YAML   -> can specialize configuration for one model or group of models
```

For example, `profiles.yml` can choose the Snowflake schema `DEV`, while `dbt_project.yml` can make all staging models views. The final relation might therefore be created as `AIRBNB.DEV.STG_LISTINGS` as a view.

## Properties files: use YAML, not `.properties`

dbt does not use a Java-style or generic `.properties` file for model configuration. In dbt, the term **properties file** normally means a YAML file containing resource properties, often named `schema.yml`, `models.yml`, or `properties.yml` under the project directory.

A properties YAML file can document a model, define columns and tests, and provide model configuration:

```yaml
version: 2

models:
	- name: stg_listings
		description: Cleaned listing records.
		config:
			materialized: view
			tags: [staging]
		columns:
			- name: listing_id
				description: Unique listing identifier.
				tests:
					- not_null
					- unique
```

The filename is flexible, but it must be in a configured resource path and use valid dbt YAML structure. A schema/properties file is also the usual place for tests and documentation. It is not the same as `profiles.yml`: properties describe dbt resources, while profiles describe warehouse connections.

## Configuration locations and precedence

For a model configuration, use the most specific location that should own the rule. The practical precedence is:

```text
model SQL:       {{ config(...) }}
properties YAML: models: - name: ... config: ...
dbt_project.yml: models: project/folder defaults
```

More-specific configuration overrides a less-specific configuration for the same setting. A project default can therefore be defined once and changed only for an individual model when necessary.

### Project-level default

```yaml
# dbt_project.yml
models:
	airbnb:
		staging:
			+materialized: view
```

Every model in `models/staging/` is a view unless a more specific config overrides it.

### Properties-file override

```yaml
# models/schema.yml
version: 2

models:
	- name: stg_listings
		config:
			materialized: table
```

`stg_listings` becomes a table even though the staging folder default is `view`.

### Model-level override

```sql
{{ config(materialized='incremental', unique_key='listing_id') }}

SELECT *
FROM {{ ref('src_listings') }}
```

This SQL-level configuration is the most specific. It applies only to this model and overrides the broader project or properties-file value for `materialized`.

Use folder-level configuration for consistent conventions, properties YAML for resource documentation/tests and shared model settings, and SQL `config()` for a model-specific exception. Avoid setting the same option in several places unless the override is intentional and documented.

## Useful checks

```bash
dbt debug                 # Validate profile and connection
dbt parse                 # Validate project, YAML, Jinja, and references
dbt ls --resource-type model
dbt config get --select stg_listings --config materialized
```

The exact `dbt config get` options can vary by dbt version. `dbt parse` and `dbt debug` are the first checks to run when changing project or profile configuration.
