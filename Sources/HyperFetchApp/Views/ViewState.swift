//
//  ViewState.swift
//  HyperFetchApp
//

import SwiftUI

/// A property wrapper that wraps `SwiftUI.State` struct directly without invoking
/// the Swift compiler `SwiftUIMacros` macro plugin.
@propertyWrapper
public struct ViewState<Value>: DynamicProperty {
    private var state: SwiftUI.State<Value>

    public init(wrappedValue: Value) {
        self.state = SwiftUI.State(initialValue: wrappedValue)
    }

    public var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }

    public var projectedValue: Binding<Value> {
        state.projectedValue
    }
}
