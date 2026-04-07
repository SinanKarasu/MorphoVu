//
//  Splitter.swift
//  SplitView
//
//  Created by Steven Harris on 8/18/21.
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

public struct Splitter: View {
    @Binding private var orientation: SplitOrientation

    private let color: Color
    private let inset: CGFloat
    private let width: CGFloat
    private let invisibleWidth: CGFloat

    public var body: some View {
        ZStack {
            switch orientation {
            case .horizontal:
                Color.clear
                    .frame(width: invisibleWidth)
                    .padding(0)
                RoundedRectangle(cornerRadius: width / 2)
                    .fill(color)
                    .frame(width: width)
                    .padding(EdgeInsets(top: inset, leading: 0, bottom: inset, trailing: 0))
            case .vertical:
                Color.clear
                    .frame(height: invisibleWidth)
                    .padding(0)
                RoundedRectangle(cornerRadius: width / 2)
                    .fill(color)
                    .frame(height: width)
                    .padding(EdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset))
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            #if targetEnvironment(macCatalyst) || os(macOS)
            NSCursor.pop()
            if inside {
                orientation == .horizontal ? NSCursor.resizeLeftRight.push() : NSCursor.resizeUpDown.push()
            }
            #endif
        }
    }

    public init(
        orientation: Binding<SplitOrientation>,
        color: Color = .gray,
        inset: CGFloat = 6,
        width: CGFloat = 2,
        invisibleWidth: CGFloat = 30
    ) {
        self._orientation = orientation
        self.color = color
        self.inset = inset
        self.width = width
        self.invisibleWidth = invisibleWidth
    }
}
