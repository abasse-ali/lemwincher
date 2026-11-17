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

        let ranking = element(app, "chainRankingLink")
        if ranking.waitForExistence(timeout: 150) || scrollDown(until: ranking, in: app) {
            if !ranking.isHittable {
                app.collectionViews.firstMatch.swipeUp(velocity: .slow)
            }
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
