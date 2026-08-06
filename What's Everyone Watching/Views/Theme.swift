import SwiftUI

// MARK: - Color Theme

extension Color {
    static let theme = ColorTheme()
}

struct ColorTheme {
    // Primary Colors
    let accent = Color.blue
    let primary = Color.primary
    let secondary = Color.secondary
    
    // Background Colors
    let background = Color(.systemBackground)
    let secondaryBackground = Color(.secondarySystemBackground)
    let tertiaryBackground = Color(.tertiarySystemBackground)
    let groupedBackground = Color(.systemGroupedBackground)
    
    // UI Element Colors
    let cardBackground = Color(.systemGray6)
    let divider = Color(.separator)
    
    // Semantic Colors
    let success = Color.green
    let warning = Color.orange
    let error = Color.red
    let info = Color.blue
    
    // Content Colors
    let shows = Color.blue
    let movies = Color.purple
    let ratings = Color.orange
    let watchlist = Color.green
    
    // Text Colors
    let primaryText = Color.primary
    let secondaryText = Color.gray
    let tertiaryText = Color(.tertiaryLabel)
}

// MARK: - Typography

extension Font {
    static let theme = FontTheme()
}

struct FontTheme {
    // Titles
    let largeTitle = Font.largeTitle.weight(.bold)
    let title = Font.title.weight(.bold)
    let title2 = Font.title2.weight(.bold)
    let title3 = Font.title3.weight(.semibold)
    
    // Body
    let body = Font.body
    let bodyBold = Font.body.weight(.semibold)
    let callout = Font.callout
    
    // Supporting
    let caption = Font.caption
    let caption2 = Font.caption2
    let footnote = Font.footnote
}

// MARK: - Spacing

extension CGFloat {
    static let theme = SpacingTheme()
}

struct SpacingTheme {
    let xxxSmall: CGFloat = 2
    let xxSmall: CGFloat = 4
    let xSmall: CGFloat = 6
    let small: CGFloat = 8
    let medium: CGFloat = 12
    let large: CGFloat = 16
    let xLarge: CGFloat = 20
    let xxLarge: CGFloat = 24
    let xxxLarge: CGFloat = 32
}

// MARK: - Corner Radius

extension CGFloat {
    static let radius = CornerRadiusTheme()
}

struct CornerRadiusTheme {
    let small: CGFloat = 4
    let medium: CGFloat = 8
    let large: CGFloat = 12
    let xLarge: CGFloat = 16
    let circle: CGFloat = 999
}

// MARK: - Icon Sizes

extension CGFloat {
    static let icon = IconSizeTheme()
}

struct IconSizeTheme {
    let xSmall: CGFloat = 16
    let small: CGFloat = 20
    let medium: CGFloat = 24
    let large: CGFloat = 32
    let xLarge: CGFloat = 40
    let xxLarge: CGFloat = 60
}

// MARK: - Reusable Components

struct ThemedCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(.theme.medium)
            .background(Color.theme.cardBackground)
            .cornerRadius(.radius.medium)
    }
}

struct ThemedButton: View {
    let title: String
    let icon: String?
    let color: Color
    let action: () -> Void
    
    init(title: String, icon: String? = nil, color: Color = .blue, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: .theme.small) {
                if let icon = icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.theme.bodyBold)
            .foregroundColor(.white)
            .padding(.horizontal, .theme.large)
            .padding(.vertical, .theme.medium)
            .background(color)
            .cornerRadius(.radius.medium)
        }
    }
}

struct ThemedEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String?
    
    init(icon: String, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }
    
    var body: some View {
        VStack(spacing: .theme.large) {
            Image(systemName: icon)
                .font(.system(size: .icon.xLarge))
                .foregroundColor(Color.theme.secondaryText.opacity(0.5))
            
            Text(title)
                .font(.theme.bodyBold)
                .foregroundColor(Color.theme.secondaryText)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.theme.caption)
                    .foregroundColor(Color.theme.tertiaryText)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding(.top, .theme.xxxLarge)
    }
}

struct ThemedSearchBar: View {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    
    var body: some View {
        HStack(spacing: .theme.small) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color.theme.secondaryText)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit(onSubmit)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.theme.secondaryText)
                }
            }
        }
        .padding(.horizontal, .theme.medium)
        .padding(.vertical, .theme.small)
        .background(Color.theme.cardBackground)
        .cornerRadius(.radius.large)
    }
}

// MARK: - View Modifiers

struct ThemedSectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.theme.large)
    }
}

extension View {
    func themedSection() -> some View {
        modifier(ThemedSectionStyle())
    }
}
