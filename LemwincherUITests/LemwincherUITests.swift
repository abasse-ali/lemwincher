import XCTest

/// Parcours de l'app sur simulateur avec des données de démonstration (domicile : Capitole, Toulouse).
/// Chaque écran est photographié : les captures sont publiées par GitHub Actions.
final class LemwincherUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
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

    /// Fait défiler la liste jusqu'à ce que l'élément soit visible (au plus `swipes` fois).
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 4) {
        var count = 0
        while (!element.exists || !element.isHittable) && count < swipes {
            app.swipeUp()
            count += 1
        }
    }

    private func tab(_ app: XCUIApplication, _ label: String) {
        let button = app.tabBars.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "onglet \(label)")
        button.tap()
    }

    func testOnboarding() {
        let app = launch(["-onboarding"])
        let next = element(app, "onboardingNext")
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        snapshot("00-presentation-1")
        for index in 2...4 {
            next.tap()
            sleep(1)
            snapshot("00-presentation-\(index)")
        }
        next.tap()
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
        app.swipeUp()
        sleep(1)
        snapshot("02-autour-de-moi-liste")

        if storeRow.exists && storeRow.isHittable {
            storeRow.tap()
            sleep(5)
            snapshot("03-fiche-magasin")
            app.swipeUp()
            sleep(1)
            snapshot("04-fiche-magasin-horaires")
            goBack(app)
        }
        // Toucher l'onglet actif ramène en haut de la liste.
        tab(app, "Autour de moi")
        tab(app, "Autour de moi")
        sleep(1)

        let fuel = element(app, "fuelLink")
        if fuel.waitForExistence(timeout: 30) {
            if !fuel.isHittable { app.swipeDown() }
            fuel.tap()
            _ = element(app, "fuelStationFirst").waitForExistence(timeout: 40)
            sleep(3)
            snapshot("05-carburants")
            app.swipeUp()
            sleep(1)
            snapshot("06-carburants-liste")
            let first = element(app, "fuelStationFirst")
            if first.exists && first.isHittable {
                first.tap()
                sleep(2)
                snapshot("07-station")
                goBack(app)
            }
            goBack(app)
        } else {
            snapshot("05-carburants-introuvable")
            dump(app, "05-carburants-introuvable")
        }

        let ranking = element(app, "chainRankingLink")
        if ranking.waitForExistence(timeout: 150) {
            scrollTo(ranking, in: app)
            ranking.tap()
            sleep(2)
            snapshot("07b-classement-enseignes")
            goBack(app)
        } else {
            snapshot("07b-classement-introuvable")
            dump(app, "07b-classement-introuvable")
        }

        // 2. Comparer : produits suivis, rappels, produits consultés.
        tab(app, "Comparer")
        sleep(6)
        snapshot("08-comparer")

        let recent = element(app, "recentProduct")
        if recent.waitForExistence(timeout: 10) {
            if !recent.isHittable { app.swipeUp() }
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
        if recalls.waitForExistence(timeout: 10) {
            if !recalls.isHittable { app.swipeDown() }
            recalls.tap()
            sleep(6)
            snapshot("12-rappels")
            goBack(app)
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
        app.swipeUp()
        sleep(1)
        snapshot("14-ma-liste-magasins")

        // 4. Mes prix : statistiques et évolution.
        tab(app, "Mes prix")
        sleep(2)
        snapshot("15-mes-prix")

        // 5. Réglages.
        tab(app, "Réglages")
        sleep(1)
        snapshot("16-reglages")
        app.swipeUp()
        sleep(1)
        snapshot("17-reglages-suite")
    }
}
