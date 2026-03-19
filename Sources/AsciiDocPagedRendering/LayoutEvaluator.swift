import Foundation
import AsciiDocCore

public struct XADLayoutEvaluationResult {
    public var tree: [String: Any]
    public var warnings: [AdocWarning]

    public init(tree: [String: Any], warnings: [AdocWarning]) {
        self.tree = tree
        self.warnings = warnings
    }
}

public struct XADLayoutEvaluator {
    public init() {}

    public func evaluate(
        program: LayoutProgram,
        slots: [String: [[String: Any]]],
        collections: [String: [[String: Any]]]
    ) -> XADLayoutEvaluationResult {
        var warnings: [AdocWarning] = []
        let nodes = program.expressions.compactMap { expr in
            evalExpr(expr, slots: slots, collections: collections, warnings: &warnings)
        }
        return XADLayoutEvaluationResult(
            tree: [
                "kind": "program",
                "nodes": nodes
            ],
            warnings: warnings
        )
    }

    private func evalExpr(
        _ expr: LayoutExpr,
        slots: [String: [[String: Any]]],
        collections: [String: [[String: Any]]],
        warnings: inout [AdocWarning]
    ) -> Any? {
        switch expr {
        case .node(let node):
            return evalNode(node, slots: slots, collections: collections, warnings: &warnings)
        case .value(let value):
            return evalValue(value)
        }
    }

    private func evalNode(
        _ node: LayoutNode,
        slots: [String: [[String: Any]]],
        collections: [String: [[String: Any]]],
        warnings: inout [AdocWarning]
    ) -> [String: Any] {
        let args = evalArgs(node.args, slots: slots, collections: collections, warnings: &warnings)
        let children = node.children.compactMap { evalExpr($0, slots: slots, collections: collections, warnings: &warnings) }

        switch node.name {
        case "slot":
            let name = argString(args, key: nil) ?? "main"
            return [
                "kind": "source",
                "source": "slot",
                "name": name,
                "blocks": slots[name] ?? []
            ]

        case "collect":
            let name = argString(args, key: nil) ?? ""
            return [
                "kind": "source",
                "source": "collect",
                "name": name,
                "blocks": collections[name] ?? []
            ]

        case "flow":
            var blocks: [[String: Any]] = []
            var sources: [[String: Any]] = []
            for value in args.values {
                if let extracted = extractBlocks(from: value) {
                    blocks.append(contentsOf: extracted)
                }
                if let source = extractSource(from: value) {
                    sources.append(source)
                }
            }
            for child in children {
                if let extracted = extractBlocks(from: child) {
                    blocks.append(contentsOf: extracted)
                }
                if let source = extractSource(from: child) {
                    sources.append(source)
                }
            }
            var payload: [String: Any] = [
                "kind": "flow",
                "args": args,
                "blocks": blocks,
                "children": children.filter { !isSourceNode($0) }
            ]
            if let dataSlot = singleSlotName(from: sources) {
                payload["dataSlot"] = dataSlot
            }
            if !sources.isEmpty {
                payload["sources"] = sources
            }
            return payload

        case "place":
            return [
                "kind": "place",
                "args": args,
                "children": children
            ]

        case "grid":
            return [
                "kind": "grid",
                "args": args,
                "children": children
            ]

        case "stack":
            return [
                "kind": "stack",
                "args": args,
                "children": children
            ]

        case "pages":
            return [
                "kind": "pages",
                "children": children
            ]

        case "page":
            return [
                "kind": "page",
                "args": args,
                "children": children
            ]

        case "text":
            let value = argString(args, key: nil) ?? ""
            return [
                "kind": "text",
                "text": value
            ]

        case "counter":
            return [
                "kind": "counter",
                "args": args
            ]

        case "sink":
            return [
                "kind": "sink",
                "args": args
            ]

        default:
            return [
                "kind": node.name,
                "args": args,
                "children": children
            ]
        }
    }

    private func evalArgs(
        _ args: [LayoutArg],
        slots: [String: [[String: Any]]],
        collections: [String: [[String: Any]]],
        warnings: inout [AdocWarning]
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        var positionalIndex = 0
        for arg in args {
            let value = evalExpr(arg.value, slots: slots, collections: collections, warnings: &warnings)
            if let name = arg.name, !name.isEmpty {
                result[name] = value ?? NSNull()
            } else {
                result["$\(positionalIndex)"] = value ?? NSNull()
                positionalIndex += 1
            }
        }
        return result
    }

    private func evalValue(_ value: LayoutValue) -> Any {
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            return number
        case .boolean(let bool):
            return bool
        case .null:
            return NSNull()
        case .array(let values):
            return values.map { evalValue($0) }
        case .dict(let dict):
            var out: [String: Any] = [:]
            for (key, entry) in dict {
                out[key] = evalValue(entry)
            }
            return out
        case .ref(let ref):
            var payload: [String: Any] = [
                "type": "ref",
                "parts": ref.parts
            ]
            if let index = ref.index {
                payload["index"] = evalIndex(index)
            }
            return payload
        }
    }

    private func evalIndex(_ index: LayoutIndex) -> Any {
        switch index {
        case .number(let number):
            return ["type": "number", "value": number]
        case .string(let string):
            return ["type": "string", "value": string]
        case .identifier(let ident):
            return ["type": "identifier", "value": ident]
        }
    }

    private func argString(_ args: [String: Any], key: String?) -> String? {
        if let key {
            return args[key] as? String
        }
        return args["$0"] as? String
    }

    private func isSourceNode(_ value: Any) -> Bool {
        guard let dict = value as? [String: Any] else { return false }
        return dict["kind"] as? String == "source"
    }

    private func extractBlocks(from value: Any) -> [[String: Any]]? {
        if let dict = value as? [String: Any],
           dict["kind"] as? String == "source",
           let blocks = dict["blocks"] as? [[String: Any]] {
            return blocks
        }
        return nil
    }

    private func extractSource(from value: Any) -> [String: Any]? {
        guard let dict = value as? [String: Any],
              dict["kind"] as? String == "source",
              let source = dict["source"] as? String,
              let name = dict["name"] as? String else {
            return nil
        }
        return ["source": source, "name": name]
    }

    private func singleSlotName(from sources: [[String: Any]]) -> String? {
        guard sources.count == 1,
              let source = sources.first,
              source["source"] as? String == "slot",
              let name = source["name"] as? String else {
            return nil
        }
        return name
    }
}
