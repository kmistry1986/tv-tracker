import SwiftUI

struct FriendsView: View {
    @StateObject private var supabase = SupabaseService.shared
    @State private var friends: [User] = []
    @State private var friendRequests: [Friendship] = []
    @State private var isLoading = false
    @State private var selectedTab = 0
    @State private var showSearchSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Friends").tag(0)
                    Text("Requests").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                .padding(.top, -10)

                if isLoading {
                    VStack {
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else if selectedTab == 0 {
                    friendsList
                } else {
                    requestsList
                }
            }
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSearchSheet = true }) {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .onAppear {
                loadFriends()
            }
            .sheet(isPresented: $showSearchSheet) {
                SearchFriendsView(onFriendAdded: {
                    loadFriends()
                })
            }
        }
    }

    private var friendsList: some View {
        Group {
            if friends.isEmpty {
                VStack {
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No friends yet")
                        .foregroundColor(.gray)
                    Text("Search to find and add friends")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(friends, id: \.id) { friend in
                        NavigationLink(destination: FriendProfileView(userId: friend.id, userName: friend.name)) {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.blue)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(friend.name)
                                        .fontWeight(.semibold)
                                    Text(friend.email)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                removeFriend(friend.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var requestsList: some View {
        Group {
            if friendRequests.isEmpty {
                VStack {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No friend requests")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(friendRequests, id: \.id) { request in
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Friend Request")
                                    .fontWeight(.semibold)
                                Text(request.userId)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()

                            Button(action: { acceptRequest(request) }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 20))
                            }

                            Button(action: { rejectRequest(request.id) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 20))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func loadFriends() {
        guard let userId = supabase.currentUser?.id else { return }
        isLoading = true

        Task {
            do {
                async let friendsData = supabase.fetchFriends(userId: userId)
                async let requestsData = supabase.fetchFriendRequests(userId: userId)

                let (loadedFriends, loadedRequests) = await (friendsData, requestsData)

                DispatchQueue.main.async {
                    self.friends = loadedFriends
                    self.friendRequests = loadedRequests
                    self.isLoading = false
                }
            } catch {
                print("Error loading friends: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }

    private func removeFriend(_ friendId: String) {
        guard let userId = supabase.currentUser?.id else { return }

        Task {
            do {
                try await supabase.removeFriend(userId: userId, friendId: friendId)
                friends.removeAll { $0.id == friendId }
            } catch {
                print("Error removing friend: \(error)")
            }
        }
    }

    private func acceptRequest(_ request: Friendship) {
        guard let userId = supabase.currentUser?.id else { return }

        Task {
            do {
                try await supabase.acceptFriendRequest(requestId: request.id, userId: userId, friendId: request.userId)
                friendRequests.removeAll { $0.id == request.id }
                loadFriends()
            } catch {
                print("Error accepting request: \(error)")
            }
        }
    }

    private func rejectRequest(_ requestId: Int) {
        Task {
            do {
                try await supabase.rejectFriendRequest(requestId: requestId)
                friendRequests.removeAll { $0.id == requestId }
            } catch {
                print("Error rejecting request: \(error)")
            }
        }
    }
}

struct SearchFriendsView: View {
    @StateObject private var supabase = SupabaseService.shared
    @State private var searchText = ""
    @State private var results: [UserProfile] = []
    @State private var isLoading = false
    @Environment(\.dismiss) var dismiss
    var onFriendAdded: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $searchText, onSearch: performSearch)

                if isLoading {
                    VStack {
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else if results.isEmpty {
                    VStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("Search for friends")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding()
                } else {
                    List(results, id: \.id) { result in
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.displayName)
                                    .fontWeight(.semibold)
                                if let bio = result.bio {
                                    Text(bio)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Button(action: { sendRequest(result.userId) }) {
                                Image(systemName: "person.badge.plus")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 18))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Find Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }

        isLoading = true
        Task {
            do {
                results = try await supabase.searchUsers(query: searchText)
                isLoading = false
            } catch {
                print("Error searching users: \(error)")
                isLoading = false
            }
        }
    }

    private func sendRequest(_ friendId: String) {
        guard let userId = supabase.currentUser?.id else { return }

        Task {
            do {
                try await supabase.sendFriendRequest(userId: userId, friendId: friendId)
                results.removeAll { $0.userId == friendId }
                onFriendAdded()
            } catch {
                print("Error sending request: \(error)")
            }
        }
    }
}

struct FriendProfileView: View {
    let userId: String
    let userName: String
    @StateObject private var supabase = SupabaseService.shared
    @StateObject private var tmdb = TMDBService.shared
    @State private var ratings: [UserShow] = []
    @State private var isLoading = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text(userName)
                        .font(.headline)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding()

                if isLoading {
                    VStack {
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else if ratings.isEmpty {
                    VStack {
                        Text("No rated shows")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding()
                } else {
                    List(ratings, id: \.id) { rating in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show #\(rating.showId)")
                                .fontWeight(.semibold)
                            if let rating = rating.rating {
                                Text("\(String(repeating: "★", count: rating))\(String(repeating: "☆", count: 10 - rating)) \(rating)/10")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            if let review = rating.review {
                                Text(review)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("\(userName)'s Shows")
            .onAppear {
                loadRatings()
            }
        }
    }

    private func loadRatings() {
        isLoading = true
        Task {
            do {
                ratings = try await supabase.getFriendRatings(friendId: userId)
                DispatchQueue.main.async {
                    isLoading = false
                }
            } catch {
                print("Error loading friend ratings: \(error)")
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    FriendsView()
}
