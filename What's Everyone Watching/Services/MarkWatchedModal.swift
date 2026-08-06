import SwiftUI

struct MarkWatchedModal: View {
    @Environment(\.dismiss) var dismiss

    let showId: Int
    let showTitle: String
    var onSave: ([Int]) -> Void

    @State private var markAllWatched = false
    @State private var expandedSeasons = Set<Int>()
    @State private var selectedEpisodes = Set<Int>()
    @State private var showDetails: TVShowDetail?
    @State private var isLoading = true

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

                Text("Season \(seasonNumber)")
                    .fontWeight(.medium)

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    if expandedSeasons.contains(seasonNumber) {
                        expandedSeasons.remove(seasonNumber)
                    } else {
                        expandedSeasons.insert(seasonNumber)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal)
            .background(Color(.systemGray6))
            .cornerRadius(8)

            // Expanded episodes
            if expandedSeasons.contains(seasonNumber), let episodes = getEpisodesForSeason(seasonNumber, show: show) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(episodes, id: \.id) { episode in
                        episodeRow(episode: episode)
                    }
                }
                .padding(.top, 8)
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

    private func getEpisodesForSeason(_ seasonNumber: Int, show: TVShowDetail) -> [Episode]? {
        // This would need to be fetched from TMDB
        // For now, return nil as a placeholder
        return nil
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
            // Mark all episodes as watched - would need to fetch all episodes
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
