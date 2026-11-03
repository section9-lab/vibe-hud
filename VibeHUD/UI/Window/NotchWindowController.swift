//
//  NotchWindowController.swift
//  VibeHUD
//
//  Controls the notch window positioning and lifecycle
//

import AppKit
import Combine
import SwiftUI

class NotchWindowController: NSWindowController {
    let viewModel: NotchViewModel
    private let screen: NSScreen
    private let shadowWindow: NotchShadowPanel
    private var cancellables = Set<AnyCancellable>()
    private var pendingInteractionEnable: DispatchWorkItem?


    init(screen: NSScreen, animateOnLaunch: Bool = true) {
        self.screen = screen
        self.shadowWindow = NotchShadowPanel()

        let screenFrame = screen.frame
        let notchSize = screen.notchSize

        // Window covers full width at top, tall enough for largest content (chat view)
        let windowHeight: CGFloat = 750
        let windowFrame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        // Device notch rect - positioned at center
        let deviceNotchRect = CGRect(
            x: (screenFrame.width - notchSize.width) / 2,
            y: 0,
            width: notchSize.width,
            height: notchSize.height
        )

        // Create view model
        self.viewModel = NotchViewModel(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenFrame,
            windowHeight: windowHeight,
            hasPhysicalNotch: screen.hasPhysicalNotch
        )

        // Create the window
        let notchWindow = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: notchWindow)

        // Create the SwiftUI view with pass-through hosting
        let hostingController = NotchViewController(viewModel: viewModel)
        notchWindow.contentViewController = hostingController
        shadowWindow.contentView = NSHostingView(
            rootView: NotchShadowView(viewModel: viewModel)
        )
        shadowWindow.orderOut(nil)

        notchWindow.setFrame(windowFrame, display: true)

        // Dynamically toggle mouse event handling based on notch state:
        // - Closed: ignoresMouseEvents = true (clicks pass through to menu bar/apps)
        // - Opened: ignoresMouseEvents = false (buttons inside panel work)
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] status in
                guard let self else { return }
                self.pendingInteractionEnable?.cancel()
                self.pendingInteractionEnable = nil

                switch status {
                case .opened:
                    // The passive full-width window ignores input while SwiftUI
                    // performs its rounded-corner spring. Shrink only after the
                    // animation settles, then make the visible HUD interactive.
                    notchWindow?.ignoresMouseEvents = true
                    let enableInteraction = DispatchWorkItem { [weak self, weak notchWindow, weak viewModel] in
                        guard let self, let notchWindow, let viewModel,
                              viewModel.status == .opened else { return }
                        self.pendingInteractionEnable = nil
                        let panelFrame = viewModel.geometry.interactionWindowFrame(
                            for: viewModel.openedWindowSize
                        )
                        notchWindow.setFrame(panelFrame, display: true)
                        notchWindow.ignoresMouseEvents = false
                        self.showShadow(around: panelFrame, below: notchWindow)
                        // Don't steal focus when opened by notification (task finished)
                        if viewModel.openReason != .notification {
                            NSApp.activate(ignoringOtherApps: false)
                            notchWindow.makeKey()
                        }
                    }
                    self.pendingInteractionEnable = enableInteraction
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + NotchTransitionTiming.openingDuration,
                        execute: enableInteraction
                    )

                case .closed, .popping:
                    // Stop intercepting first, then restore the passive full-width
                    // canvas used to center closed-notch animations.
                    notchWindow?.ignoresMouseEvents = true
                    self.hideShadow(from: notchWindow)
                    notchWindow?.setFrame(windowFrame, display: true)
                }
            }
            .store(in: &cancellables)

        // Content and menu heights can change while the HUD is open. Resize the
        // panel after @Published values commit so its hit region stays accurate.
        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] in
                DispatchQueue.main.async {
                    guard let self, self.pendingInteractionEnable == nil,
                          let notchWindow, let viewModel, viewModel.status == .opened else { return }
                    let panelFrame = viewModel.geometry.interactionWindowFrame(
                        for: viewModel.openedWindowSize
                    )
                    guard notchWindow.frame != panelFrame else { return }
                    self.hideShadow(from: notchWindow)
                    notchWindow.setFrame(panelFrame, display: true)
                    self.showShadow(around: panelFrame, below: notchWindow)
                }
            }
            .store(in: &cancellables)

        // Start with ignoring mouse events (closed state)
        notchWindow.ignoresMouseEvents = true

        // Perform boot animation after a brief delay (only on initial launch)
        if animateOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.viewModel.performBootAnimation()
            }
        }
    }

    private func showShadow(around panelFrame: CGRect, below notchWindow: NSWindow) {
        shadowWindow.setFrame(
            NotchShadowMetrics.windowFrame(around: panelFrame),
            display: true
        )
        if shadowWindow.parent !== notchWindow {
            shadowWindow.orderFront(nil)
            notchWindow.addChildWindow(shadowWindow, ordered: .below)
        }
    }

    private func hideShadow(from notchWindow: NSWindow?) {
        if let notchWindow, shadowWindow.parent === notchWindow {
            notchWindow.removeChildWindow(shadowWindow)
        }
        shadowWindow.orderOut(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pendingInteractionEnable?.cancel()
        shadowWindow.orderOut(nil)
    }
}
