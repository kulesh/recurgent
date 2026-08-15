# Spatiotemporal Composability — paper, patterns, Ruby

A working companion to Shi, Zhang & Cui, *A Programming Paradigm for
Spatiotemporal Composability* (Peking University / DeepSeek-AI). The paper's
revertible effects and reactive coeffects, distilled into language-agnostic
patterns and implemented as runnable, theorem-checked Ruby.

| File | What it is |
| --- | --- |
| `index.html` | The guide: intuition, 11 patterns, the reproduced paper (§1–§3.2.3), and the Ruby with click-through trace links into the paper. Generated — edit the template, not this. |
| `cordis.rb` | The library: `Effect`, `EffectContext`, `Independence`, `CoeffectContext`, `Coeffects`, `Coeffect`, `IsolatedContext`, `Component`, `System`. Pure stdlib; every construct cites the definition it implements. |
| `theorem_checks.rb` | 25 executable checks: the paper's theorems on concrete contexts, plus runtime failure-discipline regressions. |
| `demo_hot_swap.rb` | Reactive hot module replacement: mount, cascade-activate, hot-swap a provider, tear down to exactly the initial context. |
| `build.rb` | Regenerates `index.html` from `guide.template.html` + `paper/*.html` + the sources + fresh runs; verifies every internal link resolves. |
| `guide.template.html` | The page's hand-authored shell (design, patterns, prose, markers). |
| `paper/*.html` | The reproduced paper excerpt as HTML fragments with stable anchors (`#d8`, `#t16`, `#eq24`, …). |

```bash
ruby theorem_checks.rb   # all 25 checks
ruby demo_hot_swap.rb    # the hot-swap trace
ruby build.rb            # regenerate index.html
```

No gems, no API keys — plain `ruby` ≥ 3.0.
