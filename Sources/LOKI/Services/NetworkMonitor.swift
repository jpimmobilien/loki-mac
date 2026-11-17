import Foundation
import Network

/// Netzstatus für die Offline-Anzeige. LOKI braucht Internet nur für Modell-Downloads,
/// die der Nutzer selbst startet – alle Grundfunktionen laufen offline.
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnline = true
    @Published private(set) var interfaceName = ""

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "loki.network")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let name: String
            if path.usesInterfaceType(.wifi) { name = "WLAN" }
            else if path.usesInterfaceType(.wiredEthernet) { name = "Ethernet" }
            else if online { name = "Netzwerk" }
            else { name = "" }
            Task { @MainActor in
                self?.isOnline = online
                self?.interfaceName = name
            }
        }
        monitor.start(queue: queue)
    }

    var statusText: String { isOnline ? "Online · lokal" : "Offline · lokal" }
}
