# Security notes

- The workflow has only `contents: write` permission because it must advance the
  `release` branch. It does not request packages, issues, pull requests, OIDC or
  other permissions.
- `actions/checkout` is the only reusable Action and is pinned to a full commit
  SHA. Conversion and validation use repository scripts plus standard tools on
  GitHub's `ubuntu-24.04` runner.
- Mihomo is downloaded from a versioned official GitHub release URL and checked
  against the SHA-256 published on that release before execution.
- The upstream rules are untrusted input. The workflow rejects NUL, unexpected
  size, non-canonical YAML shape, invalid scalars, duplicate rules and a rule
  count below each provider's independently reviewed threshold before invoking
  Mihomo.
- Publishing uses a temporary Git worktree and one normal fast-forward commit.
  It rechecks all three MRS files against their checksum files and metadata,
  publishes the nine-file set atomically, and never force-pushes. Failure before
  `git push` leaves the old branch ref and all old artifacts intact.
- Scheduled and manual jobs publish only when the workflow runs from the
  repository's default branch.

Maintainers should review and manually update `scripts/versions.env` when
changing Mihomo versions. Do not automate upgrades to `latest`.
