import SwiftUI

struct StreamingPlatformSelector: View {
    @Binding var selectedPlatformIds: [Int]
    
    // Streaming platforms with their TMDB provider IDs
    let platforms: [(id: Int, name: String, icon: String, color: Color)] = [
        (8, "Netflix", "n.square.fill", .red),
        (337, "Disney+", "d.square.fill", .blue),
        (384, "HBO Max", "h.square.fill", .purple),
        (15, "Hulu", "h.square.fill", .green),
        (9, "Amazon Prime", "a.square.fill", .cyan),
        (350, "Apple TV+", "applelogo", .gray),
        (531, "Paramount+", "p.square.fill", .blue),
        (1899, "Max", "m.square.fill", .indigo),
        (372, "Peacock", "bird.fill", .orange),
        (2, "Apple iTunes", "cart.fill", .pink),
        (3, "Google Play", "play.fill", .blue),
        (29, "Vudu", "play.rectangle.fill", .red),
        (192, "YouTube", "play.circle.fill", .red),
        (105, "Crunchyroll", "play.fill", .orange),
        (188, "BritBox", "play.fill", .purple),
        (37, "Showtime", "play.fill", .black),
        (45, "Starz", "play.fill", .black),
        (505, "FuboTV", "tv.fill", .purple),
        (456, "Sling TV", "tv.fill", .blue),
        (386, "YouTube TV", "tv.fill", .red),
        (257, "Tubi", "play.fill", .gray),
        (189, "Pluto TV", "play.fill", .purple)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Streaming Platforms")
                .font(.headline)
            
            Text("Select the platforms you have access to")
                .font(.caption)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(platforms, id: \.id) { platform in
                    PlatformButton(
                        platform: platform,
                        isSelected: selectedPlatformIds.contains(platform.id),
                        action: {
                            togglePlatform(platform.id)
                        }
                    )
                }
            }
        }
    }
    
    private func togglePlatform(_ platformId: Int) {
        if let index = selectedPlatformIds.firstIndex(of: platformId) {
            selectedPlatformIds.remove(at: index)
        } else {
            selectedPlatformIds.append(platformId)
        }
    }
}

struct PlatformButton: View {
    let platform: (id: Int, name: String, icon: String, color: Color)
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: platform.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : platform.color)
                    .frame(width: 30)
                
                Text(platform.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? platform.color : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(platform.color.opacity(0.3), lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    StreamingPlatformSelector(selectedPlatformIds: .constant([8, 337]))
        .padding()
}
