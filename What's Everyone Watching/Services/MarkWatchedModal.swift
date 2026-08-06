import SwiftUI

struct MarkWatchedModal: View {
    @Environment(\.dismiss) var dismiss

    let showId: Int
    let showTitle: String
    var onSave: ([Int]) -> Void

    @State private var markAllWatched = false
    @State private var expandedSeasons = Set<Int>()
    @State private var selectedEpisodes = Set<Int>()
    @State private var selectedSeasons = Set<Int>()
    @State private var showDetails: TVShowDetail?
    @State private var isLoading = true
    @State private var seasonEpisodes: [Int: [Episode]] = [:]
    @State private var loadingSeasons = Set<Int>()

    @StateObject private var tmdb = TMDBService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let show = showDetails {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // Mark entire show as watched
                            HStack {
                                Image(systemName: markAllWatched ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 18))
                                    .foregroundColor(markAllWatched ? .blue : .gray)
                                Text("Mark entire show as watched")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                markAllWatched.toggle()
                                if markAllWatched {
                                    selectedEpisodes.removeAll()
                                    expandedSeasons.removeAll()
                                } else {
                                    selectedEpisodes.removeAll()
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)

                            Divider()
                                .padding(.vertical, 8)

                            if !markAllWatched {
                                Text("Select Seasons")
                                    .font(.headline)
                                    .padding(.horizontal)

                                // List seasons
                                VStack(spacing: 8) {
                                    ForEach(1...show.numberOfSeasons, id: \.self) { seasonNum in
                                        seasonRow(seasonNumber: seasonNum, show: show)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }

                // Save button
                HStack(spacing: 12) {
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                    }

                    Button(action: save) {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("Mark As Watched")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await loadShowDetails()
        }
    }

    @ViewBuilder
    private func seasonRow(seasonNumber: Int, show: TVShowDetail) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(expandedSeasons.contains(seasonNumber) ? 90 : 0))

                Image(systemName: selectedSeasons.contains(seasonNumber) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundColor(selectedSeasons.contains(seasonNumber) ? .blue : .gray)

                Text("Season \(seasonNumber)")
                    .fontWeight(.medium)

                Spacer()

                if loadingSeasons.contains(seasonNumber) {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    if expandedSeasons.contains(seasonNumber) {
                        expandedSeasons.remove(seasonNumber)
                    } else {
                        expandedSeasons.insert(seasonNumber)
                        // Load episodes when expanding
                        Task {
                            await loadEpisodes(for: seasonNumber)
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal)
            .background(Color(.systemGray6))
            .cornerRadius(8)

            // Toggle entire season
            HStack {
                Text("")
                Button(action: {
                    toggleSeason(seasonNumber)
                }) {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 12))
                        Text("All \(seasonEpisodes[seasonNumber]?.count ?? 0) episodes")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Expanded episodes
            if expandedSeasons.contains(seasonNumber) {
                if loadingSeasons.contains(seasonNumber) {
                    VStack {
                        ProgressView()
                            .padding()
                    }
                } else if let episodes = seasonEpisodes[seasonNumber], !episodes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(episodes, id: \.id) { episode in
                            episodeRow(episode: episode)
                        }
                    }
                    .padding(.top, 8)
                } else {
                    Text("No episodes found")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding()
                }
            }
        }
    }

    @ViewBuilder
    private func episodeRow(episode: Episode) -> some View {
        HStack {
            Image(systemName: selectedEpisodes.contains(episode.id) ? "checkmark.square.fill" : "square")
                .font(.system(size: 16))
                .foregroundColor(selectedEpisodes.contains(episode.id) ? .blue : .gray)

            VStack(alignment: .leading, spacing: 2) {
                Text("E\(episode.episodeNumber): \(episode.name)")
                    .font(.caption)
                    .lineLimit(1)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedEpisodes.contains(episode.id) {
                selectedEpisodes.remove(episode.id)
            } else {
                selectedEpisodes.insert(episode.id)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(6)
    }

    private func loadEpisodes(for seasonNumber: Int) async {
        loadingSeasons.insert(seasonNumber)
        do {
            let seasonDetail = try await tmdb.getTVSeason(showId: showId, seasonNumber: seasonNumber)
            seasonEpisodes[seasonNumber] = seasonDetail.episodes
            loadingSeasons.remove(seasonNumber)
        } catch {
            print("Error loading episodes for season \(seasonNumber): \(error)")
            loadingSeasons.remove(seasonNumber)
        }
    }

    private func toggleSeason(_ seasonNumber: Int) {
        guard let episodes = seasonEpisodes[seasonNumber] else { return }
        let seasonEpisodeIds = Set(episodes.map { $0.id })

        // Check if all episodes in season are selected
        let allSelected = seasonEpisodeIds.allSatisfy { selectedEpisodes.contains($0) }

        if allSelected {
            // Deselect all
            selectedEpisodes.subtract(seasonEpisodeIds)
            selectedSeasons.remove(seasonNumber)
        } else {
            // Select all
            selectedEpisodes.formUnion(seasonEpisodeIds)
            selectedSeasons.insert(seasonNumber)
        }
    }

    private func loadShowDetails() async {
        do {
            showDetails = try await tmdb.getTVShow(id: showId)
            isLoading = false
        } catch {
            print("Error loading show details: \(error)")
            isLoading = false
        }
    }

    private func save() {
        if markAllWatched {
            // Mark all episodes as watched
            onSave([])
        } else {
            onSave(Array(selectedEpisodes))
        }
        dismiss()
    }
}

#Preview {
    MarkWatchedModal(showId: 1399, showTitle: "Breaking Bad") { episodes in
        print("Selected episodes: \(episodes)")
    }
}
