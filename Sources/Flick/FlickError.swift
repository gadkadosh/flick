import Foundation

struct FlickError: LocalizedError {
    let message: String
    static func message(_ text: String) -> FlickError { FlickError(message: text) }
    var errorDescription: String? { message }
}
