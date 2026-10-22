enum DemoScenario: String, CaseIterable, Equatable {
    case charging
    case battery
    case draining
    case desktop

    static let `default` = DemoScenario.charging
}
