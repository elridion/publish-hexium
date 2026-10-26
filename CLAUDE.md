# publish-hexium

Composite GitHub Action shared by the el_team Valheim mods (`../warden`, `../heraldry`,
`../spearbreaker`, `../cask`): uploads a version, submits it, then sets the listing's categories and
install location. Each mod keeps only a `hexium.json`; its `build.yml` `hexium` job runs the action
as one step on `v*` tags.

## Layout

| Path | Purpose |
| --- | --- |
| `action.yml` | `elridion/publish-hexium@v1`: resolves the package glob, runs `hexium.sh publish` |
| `hexium.sh` | Validates `hexium.json`; `publish` = initiate, part upload, finish, submit, set-metadata; `metadata` = set-metadata only (manual use) |
| `docs/hexium-api.md` | Hexium API research and the decisions behind the flow |
| `.github/workflows/check.yml` | ShellCheck and an offline test of the argument and metadata validation |

## Rules

- The repo must stay public, or the mods' workflows cannot use the action.
- Callers pin `@v1`. A compatible change is released by tagging `vX.Y.Z` and moving `v1` to it
  (see `README.md`); a breaking change to inputs or the `hexium.json` format needs `v2` and an
  update in every mod. Tagging and pushing tags only happens when the user asks. Moving a tag is a
  force push, which Claude Code's auto mode blocks; the user runs that push.
- The token is a team API token with publish rights. Never echo it, and keep it out of URLs.
- Nothing here can be tested locally without bash; `check.yml` runs on push. The real upload is
  only exercised by a mod's release, so say so when a change touches the API calls.
- Commits: plain imperative, sentence-case subject, no type prefix; work directly on `main`.
