"""Utilitaires partagés du proxy d'agrégation Rubato."""
import re
import unicodedata

# LRCLIB exige un User-Agent identifiant l'app ; The Session (derrière un
# pare-feu anti-bot) préfère un UA navigateur — on l'applique par requête.
USER_AGENT = "Rubato/0.1 (carnet d'accords personnel)"
BROWSER_UA = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/125.0 Safari/537.36"
)


def slugify(text: str) -> str:
    """kebab-case ASCII, aligné sur la convention d'id des scripts Python."""
    text = unicodedata.normalize("NFKD", text or "").encode("ascii", "ignore").decode()
    text = text.strip().lower()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_-]+", "-", text).strip("-")
    return text or "untitled"
