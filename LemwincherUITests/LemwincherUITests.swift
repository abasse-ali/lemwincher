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

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
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
        app.swipeDown()
        app.swipeDown()

        let fuel = element(app, "fuelLink")
        if fuel.waitForExistence(timeout: 20) {
            fuel.tap()
            _ = element(app, "fuelStationFirst").waitForExistence(timeout: 40)
            sleep(3)
            snapshot("05-carburants")
            let first = element(app, "fuelStationFirst")
            if first.exists && first.isHittable {
                first.tap()
                sleep(2)
                snapshot("06-station")
                goBack(app)
            }
            goBack(app)
        }

        let ranking = element(app, "chainRankingLink")
        if ranking.waitForExistence(timeout: 60) {
            if !ranking.isHittable { app.swipeUp() }
            ranking.tap()
            sleep(2)
            snapshot("07-classement-enseignes")
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
