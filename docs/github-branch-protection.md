# GitHub branch protection

Maintainer runbook for the repository's branch rules. Contributor instructions belong in [`CONTRIBUTING.md`](../CONTRIBUTING.md).

## Intended policy

- Protect only `main` and `develop`.
- Require pull requests and passing CI checks before merging into either branch.
- Require an approval from `@pepesan` on those pull requests. Use a `CODEOWNERS` rule for the paths covered by that approval.
- Do not require approval for feature, fix, release, or hotfix branches.
- Treat administrator bypass as an explicit exception, not the usual merge path.

A pull-request author cannot approve their own pull request. If `@pepesan` creates a PR targeting `main` or `develop`, another account with repository write access must create the PR for `@pepesan` to review it; otherwise the owner approval cannot be satisfied. An administrator bypass is an exception to this policy, not an approval.

## Configure the repository

1. Add `.github/CODEOWNERS` on the base branches. To require `@pepesan` for all changes, use:

   ```text
   * @pepesan
   ```

2. In **Settings → Rules → Rulesets**, scope the ruleset to `main` and `develop` only.
3. Require a pull request before merging, at least one approving review, and approval from a code owner. Require the CI checks used by `.github/workflows/ci.yml` to pass.
4. Do not apply this ruleset to other branch names. Keep any administrator bypass narrowly scoped and use it only by explicit decision.
5. Test the policy with one PR to `develop` and one to `main`: the owner approval and CI checks should be required, while a non-protected feature branch should remain pushable.

Make sure `.github/CODEOWNERS` is present on each protected branch before requiring code-owner review there. GitHub evaluates code owners from the PR's base branch.

## Current repository setting

Last checked on 2026-11-04, the active ruleset was named `Owner-only updates to main and develop`. It matched `main` and `develop`, but its only rule was `update`; it did not require a pull request review or approval. The repository administrator had an always-available bypass. This update-only rule blocked normal PR merges with `Cannot update this protected ref` even when CI checks passed.

Replace that update-only rule with the intended pull-request and review requirements above. Until the ruleset is updated, the settings and the intended policy in this document do not match.
