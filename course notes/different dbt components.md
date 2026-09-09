# dbt Project Components

dbt projects are made from different resource types. Each resource has a different purpose in the transformation workflow.

```text
source data -> models -> tests and documentation
											 |
											 +-> seeds for small reference data
											 +-> snapshots for historical change tracking
											 +-> analyses for investigations and reporting SQL
											 +-> macros for reusable Jinja/SQL logic
```

The project directories are configured in `dbt_project.yml`:

```yaml
model-paths: [models]
analysis-paths: [analyses]
test-paths: [tests]
seed-paths: [seeds]
macro-paths: [macros]
snapshot-paths: [snapshots]
```

## 1. Models

A **model** is a SQL or Python transformation managed by dbt. A model normally selects from sources or upstream models and creates a relation in the warehouse. SQL models are the most common dbt resource.

Example SQL model:

```sql
-- models/staging/stg_listings.sql
{{ config(materialized='view') }}

SELECT
		id AS listing_id,
		name AS listing_name,
		price AS price_str,
		host_id
FROM {{ source('raw', 'listings') }}
```

Use `ref()` for another dbt model:

```sql
-- models/marts/fct_bookings.sql
SELECT
		booking_id,
		listing_id,
		booking_date
FROM {{ ref('stg_bookings') }}
```

### Model materialization types

Materialization is the strategy dbt uses to build a model. Set it with `{{ config(materialized='...') }}` or in `dbt_project.yml`.

| Materialization | What dbt creates | Typical use |
| --- | --- | --- |
| `view` | A database view whose SQL is re-evaluated when queried | Lightweight staging transformations |
| `table` | A physical table rebuilt during the model run | Stable marts and moderate-sized transformations |
| `incremental` | A table that inserts or merges only new/changed rows after the first run | Large event or transaction tables |
| `ephemeral` | No database relation; SQL is injected as a CTE into downstream models | Small reusable SQL snippets |
| `materialized_view` | A warehouse-managed materialized view, where the adapter supports it | Warehouse-managed refresh of query results |
| custom | A project or package-defined materialization macro | Specialized warehouse behavior |

Incremental example:

```sql
{{ config(
		materialized='incremental',
		unique_key='event_id'
) }}

SELECT *
FROM {{ source('raw', 'events') }}
{% if is_incremental() %}
WHERE updated_at >= (SELECT MAX(updated_at) FROM {{ this }})
{% endif %}
```

`is_incremental()` is true when the model already exists, the run is not a full refresh, and the model is configured as incremental. `{{ this }}` refers to the current model relation.

### Model naming layers

`staging`, `intermediate`, and `marts` are common architecture conventions, not built-in dbt model types:

- **Staging**: rename columns, cast types, and lightly clean one source.
- **Intermediate**: combine or transform staging models into reusable business logic.
- **Marts**: business-facing facts, dimensions, and reporting tables.

SQL models can also be Python models in supported adapters. Python models use a Python model function and adapter-specific execution rules; they still participate in `ref()` lineage and model selection.

## 2. Seeds

A **seed** is a CSV file committed to the dbt project and loaded into the warehouse by `dbt seed`. Seeds are appropriate for small, stable reference data maintained by the analytics team, such as country codes, status mappings, or tax rates.

Example CSV:

```csv
status_code,status_name,is_active
A,Active,true
I,Inactive,false
```

Example file location:

```text
seeds/status_codes.csv
```

Reference a seed from a model with `ref()`:

```sql
SELECT
		orders.order_id,
		orders.status_code,
		statuses.status_name
FROM {{ ref('orders') }} AS orders
LEFT JOIN {{ ref('status_codes') }} AS statuses
		ON orders.status_code = statuses.status_code
```

### Seed configuration types

Seed configuration is adapter-dependent, but common settings include:

- `column_types`: explicitly set warehouse data types for columns;
- `quote_columns`: quote CSV column names when required by the warehouse;
- `delimiter`: use a delimiter other than a comma;
- `full_refresh`: control whether an existing seed is replaced;
- `schema`, `database`, and `alias`: control the destination relation;
- `tags`, `enabled`, and `meta`: organize or annotate the seed.

Example properties file:

```yaml
version: 2

seeds:
	- name: status_codes
		description: Stable status mappings maintained by the analytics team.
		config:
			column_types:
				status_code: varchar(10)
				status_name: varchar(100)
				is_active: boolean
```

Useful commands:

```bash
dbt seed
dbt seed --select status_codes
dbt seed --full-refresh
```

Do not use seeds for large operational datasets or data that should be loaded through a production ingestion process.

## 3. Analyses

An **analysis** is SQL stored in the `analyses/` directory for exploration, investigation, or business reporting. dbt compiles an analysis but does not create a model relation for it during `dbt run` or `dbt build`.

Example:

```sql
-- analyses/monthly_revenue_check.sql
SELECT
		DATE_TRUNC('month', order_date) AS order_month,
		SUM(amount) AS revenue
FROM {{ ref('fct_orders') }}
GROUP BY 1
ORDER BY 1
```

Analyses can use `ref()`, `source()`, macros, variables, and Jinja just like models. This means dbt can compile them against the correct environment and track their upstream references.

Typical analysis types are organizational conventions:

- ad hoc investigation of an unexpected metric;
- data quality or reconciliation query;
- exploratory business analysis;
- SQL intended for a BI tool or scheduled report;
- migration or backfill planning query.

An analysis is not the right resource when the result must be materialized and reused by other dbt models. Use a model for that case.

Compile an analysis with:

```bash
dbt compile --select analysis:monthly_revenue_check
```

The compiled SQL is written under `target/compiled/`.

## 4. Tests

A **test** checks an assumption about the data. dbt tests return failing rows: zero rows means the test passes, while one or more rows means it fails.

### Generic tests

Generic tests are reusable test definitions applied to models, columns, sources, seeds, or snapshots. dbt provides built-in generic tests:

- `unique`: values are not duplicated;
- `not_null`: values are present;
- `accepted_values`: values belong to an allowed list;
- `relationships`: values exist in a related model or column.

Example:

```yaml
version: 2

models:
	- name: dim_listings
		columns:
			- name: listing_id
				tests:
					- not_null
					- unique
			- name: host_id
				tests:
					- relationships:
							to: ref('dim_hosts')
							field: host_id
```

### Singular tests

A **singular test** is a one-off SQL query stored in `tests/`. It should return failing records.

```sql
-- tests/assert_no_negative_prices.sql
SELECT listing_id, price
FROM {{ ref('dim_listings') }}
WHERE price < 0
```

### Unit tests

Where supported by the dbt version and adapter, **unit tests** validate model logic against small inline or fixture inputs before the model is run against full warehouse data. They are useful for edge cases such as null handling and case expressions. They are different from data tests: unit tests check transformation logic, while data tests check the resulting relation.

Run tests with:

```bash
dbt test
dbt test --select model:dim_listings
dbt build --select dim_listings
```

`dbt build` builds selected resources and runs their applicable tests in dependency order.

## 5. Documentation

dbt documentation explains what models, columns, sources, seeds, and metrics mean. Documentation can be written in YAML descriptions or reusable Markdown `docs` blocks.

### YAML descriptions

```yaml
version: 2

models:
	- name: dim_listings
		description: One row per listing with cleaned pricing attributes.
		columns:
			- name: listing_id
				description: Unique identifier for the listing.
```

### Reusable docs blocks

Create a Markdown file under a configured resource path:

```md
{% docs listing_id_definition %}
The stable identifier assigned to a listing by the source system.
{% enddocs %}
```

Reference the block in YAML:

```yaml
columns:
	- name: listing_id
		description: '{{ doc("listing_id_definition") }}'
```

Documentation resource types include:

- model and column descriptions;
- source and source-column descriptions;
- seed and snapshot descriptions;
- test descriptions;
- exposures for dashboards, notebooks, or downstream applications;
- groups, metrics, and semantic-model metadata where supported by the dbt version.

Generate and serve the documentation site:

```bash
dbt docs generate
dbt docs serve
```

The documentation site includes model lineage and shows upstream and downstream relationships created by `ref()` and `source()`.

## 6. Macros

A **macro** is reusable Jinja code that can generate SQL or perform reusable dbt logic. Macros are stored in `macros/` and are called with `{{ macro_name(...) }}`.

Simple macro:

```sql
-- macros/cents_to_dollars.sql
{% macro cents_to_dollars(column_name) %}
		({{ column_name }} / 100.0)
{% endmacro %}
```

Use it in a model:

```sql
SELECT
		{{ cents_to_dollars('amount_cents') }} AS amount_dollars
FROM {{ ref('payments') }}
```

### Macro types and patterns

- **SQL-generation macros** return a SQL expression or clause.
- **Utility macros** normalize names, build dates, or handle adapter differences.
- **Control-flow macros** use Jinja loops and conditions to generate repeated SQL.
- **Metadata macros** inspect the graph or relation metadata.
- **Hook macros** run SQL before or after a model, seed, snapshot, or project operation.
- **Materialization macros** implement custom strategies for creating relations.
- **Dispatchable macros** provide adapter-specific implementations through `adapter.dispatch()`.

Macro arguments are strings or Jinja expressions. Quote a column name when the macro expects SQL text, and use `ref()` inside a macro when the macro needs to reference a dbt resource.

Macros do not usually create a dependency merely because a macro exists. A dependency is created when the compiled macro usage contains a parsed `ref()` or `source()` call. Keep dependency-relevant references visible and test macro output with `dbt compile`.

## 7. Snapshots

A **snapshot** records historical versions of rows that change over time. It is useful when the source table does not preserve history and the business needs to answer questions such as “what was the customer status on a previous date?”

Example snapshot:

```sql
{% snapshot customers_snapshot %}

{{ config(
		target_schema='snapshots',
		unique_key='customer_id',
		strategy='timestamp',
		updated_at='updated_at'
) }}

SELECT
		customer_id,
		customer_status,
		updated_at
FROM {{ source('raw', 'customers') }}

{% endsnapshot %}
```

### Snapshot strategy types

**Timestamp strategy** compares an `updated_at` column. It is preferred when the source reliably updates a timestamp whenever tracked values change.

```sql
strategy='timestamp',
updated_at='updated_at'
```

**Check strategy** compares one or more columns and detects a change when their values differ.

```sql
strategy='check',
check_cols=['customer_status', 'email']
```

`check_cols='all'` is also possible, but explicitly listing important columns is often clearer and less expensive.

Snapshots add metadata columns such as `dbt_valid_from`, `dbt_valid_to`, `dbt_scd_id`, and `dbt_updated_at`. A row version with a null `dbt_valid_to` is the current version in the snapshot table.

Run snapshots with:

```bash
dbt snapshot
dbt snapshot --select customers_snapshot
```

Snapshots are for change history, not for general-purpose incremental loading. An incremental model usually keeps the latest transformed rows, while a snapshot keeps multiple historical versions.

## 8. How resources relate to each other

```text
source() or seed -> staging model -> intermediate model -> mart model
															|             |                 |
															+-------------+-----------------+
																			tests and docs

source() -> snapshot -> historical reporting model

macro -> generates SQL used by models, tests, analyses, or snapshots
```

The main dependency functions are:

- `ref('resource_name')`: references a dbt model, seed, or snapshot;
- `source('source_name', 'table_name')`: references an externally loaded source;
- `doc('block_name')`: references reusable documentation text;
- `var('name')` and `env_var('NAME')`: read configuration values, but do not normally create lineage edges.

Use `dbt ls`, `dbt docs generate`, and the `parent_map`/`child_map` sections of `target/manifest.json` to inspect the resulting graph.

## 9. Quick comparison

| Resource | Main output | Built by | Common types or strategies |
| --- | --- | --- | --- |
| Model | View, table, or other relation | `dbt run` or `dbt build` | view, table, incremental, ephemeral, Python |
| Seed | Relation loaded from CSV | `dbt seed` or `dbt build` | CSV reference data, typed columns |
| Analysis | Compiled SQL, no normal relation | `dbt compile` | investigation, reconciliation, reporting SQL |
| Test | Pass/fail result from returned rows | `dbt test` or `dbt build` | generic, singular, unit, source tests |
| Documentation | Metadata and browsable lineage site | `dbt docs generate` | YAML descriptions, docs blocks, exposures |
| Macro | Reusable generated SQL or dbt logic | During compilation/execution | SQL, utility, hook, materialization, dispatch |
| Snapshot | Historical relation versions | `dbt snapshot` or `dbt build` | timestamp, check |

The best resource depends on the desired result: use a model for a reusable transformation, a seed for small version-controlled CSV data, an analysis for compiled exploration, a test for an assertion, a macro for reusable logic, documentation for meaning and lineage, and a snapshot for row history.
