# Documentation and Exposures in dbt

## Documentation

### What it is
dbt lets you attach human-readable descriptions to models, columns, sources, seeds, snapshots, and macros, and then generates a browsable, searchable **documentation website** with an interactive lineage graph (DAG) built from `ref()`/`source()` relationships.

### How it's written in dbt

**YAML descriptions** (most common):
```yaml
version: 2

models:
  - name: dim_customers
    description: One row per customer with cleaned attributes and lifetime metrics.
    columns:
      - name: customer_id
        description: Unique identifier for a customer, sourced from the CRM.
```

**Reusable Markdown doc blocks** — useful when the same explanation applies in multiple places, or the description is long:
```md
{# docs/customer_id.md #}
{% docs customer_id %}
The stable identifier assigned to a customer by the CRM system.
Do not confuse with `crm_contact_id`, which can change if a contact record is merged.
{% enddocs %}
```
```yaml
columns:
  - name: customer_id
    description: '{{ doc("customer_id") }}'
```

Generate and view the site:
```bash
dbt docs generate
dbt docs serve
```

### Best practices
- Document every model's *purpose* (what business question it answers, its grain) — not just a restatement of the column names.
- Document the **grain** of every model explicitly (e.g., "one row per customer per day") — this is the single most useful sentence for anyone querying it later.
- Use Markdown doc blocks for long or repeated explanations (business definitions, caveats) instead of duplicating the same paragraph across many YAML files.
- Keep descriptions close to the code they describe — commit YAML/docs changes in the same PR as the model change, so docs never drift from reality.
- Regenerate docs as part of CI/CD (or automatically on merge to main) so the hosted site reflects production, not a stale local build.

### When to use
- Always, for any model that other people (analysts, other teams, future you) will query — undocumented models create tribal knowledge and repeated Slack questions.
- Doc blocks specifically when a definition needs more than one sentence, or needs to be reused verbatim across several columns/models.

---

## Exposures

### What they are
An **exposure** declares a downstream consumer of your dbt models — a dashboard, notebook, ML pipeline, or application — so that dependency lives *in* the dbt DAG. This makes it possible to see "if I change this model, what dashboards break?" directly from lineage, instead of relying on tribal knowledge.

### How it's written in dbt
```yaml
# models/marts/exposures.yml
version: 2

exposures:
  - name: executive_revenue_dashboard
    type: dashboard
    maturity: high
    url: https://bi-tool.example.com/dashboards/executive-revenue
    description: Monthly revenue and churn dashboard reviewed by leadership.
    depends_on:
      - ref('fct_orders')
      - ref('dim_customers')
    owner:
      name: Analytics Team
      email: analytics@example.com
```

Exposures show up in `dbt docs generate`'s lineage graph as a terminal node, and can be selected like any other resource:
```bash
dbt build --select +exposure:executive_revenue_dashboard
```

### Best practices
- Add an exposure for every dashboard/report that leadership or external stakeholders rely on — these are the ones you most need to protect from breaking changes.
- Set `owner` so it's clear who to notify (or who to ask) before making a breaking change to an upstream model.
- Use `maturity` (`low`/`medium`/`high`) to signal how stable/trusted a downstream asset is, useful when triaging the impact of a proposed change.
- Before modifying or deprecating a widely-used model, run `dbt ls --select <model>+` and check which exposures depend on it.

### When to use
- Any significant, known downstream consumer: an exec dashboard, a scheduled export, a notebook feeding a model, an application reading from a mart table.
- Not necessary for ad hoc, one-off queries with no lasting stakeholder impact.
