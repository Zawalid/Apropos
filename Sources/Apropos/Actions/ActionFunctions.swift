import Foundation

/// A Swift implementation of an action, for what a declarative backend cannot express. Returns the text to deliver, or
/// nil when the effect was the point. Throws `ActionError` (or `TextToolError`, mapped to `.invalidInput`).
public typealias ActionFunction = @Sendable (ActionInput, ActionServices) async throws -> String?

/// Functions by name, as pack files refer to them (`{ "type": "function", "name": "text.upper" }`).
public struct ActionFunctionRegistry: Sendable {
    private var functions: [String: ActionFunction]

    public init(_ functions: [String: ActionFunction] = [:]) { self.functions = functions }

    public subscript(name: String) -> ActionFunction? { functions[name] }

    public var names: Set<String> { Set(functions.keys) }

    public func adding(_ name: String, _ function: @escaping ActionFunction) -> ActionFunctionRegistry {
        var copy = self
        copy.functions[name] = function
        return copy
    }
}

extension ActionFunctionRegistry {
    /// The functions shipped with Apropos. Filled in by the built-in catalogue.
    public static var builtin: ActionFunctionRegistry { BuiltinActions.functions }
}
