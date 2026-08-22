# Spatiotemporal Composability — paper, patterns, Ruby

A working companion to Shi, Zhang & Cui, *A Programming Paradigm for
Spatiotemporal Composability* (Peking University / DeepSeek-AI) — the full
88-page paper: revertible effects and reactive coeffects (§3), the context
paradigm (§3.3), the fiber calculus and its metatheory (§4), and the
declarative loader (§5), distilled into language-agnostic patterns and
implemented as runnable, property-checked Ruby.

| File | What it is |
| --- | --- |
| `index.html` | The guide: intuition, 19 patterns, the reproduced paper (§1–§8), and the Ruby with click-through trace links into the paper. Generated — edit the template, not this. |
| `cordis.rb` | §3 as a library: `Effect`, `EffectContext`, `Independence`, `CoeffectContext`, `Coeffects`, `Coeffect`, `InterceptedContext`, `IsolatedContext`, `Component`, `System`. Pure stdlib; every construct cites the definition it implements. |
| `cordis_calculus.rb` | §4 as an executable operational semantics: fibers, the derived context, target vs committed views, and the ten rules driven by a seeded nondeterministic scheduler. |
| `cordis_loader.rb` | §5.2: declarative entries, reconciliation, and the pure HMR phases (Algorithms 8–9). |
| `theorem_checks.rb` | 28 checks: §3's theorems on concrete contexts, plus runtime failure-discipline regressions. |
| `calculus_checks.rb` | 14 checks: §4's metatheory (preservation, ordering, progress, recovery, confluence) and §5.2's loader guarantees, over randomized schedules. |
| `demo_hot_swap.rb` | Reactive hot module replacement on the §3 runtime. |
| `demo_reconcile.rb` | Declarative reconciliation on the §4 calculus (Theorem 73's licence, demonstrated). |
| `build.rb` | Regenerates `index.html` from `guide.template.html` + `paper/*.html` + the sources + fresh runs; verifies every internal link resolves. |
| `guide.template.html` | The page's hand-authored shell (design, patterns, prose, markers). |
| `paper/*.html` | The reproduced paper as HTML fragments with stable anchors (`#d8`, `#t73`, `#rule-l-unload`, `#alg8`, …). |

```bash
ruby theorem_checks.rb   # §3: 28 checks
ruby calculus_checks.rb  # §4/§5: 14 checks over randomized schedules
ruby demo_hot_swap.rb    # the hot-swap trace
ruby demo_reconcile.rb   # the reconciliation trace
ruby build.rb            # regenerate index.html
```

No gems, no API keys — plain `ruby` ≥ 3.0.
