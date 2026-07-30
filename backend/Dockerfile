# Image de production du backend Rubato — c'est elle que Fly.io déploie
# (`make api-deploy`). En dev on ne s'en sert pas : le docker-compose monte la
# source dans `golang:1.24` et fait `go run`.
#
# Se builder/tester en local : `make api-image-run` → http://localhost:8091

# ── Étape 1 : compilation ────────────────────────────────────────────────────
FROM golang:1.24 AS build

WORKDIR /src
# Aucune dépendance externe (go.sum vide) : rien à télécharger, on copie tout
# d'un coup. Le corpus iReal de search/sources/data/ part avec, il est embarqué
# dans le binaire par go:embed.
COPY . .

# CGO désactivé → binaire statique, l'image finale n'a besoin d'aucune libc Go.
# -trimpath + -s -w : pas de chemins de build dans le binaire, et plus léger.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /rubato-backend .

# ── Étape 2 : exécution ──────────────────────────────────────────────────────
# Pas de `scratch` ni de distroless : les sources appellent le réseau via le
# binaire **curl** (cf. search/sources/fetch.go — le fingerprint TLS de la
# stdlib Go est bloqué par Cloudflare, celui de curl passe). L'image finale doit
# donc embarquer curl + les certificats racine.
#
# `trixie-slim` et pas `stable-slim` : c'est la base de golang:1.24, donc le même
# curl (8.14, OpenSSL 3.5) que celui qui passe en dev. Épinglé exprès — si le tag
# `stable` glissait vers la Debian suivante, le fingerprint TLS changerait sans
# qu'on s'en rende compte.
FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install --no-install-recommends -y curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Le backend n'écrit rien sur le disque (le corpus est dans le binaire) → il
# peut tourner sans privilèges.
RUN useradd --system --create-home --uid 10001 rubato
USER 10001:10001

COPY --from=build /rubato-backend /usr/local/bin/rubato-backend

# PORT : lu par le backend (cf. listenAddr dans main.go). Les hébergeurs
# l'injectent souvent eux-mêmes ; on garde 8080 comme valeur par défaut, comme
# dans le docker-compose.
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/rubato-backend"]
