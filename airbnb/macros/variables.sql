{% macro variables() %}
  {% set name = "Paresh" %}
  {{ log("Hello, " ~ name, info=True) }}
  {{ log("This is a test message.", info=True) }}

  {{ log("Hello, " ~ var('user_name'), info=True) }}

{% endmacro %}