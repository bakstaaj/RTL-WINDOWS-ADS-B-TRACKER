# Development and Publication Workflow

## Consolidated feature-branch model

New application work is developed on an isolated branch created from synchronized `main`.

```text
main -> feature branch -> fast source checks -> one meaningful live validation
     -> commit validated source -> fast-forward main -> push
```

A hardware/API validation is not repeated solely because the validated commit is being published. A second live validation is appropriate only when code has changed after a failure or during a planned multi-feature regression checkpoint.

## Failure and rollback

Until validation succeeds and the feature commit is merged, `main` remains the last published known-good state. Failed feature work can be repaired in place or discarded:

```bash
git switch main
git branch -D feature/<feature-name>
```

Generated catalogs, runtime settings, logs, audio samples, caches and build artifacts remain excluded from publication.
