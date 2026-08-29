import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension HTTPURLResponse {
    var headersDictionary: [String: String] {
        var out: [String: String] = [:]
        for (key, value) in allHeaderFields { out[String(describing: key)] = String(describing: value) }
        return out
    }
}
