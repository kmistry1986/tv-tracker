//  BingeRatingSheet.swift
//  The rating modal. One required call (1–5 stars), one optional note.
//
//  Saves through the existing SupabaseService.updateRating(...), which PATCHes
//  user_shows.rating / .review for shows and user_movies.rating / .review for
//  movies. `itemId` is the DB row id (show_id or movie_id), NOT the tmdb id.

import SwiftUI

struct BingeRatingSheet: View {
    let title: String
    var posterUrl: String? = nil
    let itemId: Int
    let isMovie: Bool
    var existingRating: Int? = nil
    var existingReview: String? = nil
    var onSaved: (Int, String?) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var rating = 0
    @State private var review = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let verdicts = ["", "Didn't finish it", "Watchable", "Good", "Recommend it", "Tell everyone"]

    var body: some View {
        VStack(spacing: 0) {
            header
            BingeRule(strong: true)
            subject
            BingeRule(strong: true)
            starsSection
            BingeRule(strong: true)
            reviewSection
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BingeTheme.ground)
        .foregroundStyle(BingeTheme.ink)
        .onAppear {
            rating = existingRating ?? 0
            review = existingReview ?? ""
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Rate it").bingeDisplay(30).textCase(.uppercase)
            Spacer(minLength: 12)
            Button { dismiss() } label: {
                Text("Cancel").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                    .padding(.vertical, 10).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.top, 20).padding(.bottom, 12)
    }

    private var subject: some View {
        HStack(spacing: 14) {
            BingePoster(urlString: posterUrl, width: 56, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text(isMovie ? "Film" : "Series").bingeLabel(11)
                    .foregroundStyle(BingeTheme.inkMuted)
                Text(title).bingeHeadline(18)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
    }

    // MARK: Stars — required

    private var starsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your rating").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                Spacer()
                Text("Required").bingeLabel(11).foregroundStyle(BingeTheme.accent)
            }

            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) { rating = star }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(star <= rating ? BingeTheme.accent : BingeTheme.hairline)
                            .frame(width: 52, height: 48, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                    .accessibilityAddTraits(star == rating ? [.isButton, .isSelected] : .isButton)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text(rating == 0 ? "Pick a number — this is the part Tonight learns from."
                                 : verdicts[rating])
                    .bingeBody(13)
                    .foregroundStyle(rating == 0 ? BingeTheme.inkMuted : BingeTheme.ink)
                Spacer(minLength: 0)
                if rating > 0 {
                    Text("\(rating)/5").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
    }

    // MARK: Review — optional

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("One line for your friends").bingeLabel(11)
                    .foregroundStyle(BingeTheme.inkMuted)
                Spacer()
                Text("Optional").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
            }

            ZStack(alignment: .topLeading) {
                if review.isEmpty {
                    Text("“Episode 6 broke me. Do not start this at 11pm.”")
                        .bingeBody(14).foregroundStyle(BingeTheme.inkFaint)
                        .padding(.horizontal, 12).padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $review)
                    .bingeBody(14)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(height: 104)
            }
            .overlay(Rectangle().stroke(BingeTheme.ink, lineWidth: 1))

            Text("Reviews show up in your friends' feed under your name.")
                .bingeBody(12).foregroundStyle(BingeTheme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 16)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                Text(errorMessage).bingeBody(12).foregroundStyle(BingeTheme.accent)
            }
            Button { Task { await save() } } label: {
                HStack {
                    Text(isSaving ? "Saving…" : "Save rating")
                        .bingeHeadline(15).textCase(.uppercase)
                    Spacer(minLength: 12)
                    Text("→").bingeHeadline(15)
                }
                .padding(.horizontal, 18).padding(.vertical, 17)
                .frame(maxWidth: .infinity, minHeight: BingeTheme.minTap)
                .background(rating == 0 ? BingeTheme.hairline : BingeTheme.accent)
                .foregroundStyle(rating == 0 ? BingeTheme.inkMuted : .white)
            }
            .buttonStyle(.plain)
            .disabled(rating == 0 || isSaving)
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.top, 14).padding(.bottom, 20)
    }

    private func save() async {
        guard rating > 0, let userId = SupabaseService.shared.currentUser?.id else { return }
        isSaving = true
        errorMessage = nil
        let trimmed = review.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await SupabaseService.shared.updateRating(
                userId: userId,
                itemId: itemId,
                rating: rating,
                review: trimmed.isEmpty ? nil : trimmed,
                isMovie: isMovie)
            onSaved(rating, trimmed.isEmpty ? nil : trimmed)
            dismiss()
        } catch {
            errorMessage = "Couldn't save that. Check your connection and try again."
        }
        isSaving = false
    }
}
