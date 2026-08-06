import SwiftUI

struct ActivityFeedView: View {
    @StateObject private var supabase = SupabaseService.shared
    @State private var feedItems: [ActivityFeedItem] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView()
                } else if feedItems.isEmpty {
                    VStack {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)

                        Text("No Activity Yet")
                            .font(.headline)

                        Text("Follow friends to see their watching activity")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                } else {
                    List(feedItems) { item in
                        ActivityFeedItemRow(item: item)
                    }
                }
            }
            .navigationTitle("Activity Feed")
            .padding(.top, 10)
            .refreshable {
                await loadFeed()
            }
            .onAppear {
                Task {
                    await loadFeed()
                }
            }
        }
    }
    
    private func loadFeed() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            feedItems = try await supabase.fetchActivityFeed(userId: userId)
        } catch {
            print("Error loading feed: \(error)")
        }
    }
}

struct ActivityFeedItemRow: View {
    let item: ActivityFeedItem
    @StateObject private var supabase = SupabaseService.shared
    @State private var friendName = "Friend"
    @State private var mediaTitle = "Show"
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: actionIcon)
                        .foregroundColor(.blue)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(friendName)
                        .fontWeight(.semibold)
                    
                    Text(actionText)
                        .foregroundColor(.gray)
                }
                
                Text(mediaTitle)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(formatDate(item.createdAt))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .onAppear {
            loadActivityDetails()
        }
    }
    
    private var actionText: String {
        switch item.actionType {
        case "watched":
            return "watched"
        case "rated":
            return "rated"
        case "reviewed":
            return "reviewed"
        default:
            return "updated"
        }
    }
    
    private var actionIcon: String {
        switch item.actionType {
        case "watched":
            return "eye.fill"
        case "rated":
            return "star.fill"
        case "reviewed":
            return "bubble.right.fill"
        default:
            return "checkmark.circle.fill"
        }
    }
    
    private func loadActivityDetails() {
        Task {
            if let friendId = item.friendId {
                do {
                    let friend = try await supabase.fetchUser(userId: friendId)
                    friendName = friend.name
                } catch {
                    friendName = "Friend"
                }
            }
            
            if let episodeId = item.episodeId {
                mediaTitle = "Episode \(episodeId)"
            } else if let movieId = item.movieId {
                mediaTitle = "Movie \(movieId)"
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .short
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return dateString
    }
}

#Preview {
    ActivityFeedView()
}
