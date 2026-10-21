import Foundation

struct RegistryProperties {
    static let maximumVisitedContainers = 4096

    private enum Container {
        case dictionary([String: Any])
        case array([Any])

        init?(_ value: Any) {
            switch value {
            case let dictionary as [String: Any]: self = .dictionary(dictionary)
            case let array as [Any]: self = .array(array)
            default: return nil
            }
        }
    }

    private let root: [String: Any]
    private let occurrences: [String: [Any]]

    init(_ root: [String: Any]) {
        self.root = root
        occurrences = Self.indexBreadthFirst(root)
    }

    func integer(_ key: String, preferring container: String? = nil) -> Int64? {
        values(for: key, preferring: container).lazy.compactMap(Self.integer(from:)).first
    }

    func bool(_ key: String) -> Bool? {
        values(for: key).lazy.compactMap(Self.bool(from:)).first
    }

    func string(_ key: String) -> String? {
        values(for: key).lazy.compactMap { $0 as? String }.first
    }

    func dictionaries(for key: String) -> [[String: Any]] {
        values(for: key).flatMap { value -> [[String: Any]] in
            switch Container(value) {
            case .dictionary(let dictionary)?: return [dictionary]
            case .array(let array)?: return array.compactMap { $0 as? [String: Any] }
            case nil: return []
            }
        }
    }

    static func integer(from value: Any) -> Int64? {
        switch value {
        case let number as NSNumber:
            return integer(from: number)
        case let text as String:
            return TelemetryParsers.signedInteger(from: text)
        default:
            return nil
        }
    }

    static func bool(from value: Any) -> Bool? {
        switch value {
        case let number as NSNumber:
            return number.boolValue
        case let text as String:
            switch text.lowercased() {
            case "yes", "true", "1": return true
            case "no", "false", "0": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func integer(from number: NSNumber) -> Int64? {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        if CFNumberIsFloatType(number) {
            return Int64(exactly: number.doubleValue.rounded(.towardZero))
        }
        return number.int64Value
    }

    private func values(for key: String, preferring container: String? = nil) -> [Any] {
        var found: [Any] = []
        if let own = root[key] { found.append(own) }
        if let container, let scoped = root[container] as? [String: Any], let value = scoped[key] {
            found.append(value)
        }
        found.append(contentsOf: occurrences[key] ?? [])
        return found
    }

    private static func indexBreadthFirst(_ root: [String: Any]) -> [String: [Any]] {
        var occurrences: [String: [Any]] = [:]
        var pending: [Container] = [.dictionary(root)]
        var cursor = 0
        while cursor < pending.count, cursor < maximumVisitedContainers {
            let container = pending[cursor]
            cursor += 1
            switch container {
            case .dictionary(let dictionary):
                for key in dictionary.keys.sorted() {
                    guard let value = dictionary[key] else { continue }
                    occurrences[key, default: []].append(value)
                    if let nested = Container(value) { pending.append(nested) }
                }
            case .array(let array):
                pending.append(contentsOf: array.compactMap(Container.init))
            }
        }
        return occurrences
    }
}
