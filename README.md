# Lemwincher — le moins cher autour de chez moi

Application iPhone (SwiftUI, iOS 17+) qui compare les prix des supermarchés autour de chez vous.

## Fonctions

| Onglet | Ce qu'on y trouve |
|---|---|
| **Autour de moi** | Carte + liste des supermarchés proches (filtre Supermarchés / Tous les commerces, **« Ouverts maintenant »**). **Carburant le moins cher** autour de vous (prix officiels). **Classement des enseignes présentes autour de vous** (ex. E.Leclerc −13 %, Carrefour City +14 % par rapport à la moyenne). Vos magasins favoris en tête. Fiche magasin : **horaires de la semaine**, itinéraire, téléphone, site, enseigne, prix connus, étoile « mes magasins ». |
| **Carburants** | Prix officiels de toutes les stations du rayon (Gazole, SP95-E10, SP95, SP98, E85, GPL) : carte avec les prix, classement du moins cher au plus cher (ou par distance), **économie sur un plein de 50 L**, ruptures, services, automate 24 h/24. |
| **Comparer** | Recherche par nom ou **scan du code-barres** → prix relevés dans chaque magasin proche, **estimation par enseigne**, **graphique d'évolution du prix sur 12 mois**, **produits similaires moins chers au kilo / au litre**, **Nutri-Score, NOVA, Éco-Score, allergènes et labels**, partage du comparatif. **Prix suivis** (cloche) : prix cible et **notification en cas de baisse**. **Rappels de produits** du département (RappelConso), avec alerte si un produit de votre liste est concerné. |
| **Ma liste** | **Ajout rapide** (nom ou code-barres), liste de courses → **où faire ses courses** : total du panier par magasin avec les vrais prix, complétés par l'estimation de l'enseigne. Filtre « seulement mes magasins », meilleure combinaison de magasins, partage de la liste, **alerte rappel produit**. |
| **Mes prix** | Relevé express en magasin : **magasin détecté automatiquement**, scan, **prix lu sur la photo de l'étiquette**, « Enregistrer et relever le suivant ». **Ticket de caisse en photo** → tous les prix ajoutés d'un coup. **Statistiques** et **évolution de vos prix** (hausses / baisses), **export CSV**. Option : partager sur Open Prices. |
| **Réglages** | Rayon, domicile, magasins favoris, compte Open Prices, devise, carburant préféré, **sauvegarde / restauration** (fichier JSON), présentation. |

Et aussi : **Siri** (« Ajoute à ma liste Lemwincher », « Ouvre ma liste Lemwincher »), présentation au premier lancement, liste de magasins gardée en cache quand OpenStreetMap est saturé.

### D'où viennent les données ? (gratuit, sans clé d'API)

- **Prix** : [Open Prices](https://prices.openfoodfacts.org) (Open Food Facts), base collaborative de prix relevés sur étiquettes et tickets.
  - Près de chez vous : les derniers prix relevés dans chaque magasin.
  - **Estimations par enseigne** : prix médian dans les magasins de l'enseigne en France sur 12 mois (hors promos).
  - **Classement des enseignes** : indice calculé sur ~40 produits de grandes marques vendus partout (Nutella, Barilla, St Michel…). Recalculé tous les 3 jours.
- **Magasins et horaires** : OpenStreetMap (Overpass), dernière liste gardée en cache, Plans d'Apple en secours.
- **Fiches produits** (nom, photo, contenance, catégories, Nutri-Score…) : Open Food Facts.
- **Carburants** : flux instantané officiel prix-carburants.gouv.fr (data.economie.gouv.fr), noms des stations via OpenStreetMap.
- **Rappels de produits** : RappelConso (data.economie.gouv.fr), recherche par code-barres et par département.
- **Lecture des étiquettes et tickets** : Vision, sur l'iPhone (aucune photo envoyée, sauf partage volontaire sur Open Prices).

> **Toulouse** : Open Prices y compte encore peu de relevés (≈ 370 prix et 38 magasins dans un rayon de 15 km, novembre 2026). C'est pourquoi l'app s'appuie sur les estimations par enseigne et sur vos propres relevés, et vous permet de partager les vôtres pour enrichir la base.

---

## Compiler l'IPA (sans Mac)

Une app iPhone ne se compile que sur macOS : le workflow [.github/workflows/build-ipa.yml](.github/workflows/build-ipa.yml) le fait sur un Mac de GitHub à chaque envoi de code :

1. compilation pour le simulateur ;
2. **tests unitaires** ([LemwincherTests/](LemwincherTests/) : enseignes, panier, estimations, classement, horaires, carburants, rappels, lecture d'étiquettes et de tickets, suivi des prix, sauvegarde…) — l'IPA n'est produite que s'ils passent ;
3. **tests d'interface** ([LemwincherUITests/](LemwincherUITests/)) : parcours complet de l'app à Toulouse (données de démonstration) avec **captures d'écran** publiées dans l'artefact `captures-ecran` ;
4. compilation de `Lemwincher.ipa` (non signée), publiée comme artefact `Lemwincher-ipa`.

Depuis ce PC (Git et GitHub CLI installés) :

```powershell
gh auth login --web --scopes workflow      # une seule fois
gh repo create lemwincher --private --source . --push
gh run watch                               # suivre la compilation
gh run download -n Lemwincher-ipa -D dist  # récupérer dist\Lemwincher.ipa
gh run download -n captures-ecran -D captures  # captures d'écran des tests
```

Mettez `[skip ci]` dans le message de commit pour ne pas lancer la compilation (dépôt privé : les minutes macOS comptent ×10).

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
project.yml                      Projet Xcode (XcodeGen) : app + tests
Config/Lemwincher-Info.plist     Clés Info.plist (vérification des prix en arrière-plan)
.github/workflows/build-ipa.yml  Tests + IPA sur GitHub Actions
Lemwincher/
  App/        Point d'entrée, onglets, Siri, données de démonstration (tests d'interface)
  Models/     Modèles, enseignes, calculs (panier, estimations, classement), horaires, carburants,
              rappels, suivi des prix, lecture d'étiquettes / tickets, sauvegarde
  Services/   API Open Prices / Open Food Facts / data.economie.gouv.fr, magasins (OSM/Plans) + cache,
              localisation, compte Open Prices, Vision, notifications
  Views/      Écrans SwiftUI
  Resources/  Icône, couleur
LemwincherTests/    Tests unitaires
LemwincherUITests/  Tests d'interface + captures d'écran
```

Sur un Mac : `brew install xcodegen && xcodegen generate`, puis ouvrez `Lemwincher.xcodeproj`.
