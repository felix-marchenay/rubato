# Environnement de dev Flutter (Android + Web) — 100% conteneurisé.
# Basé sur l'image cirruslabs (Flutter stable + SDK Android + JDK pré-installés).
FROM ghcr.io/cirruslabs/flutter:stable

# Utilisateur mappé sur l'hôte pour que les fichiers générés dans le volume
# monté appartiennent à toi, pas à root.
ARG UID=1001
ARG GID=1001

RUN set -eux; \
    (getent group "${GID}" >/dev/null || groupadd -g "${GID}" dev); \
    (getent passwd "${UID}" >/dev/null || useradd -m -u "${UID}" -g "${GID}" -s /bin/bash dev); \
    # Rendre les caches Flutter + Android SDK inscriptibles par cet utilisateur
    chown -R "${UID}:${GID}" "${FLUTTER_HOME:-/sdks/flutter}" 2>/dev/null || true; \
    chown -R "${UID}:${GID}" "${ANDROID_SDK_ROOT:-/opt/android-sdk-linux}" 2>/dev/null || true; \
    mkdir -p /home/dev/.pub-cache /home/dev/.gradle; \
    chown -R "${UID}:${GID}" /home/dev

ENV PUB_CACHE=/home/dev/.pub-cache
ENV GRADLE_USER_HOME=/home/dev/.gradle
# Évite les avertissements git "dubious ownership" sur le volume monté.
RUN git config --system --add safe.directory '*' || true

USER ${UID}:${GID}
WORKDIR /app
