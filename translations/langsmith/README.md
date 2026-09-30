# `trustabl.tool_loop` → LangSmith

See [`saved-filter.md`](saved-filter.md) for the actual filter and its
caveats — this file is the short pointer, kept for consistency with the
other translation-pack directories.

**Status: the most speculative pack in this set.** The source memo gives
LangSmith only "saved filter plus optional Insights input" (§5.6) — no
concrete filter syntax, and LangSmith's filter grammar has no native
"count-same-value ≥ N in a window" primitive to fully express
`rules/tool_loop.yaml`'s condition in one filter. `saved-filter.md`
documents a starting filter to narrow down candidate runs, not a complete
automated translation, consistent with memo §6.4's explicit constraint:
*"we do not replace Engine."*
