{#-
  Fare arithmetic shared by every model that decomposes a trip total.
  Kept in one place because the component list changes whenever TLC adds a
  surcharge, and a model that misses one silently lands it in the residual.
-#}

{% macro surcharge_columns() -%}
    {{ return(['extra', 'mta_tax', 'improvement_surcharge', 'congestion_surcharge']) }}
{%- endmacro %}

{#- Sum of every pass-through the passenger pays that is not fare, tip or toll. -#}
{% macro total_surcharges(alias='t') -%}
    (
    {%- for c in surcharge_columns() %}
        coalesce({{ alias }}.{{ c }}, 0){{ ' + ' if not loop.last }}
    {%- endfor %}
    )
{%- endmacro %}

{#-
  Every component the revenue walk publishes, in the order the walk reports
  them. The airport fee is not a surcharge -- it is rated separately and
  reported in its own column -- so it is named here rather than added to
  `surcharge_columns()`, whose sum is published in its own right.
-#}
{% macro decomposed_columns() -%}
    {{ return(['fare_amount', 'tip_amount', 'tolls_amount'] + surcharge_columns() + ['airport_fee']) }}
{%- endmacro %}

{#-
  What the total does not explain. A non-zero residual means either a component
  we do not model, or a total that was not derived from its parts.

  Every component the walk publishes is subtracted. A component missing from
  the subtraction and present in the walk is counted twice, so the walk no
  longer decomposes the total it reports.
-#}
{% macro fare_residual(alias='t') -%}
    (
        coalesce({{ alias }}.total_amount, 0)
        {%- for c in decomposed_columns() %}
        - coalesce({{ alias }}.{{ c }}, 0)
        {%- endfor %}
    )
{%- endmacro %}

{#-
  Both arguments are bracketed: callers pass expressions such as
  `sum(seconds) / 3600.0` or `a - b`, which would otherwise bind to the division.
-#}
{% macro safe_divide(numerator, denominator) -%}
    case when coalesce({{ denominator }}, 0) = 0 then null
         else ({{ numerator }}) / ({{ denominator }}) end
{%- endmacro %}
