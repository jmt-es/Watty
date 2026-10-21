import XCTest

enum ArgumentDomainSandbox {
    static func install(in testCase: XCTestCase) {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        testCase.addTeardownBlock {
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain)
        }
    }
}
