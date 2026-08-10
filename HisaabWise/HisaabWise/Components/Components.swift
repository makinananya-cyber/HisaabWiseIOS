/// The shared UI vocabulary: one implementation of each control, used everywhere.
///
/// The rule that makes this worth having: **a screen never styles a control itself.** If Expenses
/// needs a button that Home does not have, the variant is added here, not inlined there — otherwise
/// there are two buttons that look alike until one of them changes.
///
/// The inventory comes from the design's own CSS (`HisaabwiseDesigns/HisaabWise 6.html`), which
/// already has a component vocabulary worth honouring rather than reinventing: `.btn` with its
/// `primary` / `soft` / `ghost` / `quiet` variants, `.iconbtn`, `.editbtn`, `.field-box` with its
/// leading icon, `.label`, `.eyebrow`, `.card` and its caption and subtitle rows, the chip family,
/// the sheet family, `.row` / `.key-row`, and `.toast`.
///
/// **Components are presentational and know nothing.** They take values and closures. They do not
/// import the networking layer, do not hold a view model, and do not fetch — `LayeringTests` asserts
/// all three, because a component that can fetch is a screen wearing a component's name.
///
/// They draw with `DesignSystem`'s semantic colours and type scale, never with literals, so the
/// dark-mode palette swap stays a palette swap.
///
/// The namespace is empty until the components land (see the Components issue, blocked on the design
/// system).
enum Components {}
