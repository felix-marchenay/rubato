#!/usr/bin/env bash
# Génère la clé de signature des APK release — UNE SEULE FOIS.
#
# Android n'installe une mise à jour que si elle est signée avec la même clé
# que l'appli déjà installée : perdre ou régénérer cette clé oblige à
# désinstaller Rubato (et ses données locales) sur chaque téléphone.
#
# Écrit android/app/rubato-release.jks et android/key.properties (git-ignorés).
# Lancé par `make keystore`, qui en garde aussi une copie hors du dépôt.
set -euo pipefail
cd "$(dirname "$0")/.."

STORE=android/app/rubato-release.jks
PROPS=android/key.properties

if [ -e "$STORE" ] || [ -e "$PROPS" ]; then
  echo "❌ Clé déjà présente ($STORE / $PROPS) : ne jamais la régénérer." >&2
  exit 1
fi

PASS="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)"

keytool -genkeypair -noprompt \
  -keystore "$STORE" -storetype PKCS12 \
  -alias rubato -keyalg RSA -keysize 4096 -validity 36500 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=Rubato"

cat > "$PROPS" <<EOF
storePassword=$PASS
keyPassword=$PASS
keyAlias=rubato
storeFile=rubato-release.jks
EOF
chmod 600 "$STORE" "$PROPS"
echo "✅ Clé créée : $STORE (+ $PROPS)"
