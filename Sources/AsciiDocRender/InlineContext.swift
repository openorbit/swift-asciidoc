
import Foundation

public struct InlineContext {
    public var sourceURL: URL?
    
    public init(sourceURL: URL? = nil) {
        self.sourceURL = sourceURL
    }
}
