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
  specialist_role: String,
  method_name: String
}
```

## Design Intent

- Keep Solver flows alive across Specialist failures.
- Make typed failures explicit without collapsing the full solve loop.
- Preserve LLM-native reasoning continuity via one predictable return shape.
- Keep delegation semantics coherent by preferring `delegate(...)` inside Solver flows.

## Reference Behavior

1. Specialist success:
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
- Solver continues synthesis with partial outcomes.
