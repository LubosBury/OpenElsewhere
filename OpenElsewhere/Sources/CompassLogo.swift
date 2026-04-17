import SwiftUI

/// Vector compass logo — matches the app icon. Use as a branded header element.
struct CompassLogo: View {
    var size: CGFloat = 48
    var tint: Color = .blue

    var body: some View {
        ZStack {
            // Outer circle
            Circle()
                .strokeBorder(tint.opacity(0.35), lineWidth: size * 0.04)
                .frame(width: size * 0.95, height: size * 0.95)

            // Cardinal tick marks
            ForEach(0..<4) { i in
                Rectangle()
                    .fill(tint.opacity(0.6))
                    .frame(width: size * 0.03, height: size * 0.08)
                    .offset(y: -size * 0.46)
                    .rotationEffect(.degrees(Double(i) * 90))
            }

            // Needle — NE direction, split colors
            ZStack {
                // North half (light blue)
                Triangle()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.14, height: size * 0.38)
                    .offset(y: -size * 0.19)

                // South half (dark blue)
                Triangle()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.45), tint.opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .rotationEffect(.degrees(180))
                    .frame(width: size * 0.14, height: size * 0.38)
                    .offset(y: size * 0.19)
            }
            .rotationEffect(.degrees(45))

            // Center dot
            Circle()
                .fill(tint)
                .frame(width: size * 0.1, height: size * 0.1)
                .shadow(color: tint.opacity(0.6), radius: size * 0.06)
        }
        .frame(width: size, height: size)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    HStack(spacing: 24) {
        CompassLogo(size: 32)
        CompassLogo(size: 64, tint: .cyan)
        CompassLogo(size: 96, tint: .indigo)
    }
    .padding()
    .background(.black)
}
