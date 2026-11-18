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

    private func tab(_ app: XCUIApplication, _ label: String) {
        let button = app.tabBars.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "onglet \(label)")
        button.tap()
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
            XCTAssertTrue(app.staticTexts["Pommes Gala"].waitForExistence(timeout: 5), "produit ajouté à la liste")
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
            }
            eggs.tap()
            sleep(1)
        }

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

        // 5. Réglages.
        tab(app, "Réglages")
        sleep(1)
        snapshot("18-reglages")
        app.swipeUp()
        sleep(1)
        snapshot("18b-reglages-suite")

        // 6. En dernier (dépend du vrai site aldi.fr) : capture des prix du site d'Aldi depuis « Ma liste ».
        captureFromAldi(app)
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
        eggs.tap()
        sleep(3)
        let open = element(app, "captureFromSite")
        reveal(open, in: app, swipes: 12)
        guard open.waitForExistence(timeout: 10), open.isHittable else {
            dump(app, "19-bouton-site-introuvable")
            return
        }
        open.tap()
        let aldi = element(app, "site-aldi")
        guard aldi.waitForExistence(timeout: 10) else { return }
        if !aldi.isHittable { element(app, "siteBar").swipeLeft() }
        aldi.tap()
        // Pas de requête pendant le chargement de la page (arbre d'accessibilité du site très lourd).
        sleep(25)
        snapshot("19-site-aldi")
        let capture = app.buttons["Capturer les prix de la page"].firstMatch
        guard capture.waitForExistence(timeout: 10) else { return }
        capture.tap()
        sleep(3)
        snapshot("19b-prix-captures-aldi")
        let add = app.navigationBars.buttons["Ajouter"].firstMatch
        if add.waitForExistence(timeout: 5) && add.isEnabled {
            add.tap()
            sleep(3)
            snapshot("19c-liste-avec-prix-aldi")
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
