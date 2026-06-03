import Foundation
import SwiftUI
import Combine

struct MathKeyboardLayout: Decodable {
    let name: String
    let sourceURL: String
    let stackExchangeURL: String
    let iconName: String?
    let layers: [MathKeyboardLayer]
    let deadKeys: [MathDeadKey]

    var defaultLayerID: String {
        if layers.contains(where: { $0.id == "option" }) {
            return "option"
        }
        return layers.first?.id ?? "default"
    }
}

struct MathKeyboardLayer: Decodable, Identifiable {
    let id: String
    let title: String
    let rows: [[MathKeyboardKey]]
}

struct MathKeyboardKey: Decodable, Identifiable {
    let kind: String
    let code: Int?
    let width: Double
    let label: String?
    let defaultLegend: String?
    let shiftLegend: String?
    let output: String?
    let note: String?
    let deadState: String?

    var id: String {
        if let code {
            return "\(kind)-\(code)"
        }
        return "\(kind)-\(label ?? UUID().uuidString)"
    }

    var isFixed: Bool {
        kind == "fixed"
    }

    var isDeadKey: Bool {
        deadState != nil
    }
}

struct MathDeadKey: Decodable, Identifiable {
    let shortcut: String
    let display: String
    let state: String
    let description: String
    let examples: String

    var id: String { shortcut }
}

@MainActor
final class MathKeyboardStore: ObservableObject {
    @Published private(set) var layout: MathKeyboardLayout?
    @Published private(set) var errorMessage: String?

    init() {
        load()
    }

    func load() {
        do {
            guard let url = Bundle.main.url(forResource: "MathUnicodeLayout", withExtension: "json") else {
                errorMessage = "MathUnicodeLayout.json is missing from the app bundle."
                return
            }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            layout = try decoder.decode(MathKeyboardLayout.self, from: data)
            errorMessage = nil
        } catch {
            errorMessage = "Unable to load the keyboard layout: \(error.localizedDescription)"
        }
    }
}
