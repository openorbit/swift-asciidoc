//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public struct LineOrigin: Sendable, Equatable {
    public struct Frame: Sendable, Equatable {
        public var file: String?
        public var line: Int

        public init(file: String?, line: Int) {
            self.file = file
            self.line = line
        }
    }

    public var frames: [Frame]

    public init(frames: [Frame] = []) {
        self.frames = frames
    }

    public func appending(frame: Frame) -> LineOrigin {
        var copy = frames
        copy.append(frame)
        return LineOrigin(frames: copy)
    }

    public func fileStackDescription() -> AdocFileStack? {
        let described = frames.compactMap { frame -> String? in
            guard let file = frame.file else { return nil }
            return "\(file)#\(frame.line)"
        }
        return described.isEmpty ? nil : AdocFileStack(frames: described)
    }
}

public struct PreprocessedSource: Sendable {
    public var text: String
    public var lineOrigins: [LineOrigin]

    public init(text: String, lineOrigins: [LineOrigin] = []) {
        self.text = text
        self.lineOrigins = lineOrigins
    }
}
