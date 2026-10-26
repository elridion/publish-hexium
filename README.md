# publish-hexium

GitHub Action that publishes a Thunderstore-format Valheim mod package to
[Hexium](https://valheim.hexium.gg/): it uploads the zip, submits it as a new version, then sets the
listing's categories and install location from the mod's `hexium.json` (Hexium's submit applies
neither).

Shared by the el_team mods ([Warden](https://github.com/elridion/warden),
[Heraldry](https://github.com/elridion/heraldry), [Spearbreaker](https://github.com/elridion/spearbreaker)).
The script lives here once; each mod keeps only its listing metadata.

## The mod's hexium.json

```json
{
  "name": "Warden",
  "categories": ["Building", "Pieces", "Valheim 1.0", "Open Source"],
  "install_location": "both"
}
```

- `name`: the package name, as in the zip's `manifest.json`. Publishing fails if they differ.
- `categories`: category names as shown on the site
  (list: `https://hexium.gg/api/experimental/community/valheim/category/`). "Client-only",
  "Client & Server" and similar are not sent as categories; Hexium derives them from the install location.
- `install_location`: `client`, `server`, `both` or `client_opt_server`.

## Release job

After the job that builds the package, on version tags:

```yaml
hexium:
  if: startsWith(github.ref, 'refs/tags/v')
  needs: build
  runs-on: ubuntu-latest
  environment: hexium # add required reviewers to approve each publish by hand
  steps:
    - uses: actions/checkout@v7
    - uses: actions/download-artifact@v8
      with:
        name: mymod-package
        path: dist
    - uses: elridion/publish-hexium@v1
      with:
        token: ${{ secrets.HEXIUM_TOKEN }}
        package: dist/*.zip
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `token` | (required) | Hexium team API token, from a secret |
| `package` | (required) | Path or glob of the zip; must match exactly one file |
| `metadata` | `hexium.json` | The mod's metadata file |
| `author` | `el_team` | Hexium team namespace |
| `api` | `https://hexium.gg/api/experimental` | API base URL |

The zip needs `manifest.json` (with `name`, `version_number`, `description`, `website_url`,
`dependencies`), `README.md` and `icon.png` at its root.

An accepted submission can stay hidden while Hexium scans it; the job log prints the `hidden` flag.
Hexium's API has no license field: set the listing's license in the web UI.

The action runs `hexium.sh`, which also works outside Actions:
`HEXIUM_TOKEN=... hexium.sh publish <zip> <hexium.json>`, or `hexium.sh metadata <hexium.json>` to
only reapply the categories and install location.

## Releasing this action

Callers use the moving `v1` tag. After a change on `main`, tag the exact version and move `v1`:

```
git tag v1.0.1
git tag -f v1
git push origin v1.0.1
git push -f origin v1
```

Background and API notes: [docs/hexium-api.md](docs/hexium-api.md).

## License

MIT, see [LICENSE](LICENSE).
