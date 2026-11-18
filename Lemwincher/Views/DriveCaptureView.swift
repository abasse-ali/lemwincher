import SwiftUI
import WebKit

/// Navigateur intégré sur le site drive d'une enseigne : l'utilisateur cherche son produit
/// (et choisit son magasin sur le site), puis l'app lit les prix affichés sur la page.
struct DriveCaptureView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let query: String
    @State private var site: DriveSite
    @State private var webView = DriveCaptureView.makeWebView()
    @State private var captured: [CapturedPrice] = []
    @State private var showReview = false
    @State private var message: String? = nil

    init(query: String, preferredChain: String? = nil) {
        self.query = query
        let preferred = DriveSite.all.first { site in
            guard let preferredChain else { return false }
            return preferredChain.hasPrefix(site.chainPrefix)
        }
        _site = State(initialValue: preferred ?? DriveSite.all[1])
    }

    private static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        return view
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                siteBar
                if site.choosesStore {
                    // Drives (Leclerc, Carrefour, Auchan, Intermarché, U) : pas de prix tant qu'aucun magasin n'est choisi.
                    Label("Choisissez d'abord votre magasin sur le site (une seule fois) : ses prix s'affichent ensuite.",
                          systemImage: "storefront")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                }
                WebView(webView: webView)
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
                    Button("Fermer") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        webView.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    Button {
                        webView.goForward()
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    Spacer()
                    Button {
                        webView.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    Spacer()
                    Button {
                        capture()
                    } label: {
                        Label("Capturer les prix de la page", systemImage: "text.viewfinder")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showReview) {
                CaptureReviewView(items: captured, site: site) {
                    dismiss()
                }
            }
            .onAppear { load() }
            .onChange(of: site) { _, _ in load() }
        }
    }

    private var siteBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DriveSite.all) { item in
                        Button {
                            site = item
                        } label: {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
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

    private func load() {
        message = nil
        guard let url = site.url(for: query) else { return }
        webView.load(URLRequest(url: url))
    }

    private func capture() {
        message = nil
        webView.evaluateJavaScript(DriveCaptureParser.script) { result, _ in
            let found = DriveCaptureParser.parse(result as? String ?? "[]")
            if found.isEmpty {
                message = "Aucun prix lisible sur cette page. Ouvrez une page de résultats ou de produit (choisissez votre magasin si le site le demande), puis réessayez."
            } else {
                captured = found
                showReview = true
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
    let onSaved: () -> Void

    @State private var storeID = ""

    init(items: [CapturedPrice], site: DriveSite, onSaved: @escaping () -> Void) {
        _items = State(initialValue: items)
        self.site = site
        self.onSaved = onSaved
    }

    private var storeChoices: [Store] { model.storesByDistance() }
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

                Section {
                    ForEach($items) { $item in
                        HStack(spacing: 10) {
                            Button {
                                item.include.toggle()
                            } label: {
                                Image(systemName: item.include ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.include ? Color.brand : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            ProductThumb(url: item.image, size: 36)
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
                            Text(Fmt.price(item.price, model.settings.currency))
                                .font(.subheadline.bold().monospacedDigit())
                                .fixedSize()
                        }
                    }
                } header: {
                    Text("\(includedCount) prix lus sur \(site.name)")
                } footer: {
                    Text("Décochez ce qui ne correspond pas. Les prix sont ajoutés à « Mes prix » pour votre usage personnel ; ils ne sont pas partagés sur Open Prices.")
                }
            }
            .navigationTitle("Prix capturés")
            .navigationBarTitleDisplayMode(.inline)
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
                if storeID.isEmpty, let store = storeChoices.first(where: { site.matches($0) }) {
                    storeID = store.id
                }
            }
        }
    }

    private func save() {
        guard let store = selectedStore else { return }
        for item in items where item.include {
            var entry = MyPrice(product: item.product, store: store, price: item.price,
                                currency: model.settings.currency, date: Date())
            entry.source = "site \(site.name)"
            model.addMyPrice(entry)
        }
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
