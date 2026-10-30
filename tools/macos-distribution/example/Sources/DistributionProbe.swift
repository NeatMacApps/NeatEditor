import Foundation

#if DIRECT_DISTRIBUTION && APP_STORE
#error("Select exactly one distribution channel")
#elseif DIRECT_DISTRIBUTION
import Sparkle
#elseif !APP_STORE
#error("A distribution channel must be selected")
#endif

/// Non-UI verification fixture, not an app template or an updater implementation.
@main
enum DistributionProbe {
    static func main() {
        #if DIRECT_DISTRIBUTION
        let updater = String(reflecting: SPUStandardUpdaterController.self)
        #else
        let updater = "App Store"
        #endif
        let channel = Bundle.main.object(forInfoDictionaryKey: "DistributionChannel") as? String ?? "missing"
        print("channel=\(channel) updater=\(updater)")
    }
}
