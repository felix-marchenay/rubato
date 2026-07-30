package sources

import (
	"bytes"
	"fmt"
	"log"
	"os/exec"
	"strings"
	"time"
)

// Récupération HTTP commune à toutes les sources.
//
// Les appels passent par le binaire **`curl`**, pas par `net/http` : Cloudflare
// (e-chords, Ultimate Guitar) bloque sur le **fingerprint TLS** (JA3/JA4) du
// ClientHello de la stdlib Go — reconnu comme bot, HTTP 403 « Just a moment… »,
// même en HTTP/2 et avec des en-têtes de navigateur — alors que celui de curl
// (OpenSSL) passe. Le conteneur backend utilise donc l'image `golang:1.24`
// (Debian, embarque curl) et non `-alpine`. Toujours zéro dépendance Go.

// browserUA : User-Agent cohérent avec le fingerprint TLS de curl.
const browserUA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " +
	"(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

// fetchTimeout : délai max d'un appel, passé à curl via --max-time (secondes).
// Une source lente ne doit pas retenir toute la recherche.
const fetchTimeout = "15"

// curlGet récupère une URL et renvoie le corps de la réponse. Les en-têtes
// supplémentaires sont donnés au format « Nom: valeur ». Chaque appel est logué
// (URL, puis statut + durée) pour rester visible dans les logs du conteneur —
// c'est tout l'intérêt de `make api-search`.
//
// `-w "\n%{http_code}"` ajoute le code HTTP en fin de sortie standard, après
// tout le corps → on le récupère après le dernier saut de ligne
// (splitCurlOutput). Sans --fail, curl sort avec un code 0 même sur un 4xx (il a
// bien reçu une réponse) : l'erreur de transport reste ainsi distincte du statut.
func curlGet(u string, headers ...string) ([]byte, error) {
	start := time.Now()
	log.Printf("→ API GET %s", u)

	args := []string{
		"--silent", "--show-error",
		"--location",   // les tabs UG sont servis via redirections
		"--compressed", // pages HTML volumineuses
		"--max-time", fetchTimeout,
		"-A", browserUA,
		"-H", "Accept-Language: en,fr;q=0.8",
	}
	for _, h := range headers {
		args = append(args, "-H", h)
	}
	args = append(args, "-w", "\n%{http_code}", u)

	out, err := exec.Command("curl", args...).Output()
	if err != nil {
		stderr := ""
		if ee, ok := err.(*exec.ExitError); ok {
			stderr = strings.TrimSpace(string(ee.Stderr))
		}
		log.Printf("← API GET %s : échec curl après %s : %v", u, time.Since(start), err)
		return nil, fmt.Errorf("curl : %v (%s)", err, stderr)
	}

	body, code := splitCurlOutput(out)
	log.Printf("← API GET %s → %s (%s)", u, code, time.Since(start))
	if code != "200" {
		return nil, fmt.Errorf("statut inattendu %s", code)
	}
	return body, nil
}

// splitCurlOutput sépare le corps du code HTTP ajouté par `-w "\n%{http_code}"`
// (écrit en dernier, après tout le corps — y compris si celui-ci contient
// lui-même des sauts de ligne).
func splitCurlOutput(out []byte) (body []byte, code string) {
	if i := bytes.LastIndexByte(out, '\n'); i >= 0 {
		return out[:i], string(out[i+1:])
	}
	return nil, string(out)
}
