---
name: GitHub push workflow for this repo
description: How to publish local commits to SLatz18/rewrite-mac from Replit
---

`main` on github.com/SLatz18/rewrite-mac is protected: changes must go through a pull request and pass a required "test" status check — direct pushes to main are rejected (GH013).

**How to apply:** Push local work to a feature branch (`git push <auth-url> main:<branch>`) and open a PR via the GitHub connector's API proxy. Authenticate git with the connector token inside a `"use impure"` sandbox function (never log the token). Set repo-local git identity from `GET /user` before merge commits.

**Why:** A direct push was declined by repository rules; the PR route worked (e.g. PR #74).

Also: when merging remote GitHub work locally, the generated `project.pbxproj` conflicts whenever both sides added files — resolve with `--ours`, then register the remote's new Swift files via the python `pbxproj` package (see xcodeproj-file-registration.md).
