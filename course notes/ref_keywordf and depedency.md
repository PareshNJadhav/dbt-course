# dbt Model Dependencies and `ref()`

## 1. What are Model Dependencies?

In dbt, **model dependencies** describe which dbt models depend on other dbt models.

dbt uses these dependencies to create a **DAG (Directed Acyclic Graph)** and determine the correct order in which models should be built.

For example:

```text
customers
    |
    v
orders
    |
    v
customer_orders
```

## 2. The `ref()` function

Use `ref()` when one dbt resource depends on another dbt model, seed, or snapshot:

```sql
SELECT *
FROM {{ ref('src_listings') }}
```

`ref()` does two jobs:

1. It resolves the model name to the correct database relation, including the target database, schema, and alias.
2. It tells dbt that the current model depends on `src_listings`.

The model name is the dbt filename without `.sql`, not necessarily the physical table name. dbt renders the Jinja expression before sending SQL to the warehouse. For example, the compiled SQL might contain:

```sql
FROM AIRBNB.ANALYTICS.SRC_LISTINGS
```

Do not hard-code this relation when it is another dbt model. Hard-coding bypasses dbt's dependency graph and makes environments, schemas, and model renames harder to manage.

### `ref()` with package and version arguments

When using a model from another package, include the package name:

```sql
{{ ref('package_name', 'model_name') }}
```

If model versions are configured, a version can also be selected:

```sql
{{ ref('customers', version=2) }}
```

## 3. How dbt tracks dependencies

During parsing and compilation, dbt builds a graph of resources. A `ref()` call creates an edge from the current node to the referenced node:

```text
model.airbnb.src_listings  -->  model.airbnb.dim_listings_cleansed
```

The graph is used to:

- build upstream models before downstream models;
- select related resources with commands such as `dbt build --select src_listings+`;
- run only affected downstream resources in CI or development;
- detect cycles and invalid references;
- generate lineage in dbt documentation and the DAG view.

The graph is recorded in `target/manifest.json`. Useful fields include:

```json
{
    "depends_on": {
        "nodes": ["model.airbnb.src_listings"]
    },
    "parent_map": {
        "model.airbnb.dim_listings_cleansed": ["model.airbnb.src_listings"]
    },
    "child_map": {
        "model.airbnb.src_listings": ["model.airbnb.dim_listings_cleansed"]
    }
}
```

Node IDs include the resource type and project/package name, so two packages can contain models with the same filename without creating an ambiguous reference.

Inspect the graph with:

```bash
dbt ls --select +dim_listings_cleansed+
dbt docs generate
dbt docs serve
```

`dbt ls` is useful for checking selection and lineage without running SQL. The generated documentation site provides an interactive DAG.

## 4. `source()` for raw data dependencies

Use `source()` for tables loaded into the warehouse by an external system, rather than by another dbt model:

```sql
SELECT *
FROM {{ source('raw', 'raw_listings') }}
```

The source is declared in a YAML file:

```yaml
version: 2

sources:
    - name: raw
        schema: raw
        tables:
            - name: raw_listings
```

`source()` also creates a graph dependency. The difference is that `ref()` points to a dbt-managed resource, while `source()` points to an external table. Sources can have freshness checks, tests, and documentation.

## 5. Other related dbt Jinja functions

| Function | Purpose | Example |
| --- | --- | --- |
| `source()` | Reference an external/raw table declared in YAML | `{{ source('raw', 'orders') }}` |
| `this` | Refer to the current model's relation | `{{ this }}` |
| `config()` | Set model configuration in SQL | `{{ config(materialized='table') }}` |
| `var()` | Read a value passed in `dbt_project.yml` or with `--vars` | `{{ var('days_back', 7) }}` |
| `env_var()` | Read an environment variable | `{{ env_var('DBT_ENV_NAME') }}` |
| `doc()` | Link a column or model description to a Markdown block | `{{ doc('customer_id') }}` |
| `ref()` | Reference another dbt model, seed, or snapshot and create lineage | `{{ ref('customers') }}` |

`var()`, `env_var()`, and `config()` can change compilation or configuration, but they do not normally create a model-to-model dependency. Use `ref()` or `source()` when lineage and execution order matter.

## 6. Explicit dependencies with `-- depends_on`

Most dependencies are discovered automatically from `ref()` and `source()` calls. A dependency can be hidden inside a conditional Jinja block or macro. In that case, add a SQL comment containing a parseable reference:

```sql
-- depends_on: {{ ref('customers') }}

{% if execute %}
    {% set result = run_query('SELECT 1') %}
{% endif %}

SELECT *
FROM {{ ref('orders') }}
```

The comment does not execute as warehouse SQL, but dbt parses the `ref()` expression and adds the dependency to the graph. Prefer direct `ref()` calls in model SQL when possible because they are easier to read and maintain.

## 7. Common mistakes

- Use `{{ ref('model_name') }}`, not `ref('schema.table')`.
- Do not include the `.sql` extension in a model reference.
- Use `source()` for externally loaded tables and `ref()` for dbt resources.
- Do not use `{{ ref() }}` inside a quoted SQL string and expect dbt to discover the dependency.
- If a model is renamed, update every `ref()` call and run `dbt parse` or `dbt build` to catch invalid references.
- Use `dbt build`, not only `dbt run`, when you want models, tests, seeds, and snapshots to be built according to their dependencies.

## 8. Summary

`ref()` is both a relation resolver and a dependency declaration. dbt parses it, records the upstream node in the manifest, orders execution using the DAG, and exposes the relationship through selectors and documentation. For raw warehouse tables, use `source()` so those upstream dependencies are tracked with the same lineage system.
