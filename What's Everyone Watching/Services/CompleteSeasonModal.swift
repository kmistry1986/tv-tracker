import SwiftUI

struct CompleteSeasonModal: View {
    @Environment(\.dismiss) var dismiss

    let showId: Int
    let showTitle: String
    var watchedEpisodes: Set<Int> = []
    var episodesBySeason: [Int: [EpisodeDetail]] = [:]
    var onSave: (([Int], [Int]) -> Void)?

    @State private var selectedSeasons = Set<Int>()
    @State private var initialSelectedSeasons = Set<Int>()
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
                            Text("Select seasons to complete")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top)

                            VStack(spacing: 8) {
                                ForEach(1...show.numberOfSeasons, id: \.self) { seasonNum in
                                    HStack {
                                        Image(systemName: selectedSeasons.contains(seasonNum) ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 18))
                                            .foregroundColor(selectedSeasons.contains(seasonNum) ? .blue : .gray)

                                        Text("Season \(seasonNum)")
                                            .fontWeight(.medium)

                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedSeasons.contains(seasonNum) {
                                            selectedSeasons.remove(seasonNum)
                                        } else {
                                            selectedSeasons.insert(seasonNum)
                                        }
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
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
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(selectedSeasons.isEmpty)
                }
                .padding()
            }
            .navigationTitle("Complete Seasons")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await loadShowDetails()
        }
    }

    private func loadShowDetails() async {
        do {
            showDetails = try await tmdb.getTVShow(id: showId)

            // Pre-check seasons that are already complete
            if !episodesBySeason.isEmpty {
                for (seasonNum, episodes) in episodesBySeason {
                    let allWatched = episodes.allSatisfy { watchedEpisodes.contains($0.id) }
                    if allWatched && episodes.count > 0 {
                        selectedSeasons.insert(seasonNum)
                    }
                }
            }

            initialSelectedSeasons = selectedSeasons

            isLoading = false
        } catch {
            print("Error loading show details: \(error)")
            isLoading = false
        }
    }

    private func save() {
        // Determine which seasons were newly checked and which were unchecked
        let newlyChecked = selectedSeasons.subtracting(initialSelectedSeasons)
        let newlyUnchecked = initialSelectedSeasons.subtracting(selectedSeasons)

        onSave?(Array(newlyChecked), Array(newlyUnchecked))
        dismiss()
    }
}

#Preview {
    CompleteSeasonModal(showId: 1396, showTitle: "Breaking Bad") { watchedSeasons, unwatchedSeasons in
        print("Watched seasons: \(watchedSeasons), Unwatched seasons: \(unwatchedSeasons)")
    }
}
