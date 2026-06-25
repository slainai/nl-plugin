# Expression DSL Reference

Used in block-JSON configs to compute `date_expr`, entry `value` / `currency` fields, SelectBlock column expressions, and GroupByBlock aggregations.

---

## General shape

```json
{"type": "<operator_name>", "args": [...child_expressions...]}
```

Terminal nodes have no `args` (or use named fields). Operator nodes have `args` as a list of child expression dicts.

---

## Terminals

### col_ref — column reference

```json
{"type": "col_ref", "name": "column_name", "table": "parent"}
```

| Field | Values | Notes |
|---|---|---|
| `type` | `"col_ref"` | |
| `name` | string | Column name as it appears in `columns_alias_map` output |
| `table` | `"parent"` | Always `"parent"` in JournalBlock, identifiers, raw, and entry values. `"left"` / `"right"` only in JoinBlock. `"this"` only in SelectBlock for inter-column references. |

### literal — constant value

```json
{"type": "literal", "value": "Bank", "dtype": "string"}
```

| `dtype` | Python type of `value` |
|---|---|
| `"string"` | `str` |
| `"integer"` | `int` |
| `"float"` | `int` or `float` |
| `"boolean"` | `bool` |
| `"date"` | string in ISO format or `null` |
| `"timestamp"` | string or `null` |
| `"null"` | `null` / `None` |

### current_timestamp — current UTC time

```json
{"type": "current_timestamp"}
```

### today — today's date (midnight UTC)

```json
{"type": "today"}
```

---

## Binary operators (exactly 2 args)

| type | Semantics |
|---|---|
| `add` | `args[0] + args[1]` |
| `subtract` | `args[0] - args[1]` |
| `multiply` | `args[0] * args[1]` |
| `divide` | `args[0] / args[1]` |
| `modulo` | `args[0] % args[1]` |
| `power` | `args[0] ** args[1]` |
| `equals` | `args[0] == args[1]` |
| `not_equals` | `args[0] != args[1]` |
| `greater_than` | `args[0] > args[1]` |
| `greater_than_or_equal` | `args[0] >= args[1]` |
| `less_than` | `args[0] < args[1]` |
| `less_than_or_equal` | `args[0] <= args[1]` |
| `string_contains` | `args[1] in args[0]` |
| `string_starts_with` | `args[0].startswith(args[1])` |
| `string_ends_with` | `args[0].endswith(args[1])` |
| `logical_and` | `args[0] AND args[1]` |
| `logical_or` | `args[0] OR args[1]` |
| `logical_xor` | `args[0] XOR args[1]` |

---

## Unary operators (exactly 1 arg)

| type | Semantics |
|---|---|
| `not` | boolean NOT |
| `is_null` | `args[0] IS NULL` |
| `is_not_null` | `args[0] IS NOT NULL` |
| `negate` | arithmetic negation |
| `abs` | absolute value |
| `sqrt` | square root |
| `ceil` | ceiling |
| `floor` | floor |
| `round` | round to nearest integer |
| `sign` | sign (-1, 0, 1) |
| `upper` | uppercase string |
| `lower` | lowercase string |
| `trim` | strip both ends |
| `ltrim` | strip left |
| `rtrim` | strip right |
| `length` | string length |
| `reverse` | reverse string |
| `year` | extract year from date |
| `month` | extract month from date |
| `day` | extract day from date |
| `hour` | extract hour |
| `minute` | extract minute |
| `second` | extract second |
| `day_of_week` | day of week (0=Mon) |
| `day_of_year` | day of year |
| `is_numeric` | true if value is numeric |
| `is_string` | true if value is string |
| `is_date` | true if value is a date |
| `is_boolean` | true if value is boolean |

---

## N-ary operators (variable args)

| type | Semantics |
|---|---|
| `and` | `args[0] AND args[1] AND ...` |
| `or` | `args[0] OR args[1] OR ...` |
| `add_multiple` | sum of all args |
| `multiply_multiple` | product of all args |
| `concat` | string concatenation of all args |
| `coalesce` | first non-null arg |
| `greatest` | max value among args |
| `least` | min value among args |
| `union` | set union |
| `intersection` | set intersection |

---

## Special operators

### between

```json
{"type": "between", "args": [<value>, <lower>, <upper>]}
```

### in / not_in

```json
{"type": "in", "args": [<value>, <option1>, <option2>, ...]}
{"type": "not_in", "args": [<value>, <option1>, <option2>, ...]}
```

### cast

```json
{"type": "cast", "args": [<expression>, {"type": "literal", "value": "date", "dtype": "string"}]}
```

The second arg is a literal string naming the target dtype.

### substring

```json
{"type": "substring", "args": [<string_expr>, <start_int_literal>, <length_int_literal>]}
```

### replace

```json
{"type": "replace", "args": [<string_expr>, <pattern_literal>, <replacement_literal>]}
```

### case

```json
{
  "type": "case",
  "args": [
    [
      {"condition": <bool_expr>, "result": <value_expr>},
      {"condition": <bool_expr>, "result": <value_expr>}
    ],
    <else_expr>
  ]
}
```

`args[0]` is a list of `{condition, result}` dicts. `args[1]` is the else clause (optional).

### regex_match / regex_extract

```json
{"type": "regex_match", "args": [<string_expr>, <pattern_literal>]}
{"type": "regex_extract", "args": [<string_expr>, <pattern_literal>, <group_int_literal>]}
```

### date_add / date_diff

```json
{"type": "date_add",  "args": [<date_expr>, <n_literal>, <unit_literal>]}
{"type": "date_diff", "args": [<date_expr_a>, <date_expr_b>, <unit_literal>]}
```

Units: `"day"`, `"month"`, `"year"`, `"hour"`, `"minute"`, `"second"`.

---

## Aggregate operators (GroupByBlock aggregations only)

| type | Semantics |
|---|---|
| `sum` | sum of column |
| `avg` / `mean` | average |
| `max` | maximum |
| `min` | minimum |
| `count` | row count |
| `count_distinct` | distinct count |
| `first` | first value in group |
| `last` | last value in group |
| `stddev` | standard deviation |
| `median` | median |

---

## The 5 most common authoring patterns

### 1. Plain column reference

```json
{"type": "col_ref", "name": "amount", "table": "parent"}
```

### 2. Literal tag

```json
{"type": "literal", "value": "Bank", "dtype": "string"}
```

### 3. Concat (build composite identifier)

```json
{
  "type": "concat",
  "args": [
    {"type": "col_ref", "name": "narration", "table": "parent"},
    {"type": "literal", "value": " | ", "dtype": "string"},
    {"type": "col_ref", "name": "voucher_id", "table": "parent"}
  ]
}
```

### 4. Coalesce (fallback identifier)

Use when the primary identifier column may be null:

```json
{
  "type": "coalesce",
  "args": [
    {"type": "col_ref", "name": "utr", "table": "parent"},
    {"type": "col_ref", "name": "cheque_no", "table": "parent"},
    {"type": "col_ref", "name": "bank_ref", "table": "parent"}
  ]
}
```

### 5. Date from string column (cast)

When the date column was read as `dtype: "string"`, cast it:

```json
{
  "type": "cast",
  "args": [
    {"type": "col_ref", "name": "value_date", "table": "parent"},
    {"type": "literal", "value": "date", "dtype": "string"}
  ]
}
```

If the date format is non-standard, use `regex_extract` upstream in SelectBlock to normalize it first, then cast.

---

## Operator aliases (also accepted)

| Canonical | Aliases |
|---|---|
| `col_ref` | `column_ref` |
| `equals` | `eq` |
| `not_equals` | `ne` |
| `greater_than` | `gt` |
| `greater_than_or_equal` | `gte` |
| `less_than` | `lt` |
| `less_than_or_equal` | `lte` |
| `string_contains` | `contains` |
| `string_starts_with` | `starts_with` |
| `string_ends_with` | `ends_with` |
| `logical_xor` | `xor` |
| `negate` | `neg` |
| `length` | `len` |
| `day_of_week` | `dayofweek` |
| `day_of_year` | `dayofyear` |
| `add_multiple` | `sum_all` |
| `multiply_multiple` | `product_all` |
| `substring` | `substr` |
| `regex_match` | `regex` |
| `regex_extract` | `regex_ext` |
| `current_timestamp` | `now` |
| `avg` | `average`, `mean` |
| `max` | `maximum` |
| `min` | `minimum` |
| `count_distinct` | (no alias) |
| `first` | `first_value` |
| `last` | `last_value` |
