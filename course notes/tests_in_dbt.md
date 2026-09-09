# Tests in dbt

A **test** is an assertion about your data. dbt runs a test as a SQL query that returns rows — **zero rows means the test passed**, one or more rows means it failed. Tests let you catch broken assumptions (duplicates, nulls, invalid values, broken relationships) automatically instead of discovering them downstream in a dashboard.

dbt has three kinds of tests: **generic tests**, **singular tests**, and **unit tests**.

---

## 1. Generic Tests

### What they are
A **generic test** is a reusable, parameterized test defined once (as a macro) and applied to any model, column, source, seed, or snapshot via YAML. dbt ships with four built-in generic tests.

### How they're written in dbt
```yaml
# models/schema.yml
version: 2

models:
  - name: dim_customers
    columns:
      - name: customer_id
        tests:
          - unique
          - not_null
      - name: status
        tests:
          - accepted_values:
              values: ['active', 'inactive', 'pending']
      - name: order_id
        tests:
          - relationships:
              to: ref('fct_orders')
              field: order_id
```

Built-in generic tests:

| Test | Checks |
| --- | --- |
| `unique` | No duplicate values in a column |
| `not_null` | No null values in a column |
| `accepted_values` | Column only contains values from an allowed list |
| `relationships` | Every value in this column exists in a referenced model's column (referential integrity) |

### Writing your own generic test
```sql
-- macros/generic_tests/test_positive_value.sql
{% test positive_value(model, column_name) %}

SELECT *
FROM {{ model }}
WHERE {{ column_name }} < 0

{% endtest %}
```
Use it just like a built-in test:
```yaml
columns:
  - name: price
    tests:
      - positive_value
```

### Best practices
- Test primary keys of every model with `unique` + `not_null` at minimum.
- Use `relationships` tests to catch broken foreign keys early, especially across staging → marts joins.
- Prefer generic tests over singular tests whenever the same check applies to multiple columns/models — they're reusable and self-documenting in YAML.
- Use packages like `dbt_utils` and `dbt_expectations` for extra generic tests (e.g., `dbt_utils.expression_is_true`, `not_accepted_values`) instead of reinventing them.
- Set `severity: warn` for tests that shouldn't block a build but are worth monitoring:
  ```yaml
  tests:
    - not_null:
        config:
          severity: warn
  ```

### When to use
- Any repeatable rule that applies to a column across many models: uniqueness, null checks, enums, foreign keys.
- The default choice for almost all data-quality assertions — reach for a singular test only when the logic can't be parameterized.

---

## 2. Singular Tests

### What they are
A **singular test** is a one-off SQL query stored as a `.sql` file in the `tests/` directory. Like all tests, it must return failing rows — an empty result means the test passes.

### How they're written in dbt
```sql
-- tests/assert_no_negative_order_totals.sql
SELECT
    order_id,
    order_total
FROM {{ ref('fct_orders') }}
WHERE order_total < 0
```

No YAML is required — dbt automatically discovers any `.sql` file under `tests/` (excluding `generic/`, which is reserved for generic test definitions) and runs it as a test.

### Best practices
- Use singular tests for **business-specific logic** that doesn't generalize into a reusable macro (e.g., "revenue this month should never drop more than 50% vs. last month").
- Name the file descriptively (`assert_*`, `test_*`) so failures are self-explanatory in CI logs.
- Keep singular tests scoped to one clear assertion — don't combine multiple unrelated checks in a single file.
- If you find yourself copy-pasting a singular test with small variations across models, convert it into a generic test instead.

### When to use
- A one-off business rule specific to a single model or a specific cross-model relationship.
- Complex checks that don't fit the `(model, column_name)` signature of a generic test.

---

## 3. Unit Tests

### What they are
A **unit test** validates a model's SQL *logic* against small, hand-crafted mock inputs — checking that given specific input rows, the model produces the expected output rows. This is different from generic/singular tests (which are "data tests" that check the actual built relation) — unit tests check the *transformation code itself*, often before the model even touches real warehouse data.

### How they're written in dbt
```yaml
# models/unit_tests.yml
unit_tests:
  - name: test_discount_calculation
    model: fct_orders
    given:
      - input: ref('stg_orders')
        rows:
          - {order_id: 1, unit_price: 100, quantity: 2, discount_pct: 0.1}
    expect:
      rows:
        - {order_id: 1, order_total: 180}
```

Run with:
```bash
dbt test --select test_type:unit
```

### Best practices
- Use unit tests for models with **non-trivial SQL logic** (case statements, discount math, deduplication logic) where you want to lock in expected behavior for edge cases (nulls, zeros, boundary values).
- Keep mock input sets small and intentional — a handful of rows that exercise specific branches of your logic, not a full data sample.
- Pair unit tests with data tests: unit tests catch logic bugs before deploy; data tests catch real-world data quality issues after deploy.

### When to use
- Complex transformation logic where you want fast, deterministic feedback without needing a full warehouse build.
- Regression protection when refactoring a model's SQL — run unit tests to confirm behavior didn't change.
- Not a replacement for data tests — use both together.

---

## 4. Running Tests

```bash
dbt test                              # run all tests
dbt test --select dim_customers       # tests on one model
dbt test --select test_type:generic   # only generic tests
dbt test --select test_type:singular  # only singular tests
dbt build                             # builds models/seeds/snapshots AND runs their tests, in DAG order
```

`dbt build` is generally preferred over `dbt run` + `dbt test` separately in CI, because it stops downstream models from building on top of data that just failed a test.

## 5. Quick Comparison

| Test type | Defined in | Reusable? | Checks |
| --- | --- | --- | --- |
| Generic | YAML (calls a macro) | Yes, across columns/models | Data in the built relation |
| Singular | Standalone `.sql` file | No, one-off | Data in the built relation |
| Unit | YAML with mock rows | Per-model | Model SQL logic, using mock inputs |

**Rule of thumb:** default to generic tests, drop to a singular test for one-off business rules, and add unit tests when a model's SQL logic is complex enough that you want to pin down expected behavior for specific edge cases.
