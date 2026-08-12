import SwiftUI

/// One row in a ``HWPickerSheet``, flattened into what the sheet needs to draw and search.
///
/// A value rather than a generic item plus five closures. Four pickers in the design — countries, currencies, and
/// two security questions — differ only in what they put in each slot, so the sheet takes rows it can draw and
/// the *screen* maps its own models into them. That keeps the component presentational (`LayeringTests`) and
/// keeps the search rule out of it: what a row matches on is decided where the model is known.
struct HWPickerOption: Identifiable, Sendable, Equatable {
    /// The value that comes back on selection — an ISO code, a question id. Never the displayed name (§4.3
    /// **[FIX]**: a question is identified by `sq07`, not by its English wording).
    let id: String
    /// `.opt-name` — what the row says. Server content, so a `String` rather than copy.
    let name: String
    /// `.opt-chip` — the leading code or glyph. `nil` draws none.
    let leading: HWSheetRowLeading?
    /// `.opt-meta` — the dial code, the symbol.
    let meta: String?
    /// What a search matches against: the design searches "name + code + dial code" for a country and
    /// "name + code + symbol" for a currency, so the caller supplies the haystack rather than the sheet
    /// guessing which fields are searchable.
    let searchText: String

    init(id: String, name: String, leading: HWSheetRowLeading? = nil, meta: String? = nil, searchText: String? = nil) {
        self.id = id
        self.name = name
        self.leading = leading
        self.meta = meta
        self.searchText = searchText ?? name
    }
}

/// The design's picker sheet — a title, and the option list inside it.
///
/// One component for all four of the design's *sheets*, which is how the design itself is written: a single
/// `openSheet(config)` with four configs. Reproducing that as four sheets would be four chances for the search
/// box, the tick, and the empty state to diverge.
///
/// **The list itself is ``HWOptionList``** since #23, and the split is the design's own: Account draws the same
/// searchable list of the same rows as a *pushed page* with a blurb over it, not as a sheet. So what is shared is
/// the list and what is not is the panel — the same fold `HWFigureChips` came out of when Reports needed the
/// three-up chip row outside `HWSpendSummary`.
struct HWPickerSheet: View {
    private let title: LocalizedStringResource
    /// The `.search input` placeholder — "Search country or code".
    private let searchPrompt: LocalizedStringResource
    private let options: [HWPickerOption]
    /// The id of the current choice, or `nil` where nothing is chosen yet.
    private let selection: String?
    private let appearance: HWAppearance
    private let onSelect: (String) -> Void
    private let onClose: () -> Void

    init(
        title: LocalizedStringResource,
        searchPrompt: LocalizedStringResource,
        options: [HWPickerOption],
        selection: String?,
        appearance: HWAppearance = .surface,
        onSelect: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.searchPrompt = searchPrompt
        self.options = options
        self.selection = selection
        self.appearance = appearance
        self.onSelect = onSelect
        self.onClose = onClose
    }

    var body: some View {
        HWSheetChrome(title: title, onClose: onClose, appearance: appearance) {
            HWOptionList(
                searchPrompt: searchPrompt,
                options: options,
                selection: selection,
                appearance: appearance,
                onSelect: onSelect
            )
        }
    }
}

/// The design's `.opts` — a blurb, a search box past twelve rows, the options, and an empty state.
///
/// Two callers, which is why it is its own component: inside ``HWPickerSheet``'s panel, and as the whole of
/// Account's Language and Currency pages, where the design draws the same list on the page itself under an
/// `.explain` paragraph (#23).
///
/// **The search box appears only past twelve rows**, as `sheetSearch.style.display = data.length > 12` does: a
/// keyboard over a list of six is a keyboard in the way. Fourteen questions clear it by two, which is why the
/// question pickers have one; two shipped languages do not, which is why the language page has none.
///
/// **Filtering is case-folded and diacritic-insensitive, and locale-free.** `lowercased()` rather than a
/// localised comparison: the haystack is ISO codes and English names from server content, and a locale-sensitive
/// fold would make the same query match differently for two users looking at identical data (ADR-0011).
struct HWOptionList: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The app's locale, for the one announcement this component makes. `HWAnnouncement` resolves against what it
    /// is passed rather than reading a locale of its own (ADR-0011).
    @Environment(\.locale) private var locale

    /// `.explain` — the paragraph over the list on Account's two option pages. `nil` inside a sheet, where the
    /// title says what the list is for.
    private let blurb: LocalizedStringResource?
    private let searchPrompt: LocalizedStringResource
    private let options: [HWPickerOption]
    private let selection: String?
    private let appearance: HWAppearance
    private let onSelect: (String) -> Void

    @State private var query = ""

    init(
        blurb: LocalizedStringResource? = nil,
        searchPrompt: LocalizedStringResource,
        options: [HWPickerOption],
        selection: String?,
        appearance: HWAppearance = .surface,
        onSelect: @escaping (String) -> Void
    ) {
        self.blurb = blurb
        self.searchPrompt = searchPrompt
        self.options = options
        self.selection = selection
        self.appearance = appearance
        self.onSelect = onSelect
    }

    /// `data.length > 12` — the design's own threshold for showing the search box.
    static let searchThreshold = 12

    /// The rows a query leaves, or all of them.
    ///
    /// `static` and pure so the filter is testable without a list on screen: "searching a currency by its ISO
    /// code finds it" is a rule, and a rule worth writing is worth asserting.
    static func filtered(_ options: [HWPickerOption], matching query: String) -> [HWPickerOption] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return options }
        return options.filter {
            $0.searchText.lowercased().range(of: needle, options: .diacriticInsensitive) != nil
        }
    }

    private var visible: [HWPickerOption] { Self.filtered(options, matching: query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let blurb {
                Text(blurb)
                    .font(.hw(.body))
                    .foregroundStyle(secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
            }

            if options.count > Self.searchThreshold {
                search
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            if visible.isEmpty {
                empty
                    // **A list that emptied says so.** Typing replaces the rows in place, so a VoiceOver user
                    // searching "zzz" hears nothing change and has to swipe past the field to discover the
                    // list is gone. The same reasoning `StateView` applies to the empty-handed states.
                    .onAppear { HWAnnouncement.post("component.picker.empty", in: locale) }
            } else {
                HWSheetList {
                    ForEach(visible) { option in
                        HWSheetRow(
                            name: Text(verbatim: option.name),
                            leading: option.leading,
                            meta: option.meta.map { Text(verbatim: $0) },
                            isSelected: option.id == selection,
                            appearance: appearance
                        ) {
                            onSelect(option.id)
                        }
                    }
                }
            }
        }
    }

    /// `.search` — a field box with a magnifying glass, inset from the panel's edges.
    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.hw(.body))
                .foregroundStyle(secondaryInk)
                .accessibilityHidden(true)

            TextField(text: $query) { Text(searchPrompt) }
                .textFieldStyle(.plain)
                .font(.hw(.bodyLarge).weight(.regular))
                .foregroundStyle(primaryInk)
                .tint(appearance == .brand ? theme.palette.brand.inkAccent : theme.palette.accent.base)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(Text(searchPrompt))

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.hw(.body))
                        .foregroundStyle(secondaryInk)
                        .frame(width: HWTouchTarget.minimum, height: HWTouchTarget.minimum)
                        .contentShape(.rect)
                }
                .buttonStyle(HWPressStyle.compact)
                .accessibilityLabel(Text("component.picker.clearSearch"))
            }
        }
        .padding(.leading, 14)
        .frame(minHeight: HWTextField.minimumHeight)
        .hwBox(fill: fieldFill, radius: .medium, border: fieldBorder)
        // The clear button appears as the box gains text; a cross-fade rather than a slide keeps a control
        // that has just appeared from moving under a finger already on its way to it (ADR-0012).
        .animation(
            reduceMotion ? HWMotion.easeInOut.animation(.quick) : HWMotion.easeOut.animation(.standard),
            value: query.isEmpty
        )
    }

    /// `.empty` — "Nothing matched", which is a sentence a user reads and so is copy rather than a glyph.
    private var empty: some View {
        Text("component.picker.empty")
            .font(.hw(.body))
            .foregroundStyle(secondaryInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
    }

    private var primaryInk: Color {
        appearance == .brand ? theme.palette.brand.ink : theme.palette.surface.ink
    }

    private var secondaryInk: Color {
        appearance == .brand ? theme.palette.brand.inkSecondary : theme.palette.surface.inkSecondary
    }

    private var fieldFill: Color {
        appearance == .brand ? theme.palette.brand.raised : theme.palette.surface.backgroundSecondary
    }

    private var fieldBorder: Color {
        appearance == .brand ? theme.palette.brand.separator : theme.palette.surface.separator
    }
}

#if DEBUG
/// Enough rows to put the search box on screen — the threshold is twelve, so a short sample would preview the
/// wrong sheet.
private let previewCurrencies: [HWPickerOption] = [
    ("AED", "UAE Dirham", "د.إ"), ("INR", "Indian Rupee", "₹"), ("PHP", "Philippine Peso", "₱"),
    ("PKR", "Pakistani Rupee", "₨"), ("USD", "US Dollar", "$"), ("GBP", "Pound Sterling", "£"),
    ("EUR", "Euro", "€"), ("EGP", "Egyptian Pound", "E£"), ("LKR", "Sri Lankan Rupee", "Rs"),
    ("BDT", "Bangladeshi Taka", "৳"), ("NPR", "Nepalese Rupee", "Rs"), ("SAR", "Saudi Riyal", "﷼"),
    ("KWD", "Kuwaiti Dinar", "KD"), ("OMR", "Omani Rial", "﷼"),
].map { code, name, symbol in
    HWPickerOption(
        id: code,
        name: name,
        leading: .code(symbol),
        meta: code,
        searchText: "\(name) \(code) \(symbol)"
    )
}

private let previewQuestions: [HWPickerOption] = [
    "What was the name of your first school?",
    "In which city were you born?",
    "What is your mother's maiden name?",
].enumerated().map { index, text in
    HWPickerOption(id: "sq0\(index + 1)", name: text)
}

#Preview("Picker — a long list on brand, with search") {
    HWPickerSheet(
        title: "Select currency",
        searchPrompt: "Search currency or code",
        options: previewCurrencies,
        selection: "INR",
        appearance: .brand,
        onSelect: { _ in },
        onClose: {}
    )
    .hwTheme()
}

#Preview("Picker — a short list on surface, no search box") {
    HWPickerSheet(
        title: "Security question 1",
        searchPrompt: "Search questions",
        options: previewQuestions,
        selection: "sq02",
        onSelect: { _ in },
        onClose: {}
    )
    .hwTheme()
}

#Preview("Picker — nothing matched") {
    HWPickerSheet(
        title: "Select currency",
        searchPrompt: "Search currency or code",
        options: [],
        selection: nil,
        appearance: .brand,
        onSelect: { _ in },
        onClose: {}
    )
    .hwTheme()
}

#Preview("AX3 — the rows wrap rather than truncating") {
    HWPickerSheet(
        title: "Security question 1",
        searchPrompt: "Search questions",
        options: previewQuestions,
        selection: "sq01",
        appearance: .brand,
        onSelect: { _ in },
        onClose: {}
    )
    .dynamicTypeSize(.accessibility3)
    .hwTheme()
}

#Preview("RTL — the chip and the tick swap sides") {
    HWPickerSheet(
        title: "اختر العملة",
        searchPrompt: "ابحث عن عملة أو رمز",
        options: previewCurrencies,
        selection: "AED",
        appearance: .brand,
        onSelect: { _ in },
        onClose: {}
    )
    .environment(\.layoutDirection, .rightToLeft)
    .hwTheme()
}
#endif
