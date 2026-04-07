//
//  Split.swift
//  SplitView
//
//  Created by Steven Harris on 8/9/21.
//
//  MIT License
//
//  Copyright (c) 2023 Steven G. Harris
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import SwiftUI

public struct Split<P: View, D: View, S: View>: View {
    @ViewBuilder private let primary: () -> P
    @ViewBuilder private let secondary: () -> S
    @ViewBuilder private let splitter: () -> D

    private let splitterWidth: CGFloat
    private let hideOnSide: Bool
    private let constraints: SplitConstraints
    private let onDrag: ((CGFloat) -> Void)?

    @Binding private var orientation: SplitOrientation
    @Binding private var fraction: CGFloat
    @Binding private var hiddenSide: SplitSide?

    @State private var splitterHidden = false
    @State private var constrainedFraction: CGFloat
    @State private var fullFraction: CGFloat
    @State private var oldSize: CGSize? = nil
    @State private var previousPosition: CGFloat? = nil

    public var body: some View {
        GeometryReader { geometry in
            let horizontal = orientation == .horizontal
            let size = geometry.size
            let length = horizontal ? size.width : size.height
            let breadth = horizontal ? size.height : size.width
            let hidePrimary = sideToHide() == .primary || hiddenSide == .primary
            let hideSecondary = sideToHide() == .secondary || hiddenSide == .secondary
            let minPLength = length * ((hidePrimary ? 0 : constraints.minPFraction) ?? 0)
            let minSLength = length * ((hideSecondary ? 0 : constraints.minSFraction) ?? 0)
            let pLength = max(minPLength, self.pLength(in: size))
            let sLength = max(minSLength, self.sLength(in: size))
            let spacing = self.spacing()
            let pWidth = horizontal ? max(minPLength, min(size.width - spacing, pLength - spacing / 2)) : breadth
            let pHeight = horizontal ? breadth : max(minPLength, min(size.height - spacing, pLength - spacing / 2))
            let sWidth = horizontal ? max(minSLength, min(size.width - pLength, sLength - spacing / 2)) : breadth
            let sHeight = horizontal ? breadth : max(minSLength, min(size.height - pLength, sLength - spacing / 2))
            let sOffset = horizontal ? CGSize(width: pWidth + spacing, height: 0) : CGSize(width: 0, height: pHeight + spacing)
            let dCenter = horizontal ? CGPoint(x: pWidth + spacing / 2, y: size.height / 2) : CGPoint(x: size.width / 2, y: pHeight + spacing / 2)

            ZStack(alignment: .topLeading) {
                if !hidePrimary {
                    primary()
                        .frame(width: pWidth, height: pHeight)
                }
                if !hideSecondary {
                    secondary()
                        .frame(width: sWidth, height: sHeight)
                        .offset(sOffset)
                }
                if isDraggable() {
                    splitter()
                        .position(dCenter)
                        .gesture(drag(in: size))
                }
            }
            .onChange(of: fraction) { _, newValue in
                let constrainedValue = min(1 - (constraints.minSFraction ?? 0), max((constraints.minPFraction ?? 0), newValue))
                if constrainedValue != constrainedFraction {
                    withAnimation {
                        constrainedFraction = constrainedValue
                        fullFraction = constrainedValue
                    }
                }
            }
            .task(id: geometry.size) {
                setConstrainedFraction(in: geometry.size)
            }
            .clipped()
        }
    }

    public init(
        orientation: Binding<SplitOrientation> = .constant(.horizontal),
        fraction: Binding<CGFloat> = .constant(0.5),
        hidden: Binding<SplitSide?> = .constant(nil),
        @ViewBuilder primary: @escaping () -> P,
        @ViewBuilder secondary: @escaping () -> S
    ) where D == Splitter {
        self.init(
            orientation: orientation,
            fraction: fraction,
            hidden: hidden,
            primary: primary,
            secondary: secondary,
            splitter: { Splitter(orientation: orientation) }
        )
    }

    public init(
        orientation: Binding<SplitOrientation> = .constant(.horizontal),
        fraction: Binding<CGFloat> = .constant(0.5),
        hidden: Binding<SplitSide?> = .constant(nil),
        splitterWidth: CGFloat = 2,
        hideOnSide: Bool = true,
        constraints: SplitConstraints = SplitConstraints(),
        onDrag: ((CGFloat) -> Void)? = nil,
        @ViewBuilder primary: @escaping () -> P,
        @ViewBuilder secondary: @escaping () -> S,
        @ViewBuilder splitter: @escaping () -> D
    ) {
        _orientation = orientation
        _fraction = fraction
        _hiddenSide = hidden
        self.splitterWidth = splitterWidth
        self.hideOnSide = constraints.dragToHideP || constraints.dragToHideS || hideOnSide
        self.constraints = constraints
        self.onDrag = onDrag
        self.primary = primary
        self.secondary = secondary
        self.splitter = splitter
        _constrainedFraction = State(initialValue: fraction.wrappedValue)
        _fullFraction = State(initialValue: fraction.wrappedValue)
    }

    internal func spacing() -> CGFloat {
        if splitterHidden || (hiddenSide != nil && hideOnSide) {
            return 0
        } else {
            return splitterWidth
        }
    }

    private func setConstrainedFraction(in size: CGSize) {
        guard let side = constraints.priority else {
            return
        }
        guard let oldSize else {
            self.oldSize = size
            return
        }
        let horizontal = orientation == .horizontal
        let oldLength = horizontal ? oldSize.width : oldSize.height
        let newLength = horizontal ? size.width : size.height
        let delta = newLength - oldLength
        self.oldSize = size
        if delta == 0 {
            return
        }
        let oldPLength = constrainedFraction * oldLength
        let newPLength = side == .primary ? oldPLength : oldPLength + delta
        let newFraction = newPLength / newLength
        constrainedFraction = min(1 - (constraints.minSFraction ?? 0), max((constraints.minPFraction ?? 0), newFraction))
        fraction = constrainedFraction
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { gesture in
                unhide(in: size)
                let fraction = fraction(for: gesture, in: size)
                constrainedFraction = fraction.constrained
                fullFraction = fraction.full
                splitterHidden = !isDraggable() || sideToHide() != nil
                onDrag?(constrainedFraction)
                previousPosition = orientation == .horizontal ? constrainedFraction * size.width : constrainedFraction * size.height
            }
            .onEnded { gesture in
                _ = gesture
                previousPosition = nil
                splitterHidden = false
                hiddenSide = sideToHide()
                fullFraction = constrainedFraction
                fraction = constrainedFraction
            }
    }

    private func sideToHide() -> SplitSide? {
        guard constraints.dragToHideP || constraints.dragToHideS else {
            return nil
        }
        if constraints.dragToHideP && (round(fullFraction * 1000) / 1000.0) <= (constraints.minPFraction! / 2) {
            return .primary
        } else if constraints.dragToHideS &&
                    (round((1 - fullFraction) * 1000) / 1000.0) <= (constraints.minSFraction! / 2) {
            return .secondary
        } else {
            return nil
        }
    }

    func fraction(for gesture: DragGesture.Value, in size: CGSize) -> (constrained: CGFloat, full: CGFloat) {
        let horizontal = orientation == .horizontal
        let length = horizontal ? size.width : size.height
        let splitterLocation = length * constrainedFraction
        let gestureLocation = horizontal ? gesture.location.x : gesture.location.y
        let gestureTranslation = horizontal ? gesture.translation.width : gesture.translation.height
        let delta = previousPosition == nil ? gestureTranslation : gestureLocation - previousPosition!
        let constrainedLocation = max(0, min(length, splitterLocation + delta))
        let fullFraction = constrainedLocation / length
        let constrainedFraction = min(1 - (constraints.minSFraction ?? 0), max((constraints.minPFraction ?? 0), fullFraction))
        return (constrained: constrainedFraction, full: fullFraction)
    }

    private func isDraggable() -> Bool {
        if hiddenSide == nil {
            return true
        } else if hideOnSide {
            return false
        } else if constraints.minPFraction == nil && constraints.minSFraction == nil {
            return true
        } else if hiddenSide == .primary {
            return constraints.minPFraction == nil
        } else {
            return constraints.minSFraction == nil
        }
    }

    private func unhide(in size: CGSize) {
        if hiddenSide != nil {
            let length = orientation == .horizontal ? size.width : size.height
            let pLength = self.pLength(in: size)
            constrainedFraction = pLength / length
            hiddenSide = nil
        }
    }

    private func pLength(in size: CGSize) -> CGFloat {
        let length = orientation == .horizontal ? size.width : size.height
        if let hiddenSide {
            return hiddenSide == .secondary ? length : 0
        } else if let sideToHide = sideToHide() {
            return sideToHide == .secondary ? length : 0
        } else {
            return length * constrainedFraction
        }
    }

    private func sLength(in size: CGSize) -> CGFloat {
        let length = orientation == .horizontal ? size.width : size.height
        if let hiddenSide {
            return hiddenSide == .primary ? length : 0
        } else if let sideToHide = sideToHide() {
            return sideToHide == .primary ? length : 0
        } else {
            return length - pLength(in: size)
        }
    }

    public func splitter<T>(@ViewBuilder _ splitter: @escaping () -> T) -> Split<P, T, S> where T: View {
        Split<P, T, S>(
            orientation: _orientation,
            fraction: _fraction,
            hidden: _hiddenSide,
            splitterWidth: splitterWidth,
            hideOnSide: hideOnSide,
            constraints: constraints,
            onDrag: onDrag,
            primary: primary,
            secondary: secondary,
            splitter: splitter
        )
    }

    public func constraints(
        minPFraction: CGFloat? = nil,
        minSFraction: CGFloat? = nil,
        priority: SplitSide? = nil,
        dragToHideP: Bool = false,
        dragToHideS: Bool = false
    ) -> Split<P, D, S> {
        constraints(
            SplitConstraints(
                minPFraction: minPFraction,
                minSFraction: minSFraction,
                priority: priority,
                dragToHideP: dragToHideP,
                dragToHideS: dragToHideS
            )
        )
    }

    public func constraints(_ constraints: SplitConstraints) -> Split<P, D, S> {
        Split(
            orientation: _orientation,
            fraction: _fraction,
            hidden: _hiddenSide,
            splitterWidth: splitterWidth,
            hideOnSide: hideOnSide,
            constraints: constraints,
            onDrag: onDrag,
            primary: primary,
            secondary: secondary,
            splitter: splitter
        )
    }

    public func onDrag(_ callback: ((CGFloat) -> Void)?) -> Split<P, D, S> {
        Split(
            orientation: _orientation,
            fraction: _fraction,
            hidden: _hiddenSide,
            splitterWidth: splitterWidth,
            hideOnSide: hideOnSide,
            constraints: constraints,
            onDrag: callback,
            primary: primary,
            secondary: secondary,
            splitter: splitter
        )
    }
}
