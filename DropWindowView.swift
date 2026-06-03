import SwiftUI
import UniformTypeIdentifiers

struct DropWindowView: View {

    private enum Phase: Equatable {
        case ready
        case processing
        case done(String)
        case warning(String)
        case failed(String)
    }

    @State private var phase: Phase = .ready
    @State private var isTargeted = false
    @State private var generation = 0

    var body: some View {
        content
            .padding(28)
            .frame(width: 320, height: 300)
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: hoverBinding) { providers in
                handleDrop(providers)
            }
    }

    // Only show the hover highlight while we are idle and ready for a file.
    private var hoverBinding: Binding<Bool> {
        Binding(
            get: { isTargeted },
            set: { newValue in
                guard phase == .ready else { return }
                withAnimation(.easeOut(duration: 0.15)) { isTargeted = newValue }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .ready:
            dropArea

        case .processing:
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text("Cleaning metadata…")
                    .foregroundStyle(.secondary)
            }

        case .done(let message):
            VStack(spacing: 16) {
                CheckmarkView()
                Text(message).font(.headline)
            }

        case .warning(let message):
            VStack(spacing: 14) {
                CheckmarkView()
                Text("Done").font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var dropArea: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text("Drop a file here")
                .font(.headline)
            Text("Metadata is cleaned automatically")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
        )
        .scaleEffect(isTargeted ? 1.02 : 1.0)
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if phase == .processing { return false }

        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let direct = item as? URL {
                url = direct
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            guard let url else { return }
            Task { await process(url) }
        }
        return true
    }

    @MainActor
    private func process(_ url: URL) async {
        generation += 1
        let token = generation

        isTargeted = false
        withAnimation(.easeInOut(duration: 0.2)) { phase = .processing }

        // Run the actual work off the main actor so the window never freezes.
        let result = await Task.detached(priority: .userInitiated) {
            await MetadataCleanerService().clean(url: url)
        }.value

        switch result.status {
        case .success:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                phase = .done("Metadata cleaned")
            }
        case .warning(let message):
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                phase = .warning(message)
            }
        case .failure(let message):
            withAnimation(.easeInOut(duration: 0.2)) {
                phase = .failed(message)
            }
        }

        // Return to the ready state shortly after, unless a newer file took over.
        try? await Task.sleep(nanoseconds: 1_700_000_000)
        if token == generation {
            withAnimation(.easeInOut(duration: 0.25)) { phase = .ready }
        }
    }
}

// MARK: - Animated green checkmark

private struct CheckmarkView: View {
    @State private var trim: CGFloat = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.15))
                .frame(width: 84, height: 84)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            CheckShape()
                .trim(from: 0, to: trim)
                .stroke(Color.green,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .frame(width: 40, height: 30)
        }
        .frame(height: 84)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                ringScale = 1
                ringOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.45).delay(0.08)) {
                trim = 1
            }
        }
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
