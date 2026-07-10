# Migrating an existing hand-rolled sync implementation

This is for the case the [main guide](GUIDE.md) doesn't fully cover:
you already have a working sync repository (one class, several
hand-written loops, a single-flight guard) and want to move it onto this
kit **without a big-bang rewrite**.

If you're starting a feature from scratch instead, see the
[fresh project walkthrough](FRESH_PROJECT_WALKTHROUGH.md) — it's simpler
and this doc doesn't apply.

---

## Migration order: one domain at a time

Don't swap everything at once.

1. **Pick the lowest-risk domain first** — usually whichever one has the
   least extra business policy layered on top of "transient/permanent"
   (see step 3 of the main guide for what counts as policy vs. mechanics).
2. Write its `OfflineQueueStore` + classifier, wired through
   `SyncOrchestrator` in parallel with the existing code path — either
   behind a feature flag, or just call both and log if results disagree.
3. Once you trust it, delete that domain's block from the old repository
   class and route your presentation layer (cubit/bloc/provider) to the
   new pass.
4. Repeat for the next domain. Save the one with the most embedded policy
   (special-case deletion rules, skip-rest-of-batch-on-failure, etc.) for
   last, and give it the most test coverage before cutting over — it's
   the one most likely to have a subtle behavior difference.
5. Once everything is migrated, the old repository class can be deleted
   entirely, or reduced to a thin facade that just calls
   `orchestrator.syncAll(...)` for callers that haven't been updated yet.

---

## Quick reference: mapping old code to new

This is the actual mapping used the first time this kit was extracted
from an existing app — useful as a template for describing your own
migration, not literal for every project:

| Old (hand-rolled repository) | New |
|---|---|
| `_syncOfflineCheckinOutInternal()` | `SyncPass<CheckInOutAction, String>` + `CheckInOutQueueStore` |
| `_syncOfflineTaskActivitiesInternal()` | `SyncPass<OfflineTaskActivity, int>` + `TaskActivityQueueStore` |
| `_syncOfflineActivityReportsInternal()` | `SyncPass<OfflineFormActivityState, String>` + `ActivityReportQueueStore` |
| `_inFlightSync` guard | `SyncOrchestrator.syncAll(...)` (built in) |
| Inline flash-message building | Stays in the presentation layer, now consumes `Map<String, SyncPassResult>` |

Fill in your own left column with your repository's actual method names
before treating this as a checklist.

---

## Why incremental, not big-bang

The main risk in this kind of migration isn't the engine — `SyncPass` is
a straight port of the loop shape every hand-rolled version already has.
The risk is silently changing behavior in the classifier or the adapter
(e.g. a subtly different sort order, or a policy rule that got dropped
in translation). Running old and new in parallel for one domain at a
time, before deleting the old code, is what catches that class of bug
before it reaches production instead of after.
