import SwiftUI

struct WatchlistPriorityModal: View {
    @Environment(\.dismiss) var dismiss

    let showTitle: String
    let isMovie: Bool
    var onSave: (String, String?) -> Void

    @State private var selectedPriority = "medium"
    @State private var notes = ""

    let priorities = ["high", "medium", "low"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Add to Watchlist")
                    .font(.headline)
                    .padding(.top)

                VStack(alignment: .leading, spacing: 12) {
                    Text(showTitle)
                        .font(.headline)
                        .lineLimit(1)

                    Divider()

                    // Priority Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Priority")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        HStack(spacing: 8) {
                            ForEach(priorities, id: \.self) { priority in
                                Button(action: { selectedPriority = priority }) {
                                    Text(priority.capitalized)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(selectedPriority == priority ? Color.blue : Color(.systemGray5))
                                        .foregroundColor(selectedPriority == priority ? .white : .primary)
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }

                    Divider()

                    // Notes Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (Optional)")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        TextEditor(text: $notes)
                            .frame(height: 100)
                            .scrollContentBackground(.hidden)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                            .placeholder(when: notes.isEmpty) {
                                Text("Add any notes about why you want to watch this...")
                                    .foregroundColor(.gray)
                                    .padding(8)
                            }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

                Spacer()

                // Buttons
                HStack(spacing: 12) {
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }

                    Button(action: save) {
                        Text("Add to Watchlist")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func save() {
        let notesValue = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes
        onSave(selectedPriority, notesValue)
        dismiss()
    }
}

extension View {
    func placeholder<Content: View>(when shouldShow: Bool, alignment: Alignment = .leading, @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

#Preview {
    WatchlistPriorityModal(showTitle: "Breaking Bad", isMovie: false) { priority, notes in
        print("Priority: \(priority), Notes: \(notes ?? "none")")
    }
}
