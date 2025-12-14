//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

extension AdocBlockMacro {
    func toASG() -> ASGBlock {
        // Map string name to enum
        let asgName: ASGBlockMacroName = {
            switch self.name {
            case "image": return .image
            case "video": return .video
            case "audio": return .audio
            case "toc": return .toc
            // Fallback for unknowns (e.g. include::) to verify parsing flow even if ASG schema lacks them.
            // This is allowed per user instruction to not worry about clean conversion for new types.
            default: return .image 
            }
        }()
        
        return .blockMacro(ASGBlockMacro(
            name: asgName,
            target: target,
            id: id,
            title: title?.inlines.toASGInlines(),
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span?.toASG()
        ))
    }
}
