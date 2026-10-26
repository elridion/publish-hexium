# Research: publishing releases to Hexium from CI

Status: implemented as this repo's action (`action.yml`, `hexium.sh`), team `el_team`,
called from the `hexium` job of each mod's `.github/workflows/build.yml`. Researched 2026-10-18 for
Warden, which first carried its own copy of the script; moved here 2026-10-26 when the mods' copies
had drifted apart. Hexium's API has no license field: a listing's license is set in the web UI only.

[Hexium](https://hexium.gg/) is a community-run mod platform with a Valheim section
([valheim.hexium.gg](https://valheim.hexium.gg/)). Mod managers such as Gale and Vortex can install
from it. This note collects how a tagged release could be uploaded automatically from
`.github/workflows/build.yml`, next to the GitHub release.

## Findings

### API token

From the [Hexium FAQ](https://hexium.gg/faq): sign in, open the team settings through the settings
icon next to the username, and create an API token at the bottom of the team management page. A
team is required; it becomes the package namespace. Anyone holding the token can act as the
account, so it may only live in a GitHub Actions secret.

### Upload API

Update 2026-10-21: Hexium publishes an OpenAPI spec at https://hexium.gg/api/openapi.json (rendered
at https://hexium.gg/api/docs/). It confirms the flow below and adds
`POST /api/mod/{namespace}/{name}/set-metadata` with `install_location` (`client`, `server`,
`both`, `client_opt_server`) and `categories`. The 0.3.0 submit did not apply the categories it was sent, and a
new listing defaults to install location `client` ("Client-only"), so the script calls
`set-metadata` after submitting. "Client-only", "Client & Server" and similar are derived from the
install location, not sent as categories.

Originally there was no official API documentation. The flow below is taken from the source of the community
action [Klastic/publish-to-hexium](https://github.com/Klastic/publish-to-hexium)
([`src/hexium.ts`](https://raw.githubusercontent.com/Klastic/publish-to-hexium/main/src/hexium.ts)).
It is the same flow as Thunderstore's experimental API.

Base URL: `https://hexium.gg/api/experimental`. Every call except the part uploads sends
`Authorization: Bearer <token>` and `Content-Type: application/json`.

| Step | Request | Body | Response |
| --- | --- | --- | --- |
| 1. Initiate | `POST /usermedia/initiate-upload/` | `filename`, `file_size_bytes` | `user_media.uuid`, `upload_urls[]` with `url`, `offset`, `length`, `part_number` |
| 2. Upload parts | `PUT <part url>` per entry, `Content-Type: application/octet-stream`, no auth header | Bytes `offset` to `offset + length` of the zip | `ETag` header |
| 3. Finish | `POST /usermedia/<uuid>/finish-upload/` | `parts: [{ "ETag", "PartNumber" }]` | |
| 3b. Abort (on failure) | `POST /usermedia/<uuid>/abort-upload/` | `uuid` | |
| 4. Submit | `POST /submission/submit/` | `author_name`, `communities: ["valheim"]`, `community_categories: { "valheim": [...] }`, `categories: []`, `has_nsfw_content`, `upload_uuid` | `hidden` |

Steps 1 to 3 only upload a file; step 4 is the publish. An accepted submission can still be
`hidden` while Hexium scans it, so success does not mean the version is publicly visible yet.

### Package format

The zip needs `manifest.json`, `README.md` (from `package/README.md`) and `icon.png` at its root, and the manifest needs
`name`, `version_number` (semver), `description`, `website_url` and `dependencies`. The zip that
`dotnet build -c Release -t:Package` already writes for Thunderstore meets this.

### Categories

The action's example sends category names as shown on the site, not slugs, e.g.
`"valheim": ["Client & Server", "Mods", "Open Source", "Valheim 1.0"]`. Candidates for Warden from
the site's tag list: `Client & Server` (every peer needs the mod), `Building`, `Pieces`,
`Valheim 1.0`, and `Open Source` while the GitHub repo is public.

### The community action

`Klastic/publish-to-hexium` wraps the whole flow (inputs `token`, `package`, `author-name`,
`community-categories`; output `hidden`). At the time of writing it had 0 stars, 6 commits and no
published releases, so the `@v1` tag its README refers to may not exist. Handing it the team token
means trusting unreviewed third-party code with publish rights.

## Proposal

- Do not use the community action. Add a short `curl`/`jq` step (about 40 lines) to the `release`
  job of `.github/workflows/build.yml` that performs the four calls itself, running only on `v*`
  tags after the GitHub release is created.
- Store the token as the secret `HEXIUM_TOKEN` in a protected GitHub environment (e.g.
  `hexium`) with required reviewers, so every publish needs a manual approval.
- Print the `hidden` flag from the submit response in the job log.

## Open questions

- Final category list. The script defaults to `Client & Server`, `Building`, `Pieces`,
  `Valheim 1.0` and `Open Source`; the last one assumes the GitHub repo is public when releasing.
- Whether publishing should require approval through a protected environment (recommended).
- Whether Jotunn is listed on Hexium as `ValheimModding-Jotunn`, so the manifest dependency
  `ValheimModding-Jotunn-2.30.2` resolves there.
- The API lives under `/api/experimental` and is undocumented; expect the first real publish to
  need a fix and watch that run.

## Manual steps for the user

- Create the team (if needed) and the API token on Hexium.
- Add the token to the GitHub repo as the `HEXIUM_TOKEN` secret (and the environment, if used).

## Sources

- [Hexium](https://hexium.gg/)
- [Hexium FAQ](https://hexium.gg/faq)
- [Hexium Valheim mods](https://valheim.hexium.gg/)
- [Klastic/publish-to-hexium](https://github.com/Klastic/publish-to-hexium)
- [Klastic/publish-to-hexium `action.yml`](https://raw.githubusercontent.com/Klastic/publish-to-hexium/main/action.yml)
- [Klastic/publish-to-hexium `src/hexium.ts`](https://raw.githubusercontent.com/Klastic/publish-to-hexium/main/src/hexium.ts)
