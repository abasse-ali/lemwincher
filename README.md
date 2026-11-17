# Lemwincher — le moins cher autour de chez moi

Application iPhone (SwiftUI, iOS 17+) qui compare les prix des supermarchés autour de chez vous.

## Fonctions

| Onglet | Ce qu'on y trouve |
|---|---|
| **Autour de moi** | Carte + liste des supermarchés proches (filtre Supermarchés / Tous les commerces). **Classement des enseignes présentes autour de vous** (ex. E.Leclerc −13 %, Carrefour City +14 % par rapport à la moyenne). Vos magasins favoris en tête. Fiche magasin : itinéraire, enseigne, prix connus, étoile « mes magasins ». |
| **Comparer** | Recherche par nom ou **scan du code-barres** → prix relevés dans chaque magasin proche (du moins cher au plus cher), **estimation par enseigne** quand personne n'a relevé le produit près de chez vous, **graphique d'évolution du prix sur 12 mois**, **produits similaires moins chers au kilo / au litre**. |
| **Ma liste** | Liste de courses → **où faire ses courses** : pour chaque magasin, total du panier avec les vrais prix relevés, complétés par l'estimation de l'enseigne (marqués « estimé »). Filtre « seulement mes magasins », meilleure combinaison de magasins, partage de la liste (Messages, WhatsApp…). |
| **Mes prix** | Relevé express en magasin : le **magasin est détecté automatiquement** (GPS), on scanne, on tape le prix, « Enregistrer et relever le suivant ». Option : **partager sur Open Prices** avec la photo de l'étiquette. |
| **Réglages** | Rayon (8 km par défaut, pour inclure les hypermarchés de périphérie), domicile, magasins favoris, compte Open Prices, devise. |

### D'où viennent les données ? (gratuit, sans clé d'API)

- **Prix** : [Open Prices](https://prices.openfoodfacts.org) (Open Food Facts), base collaborative de prix relevés sur étiquettes et tickets.
  - Près de chez vous : les derniers prix relevés dans chaque magasin.
  - **Estimations par enseigne** : prix médian dans les magasins de l'enseigne en France sur 12 mois (hors promos).
  - **Classement des enseignes** : indice calculé sur ~40 produits de grandes marques vendus partout (Nutella, Barilla, St Michel…). Recalculé tous les 3 jours.
- **Magasins** : OpenStreetMap (Overpass), Plans d'Apple en secours.
- **Fiches produits** (nom, photo, contenance, catégories) : Open Food Facts.

> **Toulouse** : Open Prices y compte encore peu de relevés (≈ 370 prix et 38 magasins dans un rayon de 15 km, novembre 2026). C'est pourquoi l'app s'appuie sur les estimations par enseigne et sur vos propres relevés, et vous permet de partager les vôtres pour enrichir la base.

---

## Compiler l'IPA (sans Mac)

Une app iPhone ne se compile que sur macOS : le workflow [.github/workflows/build-ipa.yml](.github/workflows/build-ipa.yml) le fait gratuitement sur un Mac de GitHub à chaque envoi de code, et publie `Lemwincher.ipa` (non signé) comme artefact.

Depuis ce PC (Git et GitHub CLI installés) :

```powershell
gh auth login --web --scopes workflow      # une seule fois
gh repo create lemwincher --private --source . --push
gh run watch                               # suivre la compilation
gh run download -n Lemwincher-ipa -D dist  # récupérer dist\Lemwincher.ipa
```

## Installer l'IPA sur l'iPhone depuis Windows

L'IPA doit être signée avec votre identifiant Apple : **Sideloadly** le fait gratuitement.

1. Installez **iTunes** et **iCloud** depuis le site d'Apple (pas la version Microsoft Store), puis **Sideloadly** depuis <https://sideloadly.io>.
2. Branchez l'iPhone en USB, déverrouillez-le, touchez **« Faire confiance »**.
3. Dans Sideloadly : glissez `dist\Lemwincher.ipa`, entrez votre identifiant Apple, cliquez **Start**.
4. Sur l'iPhone : **Réglages → Confidentialité et sécurité → Mode développeur** (activer, redémarrage), puis **Réglages → Général → VPN et gestion de l'appareil** → faire confiance à votre identifiant.
5. Ouvrez **Lemwincher** et autorisez la localisation et la caméra.

> Identifiant Apple **gratuit** : l'app doit être re-signée **tous les 7 jours** (relancer Sideloadly, ou activer son rafraîchissement automatique en Wi-Fi). Compte **Apple Developer** (99 $/an) : 1 an.

---

## Structure du code

```
project.yml                      Projet Xcode (XcodeGen)
.github/workflows/build-ipa.yml  Compilation de l'IPA sur GitHub Actions
Lemwincher/
  App/        Point d'entrée, onglets
  Models/     Modèles, enseignes, calculs (comparaisons, panier, estimations, classement)
  Services/   API Open Prices / Open Food Facts, magasins (OSM/Plans), localisation, compte Open Prices
  Views/      Écrans SwiftUI, scanner de code-barres, appareil photo
  Resources/  Icône, couleur
```

Sur un Mac : `brew install xcodegen && xcodegen generate`, puis ouvrez `Lemwincher.xcodeproj`.
