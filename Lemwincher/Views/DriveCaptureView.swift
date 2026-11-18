import SwiftUI
import WebKit

/// Navigateur de l'app, avec la lecture des prix : il garde la page web et reçoit l'avancement
/// de la lecture (« 156 produits lus ») envoyé par le script.
final class CaptureSession: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    @Published var running = false
    @Published var count = 0

    /// `viewport` : taille de la page pour une lecture invisible (mise à jour automatique des rayons suivis).
    init(viewport: CGRect = .zero) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Intermédiaire « faible » : sinon la page web garderait la session en vie (et inversement).
        let relay = WeakScriptRelay()
        configuration.userContentController.add(relay, name: "lemwincher")
        webView = WKWebView(frame: viewport, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        relay.target = self
    }

    // MARK: Lecture invisible d'une page (rayons suivis)

    private var loadCompletion: ((Bool) -> Void)?

    /// Charge une page sans l'afficher ; `completion` une seule fois (chargée, échec ou 30 s écoulées).
    func load(_ url: URL, completion: @escaping (Bool) -> Void) {
        loadCompletion = completion
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.finishLoad(false)
        }
    }

    private func finishLoad(_ ok: Bool) {
        guard let completion = loadCompletion else { return }
        loadCompletion = nil
        completion(ok)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoad(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoad(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoad(false)
    }

    /// Charge la page, laisse le site afficher ses produits (3 s), puis lit tout ce qu'elle contient.
    @MainActor
    func capture(url: URL, maxMs: Int) async -> String {
        await withCheckedContinuation { continuation in
            load(url) { [weak self] ok in
                guard let self, ok else {
                    continuation.resume(returning: "[]")
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.start(script: DriveCaptureParser.captureScript(maxMs: maxMs)) { json in
                        continuation.resume(returning: json)
                    }
                }
            }
        }
    }

    /// Lecture en cours : identifiant (une réponse tardive d'une lecture précédente est ignorée) et suite.
    private var token = 0
    private var onDone: ((String) -> Void)?

    /// Lance la lecture complète. Le script renvoie le résultat par message (« done ») :
    /// `evaluateJavaScript` ne sait pas attendre une promesse, et `callAsyncJavaScript` a besoin d'une
    /// bibliothèque Swift absente d'iOS 17 / 18 (l'app ne démarrait plus).
    func start(script: String, completion: @escaping (String) -> Void) {
        token += 1
        let current = token
        count = 0
        running = true
        onDone = { [weak self] json in
            guard let self, self.token == current, self.running else { return }
            self.running = false
            completion(json)
        }
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if error != nil { self?.onDone?("[]") }
        }
        // Filet de sécurité : la page a pu changer pendant la lecture (le script ne répondrait jamais).
        DispatchQueue.main.asyncAfter(deadline: .now() + 100) { [weak self] in
            guard let self, self.token == current, self.running else { return }
            self.collectPartial()
        }
    }

    /// Arrête la lecture : le script rend ce qu'il a déjà lu (sinon on le lui demande).
    func stop() {
        webView.evaluateJavaScript("window.__lemwincherStop = true;")
        let current = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.token == current, self.running else { return }
            self.collectPartial()
        }
    }

    private func collectPartial() {
        webView.evaluateJavaScript("JSON.stringify(window.__lemwincherOut || [])") { [weak self] result, _ in
            self?.onDone?(result as? String ?? "[]")
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if let count = body["count"] as? Int {
            DispatchQueue.main.async { self.count = count }
        }
        if let json = body["done"] as? String {
            DispatchQueue.main.async { self.onDone?(json) }
        }
    }
}

private final class WeakScriptRelay: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Navigateur intégré sur le site d'une enseigne (ou d'un magasin) : on y parcourt les rayons ou on cherche
/// un produit, puis l'app lit TOUS les produits et leurs prix (« Voir plus » et pages suivantes compris).
struct DriveCaptureView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let query: String
    /// Page à ouvrir d'abord (les rayons de l'enseigne, le site du magasin) plutôt que la recherche.
    let startURL: URL?
    /// Magasin d'où l'on vient (carte, fiche) : proposé d'office pour enregistrer les prix.
    let store: Store?
    /// Site propre d'un magasin (hors enseignes connues), ajouté en tête de la barre.
    let customSite: DriveSite?

    @State private var site: DriveSite
    @StateObject private var session = CaptureSession()
    @State private var didLoad = false
    /// Prix lus sur la page, transmis tels quels à la feuille de vérification
    /// (avec `sheet(isPresented:)`, la feuille pouvait s'ouvrir avec une liste encore vide).
    @State private var review: CaptureBatch?
    @State private var message: String? = nil

    struct CaptureBatch: Identifiable {
        let id = UUID()
        let items: [CapturedPrice]
        let site: DriveSite
        let store: Store?
        /// Page lue (rayon, recherche) : gardée en mémoire pour être relue automatiquement.
        let pageURL: URL?
        let pageTitle: String?
    }

    init(query: String, preferredChain: String? = nil, startURL: URL? = nil, store: Store? = nil,
         customSite: DriveSite? = nil) {
        self.query = query
        self.startURL = startURL
        self.store = store
        self.customSite = customSite
        let preferred = DriveSite.all.first { site in
            guard let preferredChain else { return false }
            return preferredChain.hasPrefix(site.chainPrefix)
        }
        _site = State(initialValue: customSite ?? preferred ?? DriveSite.all[1])
    }

    private var sites: [DriveSite] {
        (customSite.map { [$0] } ?? []) + DriveSite.all
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                siteBar
                if site.choosesStore {
                    // Drives (Leclerc, Carrefour, Auchan, Intermarché, U…) : pas de prix tant qu'aucun magasin n'est choisi.
                    Label("Choisissez d'abord votre magasin sur le site (une seule fois) : ses prix s'affichent ensuite.",
                          systemImage: "storefront")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                }
                WebView(webView: session.webView)
                    .overlay(alignment: .bottom) {
                        if session.running { progressCard }
                    }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.white)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                }
            }
            .navigationTitle(site.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        session.stop()
                        dismiss()
                    }
                }
                // Le titre est un menu : changer d'enseigne d'un geste, même celles hors de la barre.
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(sites) { item in
                            Button {
                                site = item
                            } label: {
                                if item == site {
                                    Label(item.name, systemImage: "checkmark")
                                } else {
                                    Text(item.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(site.name).font(.headline).lineLimit(1)
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                    .accessibilityIdentifier("sitePicker")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        session.webView.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Page précédente")
                    Button {
                        session.webView.goForward()
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .accessibilityLabel("Page suivante")
                    Spacer()
                    Button {
                        session.webView.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Recharger")
                    Spacer()
                    Button {
                        capture()
                    } label: {
                        Label("Capturer les prix de la page", systemImage: "text.viewfinder")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.running)
                }
            }
            .sheet(item: $review) { batch in
                CaptureReviewView(items: batch.items, site: batch.site, preferredStore: batch.store,
                                  pageURL: batch.pageURL, pageTitle: batch.pageTitle) {
                    dismiss()
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                if let startURL {
                    session.webView.load(URLRequest(url: startURL))
                } else {
                    load()
                }
            }
            .onChange(of: site) { _, _ in load() }
        }
    }

    /// Pendant la lecture : nombre de produits déjà lus, et « Arrêter » pour vérifier ce qui est lu.
    private var progressCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("Lecture de tous les produits…")
                    .font(.subheadline.weight(.semibold))
                Text(session.count == 1 ? "1 produit lu" : "\(session.count) produits lus")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Arrêter") { session.stop() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("stopCapture")
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(12)
        .accessibilityIdentifier("captureProgress")
    }

    private var siteBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sites) { item in
                        Button {
                            site = item
                        } label: {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(item == site ? Color.brand : Color(.tertiarySystemFill), in: Capsule())
                                .foregroundStyle(item == site ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .accessibilityIdentifier("site-\(item.id)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            // L'enseigne choisie reste visible (Aldi est en bout de barre).
            .onAppear { proxy.scrollTo(site.id, anchor: .center) }
            .onChange(of: site) { _, new in
                withAnimation { proxy.scrollTo(new.id, anchor: .center) }
            }
            .accessibilityIdentifier("siteBar")
        }
        .background(.bar)
    }

    /// Recherche du produit sur le site choisi (ou ses rayons / son accueil si rien n'est cherché).
    private func load() {
        message = nil
        let url = query.trimmed.isEmpty ? site.startURL : site.url(for: query)
        guard let url else { return }
        session.webView.load(URLRequest(url: url))
    }

    /// Lit tous les produits : défile, « Voir plus », pages suivantes ; « Arrêter » rend ce qui est déjà lu.
    private func capture() {
        message = nil
        session.start(script: DriveCaptureParser.fullScript) { json in
            let found = DriveCaptureParser.parse(json)
            if found.isEmpty {
                message = "Aucun prix lisible sur cette page. Ouvrez un rayon ou une recherche (choisissez votre magasin si le site le demande), puis réessayez."
                Log.warning(.sites, "Site \(site.name) : aucun prix lisible sur la page",
                            details: Fmt.join(session.webView.title, Log.describe(session.webView.url))
                                + "\nRéponse du script : \(String(json.prefix(200)))")
            } else {
                Log.info(.sites, "Site \(site.name) : \(found.count) prix lus",
                         details: Log.describe(session.webView.url))
                review = CaptureBatch(items: found, site: site, store: store,
                                      pageURL: session.webView.url, pageTitle: session.webView.title)
            }
        }
    }
}

/// Vérification des prix lus avant de les ajouter à « Mes prix ».
struct CaptureReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State var items: [CapturedPrice]
    let site: DriveSite
    /// Magasin d'où l'on a ouvert le site (carte, fiche) : choisi d'office.
    let preferredStore: Store?
    let pageURL: URL?
    let pageTitle: String?
    let onSaved: () -> Void

    @State private var storeID = ""
    /// Filtre de la liste (utile quand des centaines de produits ont été lus).
    @State private var filter = ""
    /// Garder ce rayon en mémoire et le relire automatiquement.
    @State private var track = true

    init(items: [CapturedPrice], site: DriveSite, preferredStore: Store? = nil, pageURL: URL? = nil,
         pageTitle: String? = nil, onSaved: @escaping () -> Void) {
        _items = State(initialValue: items)
        self.site = site
        self.preferredStore = preferredStore
        self.pageURL = pageURL
        self.pageTitle = pageTitle
        self.onSaved = onSaved
    }

    private var storeChoices: [Store] { model.storesByDistance(including: preferredStore) }
    private var selectedStore: Store? { storeChoices.first { $0.id == storeID } }
    private var includedCount: Int { items.filter(\.include).count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Magasin", selection: $storeID) {
                        Text("Choisir…").tag("")
                        ForEach(storeChoices) { store in
                            Text(store.name).tag(store.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("Ces prix sont ceux de quel magasin ?")
                } footer: {
                    if site.choosesStore {
                        Text("Choisissez le magasin sélectionné sur le site \(site.name). Les prix en ligne peuvent différer légèrement de ceux en rayon.")
                    } else {
                        Text("Le site \(site.name) affiche les prix de l'enseigne, sans choix de magasin : indiquez celui où vous faites vos courses. Les prix en rayon peuvent différer légèrement.")
                    }
                }

                if pageURL != nil {
                    Section {
                        Toggle(isOn: $track) {
                            Label("Garder ce rayon et le mettre à jour automatiquement", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .tint(Color.brand)
                        .accessibilityIdentifier("trackPage")
                    } footer: {
                        Text("Ses produits restent dans « Mes rayons en ligne » (onglet Produits) ; leurs prix sont relus à l'ouverture de l'app, au plus toutes les 12 h, et vous êtes prévenu des baisses.")
                    }
                }

                Section {
                    ForEach($items) { $item in
                        if filter.trimmed.isEmpty || item.name.localizedCaseInsensitiveContains(filter.trimmed)
                            || (item.brand ?? "").localizedCaseInsensitiveContains(filter.trimmed) {
                        HStack(spacing: 10) {
                            Button {
                                item.include.toggle()
                            } label: {
                                Image(systemName: item.include ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.include ? Color.brand : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            ProductThumb(url: item.image, size: 36, name: item.name)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.subheadline).lineLimit(2)
                                let details = Fmt.join(item.brand, item.quantity)
                                if !details.isEmpty {
                                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                if let gtin = item.gtin, gtin.filter(\.isNumber).isBarcodeLike {
                                    Label(gtin, systemImage: "barcode").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 2) {
                                if item.promo {
                                    PromoBadge()
                                }
                                Text(Fmt.price(item.price, model.settings.currency))
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(item.promo ? Color.pink : Color.primary)
                                if let old = item.oldPrice {
                                    Text(Fmt.price(old, model.settings.currency))
                                        .font(.caption2.monospacedDigit())
                                        .strikethrough()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .fixedSize()
                        }
                        }
                    }
                } header: {
                    HStack {
                        Text("\(includedCount)/\(items.count) prix lus sur \(site.name)")
                        Spacer()
                        Button(includedCount == items.count ? "Tout décocher" : "Tout cocher") {
                            let include = includedCount != items.count
                            for index in items.indices { items[index].include = include }
                        }
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                    }
                } footer: {
                    Text("Décochez ce qui ne correspond pas. Les prix sont ajoutés à « Mes prix » pour votre usage personnel ; ils ne sont pas partagés sur Open Prices.")
                }
            }
            .navigationTitle("Prix capturés")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Filtrer les produits lus")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { save() }
                        .disabled(selectedStore == nil || includedCount == 0)
                }
            }
            .onAppear {
                guard storeID.isEmpty else { return }
                if let preferredStore {
                    storeID = preferredStore.id
                } else if let store = storeChoices.first(where: { site.matches($0) }) {
                    storeID = store.id
                }
            }
        }
    }

    /// Prix dans « Mes prix » (sans doublon : un prix inchangé est daté du jour) et, si demandé, rayon suivi.
    private func save() {
        guard let store = selectedStore else { return }
        model.recordCapture(items, site: site, store: store, pageURL: pageURL, pageTitle: pageTitle, track: track)
        dismiss()
        onSaved()
    }
}

/// WKWebView dans SwiftUI.
struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
