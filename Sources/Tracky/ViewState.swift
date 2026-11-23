import SwiftUI

/// Drop-in for `@State`. On the macOS 27 SDK `@State` is a macro whose plugin ships only with Xcode,
/// so this wraps `State` directly to build with the Command Line Tools alone.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let state: State<Value>
    init(wrappedValue: Value) { state = State(initialValue: wrappedValue) }
    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }
    var projectedValue: Binding<Value> { state.projectedValue }
}
