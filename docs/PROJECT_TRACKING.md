# Project tracking - one-time GitHub setup

1. **Repo** `Dane64/arc-dgpu-ctl`, push `main`.
2. **Labels**: *Actions → Sync labels → Run workflow* once; afterwards it runs
   when `.github/labels.yml` changes.
3. **Project board**: *Profile → Projects → New → Board* `arc-dgpu-ctl`.
   Status: `Triage → Backlog → In progress → In review → Done`.
   Fields: `Priority` (P0-P2), `Family` (mobile/desktop), `Target release`.
   Built-in workflows: item added → Triage, item closed / PR merged → Done.
4. **Auto-add to board** (`.github/workflows/project.yml`):
   - Variable `PROJECT_URL` = `https://github.com/users/Dane64/projects/<n>`
   - Secret `PROJECT_TOKEN` = classic PAT with `project` scope (user-owned projects)
5. **Milestones**: one per release (`v3.6.0`, ...).
6. **Branch protection** on `main`: PR required, checks `lint`, `test`, `deb`
   required, no force-push.
7. **Security**: enable private vulnerability reporting and Dependabot alerts.

Triage: issue forms add `needs-triage` → set type + `mobile`/`desktop` label +
milestone → `needs-info` while `diag` output is missing.
