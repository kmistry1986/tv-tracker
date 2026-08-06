import SwiftUI

struct RatingView: View {
    let title: String
    let mediaType: String
    let itemId: Int
    let isMovie: Bool

    @StateObject private var supabase = SupabaseService.shared
    @State private var rating: Int = 0
    @State private var review: String = ""
    @State private var isSaving = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rate & Review")
                        .font(.headline)
                    
                    Text(title)
                        .font(.body)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(spacing: 12) {
                    Text("Rating")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { star in
                            Button(action: { rating = star }) {
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.title3)
                                    .foregroundColor(star <= rating ? .yellow : .gray)
                            }
                        }
                        
                        Spacer()
                        
                        Text(rating > 0 ? "\(rating)/5" : "Not rated")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review (Optional)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    TextEditor(text: $review)
                        .frame(height: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                    
                    Button(action: saveRating) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(isSaving || rating == 0)
                }
            }
            .padding()
            .navigationTitle(mediaType)
        }
    }
    
    private func saveRating() {
        isSaving = true
        Task {
            defer { isSaving = false }

            guard let userId = supabase.currentUser?.id else {
                print("User not logged in")
                return
            }

            do {
                try await supabase.updateRating(
                    userId: userId,
                    itemId: itemId,
                    rating: rating,
                    review: review.isEmpty ? nil : review,
                    isMovie: isMovie
                )
                dismiss()
            } catch {
                print("Error saving rating: \(error)")
            }
        }
    }
}

#Preview {
    RatingView(title: "Breaking Bad", mediaType: "TV Show", itemId: 1396, isMovie: false)
}
