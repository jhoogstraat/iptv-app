//
//  ScopedPlaceholderView.swift
//  iptv
//
//  Created by Codex on 22.02.26.
//

import SwiftUI

struct ScopedPlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.largeTitle)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
