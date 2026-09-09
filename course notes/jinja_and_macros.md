# Jinja and Macros in dbt

## What Jinja is
**Jinja** is the templating language dbt uses inside `.sql` files. It lets you write SQL that includes variables, conditionals, loops, and function calls — dbt renders (compiles) the Jinja into plain SQL before sending it to the warehouse. This is what makes `ref()`, `config()`, loops over columns, and reusable macros possible.

Jinja has three syntax forms:

| Syntax | Purpose | Example |
| --- | --- | --- |
| `{{ ... }}` | Expression — outputs a value | `{{ ref('customers') }}` |
| `{% ... %}` | Statement — control flow, no output | `{% if is_incremental() %} ... {% endif %}` |
| `{# ... #}` | Comment — ignored during compilation | `{# TODO: revisit this filter #}` |

## Macros

### What they are
A **macro** is a reusable, parameterized block of Jinja that generates SQL (or performs logic) and can be called from any model, test, snapshot, or another macro — similar to a function. Macros live in `.sql` files under the `macros/` directory and are called with `{{ macro_name(...) }}`.

### How they're written in dbt

```sql
-- macros/cents_to_dollars.sql
{% macro cents_to_dollars(column_name) %}
    ({{ column_name }} / 100.0)
{% endmacro %}
```

Used in a model:
```sql
SELECT
    order_id,
    {{ cents_to_dollars('amount_cents') }} AS amount_dollars
FROM {{ ref('stg_payments') }}
```

Compiles to:
```sql
SELECT
    order_id,
    (amount_cents / 100.0) AS amount_dollars
FROM analytics.staging.stg_payments
```

### Loops: generating repetitive SQL
```sql
-- macros/pivot_status_flags.sql
{% macro status_flags(statuses) %}
    {% for status in statuses %}
        CASE WHEN status = '{{ status }}' THEN 1 ELSE 0 END AS is_{{ status }}{{ "," if not loop.last }}
    {% endfor %}
{% endmacro %}
```
```sql
SELECT
    order_id,
    {{ status_flags(['pending', 'shipped', 'delivered']) }}
FROM {{ ref('stg_orders') }}
```

### Adapter-specific logic with `adapter.dispatch()`
```sql
{% macro current_timestamp() %}
    {{ return(adapter.dispatch('current_timestamp')()) }}
{% endmacro %}

{% macro default__current_timestamp() %}
    CURRENT_TIMESTAMP()
{% endmacro %}

{% macro bigquery__current_timestamp() %}
    CURRENT_TIMESTAMP
{% endmacro %}
```
`adapter.dispatch` picks the implementation matching the active warehouse adapter, falling back to `default__` if no adapter-specific version exists. This is how dbt-core and packages like `dbt_utils` support many warehouses from one macro name.

### Hooks as macros
Macros are also used for pre/post-hooks:
```sql
{{ config(
    post_hook="GRANT SELECT ON {{ this }} TO ROLE reporter"
) }}
```

## Useful built-in Jinja/dbt context variables

| Variable/function | Purpose |
| --- | --- |
| `{{ this }}` | The current model's own relation |
| `{{ target }}` | Info about the current run's target (e.g., `target.name`, `target.schema`) |
| `{{ var('name', default) }}` | Read a variable passed via `dbt_project.yml` or `--vars` |
| `{{ env_var('NAME') }}` | Read an environment variable |
| `run_query(sql)` | Run a SQL query at compile time and use its result in Jinja logic |
| `{{ log(msg, info=True) }}` | Print a debug message during compilation |

## Best practices
- Extract any SQL snippet that's copy-pasted across 2+ models into a macro — this is the main way to keep dbt SQL DRY.
- Keep macros small and single-purpose; a macro that tries to do too much becomes as hard to read as inline SQL.
- Use `adapter.dispatch()` only when you actually need multi-warehouse portability (e.g., writing a shared package) — for a single-warehouse project it's often unnecessary complexity.
- Don't hide a `ref()`/`source()` call inside deeply conditional Jinja without a `-- depends_on:` comment — dbt may fail to detect the dependency, breaking the DAG.
- Use `dbt compile` or `dbt show --select model_name` to inspect what Jinja actually rendered — never guess.
- Reach for existing packages (`dbt_utils`, `dbt_expectations`) before writing a custom macro — many common needs (date spines, pivoting, surrogate keys) are already solved.

## When to use
- Repeated SQL logic (unit conversions, standard CASE statements, column-name generation).
- Generating SQL dynamically based on a list of columns/values known at compile time (e.g., pivoting).
- Custom materializations, hooks, or adapter-specific behavior.
- **Not** a substitute for a real dbt model — if the output should be queryable as its own table/view, write a model, not a macro that just emits a giant `SELECT`.
