# FEDCON Org Config

Reusable GitHub Actions workflows and org-level configuration for the FEDCON GitHub organization.

## Reusable Workflows

### `notify-linear.yml`

Posts project updates to Linear when code is pushed or deployed. Maps each repo to its Linear project automatically.

**Features:**
- Commit updates on push to main
- Deploy status (success/failure) with project health tracking
- `[linear]` prefix in commit messages creates enriched project notes
- Repo-to-project mapping maintained centrally in this repo

**Usage — push notifications (add to any repo):**

Create `.github/workflows/notify-linear.yml`:
```yaml
name: Notify Linear
on:
  push:
    branches: [main]
jobs:
  notify:
    uses: FEDCON/.github/.github/workflows/notify-linear.yml@main
    secrets:
      LINEAR_API: ${{ secrets.LINEAR_API }}
```

**Usage — deploy notifications (add to existing deploy.yml):**

```yaml
  notify-linear:
    needs: deploy
    if: always()
    uses: FEDCON/.github/.github/workflows/notify-linear.yml@main
    with:
      trigger_type: deploy
      deploy_status: ${{ needs.deploy.result }}
    secrets:
      LINEAR_API: ${{ secrets.LINEAR_API }}
```

**Usage — enriched project notes:**

Prefix a commit message with `[linear]` to post an enriched update:
```
git commit -m "[linear] Switched from polling to Pub/Sub — reduces latency from 2min to <5s"
```

## Repo-to-Project Mapping

The mapping is maintained in `.github/workflows/notify-linear.yml`. Edit it when repos are added or reassigned to different projects.

## Secrets

| Secret | Scope | Purpose |
|--------|-------|---------|
| `LINEAR_API` | Per-repo (GitHub Free plan limitation) | Linear API authentication |

**Note:** GitHub Free orgs can't share org secrets with private repos. Set `LINEAR_API` on each repo:
```bash
gh secret set LINEAR_API --repo FEDCON/<repo-name>
```
