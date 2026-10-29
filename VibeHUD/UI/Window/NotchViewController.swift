//
//  NotchViewController.swift
//  VibeHUD
//
//  Hosts the SwiftUI NotchView in AppKit with click-through support
//

import AppKit
import SwiftUI

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
    private let preferences: AppPreferences
    private let monitoringStore: MonitoringStore
    private var hostingView: PassThroughHostingView<NotchView>!

    init(viewModel: NotchViewModel,
         preferences: AppPreferences = .shared,
         monitoringStore: MonitoringStore = .shared) {
        self.viewModel = viewModel
        self.preferences = preferences
        self.monitoringStore = monitoringStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        hostingView = PassThroughHostingView(rootView: NotchView(
            viewModel: viewModel, preferences: preferences, monitoringStore: monitoringStore
        ))

        // Calculate the hit-test rect based on panel state
        hostingView.hitTestRect = { [weak self] in
            guard let self = self else { return .zero }
            let vm = self.viewModel
            let geometry = vm.geometry

            // Window coordinates: origin at bottom-left, Y increases upward
            // The window is positioned at top of screen, so panel is at top of window
            let windowHeight = geometry.windowHeight

            switch vm.status {
            case .opened:
                let panelSize = vm.openedSize
                // Panel is centered horizontally, anchored to top
                let panelWidth = panelSize.width + 52  // Account for corner radius padding
                let panelHeight = panelSize.height
                let screenWidth = geometry.screenRect.width
                return CGRect(
                    x: (screenWidth - panelWidth) / 2,
                    y: windowHeight - panelHeight,
                    width: panelWidth,
                    height: panelHeight
                )
            case .closed, .popping:
                // Match the rendered capsule, including the right-side status items.
                let rect = geometry.closedContentScreenRect(
                    leadingExtension: vm.closedLeadingExtension,
                    trailingExtension: vm.closedTrailingExtension
                )
                return CGRect(
                    x: rect.minX - geometry.screenRect.minX - 3,
                    y: windowHeight - rect.height - 5,
                    width: rect.width + 6,
                    height: rect.height + 10
                )
            }
        }

        self.view = hostingView
    }
}
