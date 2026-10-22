import SwiftUI

/// Drop-in replacement for `@State`. SwiftUI's `@State` is a macro in newer SDKs, and the
/// macro plugin isn't shipped with the Command Line Tools, so it can't be used without Xcode.
/// This is built on `@StateObject`, which is a plain property wrapper.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    private final class Box: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }

    @StateObject private var box: Box

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: Box(wrappedValue))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
}
