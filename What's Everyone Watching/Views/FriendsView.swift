import SwiftUI

struct FriendsView: View {
    @StateObject private var supabase = SupabaseService.shared
    @State private var friends: [User] = []
    @State private var friendRequests: [Friendship] = []
    @State private var isLoading = false
    @State private var selectedTab = 0
    @State private var showSearchSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("FRIENDS").displayTitle(40)
                Spacer()
                Button(action: { showSearchSheet = true }) {
                    Text("Find").label(11).foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.lg)
            
            // Segmented control
            RuledSegmented(options: ["Friends", "Requests"], selection: $selectedTab)
                .padding(.horizontal, Theme.gutter)
            
            Rule(strong: true)
            
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
        .background(Theme.ground)
        .onAppear {
            loadFriends()
        }
        .sheet(isPresented: $showSearchSheet) {
            SearchFriendsView(onFriendAdded: {
                loadFriends()
            })
        }
    }

    private var friendsList: some View {
        Group {
            if friends.isEmpty {
                VStack(spacing: Theme.Space.lg) {
                    Spacer().frame(height: 60)
                    Text("NO FRIENDS YET").headline(18).foregroundStyle(Theme.inkMuted)
                    Text("Search to find and add friends")
                        .bodyCopy(13)
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.gutter)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(friends.indices, id: \.self) { index in
                            let friend = friends[index]
                            
                            NavigationLink(destination: FriendProfileView(userId: friend.id, userName: friend.name)) {
                                HStack(spacing: Theme.Space.md) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(friend.name)
                                            .headline(17)
                                            .foregroundStyle(Theme.ink)
                                        Text(friend.email)
                                            .label(10)
                                            .foregroundStyle(Theme.inkMuted)
                                    }
                                    Spacer()
                                    Text("→")
                                        .font(Theme.heavy(17))
                                        .foregroundStyle(Theme.inkMuted)
                                }
                                .padding(.horizontal, Theme.gutter)
                                .padding(.vertical, Theme.Space.lg)
                                .background(Theme.ground)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    removeFriend(friend.id)
                                } label: {
                                    Text("Remove")
                                }
                            }
                            
                            if index < friends.count - 1 {
                                Rule().padding(.horizontal, Theme.gutter)
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
                VStack(spacing: Theme.Space.lg) {
                    Spacer().frame(height: 60)
                    Text("NO REQUESTS").headline(18).foregroundStyle(Theme.inkMuted)
                    Text("Requests from other users will appear here")
                        .bodyCopy(13)
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.gutter)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(friendRequests.indices, id: \.self) { index in
                            let request = friendRequests[index]
                            
                            FriendRequestRow(
                                request: request,
                                onAccept: { acceptRequest(request) },
                                onReject: { rejectRequest(request.id) }
                            )
                            
                            if index < friendRequests.count - 1 {
                                Rule().padding(.horizontal, Theme.gutter)
                            }
                        }
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
                async let friendsData = try supabase.fetchFriends(userId: userId)
                async let requestsData = try supabase.fetchFriendRequests(userId: userId)

                let (loadedFriends, loadedRequests) = try await (friendsData, requestsData)

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
    @State private var sentRequests: Set<String> = []
    @Environment(\.dismiss) var dismiss
    var onFriendAdded: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("FIND FRIENDS").displayTitle(32)
                Spacer()
                Button(action: { dismiss() }) {
                    Text("Done").label(11).foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.lg)
            
            // Search box
            HStack(spacing: Theme.Space.sm) {
                TextField("Search by username", text: $searchText)
                    .font(Theme.body(15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { performSearch() }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        results = []
                    }) {
                        Text("×").font(Theme.heavy(24)).foregroundStyle(Theme.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Space.md)
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, Theme.Space.lg)
            
            Rule(strong: true)

            if isLoading {
                VStack {
                    ProgressView()
                        .padding()
                    Spacer()
                }
            } else if results.isEmpty && !searchText.isEmpty {
                VStack(spacing: Theme.Space.lg) {
                    Spacer().frame(height: 60)
                    Text("NO USERS FOUND").headline(18).foregroundStyle(Theme.inkMuted)
                    Text("Try a different username")
                        .bodyCopy(13)
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                }
            } else if results.isEmpty {
                VStack(spacing: Theme.Space.lg) {
                    Spacer().frame(height: 60)
                    Text("SEARCH FOR FRIENDS").headline(18).foregroundStyle(Theme.inkMuted)
                    Text("Enter a username to get started")
                        .bodyCopy(13)
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(results.indices, id: \.self) { index in
                            let result = results[index]
                            
                            HStack(alignment: .top, spacing: Theme.Space.md) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(result.displayName)
                                        .headline(17)
                                        .foregroundStyle(Theme.ink)
                                    
                                    if let bio = result.bio, !bio.isEmpty {
                                        Text(bio)
                                            .bodyCopy(13)
                                            .foregroundStyle(Theme.inkMuted)
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                
                                Spacer()
                                
                                if sentRequests.contains(result.userId) {
                                    Text("SENT")
                                        .label(9)
                                        .foregroundStyle(Theme.inkMuted)
                                } else {
                                    Button(action: { sendRequest(result.userId) }) {
                                        Text("Add")
                                            .label(10)
                                            .foregroundStyle(Theme.accent)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Theme.gutter)
                            .padding(.vertical, Theme.Space.lg)
                            
                            if index < results.count - 1 {
                                Rule().padding(.horizontal, Theme.gutter)
                            }
                        }
                    }
                }
            }
        }
        .background(Theme.ground)
        .onChange(of: searchText) {
            if searchText.isEmpty {
                results = []
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
                let allResults = try await supabase.searchUsers(query: searchText)
                // Filter out current user
                let filteredResults = allResults.filter { $0.userId != supabase.currentUser?.id }
                
                DispatchQueue.main.async {
                    self.results = filteredResults
                    self.isLoading = false
                }
            } catch {
                print("Error searching users: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }

    private func sendRequest(_ friendId: String) {
        guard let userId = supabase.currentUser?.id else { return }

        Task {
            do {
                try await supabase.sendFriendRequest(userId: userId, friendId: friendId)
                
                DispatchQueue.main.async {
                    sentRequests.insert(friendId)
                    onFriendAdded()
                }
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
    @State private var ratedShows: [UserShow] = []
    @State private var ratedMovies: [UserMovie] = []
    @State private var recentEpisodes: [Episode] = []
    @State private var isLoading = false
    @State private var selectedTab = 0
    @State private var showStats = FriendStats()
    
    struct FriendStats {
        var totalShows = 0
        var totalMovies = 0
        var totalEpisodes = 0
        var ratedCount = 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with stats
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(userName)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("\(showStats.totalShows + showStats.totalMovies) items watched")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                
                // Stats Cards
                HStack(spacing: 12) {
                    StatCard(icon: "tv", title: "Shows", value: "\(showStats.totalShows)", color: .blue)
                    StatCard(icon: "film", title: "Movies", value: "\(showStats.totalMovies)", color: .purple)
                    StatCard(icon: "star.fill", title: "Rated", value: "\(showStats.ratedCount)", color: .orange)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .background(Color(.systemGray6))
            
            // Tab selector
            Picker("", selection: $selectedTab) {
                Text("Shows").tag(0)
                Text("Movies").tag(1)
                Text("Recent").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            if isLoading {
                VStack {
                    ProgressView()
                        .padding()
                    Spacer()
                }
            } else {
                if selectedTab == 0 {
                    showsList
                } else if selectedTab == 1 {
                    moviesList
                } else {
                    recentEpisodesList
                }
            }
        }
        .navigationTitle(userName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadFriendData()
        }
    }
    
    private var showsList: some View {
        Group {
            if ratedShows.isEmpty {
                VStack {
                    Image(systemName: "tv")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No shows yet")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(ratedShows, id: \.id) { show in
                        ShowRatingRow(show: show)
                    }
                }
            }
        }
    }
    
    private var moviesList: some View {
        Group {
            if ratedMovies.isEmpty {
                VStack {
                    Image(systemName: "film")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No movies yet")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(ratedMovies, id: \.id) { movie in
                        MovieRatingRow(movie: movie)
                    }
                }
            }
        }
    }
    
    private var recentEpisodesList: some View {
        Group {
            if recentEpisodes.isEmpty {
                VStack {
                    Image(systemName: "clock")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No recent activity")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(recentEpisodes.prefix(20), id: \.id) { episode in
                        RecentEpisodeRow(episode: episode)
                    }
                }
            }
        }
    }

    private func loadFriendData() {
        isLoading = true
        Task {
            do {
                async let shows = supabase.fetchUserShows(userId: userId)
                async let movies = supabase.fetchUserMovies(userId: userId)
                async let episodes = supabase.fetchUserEpisodes(userId: userId)
                
                let (loadedShows, loadedMovies, loadedEpisodes) = try await (shows, movies, episodes)
                
                DispatchQueue.main.async {
                    self.ratedShows = loadedShows
                    self.ratedMovies = loadedMovies
                    self.recentEpisodes = loadedEpisodes
                    
                    self.showStats = FriendStats(
                        totalShows: loadedShows.count,
                        totalMovies: loadedMovies.count,
                        totalEpisodes: loadedEpisodes.count,
                        ratedCount: loadedShows.filter { $0.rating != nil }.count + loadedMovies.filter { $0.rating != nil }.count
                    )
                    
                    self.isLoading = false
                }
            } catch {
                print("Error loading friend data: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ShowRatingRow: View {
    let show: UserShow
    @StateObject private var tmdb = TMDBService.shared
    @State private var showTitle = ""
    @State private var posterUrl: String?
    
    var body: some View {
        HStack(spacing: 12) {
            if let urlString = posterUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.gray
                }
                .frame(width: 50, height: 75)
                .cornerRadius(6)
            } else {
                Color.gray
                    .frame(width: 50, height: 75)
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(showTitle.isEmpty ? "Loading..." : showTitle)
                    .fontWeight(.semibold)
                
                if let rating = show.rating {
                    HStack(spacing: 2) {
                        ForEach(0..<rating, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.caption2)
                        }
                        ForEach(rating..<10, id: \.self) { _ in
                            Image(systemName: "star")
                                .font(.caption2)
                        }
                    }
                    .foregroundColor(.orange)
                }
                
                if let review = show.review, !review.isEmpty {
                    Text(review)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .onAppear {
            loadShowDetails()
        }
    }
    
    private func loadShowDetails() {
        Task {
            do {
                let details = try await tmdb.getTVShow(id: show.showId)
                showTitle = details.name
                posterUrl = details.posterPath.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
            } catch {
                showTitle = "Show #\(show.showId)"
            }
        }
    }
}

struct MovieRatingRow: View {
    let movie: UserMovie
    @StateObject private var tmdb = TMDBService.shared
    @State private var movieTitle = ""
    @State private var posterUrl: String?
    
    var body: some View {
        HStack(spacing: 12) {
            if let urlString = posterUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.gray
                }
                .frame(width: 50, height: 75)
                .cornerRadius(6)
            } else {
                Color.gray
                    .frame(width: 50, height: 75)
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(movieTitle.isEmpty ? "Loading..." : movieTitle)
                    .fontWeight(.semibold)
                
                if let rating = movie.rating {
                    HStack(spacing: 2) {
                        ForEach(0..<rating, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.caption2)
                        }
                        ForEach(rating..<10, id: \.self) { _ in
                            Image(systemName: "star")
                                .font(.caption2)
                        }
                    }
                    .foregroundColor(.orange)
                }
                
                if let review = movie.review, !review.isEmpty {
                    Text(review)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .onAppear {
            loadMovieDetails()
        }
    }
    
    private func loadMovieDetails() {
        Task {
            do {
                let details = try await tmdb.getMovie(id: movie.movieId)
                movieTitle = details.title
                posterUrl = details.posterPath.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
            } catch {
                movieTitle = "Movie #\(movie.movieId)"
            }
        }
    }
}

struct RecentEpisodeRow: View {
    let episode: Episode
    @StateObject private var tmdb = TMDBService.shared
    @State private var showTitle = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(showTitle.isEmpty ? "Loading..." : showTitle)
                .fontWeight(.semibold)
            
            HStack {
                Text("S\(episode.seasonNumber)E\(episode.episodeNumber)")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text(episode.name)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            if let watchedAt = episode.watchedAt {
                Text(formatDate(watchedAt))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            loadShowTitle()
        }
    }
    
    private func loadShowTitle() {
        Task {
            do {
                let details = try await tmdb.getTVShow(id: episode.showId)
                showTitle = details.name
            } catch {
                showTitle = episode.showTitle ?? "Show #\(episode.showId)"
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

// MARK: - Friend Request Row

struct FriendRequestRow: View {
    let request: Friendship
    let onAccept: () -> Void
    let onReject: () -> Void
    @StateObject private var supabase = SupabaseService.shared
    @State private var userName = "User"
    @State private var userBio: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(userName)
                        .headline(17)
                        .foregroundStyle(Theme.ink)
                    
                    if let bio = userBio, !bio.isEmpty {
                        Text(bio)
                            .bodyCopy(13)
                            .foregroundStyle(Theme.inkMuted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Sent you a friend request")
                            .label(10)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                Spacer()
            }
            
            HStack(spacing: Theme.Space.sm) {
                Button(action: onAccept) {
                    Text("ACCEPT")
                        .label(10)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.vertical, Theme.Space.md)
                        .frame(maxWidth: .infinity)
                        .background(Theme.accent)
                }
                .buttonStyle(.plain)
                
                Button(action: onReject) {
                    Text("IGNORE")
                        .label(10)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.vertical, Theme.Space.md)
                        .frame(maxWidth: .infinity)
                        .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.Space.lg)
        .onAppear {
            loadUserInfo()
        }
    }
    
    private func loadUserInfo() {
        Task {
            do {
                let user = try await supabase.fetchUser(userId: request.userId)
                userName = user.name
                
                // Try to get user profile for bio
                if let profile = try? await supabase.getUserProfile(userId: request.userId) {
                    userBio = profile.bio
                }
            } catch {
                userName = "User"
            }
        }
    }
}

#Preview {
    FriendsView()
}
