#!/usr/bin/env bash
# Envoie l'APK release de Rubato sur une conversation Telegram via l'API Bot.
#
# Prérequis : un bot Telegram (créé avec @BotFather) et l'id de la conversation
# cible. Renseigne-les dans un fichier .env à la racine (voir .env.example) :
#
#   TELEGRAM_BOT_TOKEN=123456789:AA...            # token donné par @BotFather
#   TELEGRAM_CHAT_ID=123456789                     # id de ta conversation
#
# Astuce pour trouver ton chat_id : écris un message à ton bot, puis ouvre
#   https://api.telegram.org/bot<TOKEN>/getUpdates
# et lis le champ "chat":{"id": ...}.
#
# Ce script tourne dans le conteneur (make telegram / make apk-telegram) mais
# fonctionne aussi tel quel sur l'hôte si curl est présent.
set -euo pipefail

# Se placer à la racine du repo (le script vit dans scripts/).
cd "$(dirname "$0")/.."

# Charger .env s'il existe, sans écraser une variable déjà définie dans l'env.
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

: "${TELEGRAM_BOT_TOKEN:?Manque TELEGRAM_BOT_TOKEN — copie .env.example vers .env et remplis-le}"
: "${TELEGRAM_CHAT_ID:?Manque TELEGRAM_CHAT_ID — copie .env.example vers .env et remplis-le}"

APK="${APK_PATH:-build/app/outputs/flutter-apk/app-release.apk}"
if [ ! -f "$APK" ]; then
  echo "❌ APK introuvable : $APK" >&2
  echo "   Compile-le d'abord :  make apk   (ou lance  make apk-telegram)" >&2
  exit 1
fi

# Nom de fichier lisible côté Telegram : rubato-<version>-<horodatage>.apk
VERSION="$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)"
VERSION="${VERSION:-dev}"
STAMP="$(date +%Y%m%d-%H%M)"
FILENAME="rubato-${VERSION}-${STAMP}.apk"
SIZE="$(du -h "$APK" | cut -f1)"

echo "→ Envoi de $APK ($SIZE) vers Telegram sous le nom $FILENAME…"

RESP=/tmp/rubato_tg_resp.json
HTTP="$(curl -sS -o "$RESP" -w '%{http_code}' \
  -F "chat_id=${TELEGRAM_CHAT_ID}" \
  -F "document=@${APK};filename=${FILENAME};type=application/vnd.android.package-archive" \
  -F "caption=📦 Rubato ${VERSION} — build ${STAMP}" \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument")"

if [ "$HTTP" = "200" ]; then
  echo "✅ APK envoyé sur Telegram — récupère-le depuis ton téléphone."
else
  echo "❌ Échec de l'envoi Telegram (HTTP $HTTP) :" >&2
  cat "$RESP" >&2 2>/dev/null || true
  echo >&2
  exit 1
fi
