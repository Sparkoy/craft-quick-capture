# CraftQuickCapture

Application macOS menu bar pour capturer du texte et des images dans vos documents [Craft](https://craft.do).

**⌥⌘Space** ouvre une petite fenêtre sombre : tapez (ou déposez une image), choisissez un document, ⌘↩ — c'est dans Craft.

Aucun Electron, aucune dépendance. Un seul binaire Swift qui parle directement à l'API de Craft.

---

## Prérequis

- macOS 13 Ventura ou supérieur
- Xcode Command Line Tools : `xcode-select --install`

## Installation

```bash
git clone https://github.com/brandhull/craft-quick-capture.git
cd craft-quick-capture
./build.sh --install
```

Au premier lancement, configurez votre **lien MCP Craft** via l'icône menu bar → Préférences…  
Générez-le dans Craft → Réglages → AI / Imagine → "Connecter un assistant AI".  
Il ressemble à `https://mcp.craft.do/links/…/mcp`.  
Stocké dans `~/Library/Application Support/CraftQuickCapture/config.json`, ne quitte jamais votre machine.

## Utilisation

| Action | Résultat |
|--------|---------|
| **⌥⌘Space** | Ouvre / ferme la fenêtre de capture |
| Taper du texte + **⌘↩** | Ajoute au document sélectionné |
| Glisser une image | Bascule en mode image |
| **⌘V** | Colle depuis le presse-papier |
| ↑ / ↓ + ↩ | Navigue dans la liste de documents |
| Esc | Ferme la fenêtre |

La liste des documents est mise en cache (TTL 15 min) et rafraîchie en arrière-plan à chaque ouverture.

## Fonctionnement

**MCP stateless** — JSON-RPC sur HTTPS, une seule requête POST par sauvegarde, aucune gestion de session.

**Images** — Craft n'accepte que des URLs HTTPS publiques. Les images sont relayées via [tmpfiles.org](https://tmpfiles.org) (60 min) ; Craft les copie sur son CDN à l'enregistrement. Fallback : [litterbox.catbox.moe](https://litterbox.catbox.moe).

**Fichiers locaux :**
- Config : `~/Library/Application Support/CraftQuickCapture/config.json`
- Cache docs : `~/Library/Application Support/CraftQuickCapture/documents-cache.json`

## Build

```bash
./build.sh            # → .build/bundle/CraftQuickCapture.app
./build.sh --install  # → build + install /Applications + relance
```

Signé ad-hoc (fonctionne sur votre propre machine, sans Developer ID).

## Quirks API Craft (empiriques)

- Les sauts de ligne dans `craft_write` doivent être de vrais `\n`, pas des `\\n` échappés.
- Pagination cursor-based pour `documents list` (trailer "Next page:").
- Nouveau document : délai ~15–30 s avant d'accepter `blocks add`.
- Petites images (~100 bytes) déclenchent une fausse erreur "Document not found".

## Licence

MIT
