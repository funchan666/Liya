import Foundation
import UIKit

enum Examples {
    static let photoCount = 40
    static let videoCount = 10

    static func url(kind: String, index: Int, fileExtension ext: String) -> URL? {
        let name = String(format: "example_%@_%03d", kind, index + 1)
        return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Examples")
    }

    static func photo(_ index: Int) -> UIImage? {
        guard let url = url(kind: "photo", index: index, fileExtension: "jpg") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
