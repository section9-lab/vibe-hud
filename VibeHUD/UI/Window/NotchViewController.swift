//
//  NotchViewController.swift
//  VibeHUD
//
//  Hosts the SwiftUI NotchView in AppKit with click-through support
//

import AppKit
import SwiftUI

enum NotchHitTesting {
    nonisolated static func rect(
        status: NotchStatus,
        windowBounds: CGRect,
        notchSize: CGSize
    ) -> CGRect {
        switch status {
        case .opened:
            // The interactive NSPanel is already resized to the visible HUD.
            // Accept its entire local bounds, including the right-side settings button.
            return windowBounds
        case .closed, .popping:
            return CGRect(
                x: (windowBounds.width - notchSize.width) / 2 - 10,
                y: windowBounds.height - notchSize.height - 5,
                width: notchSize.width + 20,
                height: notchSize.height + 10
            )
        }
    }
}

/// Custom NSHostingView that only accepts mouse events within the panel bounds.
/// Clicks outside the panel pass through to windows behind.
class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var hitTestRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only accept hits within the panel rect
        guard hitTestRect().contains(point) else {
            return nil  // Pass through to windows behind
        }
        return super.hitTest(point)
    }
}

class NotchViewController: NSViewController {
    private let viewModel: NotchViewModel
    private var hostingView: PassThroughHostingView<NotchView>!

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        hostingView = PassThroughHostingView(rootView: NotchView(viewModel: viewModel))

        // Calculate the hit-test rect based on panel state
        hostingView.hitTestRect = { [weak self] in
            guard let self = self else { return .zero }
            let vm = self.viewModel
            return NotchHitTesting.rect(
                status: vm.status,
                windowBounds: self.hostingView.bounds,
                notchSize: vm.geometry.deviceNotchRect.size
            )
        }

        self.view = hostingView
    }
}
