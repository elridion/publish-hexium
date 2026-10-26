#!/usr/bin/env bash
# Publishes a Valheim mod to Hexium:
#
#   hexium.sh publish <package.zip> <hexium.json>   upload and submit a new version, then set the
#                                                   listing's categories and install location
#   hexium.sh metadata <hexium.json>                only set the categories and install location
#
# Env: HEXIUM_TOKEN (required), HEXIUM_AUTHOR (team namespace, default el_team), HEXIUM_API (API base URL).
#
# hexium.json belongs to the mod's repo:
#   { "name": "Warden", "categories": ["Building", "Valheim 1.0"], "install_location": "both" }
# name is the package name (manifest.json "name"). categories are names as shown on the site;
# "Client & Server" and friends are not categories to send, Hexium derives them from
# install_location (client, server, both or client_opt_server).
#
# The flow follows Hexium's OpenAPI spec (https://hexium.gg/api/openapi.json). publish: initiate a
# multipart upload, PUT each part to its presigned URL, finish the upload with the parts' ETags, then
# submit it for the Valheim community. Submitting applies neither the categories nor the install
# location (a new listing defaults to "Client-only"), so publish ends with the metadata call.

set -Eeuo pipefail

usage() { echo "usage: hexium.sh publish <package.zip> <hexium.json> | hexium.sh metadata <hexium.json>" >&2; exit 2; }

: "${HEXIUM_TOKEN:?HEXIUM_TOKEN is not set}"
author="${HEXIUM_AUTHOR:-el_team}"
api="${HEXIUM_API:-https://hexium.gg/api/experimental}"
api="${api%/}"
site="${api%/api/experimental}"

post() {
  curl -sS --fail-with-body -X POST "${3:-$api}$1" \
    -H "Authorization: Bearer $HEXIUM_TOKEN" \
    -H "Content-Type: application/json" \
    --data "$2"
}

# Fails before any request if the file is malformed.
read_meta() {
  jq -e '
    (.name | type == "string" and length > 0)
    and (.categories | type == "array" and length > 0 and all(type == "string"))
    and (.install_location | IN("client", "server", "both", "client_opt_server"))
  ' "$1" > /dev/null || { echo "::error::$1 needs a name, a non-empty categories array and a valid install_location"; exit 1; }
  name=$(jq -r '.name' "$1")
  categories=$(jq -c '.categories' "$1")
  install_location=$(jq -r '.install_location' "$1")
}

publish() {
  # work stays global: the EXIT trap that removes it runs after this function has returned.
  local zip="$1" size uuid hidden
  read_meta "$2"
  local manifest_name
  manifest_name=$(unzip -p "$zip" manifest.json | jq -r '.name')
  [ "$manifest_name" = "$name" ] || { echo "::error::$zip is package '$manifest_name' but $2 names '$name'"; exit 1; }

  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT

  size=$(stat -c %s "$zip")
  echo "Initiating upload of $(basename "$zip") ($size bytes)"
  post /usermedia/initiate-upload/ \
    "$(jq -n --arg f "$(basename "$zip")" --argjson s "$size" '{filename: $f, file_size_bytes: $s}')" \
    > "$work/initiate.json"
  uuid=$(jq -r '.user_media.uuid' "$work/initiate.json")

  # shellcheck disable=SC2317 # only called through the ERR trap
  abort() {
    echo "::error::Upload failed, aborting upload $uuid"
    post "/usermedia/$uuid/abort-upload/" "$(jq -n --arg u "$uuid" '{uuid: $u}')" > /dev/null || true
    exit 1
  }
  trap 'abort' ERR

  echo '[]' > "$work/parts.json"
  local part url offset length number etag
  while read -r part; do
    url=$(jq -r '.url' <<< "$part")
    offset=$(jq -r '.offset' <<< "$part")
    length=$(jq -r '.length' <<< "$part")
    number=$(jq -r '.part_number' <<< "$part")
    tail -c +"$((offset + 1))" "$zip" | head -c "$length" > "$work/part"
    etag=$(curl -sS --fail-with-body -X PUT "$url" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@$work/part" -D - -o /dev/null \
      | tr -d '\r' | sed -n 's/^[Ee][Tt][Aa][Gg]: *//p')
    [ -n "$etag" ] || { echo "::error::Part $number returned no ETag"; false; }
    jq --arg e "$etag" --argjson n "$number" '. + [{ETag: $e, PartNumber: $n}]' "$work/parts.json" > "$work/parts.tmp"
    mv "$work/parts.tmp" "$work/parts.json"
    echo "Uploaded part $number ($length bytes)"
  done < <(jq -c '.upload_urls[]' "$work/initiate.json")

  post "/usermedia/$uuid/finish-upload/" "$(jq '{parts: .}' "$work/parts.json")" > /dev/null
  trap - ERR
  echo "Finished upload $uuid"

  post /submission/submit/ "$(jq -n --arg a "$author" --arg u "$uuid" --argjson c "$categories" '{
    author_name: $a,
    communities: ["valheim"],
    community_categories: {valheim: $c},
    categories: [],
    has_nsfw_content: false,
    upload_uuid: $u
  }')" > "$work/submit.json"

  hidden=$(jq -r '.hidden // false' "$work/submit.json")
  echo "Submitted $author-$name to Hexium (hidden: $hidden)"
  if [ "$hidden" = "true" ]; then
    echo "::notice::Hexium accepted the package but reports it as hidden (it may still be scanning)."
  fi

  metadata "$2"
}

metadata() {
  local result
  read_meta "$1"
  result=$(post "/api/mod/$author/$name/set-metadata" \
    "$(jq -n --arg l "$install_location" --argjson c "$categories" '{install_location: $l, categories: $c}')" "$site")
  echo "Set $author-$name metadata: $(jq -c '{install_location, categories}' <<< "$result")"
}

case "${1:-}" in
  publish) [ $# -eq 3 ] || usage; publish "$2" "$3" ;;
  metadata) [ $# -eq 2 ] || usage; metadata "$2" ;;
  *) usage ;;
esac
