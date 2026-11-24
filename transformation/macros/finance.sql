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
  What the total does not explain. A non-zero residual means either a component
  we do not model, or a total that was not derived from its parts.

  This subtraction and the revenue walk's unpivot are one component list. A
  component the walk publishes on its own line and this macro leaves out is
  counted twice, and the walk sums to more than the total; the airport fee did
  exactly that. Register a new component here, not only in the walk.
-#}
{% macro fare_residual(alias='t') -%}
    (
        coalesce({{ alias }}.total_amount, 0)
        - coalesce({{ alias }}.fare_amount, 0)
        - coalesce({{ alias }}.tip_amount, 0)
        - coalesce({{ alias }}.tolls_amount, 0)
        - coalesce({{ alias }}.airport_fee, 0)
        - {{ total_surcharges(alias) }}
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
