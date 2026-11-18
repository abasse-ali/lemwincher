import XCTest

/// Parcours de l'app sur simulateur avec des données de démonstration (domicile : Capitole, Toulouse).
/// Chaque écran est photographié : les captures sont publiées par GitHub Actions.
final class LemwincherUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
        // Alertes du simulateur lui-même (pas de l'app, qui ne demande rien en mode test) : on les ferme.
        addUIInterruptionMonitor(withDescription: "Alerte système") { alert in
            for label in ["Autoriser une fois", "Allow Once", "OK", "Plus tard", "Not Now", "Fermer", "Close",
                          "Annuler", "Cancel"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            if alert.buttons.count > 0 {
                alert.buttons.element(boundBy: 0).tap()
                return true
            }
            return false
        }
    }

    /// Geste sans effet sur l'écran affiché : laisse XCTest fermer une éventuelle alerte système
    /// avant de toucher un bouton (sinon le bouton visé devient « invalide » pendant le toucher).
    private func settle(_ app: XCUIApplication) {
        app.swipeUp(velocity: .slow)
        sleep(1)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"] + extra
        app.launch()
        return app
    }

    /// Capture jointe au rapport de test + copiée sur le Mac (dossier ~/lemwincher-screenshots).
    private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
            let folder = URL(fileURLWithPath: home).appendingPathComponent("lemwincher-screenshots")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: folder.appendingPathComponent(name + ".png"))
        }
    }

    /// Arborescence de l'écran en texte, pour comprendre un élément introuvable.
    private func dump(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
            let folder = URL(fileURLWithPath: home).appendingPathComponent("lemwincher-screenshots")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? app.debugDescription.write(to: folder.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        }
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        sleep(1)
    }

    /// Remonte la liste jusqu'à ce que l'élément apparaisse (au plus `swipes` fois).
    @discardableResult
    private func scrollDown(until element: XCUIElement, in app: XCUIApplication, swipes: Int = 8) -> Bool {
        var count = 0
        while !element.exists && count < swipes {
            app.swipeDown()
            count += 1
        }
        return element.exists
    }

    /// Change d'onglet. Toucher par coordonnées + nouvel essai : une alerte du simulateur pendant le toucher
    /// ne fait plus échouer le parcours (« element is no longer valid after interruption handling »).
    private func tab(_ app: XCUIApplication, _ label: String) {
        let button = app.tabBars.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "onglet \(label)")
        for _ in 0..<3 {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            sleep(1)
            if button.isSelected { return }
        }
    }

    func testOnboarding() {
        let app = launch(["-onboarding"])
        XCTAssertTrue(element(app, "onboardingNext").waitForExistence(timeout: 20))
        snapshot("00-presentation-1")
        for index in 2...6 {
            settle(app)
            // Bouton recherché à chaque page (jamais une référence gardée d'une page à l'autre).
            let next = element(app, "onboardingNext")
            guard next.waitForExistence(timeout: 10) else { break }
            next.tap()
            sleep(1)
            if index <= 5 { snapshot("00-presentation-\(index)") }
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "la présentation se ferme")
    }

    func testTourOfTheApp() {
        let app = launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        // 1. Autour de moi : carte, carburant, enseignes, magasins.
        let storeRow = element(app, "storeRow")
        XCTAssertTrue(storeRow.waitForExistence(timeout: 90), "des magasins autour du Capitole")
        sleep(4)
        snapshot("01-autour-de-moi")

        // Toucher un magasin sur la carte : fiche rapide avec « Rayons et prix sur le site ».
        let marker = app.maps.firstMatch.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'Carrefour City' OR label CONTAINS[c] 'Aldi'")).firstMatch
        if marker.waitForExistence(timeout: 5) && marker.isHittable {
            marker.tap()
            if element(app, "storeQuickDetail").waitForExistence(timeout: 5) {
                sleep(1)
                snapshot("01b-carte-fiche-rapide")
                let close = element(app, "closeQuickSheet")
                if close.exists { close.tap() }
                sleep(2)
            }
        }

        // Carburant et classement d'abord, tant que la liste est en haut
        // (les lignes hors de l'écran n'existent pas pour les tests).
        let fuel = element(app, "fuelLink")
        if fuel.waitForExistence(timeout: 30) || scrollDown(until: fuel, in: app) {
            fuel.tap()
            _ = element(app, "fuelStationFirst").waitForExistence(timeout: 40)
            sleep(3)
            snapshot("05-carburants")
            let first = element(app, "fuelStationFirst")
            if !first.isHittable && first.exists {
                app.collectionViews.firstMatch.swipeUp(velocity: .slow)
            }
            if first.exists && first.isHittable {
                first.tap()
                sleep(2)
                snapshot("07-station")
                goBack(app)
            }
            app.swipeUp()
            sleep(1)
            snapshot("06-carburants-liste")
            goBack(app)
        } else {
            snapshot("05-carburants-introuvable")
            dump(app, "05-carburants-introuvable")
        }

        // Le lien est sous les 6 premières enseignes : on attend le calcul puis on fait défiler.
        let ranking = element(app, "chainRankingLink")
        var rankingFound = ranking.waitForExistence(timeout: 20)
        var attempts = 0
        while !rankingFound && attempts < 4 {
            reveal(ranking, in: app, swipes: 3)
            rankingFound = ranking.exists
            if !rankingFound {
                scrollDown(until: element(app, "fuelLink"), in: app)
                sleep(20)
            }
            attempts += 1
        }
        if rankingFound {
            reveal(ranking, in: app, swipes: 2)
            ranking.tap()
            sleep(2)
            snapshot("08a-classement-enseignes")
            goBack(app)
        } else {
            snapshot("08a-classement-introuvable")
            dump(app, "08a-classement-introuvable")
        }

        // Liste des magasins et fiche d'un magasin.
        app.swipeUp()
        sleep(1)
        snapshot("02-autour-de-moi-liste")
        let row = element(app, "storeRow")
        if row.exists && row.isHittable {
            row.tap()
            sleep(5)
            snapshot("03-fiche-magasin")
            // « Rayons et prix sur le site de l'enseigne » : le navigateur de l'app s'ouvre sur le site.
            let siteButton = element(app, "storeSiteButton")
            if siteButton.exists && siteButton.isHittable {
                siteButton.tap()
                sleep(15)
                snapshot("03b-site-de-l-enseigne")
                let close = app.navigationBars.buttons["Fermer"].firstMatch
                if close.waitForExistence(timeout: 5) { close.tap() }
                sleep(2)
            }
            app.swipeUp()
            sleep(1)
            snapshot("04-fiche-magasin-horaires")
            goBack(app)
        }

        // 2. Produits : rayons, suivis, rappels, consultés, recherche dans tout le catalogue.
        tab(app, "Produits")
        sleep(6)
        snapshot("08-produits")

        let dairies = element(app, "rayon-en:dairies")
        if dairies.waitForExistence(timeout: 10) {
            dairies.tap()
            sleep(10)
            snapshot("08b-rayon-produits-laitiers")
            let cheapest = app.buttons["Moins chers"]
            if cheapest.waitForExistence(timeout: 5) {
                cheapest.tap()
                sleep(10)
                snapshot("08c-rayon-moins-chers-au-kilo")
            }
            goBack(app)
        }

        let recent = element(app, "recentProduct")
        reveal(recent, in: app)
        if recent.waitForExistence(timeout: 10) {
            recent.tap()
            sleep(10)
            snapshot("09-comparatif-produit")
            app.swipeUp()
            sleep(1)
            snapshot("10-comparatif-suite")
            app.swipeUp()
            sleep(1)
            snapshot("11-comparatif-fin")
            goBack(app)
        }

        let recalls = element(app, "recallsLink")
        if !recalls.exists { scrollDown(until: recalls, in: app) }
        reveal(recalls, in: app)
        if recalls.waitForExistence(timeout: 10) {
            recalls.tap()
            sleep(6)
            snapshot("12-rappels")
            goBack(app)
        }

        let search = app.searchFields.firstMatch
        scrollDown(until: search, in: app)
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("yaourt nature\n")
            sleep(10)
            snapshot("12b-recherche-catalogue")
            app.swipeUp()
            sleep(4)
            snapshot("12c-recherche-plus-de-produits")
            // Quitter la recherche : le clavier cache la barre d'onglets.
            let cancel = app.buttons["Annuler"].firstMatch
            if cancel.exists { cancel.tap() } else { app.buttons["Cancel"].firstMatch.tap() }
            sleep(1)
        }

        // 3. Ma liste : ajout rapide et magasin le moins cher.
        tab(app, "Ma liste")
        let field = app.textFields["quickAddField"]
        if field.waitForExistence(timeout: 10) {
            field.tap()
            field.typeText("Pommes Gala\n")
            XCTAssertTrue(app.staticTexts["Pommes Gala"].waitForExistence(timeout: 15), "produit ajouté à la liste")
        }
        sleep(12)
        snapshot("13-ma-liste")

        // Un article générique se déplie : les vrais produits en dessous, avec leur prix.
        let eggs = app.staticTexts["Œufs"].firstMatch
        if eggs.waitForExistence(timeout: 5) {
            eggs.tap()
            // Pas de requête d'accessibilité pendant le chargement des prix (lente sur les Mac de GitHub) :
            // on attend, on photographie, puis on cherche un produit avec une requête ciblée.
            sleep(25)
            snapshot("13b-liste-oeufs-deplies")
            let first = app.buttons.matching(identifier: "suggestion").firstMatch
            if first.waitForExistence(timeout: 10) && first.isHittable {
                first.tap()
                sleep(2)
                snapshot("13c-liste-oeufs-choisis")
            } else {
                dump(app, "13c-suggestion-introuvable")
            }
            eggs.tap()
            sleep(1)
        }

        // Acheté = dépense du mois.
        // « Œufs » (produit choisi, prix connu) : la case à cocher, dépense directe.
        markBought(app, "Œufs", amount: nil, swipe: false)
        // « Pommes Gala » (aucun prix connu) : glisser vers la droite ; l'app demande le montant payé.
        markBought(app, "Pommes Gala", amount: "2,40", swipe: true)
        sleep(1)
        snapshot("13e-articles-coches-depenses")

        app.swipeUp()
        sleep(1)
        snapshot("14-ma-liste-magasins")

        // 4. Budget : jauge, nouvelle dépense, graphique, mes relevés de prix.
        tab(app, "Budget")
        sleep(2)
        snapshot("15-budget")

        let addExpense = element(app, "addExpenseButton")
        if addExpense.waitForExistence(timeout: 5) {
            addExpense.tap()
            let amount = app.textFields["expenseAmount"]
            if amount.waitForExistence(timeout: 5) {
                amount.tap()
                amount.typeText("18.60")
                sleep(1)
                snapshot("16-nouvelle-depense")
                let save = app.navigationBars.buttons["Enregistrer"]
                if save.exists { save.tap() }
                sleep(2)
                snapshot("16b-budget-apres-depense")
                // Alerte « 80 % du budget atteint » éventuelle.
                let ok = app.alerts.buttons["OK"]
                if ok.waitForExistence(timeout: 2) { ok.tap() }
            }
        }
        app.swipeUp()
        sleep(1)
        snapshot("16c-budget-graphiques")
        app.swipeUp()
        sleep(1)
        snapshot("16d-budget-historique")

        let myPrices = element(app, "myPricesLink")
        reveal(myPrices, in: app)
        if myPrices.waitForExistence(timeout: 5) {
            myPrices.tap()
            sleep(2)
            snapshot("17-mes-prix")
            goBack(app)
        }

        // 5. Recettes : idées, fiche, mode cuisine pas à pas, plat composé, menu de la semaine.
        tourOfRecipes(app)

        // 6. Réglages : roue dentée ⚙︎ en haut de « Autour de moi ».
        tab(app, "Autour de moi")
        sleep(1)
        let gear = app.navigationBars.buttons["Réglages"].firstMatch
        if gear.waitForExistence(timeout: 5) {
            gear.tap()
            sleep(1)
            snapshot("18-reglages")
            app.swipeUp()
            sleep(1)
            snapshot("18b-reglages-suite")
            let close = element(app, "closeSettings")
            if close.waitForExistence(timeout: 3) { close.tap() }
            sleep(1)
        }

        // 7. En dernier (dépend du vrai site aldi.fr) : capture des prix du site d'Aldi depuis « Ma liste ».
        captureFromAldi(app)
    }

    private func tourOfRecipes(_ app: XCUIApplication) {
        tab(app, "Recettes")
        sleep(2)
        snapshot("20-recettes")
        app.swipeUp()
        sleep(1)
        snapshot("20b-recettes-liste")
        app.swipeDown()
        app.swipeDown()

        // Une fiche recette, puis le mode cuisine.
        let card = element(app, "recipeCard")
        reveal(card, in: app)
        if card.waitForExistence(timeout: 5) {
            card.tap()
            sleep(2)
            snapshot("21-recette")
            app.swipeUp()
            sleep(1)
            snapshot("21b-recette-suite")
            app.swipeDown()
            app.swipeDown()
            let cook = element(app, "startCooking")
            if cook.waitForExistence(timeout: 5) && cook.isHittable {
                cook.tap()
                sleep(2)
                snapshot("22-cuisine-mise-en-place")
                let next = element(app, "cookingNext")
                // Avance jusqu'à une étape avec un minuteur (« … 5 min … »).
                for step in 1...4 where next.waitForExistence(timeout: 3) {
                    next.tap()
                    sleep(1)
                    if step == 1 { snapshot("22b-cuisine-etape") }
                    let timer = element(app, "startTimer")
                    if timer.exists && timer.isHittable {
                        timer.tap()
                        sleep(3)
                        snapshot("22c-cuisine-minuteur")
                        break
                    }
                }
                let close = app.buttons["Fermer le mode cuisine"].firstMatch
                if close.waitForExistence(timeout: 3) { close.tap() }
                sleep(1)
            }
            goBack(app)
        }

        // Composer un plat.
        let compose = app.segmentedControls.buttons["Composer"].firstMatch
        if compose.waitForExistence(timeout: 5) {
            compose.tap()
            sleep(1)
            snapshot("23-composer")
            let surprise = element(app, "surpriseDish")
            if surprise.waitForExistence(timeout: 3) {
                surprise.tap()
                sleep(1)
                snapshot("23b-composer-surprise")
            }
            let dish = element(app, "composedDish")
            if dish.waitForExistence(timeout: 3) && dish.isHittable {
                dish.tap()
                sleep(2)
                snapshot("23c-plat-compose")
                goBack(app)
            }
        }

        // Menu de la semaine et ses courses.
        let week = app.segmentedControls.buttons["Menu"].firstMatch
        if week.waitForExistence(timeout: 5) {
            week.tap()
            sleep(1)
            let generate = element(app, "generateMenu")
            if generate.waitForExistence(timeout: 3) {
                generate.tap()
                sleep(1)
                snapshot("24-menu-semaine")
            }
            let shopping = element(app, "addWeekShopping")
            reveal(shopping, in: app)
            if shopping.waitForExistence(timeout: 3) && shopping.isHittable {
                shopping.tap()
                sleep(1)
                snapshot("24b-menu-courses")
            }
        }
        // Retour sur « Idées » pour les prochaines fois.
        let ideas = app.segmentedControls.buttons["Idées"].firstMatch
        if ideas.exists { ideas.tap() }
    }

    /// Passe un article en « acheté » (case à cocher, ou glissement vers la droite puis « Acheté »)
    /// et répond à la question du montant si elle vient.
    private func markBought(_ app: XCUIApplication, _ name: String, amount: String?, swipe: Bool) {
        let label = app.staticTexts[name].firstMatch
        guard label.waitForExistence(timeout: 5) else { return }
        if !label.isHittable { reveal(label, in: app) }
        var done = false
        if swipe {
            label.swipeRight()
            let bought = app.buttons["Acheté"].firstMatch
            if bought.waitForExistence(timeout: 3) {
                bought.tap()
                done = true
            } else {
                dump(app, "13d-glisser-sans-effet")
            }
        }
        if !done {
            // La case de la même ligne que le nom de l'article.
            let boxes = app.buttons.matching(NSPredicate(format: "label == %@", "Cocher : acheté")).allElementsBoundByIndex
            guard let box = boxes.min(by: { abs($0.frame.midY - label.frame.midY) < abs($1.frame.midY - label.frame.midY) }) else {
                dump(app, "13d-case-introuvable")
                return
            }
            box.tap()
        }
        let field = app.alerts.firstMatch.textFields.firstMatch
        if field.waitForExistence(timeout: 3) {
            field.typeText(amount ?? "1")
            snapshot("13d-prix-paye")
            app.alerts.firstMatch.buttons["Ajouter au budget"].tap()
        }
        sleep(1)
    }

    private func captureFromAldi(_ app: XCUIApplication) {
        tab(app, "Ma liste")
        sleep(2)
        // Revenir tout en haut : « Œufs » figure aussi en bas, dans « Sans prix connu ».
        scrollDown(until: app.textFields["quickAddField"], in: app, swipes: 12)
        app.swipeDown()
        sleep(1)
        let eggs = app.staticTexts["Œufs"].firstMatch
        guard eggs.waitForExistence(timeout: 5) else { return }
        let open = element(app, "captureFromSite")
        if !element(app, "suggestion").exists {
            eggs.tap()   // replié : on le déplie
            sleep(3)
        }
        snapshot("19a-liste-oeufs-redeplies")
        // Petits défilements jusqu'au bouton, sans le dépasser.
        var swipes = 0
        while !open.exists && swipes < 15 {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
            swipes += 1
        }
        if open.exists && !open.isHittable {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        guard open.waitForExistence(timeout: 5), open.isHittable else {
            snapshot("19-bouton-site-introuvable")
            dump(app, "19-bouton-site-introuvable")
            return
        }
        open.tap()
        // Aldi est en bout de barre : on passe par le menu du titre.
        let picker = element(app, "sitePicker")
        guard picker.waitForExistence(timeout: 10) else { return }
        picker.tap()
        // L'entrée du menu (pas la pastille « Aldi » de la barre, hors écran).
        let aldi = app.buttons.matching(NSPredicate(format: "label == 'Aldi' AND identifier != 'site-aldi'")).firstMatch
        guard aldi.waitForExistence(timeout: 5) else {
            dump(app, "19-menu-sites")
            return
        }
        aldi.tap()
        // Pas de requête pendant le chargement de la page (arbre d'accessibilité du site très lourd).
        sleep(25)
        snapshot("19-site-aldi")
        let capture = app.buttons["Capturer les prix de la page"].firstMatch
        guard capture.waitForExistence(timeout: 10) else { return }
        capture.tap()
        // Lecture de tous les produits (« Voir plus », pages suivantes) : compteur à l'écran, puis la vérification.
        sleep(3)
        snapshot("19a2-lecture-de-tous-les-produits")
        _ = app.navigationBars["Prix capturés"].waitForExistence(timeout: 100)
        sleep(1)
        snapshot("19b-prix-captures-aldi")
        let add = app.navigationBars.buttons["Ajouter"].firstMatch
        if add.waitForExistence(timeout: 5) && add.isEnabled {
            add.tap()
            sleep(3)
            snapshot("19c-liste-avec-prix-aldi")

            // Le rayon capturé est gardé en mémoire (« Mes rayons en ligne », onglet Produits) et se met à jour.
            tab(app, "Produits")
            // Deuxième toucher sur l'onglet : retour à l'écran principal de Produits (rayons, mes rayons en ligne).
            app.tabBars.buttons["Produits"].tap()
            sleep(2)
            let cancelSearch = app.buttons["Annuler"].firstMatch
            if cancelSearch.exists && cancelSearch.isHittable { cancelSearch.tap() }
            let tracked = element(app, "trackedPageRow")
            reveal(tracked, in: app, swipes: 10)
            if !tracked.exists { dump(app, "19d-rayons-introuvables") }
            if tracked.waitForExistence(timeout: 5) && tracked.isHittable {
                snapshot("19d-mes-rayons-en-ligne")
                tracked.tap()
                sleep(2)
                snapshot("19e-rayon-suivi")
                let refresh = element(app, "refreshTrackedPage")
                if refresh.waitForExistence(timeout: 3) {
                    refresh.tap()
                    sleep(50)
                    snapshot("19f-rayon-mis-a-jour")
                }
            }
        } else {
            let close = app.buttons["Annuler"].firstMatch
            if close.exists { close.tap() }
        }
    }

    /// Fait défiler doucement vers le bas jusqu'à ce que l'élément soit visible et touchable.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) {
        var count = 0
        while (!element.exists || !element.isHittable) && count < swipes {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
            count += 1
        }
    }
}
