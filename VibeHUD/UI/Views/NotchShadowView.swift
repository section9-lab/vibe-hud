import SwiftUI

/// Draws the HUD silhouette and its soft shadow in a separate window that
/// ignores mouse events. This lets the shadow extend beyond the interactive
/// panel without creating a rectangular seam or swallowing outside clicks.
struct NotchShadowView: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                notchSilhouette
                    .shadow(
                        color: .black.opacity(0.42),
                        radius: 9,
                        x: 0,
                        y: 3
                    )

                // Remove the opaque source shape after its shadow is rendered.
                // The main panel is the only window that draws solid black.
                notchSilhouette
                    .blendMode(.destinationOut)
            }
            .compositingGroup()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private var notchSilhouette: some View {
        NotchShape(topCornerRadius: 19, bottomCornerRadius: 24)
            .fill(.black)
            .frame(
                width: viewModel.openedWindowSize.width,
                height: viewModel.openedWindowSize.height
            )
    }
}
