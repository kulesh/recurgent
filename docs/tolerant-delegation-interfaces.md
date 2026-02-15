# Tolerant Delegation Interfaces

Recurgent uses one runtime path for dynamic calls: tolerant `Outcome` envelopes.

## Runtime Contract

Every dynamic method call returns `Agent::Outcome`.

```ruby
{
  status: :ok | :error,
  value: Object,                # present when status == :ok
  error_type: String,           # provider | invalid_code | execution | timeout | budget_exceeded
  error_message: String,        # present when status == :error
  retriable: true | false,
  tool_role: String,
  method_name: String
}
```

## Design Intent

- Keep Tool Builder flows alive across Tool failures.
- Make typed failures explicit without collapsing the full solve loop.
- Preserve LLM-native reasoning continuity via one predictable return shape.
- Keep delegation semantics coherent by preferring `delegate(...)` inside Tool Builder flows.

## Reference Behavior

1. Tool success:
- `outcome.ok? == true`
- `outcome.value` carries domain result.

2. Provider returns nil/blank code:
- `outcome.error? == true`
- `outcome.error_type == "invalid_code"`

3. Generated code raises:
- `outcome.error? == true`
- `outcome.error_type == "execution"`

4. Delegation budget exhausted:
- `outcome.error? == true`
- `outcome.error_type == "budget_exceeded"`
- Tool Builder continues synthesis with partial outcomes.
