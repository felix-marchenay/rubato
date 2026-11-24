#!/usr/bin/env bash
# Publie l'APK release comme mise à jour de l'appli Android.
#
# Une seule release GitHub, « android-latest », dont on remplace les fichiers :
#   - rubato-<version>-<build>.apk
#   - latest.json : {version, build, url, sha256, notes, publishedAt}
# L'appli lit latest.json au lancement et propose la mise à jour si son build
# est plus ancien (lib/src/data/app_update_service.dart).
#
# Usage : scripts/publish-release.sh <build> [notes]   (via `make release`)
# Tourne sur l'hôte : `gh` n'est pas dans le conteneur Flutter.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD="${1:?numéro de build attendu}"
NOTES="${2:-}"
TAG=android-latest
APK=build/app/outputs/flutter-apk/app-release.apk

if [ ! -f android/key.properties ]; then
  echo "❌ Pas de clé de signature stable : lance d'abord  make keystore" >&2
  exit 1
fi
if [ ! -f "$APK" ]; then
  echo "❌ APK introuvable : $APK" >&2
  exit 1
fi

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
VERSION="$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)"
NAME="rubato-${VERSION}-${BUILD}.apk"
[ -n "$NOTES" ] || NOTES="$(git log -1 --pretty=%s)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$APK" "$TMP/$NAME"

OUT="$TMP/latest.json" VERSION="$VERSION" BUILD="$BUILD" NOTES="$NOTES" \
URL="https://github.com/${REPO}/releases/download/${TAG}/${NAME}" \
SHA="$(sha256sum "$TMP/$NAME" | cut -d' ' -f1)" \
python3 - <<'PY'
import datetime, json, os
e = os.environ
with open(e["OUT"], "w", encoding="utf-8") as f:
    json.dump({
        "version": e["VERSION"],
        "build": int(e["BUILD"]),
        "url": e["URL"],
        "sha256": e["SHA"],
        "notes": e["NOTES"],
        "publishedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    }, f, ensure_ascii=False, indent=2)
PY

if ! gh release view "$TAG" >/dev/null 2>&1; then
  gh release create "$TAG" --title "Rubato Android" --notes \
"Dernière version de l'appli Android. L'appli la propose d'elle-même au lancement ; \
sinon, télécharger l'APK ci-dessous."
fi

# L'APK d'abord, latest.json ensuite : un téléphone ne doit jamais lire un
# latest.json qui pointe vers un fichier pas encore en ligne.
gh release upload "$TAG" "$TMP/$NAME" --clobber
gh release upload "$TAG" "$TMP/latest.json" --clobber

# Ménage : on ne garde que l'APK courant.
OLD="$(gh release view "$TAG" --json assets -q '.assets[].name' \
  | grep '^rubato-.*\.apk$' | grep -vxF "$NAME" || true)"
for old in $OLD; do
  gh release delete-asset "$TAG" "$old" -y
done

echo "✅ Mise à jour publiée : ${VERSION} (build ${BUILD}) — https://github.com/${REPO}/releases/tag/${TAG}"
