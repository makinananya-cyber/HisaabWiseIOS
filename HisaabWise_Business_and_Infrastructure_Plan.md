# HisaabWise — Business & Infrastructure Plan

**Version 3.** Merges the Application Business Plan (feature walkthrough, `Application_Business_Plan_2.docx`) into the infrastructure plan, both read against the interactive design (`HisaabWise_6.html`).

- **v1** — hosting, database, domain and CI/CD skeleton, written before any features existed.
- **v2** — revised against the 7-screen design; added the FX service, month-rollover job, content pipeline, email, push, staging and monitoring.
- **v3 (this document)** — adds Part A: the product definition, market positioning, monetisation question, cost model and success metrics. Part B is the infrastructure plan, updated. New material is marked **[NEW in v3]**.

### Source documents

| Source | What it contributed | Assessment |
|---|---|---|
| `HisaabWise_6.html` (700 KB) | 7 screens, ~350 KB of editorial content, all logic, all reference data. **The authoritative feature specification.** | Byte-identical to the copy reviewed for v2, so the v2 analysis carries forward unchanged. |
| `Application_Business_Plan_2.docx` (6.6 MB) | A 17-step narrated walkthrough with 15 screenshots of the prototype. | **Confirms the design; adds no new features.** The screenshots are of the prototype itself — spot-checked against the landing, home and personal-information screens and they match exactly, down to the `AED 5,539 · 69% of pay` figure. |

**On the business plan document.** It is titled *Business Plan* but contains a **product walkthrough only**. There is no market sizing, revenue model, pricing, competitive analysis, go-to-market plan, cost projection or funding requirement in it. Those are the real gaps, and Part A fills what can be filled from evidence and flags the rest as decisions only you can make (§A.4, §A.8). I've folded the walkthrough in as the canonical user journey (§A.1), because as a statement of intended flow it is genuinely useful — it's the one document that says what order things happen in.

---
---

# PART A — BUSINESS & PRODUCT PLAN

**[NEW in v3 — this entire part.]**

## A.1 The product, as narrated

HisaabWise is a personal finance app that pairs **expense tracking** with **financial education**, aimed at the UAE market. The business plan document describes the intended journey in 17 steps; condensed:

| # | Step | Screen |
|---|---|---|
| 1 | Introductory screen with a **Get Started** action | `landing` |
| 2 | Get Started leads to sign in or register | `auth` |
| 3 | Create Account → step 1, core details | `auth` / reg1 |
| 4 | Step 2 — "personal extra details" (currency, salary, security questions) | `auth` / reg2 |
| 5 | Step 3 — "questions for salary goals" | `auth` / reg3 |
| 6 | **Submit or Skip for now** both land on Home | `home` |
| 7 | From the tab bar, Expenses | `expenses` |
| 8 | Tap a category → input how much was spent | `expenses` detail |
| 9 | Tab bar → Learn, to find the lessons | `learn` |
| 10 | Tap a module → information first, then questions | `learn` player |
| 11 | Tab bar → Reports | `reports` |
| 12 | Tap a report → all financial details and records for that month | `reports` detail |
| 13 | Tab bar → Accounts | `account` |
| 14 | Tap an option → see and change personal details or app choices | `account` detail |
| 15 | Log out returns to the introductory page | → `landing` |

That is a **five-tab app with a linear onboarding funnel and no dead ends** — every tab reachable from every other, and one exit. It matches the prototype's navigation model exactly. The value of having it written down is that it fixes the funnel: registration is three steps, skippable at the last one, and lands on Home either way.

## A.2 Complete feature inventory

Consolidated from both sources. This is the build scope.

### A.2.1 Onboarding & identity
- Landing screen: hero illustration, 4 rotating straplines, "Free to start · No card required".
- Sign in: identifier + password, "Keep me signed in", "Forgot password?" *(unimplemented in the prototype)*.
- Register step 1: full name, email, phone with dial code from **251 countries** (stored E.164), date of birth (**13+ enforced**), password + confirm with a 4-level strength meter, Terms & Privacy consent.
- Register step 2: display currency from **160 ISO-4217 currencies**, monthly salary, **two security questions** from a 14-question bank plus answers.
- Register step 3: monthly savings goal, pre-filled at **20% of salary**, with live feedback on what percentage the typed figure represents, and a **Skip for now** that accepts the suggestion.
- Log out with confirmation dialog.

### A.2.2 Home — the daily surface
- Spending donut by category with tap-to-isolate segments and a percentage-of-pay readout.
- Distinct **first-run empty state**: grey ring, one CTA.
- Savings meter: saved vs goal on a red→green gradient with a sliding pin and a percentage pill.
- **Tip of the day** — 49 tips, chosen by day-of-year, currency-token aware, with a "Show me another".
- **Streak + XP mini-card** with the next lesson name.
- **"Read more" articles** — 3 long-form researched pieces with sections, key-value lists, numbered steps, callouts and external source citations.

### A.2.3 Expenses — the core loop
- Monthly summary: total spent, split into Fixed / Variable / Income.
- **Wants budget bar** with over-budget state.
- Seven categories in three structural kinds: `log` (Groceries, Transport, Entertainment, Other, Additional Income), `lines` (Utilities — multiple named bills), `fixed` (Rent).
- Transport pick list (22 options); Other pick list (20 options + free-text "Something else…").
- Entry-level delete; per-category running total; "Today / Yesterday / N days ago" date labels.
- **Adaptive 50/30/20 engine** that degrades gracefully when needs exceed half of income.

### A.2.4 Learn — the retention engine
- **5 units, 15 lessons, ~115 steps.** Units: Build the Foundation (Income & Mindset), Control Cash Flow (Budgeting & Saving), Master Borrowing (Debt & Credit), Protect Wealth (Risk Management), Grow Wealth (Investing & Retirement).
- Teaching steps: headline, paragraphs, key-value lists, worked examples, "Remember it" tips.
- Questions: 50 single-choice, 14 numeric (±0.5 tolerance), 2 multi-select.
- **Hearts** (3 per run), **XP** (10/correct + 20 bonus), **combos** (celebrated every 3rd), **day streak**, partial-progress rings, sequential unlocking, per-unit guide sheet.
- Completion: XP, accuracy, streak, 7-day week strip, confetti.

### A.2.5 Reports — the retrospective
- Archive of completed months (6 seeded: Feb–Jul 2026), grouped by year with per-year savings totals.
- Savings-goal trend chart, bars coloured hit / near / miss against a dashed goal line.
- Per-month detail: totals, the Home donut for that month, the savings meter, wants budget, a needs/wants/savings/unspent split bar, an accordion of **every logged entry**, and a "For the record" facts grid.

### A.2.6 Account & settings
- Profile with initials avatar. Editable username, salary, phone; **email deliberately locked**.
- **87 app languages**; **160 currencies** with app-wide live conversion.
- Password change: current password → both security questions (fuzzy-matched) → new password.

### A.2.7 Cross-cutting
- `HWMoney` currency runtime: base-currency authoring, magnitude-aware rounding, symbol spacing, app-wide repaint on change.
- Reduced-motion support throughout; extensive ARIA labelling; keyboard navigation in every sheet.
- Design system: 7-colour palette, 6 category colour slots, 5 Learn unit accents, 2 easing curves.

## A.3 Market and positioning

Neither source states a target market, but **the content states it unambiguously**. The evidence:

- Money is in **AED**; the seeded salary is AED 8,000/month.
- Tips and articles cover: no UAE income tax on salary, 5% VAT, **end-of-service gratuity calculated on basic salary only**, the **Debt Burden Ratio** and its 50% Central Bank cap, the **Al Etihad Credit Bureau** score (300–900), mandatory health cover in Dubai and Abu Dhabi, and remittance costs.
- Fraud reporting routes are named specifically: Dubai Police **eCrime** and **901**, Abu Dhabi Police **Aman** (800 2626 / SMS 2828), the **MoI UAE** app, **My Safe Society**, 999.
- Sources cited are u.ae, the Central Bank of the UAE Rulebook, Emirates NBD and StashAway.
- A whole article is devoted to **sending money home** — "The UAE is one of the biggest senders of money in the world."

**The implied user:** a salaried resident of the UAE, likely an expatriate worker, paid monthly, renting, sending money home, who is not confident with money and would rather be taught than lectured. The age gate at 13 and the "Every rupee, tracked" strapline both point younger and toward the South Asian expatriate community.

**The positioning that follows:** most expense trackers assume you already know what a debt burden ratio is. This one teaches you while you track. That combination — **local, specific financial education welded to a spending tracker** — is the differentiator, and it is genuinely defensible, because the content is the moat: 49 tips and 15 lessons of UAE-specific, sourced material is expensive to replicate and gets more valuable as it grows.

**What this means for the plan:** the content pipeline (§B.5.2) is not a nice-to-have implementation detail. It is the product's competitive advantage, and it should be resourced accordingly — which is the main reason it belongs on the server rather than compiled into the binary.

**Three things worth confirming before launch**, since the content commits to them:
1. Is the UAE the launch market, or the first of several? Every figure and every regulator named is UAE-specific, so a second market means a second content set, not a translation.
2. Positioning the app as financial education rather than financial *advice* matters legally. Nothing in the content crosses into regulated advice as written — it teaches concepts and cites official sources — but that line should be held deliberately, with a disclaimer, rather than accidentally.
3. The strapline says "Every rupee" while the app displays AED. Minor, but it reads as a copy-paste from a different market.

## A.4 Monetisation — undefined, and it needs deciding

**The design contains no monetisation surface at all.** No paywall, no subscription screen, no upgrade prompt, no ads, no premium tier, no in-app purchase. The Account screen has four rows — Personal Information, Language, Currency, Password — and none of them is Billing.

Meanwhile the landing screen already commits, in print, to **"Free to start · No card required."** That is a pricing statement made in the UI before a pricing decision was made in the business plan. "Free to start" implies something is paid later.

This is the single largest gap between the two documents, and it is a business decision, not a technical one. The options, with what each costs to build:

| Model | Fit | Build cost |
|---|---|---|
| **Free, no revenue** (portfolio piece, or funded some other way) | Honest and simplest. Infra cost is ~$70–100/mo (§A.5), which one person can absorb. | Zero. Remove "Free to start" — it implies a paid tier that doesn't exist. |
| **Freemium subscription** — free tracking, paid Learn beyond Unit 1, or paid Reports history beyond 3 months | Fits the design's natural seams: unit unlocking already exists, and report history is naturally tiered. | StoreKit 2, receipt validation, entitlement state on the server, restore-purchases, subscription management. A real phase of work. |
| **One-off unlock** | Simpler than subscriptions, no renewal handling. | StoreKit 2 without renewal logic. Perhaps a third of the above. |
| **Ads** | Poor fit. An app that teaches people to avoid financial predators cannot sell them ad inventory without undermining itself. | Ad SDK, plus a materially worse App Privacy declaration and a tracking-consent prompt. |
| **B2B2C** — licence to a UAE bank or employer for staff financial wellness | Plausible, given the content quality and the Emirates NBD citation. Changes the product into an SDK or white-label. | Substantial. Not a launch consideration. |

**Recommendation: launch free, with no paywall and the "Free to start" line replaced by something that isn't a promise** — for example "Free · No card required". Ship, get real users, and learn which of Learn or Reports they'd actually pay for before building StoreKit. Adding a paywall later to an app people use is far easier than finding users for an app with a paywall and no track record. If you disagree and want revenue from day one, the freemium row above is the one to pick, and it needs to enter the plan at Phase 3 — entitlements have to exist before the content they gate.

## A.5 Cost model

At launch scale (low hundreds of users). **Verify every figure — provider pricing moves, and some of these are from memory.**

| Item | Tier | Monthly | Notes |
|---|---|---|---|
| Render — production web service | Starter | ~$7 | Free tier sleeps; not viable (§B.3) |
| Render — staging web service | Free or Starter | $0–7 | Free is acceptable for staging |
| Render — cron jobs (3) | — | small | Render bills cron by run time; these are short. Confirm current pricing. |
| MongoDB Atlas | M10 | ~$55–60 | Backups included. **Flex (~$10–30) is a reasonable way to defer this**, but confirm it offers backup. |
| Cloudflare | Free | $0 | Pro (~$20) only if free-tier WAF/rate-limit rule allowances prove too tight (§B.6.9) |
| Transactional email | Free tier | $0 | Resend ~3k/mo free; Postmark ~$15 if you outgrow it |
| FX rate provider | Free tier | $0 | One call/day is well inside every free tier |
| Sentry | Free tier | $0 | Two projects fit the free allowance at this scale |
| **Monthly total** | | **~$65–75** | ~$120 if you take Atlas M10 and Cloudflare Pro |

| Annual / one-off | Cost |
|---|---|
| Apple Developer Program | ~$99/year |
| Domain registration | ~$10–20/year |
| Xcode Cloud | Included allowance (25 compute hours/month at time of writing) covers internal builds |

**So roughly $70/month plus $110/year to run this properly.** Worth stating plainly because it reframes the v2 tier upgrades: moving off the free tiers costs about the price of two coffees a week, against the risk of losing a user's entire financial history to an un-backed-up database. That is not a close call.

The one figure to watch as you grow is Atlas. Everything else scales gently; database tier is the step function.

## A.6 Success metrics

The app already computes almost all of these — they're the same numbers the UI displays, which makes instrumentation cheap.

**Activation**
- Registration completion rate, **step by step**. Three steps with 14 fields is a lot of friction; step 2 (salary + two security questions) is where I'd expect the drop.
- Share who set a savings goal vs tapped **Skip for now**. The prototype treats skip as accepting the 20% suggestion, so both are activations — but they're different levels of intent and shouldn't be counted together.
- Share who log their **first expense within 24 hours**. This is the real activation event; the Home empty state exists specifically to drive it.

**Engagement**
- Expenses logged per user per week — the core loop.
- Lessons completed per user per week; **day-streak distribution** (the whole hearts/XP/combo apparatus exists to move this).
- Learn funnel by unit — where in the 15 lessons people stop.
- Tip-of-the-day "Show me another" taps, as a cheap proxy for content appetite.

**Retention**
- D1 / D7 / D30. For a monthly-cycle product, **D30 and M2 matter more than D1** — the app's payoff is the month-end report, so judging it on day-one retention would mislead you.
- Share of users who see **at least one completed monthly report**. This is the moment the product's value lands; retention before and after it will look like two different products.

**Health**
- Month-rollover job success rate (must be 100%; anything else is data loss).
- FX ingestion freshness.
- Crash-free session rate.

**Deliberately not measured at launch:** anything requiring a third-party analytics SDK. Sentry plus a handful of backend counters covers the list above, and adding an analytics SDK worsens the App Privacy declaration for an app that already has to declare financial data collection.

## A.7 Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **No account deletion** — App Store 5.1.1(v) requires it | **Blocking submission** | Build it in Phase 1 (§C.2) |
| **87 languages promised, ~2 deliverable** | High — it's a visible broken promise | Show only shipped languages (§C.1 Q2) |
| **Salary has no single source of truth** — Home hardcodes AED 8,000 and never reads the user's figure, while Account defaults to a ₹65,000 INR base. The screenshots show ₹65,000 on Account and "69% of pay" computed against AED 8,000 on Home. | High — the app contradicts itself about the user's income | Server-owned salary as `{amount, currency}`, read by every screen (§C.1 Q6) |
| **No monetisation and a "Free to start" promise in the UI** | Medium | Decide (§A.4) |
| Content is the moat but has one author | Medium | Content pipeline + versioning so contributors can be added without app releases |
| Month-rollover bug destroys history irreversibly | Medium-high | Staging + idempotency test as a release gate (§B.8) |
| Stale FX rates undercut the app's own remittance advice | Medium | Daily ingestion, rate date surfaced in UI (§B.4.3) |
| Financial education drifting into regulated advice | Medium | Explicit disclaimer; keep citing official sources |
| Registration friction — 14 fields across 3 steps | Medium | Measure step-by-step drop-off before optimising |
| Single-developer bus factor | Medium | Everything in git, infra documented here, no undocumented dashboard state |

## A.8 What a complete business plan still needs from you

Not gaps I can fill — they need your judgement or information I don't have:

1. **Monetisation decision** (§A.4).
2. **Funding** — is this self-funded, and what is the runway? At ~$70/month it's modest, but it isn't zero.
3. **Competitive analysis** — who else serves UAE personal finance, and how do their offerings compare? I can't assess this without market research; a fair review of the alternatives would sharpen the positioning in §A.3.
4. **Launch marketing** — the plan currently has a Cloudflare Pages site and nothing else. How do the first hundred users find this?
5. **Content roadmap** — the moat is content. What's the cadence for new lessons and tips after launch, and who writes them?
6. **Team** — is this one person, and which of the phases in §C.2 need help?
7. **Second-market plan** — if not UAE-only, which market next, and does the content get localised or rewritten?

---
---

# PART B — INFRASTRUCTURE PLAN

## B.1 Context

HisaabWise is an iOS app with a Node.js backend, MongoDB database, and a Cloudflare-managed domain. Two repos exist: [HisaabWiseIOS](https://github.com/makinananya-cyber/HisaabWiseIOS) and [HisaabWiseBackend](https://github.com/makinananya-cyber/HisaabWiseBackend).

**Why the infrastructure grew.** v1 planned for a backend whose only job was `GET /health`. The design turned out to require: a multi-currency conversion layer over 160 currencies, a gamified course with server-owned streaks, an immutable monthly archive, a shared budgeting engine, a content pipeline, transactional email, and push notifications. Each is a backend responsibility, a scheduled job, or a compliance obligation.

**Key finding carried from v1 (unchanged and still binding).** MongoDB's Atlas Data API — the REST route into MongoDB from edge runtimes like Cloudflare Workers — was shut down on 30 September 2025. Workers can open raw TCP sockets now, but the native MongoDB driver over that path is not production-ready under Workers' ephemeral execution model (connection pooling, cold starts). So: **the backend runs as a normal long-lived Node.js server**, and **Cloudflare handles DNS, CDN, TLS, WAF and caching only** — never the database connection.

## B.2 What the design requires, screen by screen

The evidence base for everything that follows.

### B.2.1 Landing
Static. No backend. The four straplines and the "Free to start" line are marketing copy for the app bundle — and per §A.4, that line needs rewording before it ships.

### B.2.2 Auth — sign in + 3-step registration

| Step | Fields |
|---|---|
| Sign in | **username** + password, "Keep me signed in", "Forgot password?" |
| Register 1 | Full name, email, phone (dial code from 251 countries → E.164), DOB, password + confirm, Terms consent |
| Register 2 | Currency (160), monthly salary, two security questions + answers |
| Register 3 | Savings goal, pre-filled at 20% of salary, skippable |

- **The sign-in identifier doesn't exist.** Sign-in asks for a username; registration never collects one. Unresolved in the design; changes the user schema. See §C.1 Q1.
- **Password rules disagree between screens:** registration demands 8+, sign-in accepts 6+. The server enforces one rule — the stricter.
- **Security answers must never reach the client.** The design says so twice: *"hash these on the server — never store or send a raw answer."* But the Account screen verifies them **locally**, with a fuzzy matcher (accent strip, punctuation strip, filler-word removal, plural tolerance, Levenshtein ≤ 1 on 5+ character words). That matcher moves server-side, and the stored value must be a hash of the **normalised key words** — hashing the raw string makes fuzzy matching impossible.
- **Age gate at 13** drives the App Store age rating and children's-privacy obligations in several markets.
- **Terms & Privacy Policy need a public URL** before external TestFlight and before submission.
- **"Forgot password?" is unimplemented** — it only toasts *"feature coming next."* Transactional email is therefore a hard dependency.
- Rate limiting is required on sign-in, registration, reset and security-question verification. The prototype already counts failed attempts and suggests support after three, so backoff is part of the design — it belongs on the server.

### B.2.3 Home
Donut, savings meter, first-run empty state, tip of the day (49 tips, day-of-year rotation, `{c}` currency tokens, inline markup), streak/XP card, 3 long-form articles with external citations.

→ Tips and articles are **editorial content that changes more often than the app ships**. Server-served, CDN-cached, translatable. Not compiled into the binary.

### B.2.4 Expenses

| Kind | Categories | Behaviour |
|---|---|---|
| `log` | Groceries, Transport, Entertainment, Other, **Additional Income** | Append-only entries (amount, label, timestamp), individually deletable |
| `lines` | Utilities | Several named monthly bills, each editable/addable/removable |
| `fixed` | Rent | One editable monthly amount |

- Transport: 22-option pick list. Other: 20 options + free-text escape hatch.
- **Additional Income** is money in, excluded from the donut, and **lifts every budget allowance**.
- **Adaptive 50/30/20:** needs = rent + utilities + groceries; wants = transport + entertainment + other. While needs ≤ 50% of income the plain rule applies (30/20). Once needs exceed half, what remains after needs splits evenly between wants and savings. **This logic appears identically in both the Expenses and Reports screens.**
- Amounts are typed in display currency, stored in base currency.

→ The budget engine lives in **one** place — the server — or the app and the report generator will drift. Category taxonomy and both pick lists are server-served so they extend without an app release.

### B.2.5 Learn
5 units, 15 lessons, ~115 steps. Steps are `teach` or `q`; questions are `choice` (50), `num` (14, ±0.5 tolerance), `multi` (2). Hearts (3), XP (10 + 20 bonus), combos every 3rd, day streak via a `lastActive` day key, partial progress persistence, sequential unlocking.

→ Consequences:
- Curriculum is **versioned content** — ~156 KB and growing. Server-served, CDN-cached, ETag-revalidated.
- Progress (`xp`, `streak`, `lastActive`, `done{}`, `progress{}`) needs persistence, and must survive reinstall.
- **The day streak has a timezone hole.** The prototype derives the day key from the device clock, so changing timezone or clock manipulates the streak. The server owns the boundary, using a stored per-user timezone.
- **XP is client-computed.** Low risk for a single-player app. Keep grading client-side for launch, but submit per-question results so the server can recompute and reject impossible submissions.
- Streaks are the main reason for push notifications (§B.4.6).

### B.2.6 Reports
One immutable record per completed month, shaped to mirror Expenses (`fixed` + `log`) "so a finished month can be filed here untouched when it rolls over." Each record carries that month's salary, goal and saved — all values that change over time, so they must be snapshotted rather than looked up. Six months seeded (Feb–Jul 2026; goal met in 2 of 6).

→ Consequences:
- **A month-rollover job is required infrastructure.** At each user's local month boundary: close the month, snapshot it immutably, reset the live month. Needs a scheduler, idempotency, and per-user timezone awareness. This is the largest single addition since v1.
- **Historical FX must be pinned.** The prototype converts the whole archive at *today's* rate, so switching currency silently rewrites financial history. February should not change because the dirham moved in August. Each snapshot stores base amounts **and** the rate set in effect at close.

### B.2.7 Account & settings
Profile; editable username/salary/phone with **email deliberately locked**; 87 languages; 160 currencies with app-wide conversion; three-step password change; log out.

→ Consequences:
- **87 languages is the biggest scope risk in the design** — it promises full localisation of UI, 49 tips, 3 long articles and ~115 lesson steps, including RTL languages. That's a translation programme, not a settings screen. See §C.1 Q2.
- **There is no "Delete account".** App Store Guideline 5.1.1(v) requires in-app deletion for any app offering account creation. As designed, this gets rejected. Needs a screen, an endpoint and an erasure path.
- **Salary is inconsistent across screens** — see §A.7 and §C.1 Q6. Home hardcodes `salary: 8000` in AED and never reads the user's value; Account defaults its base to INR. The two screens can display different incomes for the same user, and Home's "% of pay" is computed against the wrong one.

### B.2.8 Cross-cutting: the `HWMoney` runtime
Every figure is authored in a base currency and rendered through `HWMoney`, which converts, rounds by magnitude (nearest 100 above 100k, nearest 10 above 10k), spaces multi-letter codes (`AED 500` vs `₹500`), and broadcasts changes so every screen repaints together.

Rates are a **static snapshot of 160 currencies**, with a note in the source: *"Rates are an indicative static snapshot. Point conv() at a live feed and nothing else has to change."*

**That live feed is now a backend service** — and it matters more here than usual, because one of the app's own articles teaches users to compare a provider's rate against the mid-market rate and treat the gap as the true cost. Teaching that while displaying months-old rates undercuts the product.

## B.3 Decisions locked in

| Area | v1 | v2 / v3 | Why |
|---|---|---|---|
| Backend hosting | Render **free** | Render **Starter** | Free instances sleep after ~15 min idle; the next request pays a cold start near a minute. Fatal for an app opened in a shop to log a purchase. |
| Database | Atlas **M0 free** | **M10, or Flex, with continuous backup** | M0 has no backups and no point-in-time restore. This holds a household's financial history. |
| Scheduled jobs | none | **Render Cron Jobs** ×3 | Reports and multi-currency require them. |
| Domain / DNS | Cloudflare DNS + proxy | + **WAF rate limiting, cache rules, Cloudflare Pages** | Auth needs rate limiting; content benefits from CDN; the App Store requires a hosted privacy policy. |
| Environments | **production only** | **staging + production** | A buggy rollover job destroys data irreversibly. |
| Backend CI/CD | Actions → Render hook | + migration and job-dry-run steps | |
| iOS CI/CD | Xcode Cloud → TestFlight | unchanged | |
| Monitoring | **out of scope** | **Sentry ×2, uptime check, log drain, job-failure alerts** | A silently failing rollover job is invisible until a user notices a missing month. |
| Email | not considered | **transactional provider** | Password reset, email verification. |
| Push | not considered | **APNs** via `.p8` key | Streaks are the core retention mechanic. |
| FX | not considered | **provider + daily ingestion + cache + pinned history** | The whole app renders through a conversion layer. |
| Auth tokens | not considered | **short access JWT + rotating refresh**, refresh in Keychain | "Keep me signed in" is in the design. |
| Monetisation | not considered | **none at launch** — recommendation, §A.4 | **[NEW in v3]** No StoreKit until there's evidence of what people would pay for. |

## B.4 Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│  iOS App (HisaabWiseIOS) — SwiftUI, 5-tab shell                         │
│  Home · Expenses · Learn · Reports · Account                            │
│                                                                          │
│  · Keychain: refresh token          · Local queue: offline expense entry │
│  · Content cache: curriculum, tips, articles, FX (ETag-revalidated)      │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ HTTPS
                                ▼
              api.<yourdomain>.com  (Cloudflare: DNS, TLS, CDN, WAF,
                                     rate limiting, cache rules)
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Render — HisaabWiseBackend (Node.js / Express)                          │
│                                                                          │
│  Auth        register · login · refresh · logout · reset · security-Q    │
│  Profile     me · update · currency · language · timezone · DELETE       │
│  Expenses    entries CRUD · fixed/lines · categories · picklists         │
│  Budget      adaptive 50/30/20 (single source of truth)                  │
│  Learn       curriculum · progress · lesson-complete · streak            │
│  Reports     archive list · month detail (pinned FX)                     │
│  Content     tips · articles  (localised, CDN-cacheable)                 │
│  FX          GET /fx/rates (current) · GET /fx/rates/:yyyy-mm (historic) │
└───────┬───────────────────────────┬─────────────────────────┬───────────┘
        │                           │                         │
        ▼                           ▼                         ▼
┌────────────────┐      ┌───────────────────────┐   ┌────────────────────┐
│ MongoDB Atlas  │      │ Render Cron Jobs      │   │ External services  │
│ M10 + backups  │      │ · fx:refresh  daily   │   │ · FX rate provider │
│                │      │ · month:rollover hrly │   │ · Email provider   │
│ users          │      │   (per-user local     │   │ · APNs (push)      │
│ expense_entries│      │    month boundary)    │   │ · Sentry           │
│ fixed_costs    │      │ · streak:remind daily │   └────────────────────┘
│ month_archives │      └───────────────────────┘
│ learn_progress │
│ fx_rates       │
│ content        │
│ refresh_tokens │
└────────────────┘

CI/CD
  HisaabWiseBackend:  push/PR → lint + test  →  (main, if green) → Render deploy hook
  HisaabWiseIOS:      push to main → Xcode Cloud archive → TestFlight (internal)
```

### B.4.1 Screen-to-Swift mapping
The prototype is seven standalone HTML documents stitched together in iframes with `postMessage`. That's a prototyping device, not an architecture.

- The shell's `ORDER` array and `postMessage` navigation → a `TabView` with a `NavigationStack` per tab.
- The two-level list→detail pattern (Expenses, Reports, Account) → `NavigationLink` push.
- The `HWMoney` broadcast → an observable app-level currency object; every view formats through it.
- The bottom sheets (country, currency, language, pick lists) → `.sheet` with a searchable list.
- The Learn player → a full-screen cover.

### B.4.2 The base-currency rule
One rule, everywhere, or the money will be wrong:

> **Every monetary value is stored as `{ amount, currency }` — never a bare number.**

The prototype shows why: salary is held in `signupCurrency` while expenses are held in `AED`, and Home ignores both. Amount-plus-currency makes a currency change a display concern rather than a migration.

### B.4.3 FX rates
- A daily cron job pulls mid-market rates for all 160 currencies and writes a dated `fx_rates` document.
- `GET /fx/rates` serves the newest set, edge-cached ~1 hour.
- `GET /fx/rates/:yyyy-mm` serves the set pinned at that month's close, for the archive. Immutable, cached a year.
- On ingestion failure the previous set stays live and an alert fires. Rates never silently fall back to hardcoded values.
- The rate date is surfaced in the UI wherever non-base-currency totals appear.

### B.4.4 Month rollover
- Runs hourly; selects users whose local time just crossed into a new month.
- Writes a `month_archives` document: month key, salary, goal, saved, the full `fixed` + `log` payload, and the FX rate set id.
- **Idempotent** on `(userId, monthKey)` with a unique index — a retry cannot double-write.
- Resets the live month: `log` cleared, `fixed` costs carried forward unchanged.
- Emits a structured log line and a metric per user; alerts if the processed count is zero on a day it shouldn't be.

### B.4.5 Localisation
- UI strings in the app (String Catalogs, `.xcstrings`).
- Content strings (tips, articles, curriculum) served by locale, selected via `Accept-Language`, falling back to `en`.
- RTL is a SwiftUI layout discipline (leading/trailing, never left/right) — cheap from the start, expensive to retrofit.
- Ship a small launch set, not 87 (§C.1 Q2).

### B.4.6 Push notifications
- APNs `.p8` key in backend secrets; device tokens per user per device.
- Launch scope: one streak reminder, in the user's evening local time, only if no lesson was completed that day, and only on opt-in.
- The daily `streak:remind` job does the selection.

## B.5 What I'll set up directly (in-session, in-repo)

### B.5.1 Backend scaffold — `HisaabWiseBackend/`
- `package.json` — Express, Mongoose, dotenv, cors, helmet, **argon2** (password + security-answer hashing), **jsonwebtoken**, **zod**, **pino**, **express-rate-limit**. Scripts: `start`, `dev`, `lint`, `test`, `migrate`, `seed`.
- `src/server.js` — entrypoint, reads `PORT`.
- `src/db.js` — Mongoose connection from `MONGODB_URI`, fails fast with a clear error if absent.
- `GET /health` — `{status:"ok"}` plus a DB-reachable flag, for Render's health check and the uptime monitor.
- **Route modules** for every domain in §B.4, initially `501 Not Implemented` with the contract documented — so the shape is agreed before the logic exists, and iOS work isn't blocked.
- **`src/domain/budget.js`** — the adaptive 50/30/20 engine, ported from the prototype (where it appears twice, identically), with tests on both branches.
- **`src/domain/money.js`** — the `HWMoney` conversion and rounding rules server-side, so the app and the reports agree to the last digit.
- **`src/domain/securityAnswers.js`** — the normalise-and-compare matcher, with the prototype's own worked cases as tests: `Biscuit`/`biscuit` ✓, `Biscuit`/`" BISCUIT! "` ✓, `St Mary's`/`st marys` ✓, `Jaipur`/`Jodhpur` ✗.
- **Mongoose schemas** for the §B.4 collections, with the `{amount, currency}` rule enforced by a shared sub-schema.
- **`src/jobs/`** — `fxRefresh.js`, `monthRollover.js`, `streakRemind.js`, each runnable as `node src/jobs/<name>.js` so Render Cron can invoke them directly and they can be dry-run locally.
- `.env.example`, `.gitignore`, ESLint config.
- `.github/workflows/ci.yml` — push/PR to `main`: checkout → Node → `npm ci` → lint → test; then, only on push to `main` with job 1 green, `curl -X POST $RENDER_DEPLOY_HOOK_URL`.
- `docs/api.md` — the endpoint contract.

### B.5.2 Content extraction — `HisaabWiseBackend/content/`
The prototype carries ~350 KB of editorial content inline. Extracted into structured, seedable JSON — and per §A.3, this is the product's moat, so it gets first-class treatment:

- `tips.en.json` — 49 tips, `{c}` tokens preserved.
- `articles.en.json` — 3 articles with full section/list/steps/callout/sources structure.
- `curriculum.en.json` — 5 units, 15 lessons, ~115 steps, question kinds and answer keys intact.
- `reference/countries.json` (251), `currencies.json` (160), `languages.json` (87).
- `picklists.json` — 22 transport modes, 20 "Other" types.
- `npm run seed` loads these into Mongo, versioned so the app caches on ETag.

**On answer keys:** the curriculum JSON contains correct answers, so a determined user can read them. Acceptable for a self-paced literacy course — the incentive to cheat is nil — and it buys full offline lessons. A conscious choice, not an oversight.

### B.5.3 iOS repo — `HisaabWiseIOS/`
- A standard Swift/Xcode `.gitignore` (DerivedData, `.xcuserstate`, `xcuserdata/`, build products, `.swiftpm`).
- `docs/design-tokens.md` — the palette (`galaxy #081F5C`, `planetary #334EAC`, `universe #7096D1`, `venus #BAD6EB`, `sky #D0E3FF`, `meteor #F7F2EB`, `milky #FFF9F0`), the two easing curves, category colour slots 1–6, and the Learn unit accents (`sun`, `mint`, `coral`, `sky`, `violet`) — extracted from the prototype CSS so the asset catalogue matches exactly.
- `docs/screen-inventory.md` — the seven screens with every state, sheet, dialog and empty state, as a build checklist.
- `docs/user-journey.md` — the 17-step walkthrough from the business plan document, as the canonical funnel. **[NEW in v3]**
- **No `.xcodeproj` from me.** A real Xcode project needs Xcode's GUI, which can't be driven from a CLI. One-time manual step (§B.6.11); after that, app code is fair game.

## B.6 What you'll need to do manually

Dashboard and account actions I can't perform, ordered so nothing blocks on something later.

### Backend and data
1. **MongoDB Atlas** — create the account/project. Start on **M10** (or Flex to defer cost) with **continuous backup**, not M0. Create a DB user scoped to the app database, never admin. Network Access: Render's Starter tier has no static outbound IPs, so allow `0.0.0.0/0` secured by a long generated password — standard at this stage; revisit if you move to a tier with static egress. Create separate `hisaabwise-staging` and `hisaabwise-prod` databases. Copy both connection strings.
2. **Render — production** — connect `HisaabWiseBackend`. **Starter Web Service**: build `npm ci`, start `npm start`, health check `/health`. Turn **off** Render's auto-deploy-on-push (Actions triggers deploys after tests pass). Copy the **Deploy Hook URL**.
3. **Render — staging** — the same service on free or Starter, pointed at the staging database, auto-deploying from a `staging` branch. Where rollover jobs get tested.
4. **Render Cron Jobs** — three, against production: `fx:refresh` daily, `month:rollover` hourly, `streak:remind` daily.
5. **FX rate provider** — an account with a mid-market feed (openexchangerates.org, exchangerate.host, Fixer, or the ECB feed if EUR-based is acceptable). Confirm the free tier covers 160 currencies at one call/day. Copy the key.
6. **Transactional email** — Resend, Postmark or SES. Verify the sending domain in Cloudflare (SPF, DKIM, DMARC). Copy the key. Without this, password reset cannot ship.
7. **Sentry** — one org, two projects: `hisaabwise-backend` (Node), `hisaabwise-ios` (Apple). Copy both DSNs.
8. **GitHub repo secrets** — on `HisaabWiseBackend`: `RENDER_DEPLOY_HOOK_URL`. Everything else lives in Render's environment variables (§B.7), not GitHub.
9. **Cloudflare**
   - `CNAME api` → the `.onrender.com` hostname, proxy **ON**.
   - SSL/TLS **Full (strict)**, to avoid redirect loops with Render's certificate.
   - **Rate limiting** on `/auth/*`. Cloudflare's free plan includes a limited number of rate-limiting and custom WAF rules — check the current allowance; if it's too tight, either upgrade or rely on `express-rate-limit`. The app-level limiter stays either way, as defence in depth.
   - **Cache rules:** cache `GET /content/*`, `/curriculum*`, `/fx/rates`; **bypass** everything under `/auth/*`, `/me*`, `/expenses*`, `/reports*`, `/learn/progress*`. Get this wrong permissively and you serve one user's financial data to another. Treat it as a security control and verify it (§B.8).
   - **Cloudflare Pages** — a static site for marketing, **Terms of Service** and **Privacy Policy**. The privacy policy URL is mandatory for submission.
   - Email authentication records for step 6.

### iOS and TestFlight (sequential)
10. **Enrol in the Apple Developer Program** — ~$99/year, approval 24–48h. Nothing below works until it's active; start here.
11. **Create the Xcode project** — `File > New > Project` → iOS App → save inside `HisaabWiseIOS/` with a real bundle ID (e.g. `com.hisaabwise.ios`). Commit and push.
12. **Create the App Store Connect app record** — matching the bundle ID.
13. **APNs auth key** — Certificates, Identifiers & Profiles → Keys → new key with **Apple Push Notifications service** enabled. Download the `.p8` **once**; it cannot be re-downloaded. Note the Key ID and Team ID.
14. **Enable Xcode Cloud** — `Product > Xcode Cloud > Create Workflow`. Installs Xcode Cloud's GitHub App on `HisaabWiseIOS` (approve when prompted), so it triggers on pushes with no tokens to manage. The Developer Program includes a monthly compute-hour allowance (25 hours at time of writing) — enough for internal builds.
15. **Configure the workflow** — trigger: push to `main`; action: Archive; post-action: **TestFlight Internal Testing**. Managed signing — no Fastlane Match, no manual certificates.
16. **Add internal testers** — TestFlight → Internal Testing → your Apple ID and anyone else.
17. **App Privacy declarations** — this app collects name, email, phone, DOB and **financial information**, so the declarations are substantive and Apple checks them. Add a **privacy manifest** (`PrivacyInfo.xcprivacy`) declaring required-reason API use, and confirm every third-party SDK (Sentry included) ships its own signed manifest.
18. **Age rating** — set to reflect the 13+ gate.

## B.7 Environment variables

`.env.example` carries this list with empty values. Real values go in Render's per-service settings (staging and production separately) — never in the repo.

| Variable | Purpose |
|---|---|
| `NODE_ENV` | `production` / `staging` |
| `PORT` | provided by Render |
| `MONGODB_URI` | Atlas connection string, per environment |
| `JWT_ACCESS_SECRET` | signs short-lived access tokens |
| `JWT_REFRESH_SECRET` | signs rotating refresh tokens |
| `ACCESS_TOKEN_TTL` / `REFRESH_TOKEN_TTL` | e.g. `15m` / `60d` |
| `FX_PROVIDER_API_KEY` | mid-market rate feed |
| `FX_BASE_CURRENCY` | `USD` — the prototype's rate table is USD-based |
| `EMAIL_PROVIDER_API_KEY` | transactional email |
| `EMAIL_FROM` | e.g. `no-reply@<yourdomain>.com` |
| `APNS_KEY_P8` | the `.p8` contents (multi-line secret) |
| `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID` | push identifiers |
| `SENTRY_DSN` | backend error reporting |
| `CORS_ORIGINS` | allowed origins (marketing site; the iOS app needs none) |
| `RATE_LIMIT_WINDOW_MS`, `RATE_LIMIT_MAX` | app-level limiter |
| `LOG_LEVEL` | pino level |

## B.8 Verification

Things you can run and see, not checkboxes.

**Local**
- `npm install && npm run dev`, hit `/health`, confirm `{status:"ok"}` and a successful Mongo connection in the log.
- `npm test` — both budget branches, the money rounding rules, and the four security-answer cases pass.
- `npm run seed`, then `GET /content/tips` returns 49 tips and `GET /curriculum` returns 5 units / 15 lessons.

**CI**
- Open a throwaway PR; confirm lint + test run and pass.
- Push a deliberately failing test to a branch; confirm the deploy job does **not** fire.

**Deploy**
- Push to `main`; the deploy-hook job fires and Render shows a new deploy.
- Render's health check goes green and stays green.

**Domain**
- `curl https://api.<yourdomain>.com/health` returns `{status:"ok"}` over HTTPS.
- `curl -I` twice, confirm no redirect loop (the Full-strict check).

**Cache correctness — do this one carefully**
- `curl` a content endpoint twice; the second shows a Cloudflare cache HIT.
- Sign in as two users, `curl /me` for each with their own token; confirm **different** bodies and `cf-cache-status: BYPASS` or `DYNAMIC` on both. A HIT here is a data leak, not a performance win.

**FX**
- Run `node src/jobs/fxRefresh.js`; a dated document lands in `fx_rates` with all 160 codes.
- `GET /fx/rates` returns it, carrying the rate date.
- Break the provider key and re-run; the previous rates stay live, the job exits non-zero, and an alert reaches you.

**Month rollover**
- On **staging**, seed a user with a month of expenses, run `node src/jobs/monthRollover.js` with a forced boundary; a `month_archives` document appears with salary, goal, saved and the full entry payload, and the live month is cleared while rent and utility lines carry forward.
- Run it **twice**; the second run writes nothing.
- Open Reports against staging; the archived month renders with the totals it had when live.
- Change display currency; the archived month's figures convert but its **story** doesn't — the goal-hit verdict stays what it was.

**Salary consistency** **[NEW in v3]**
- Register with a salary in one currency (say INR), then check Home, Expenses, Account and Reports all show the **same** income, and Home's "% of pay" is computed against it. This is the regression test for the §A.7 defect.

**iOS**
- Push to `main`; a build starts, completes, and appears under TestFlight → Internal Testing within minutes.
- Install via TestFlight on a real device.
- Sign in, force-quit, reopen: still signed in (Keychain works).
- Airplane mode: the app opens, cached content renders, a logged expense queues and syncs on reconnect.

**Monitoring**
- Throw a deliberate error in a staging route; it appears in Sentry with a usable stack trace.
- Stop the staging service; the uptime monitor alerts you.

---
---

# PART C — DECISIONS AND DELIVERY

## C.1 Open questions

Each changes what gets built, so resolve before the corresponding code is written.

1. **Username vs email as the sign-in identifier.** *(Blocking the auth schema.)* Sign-in asks for a username; registration never collects one. Options: (a) sign in with **email**, drop the username field — simplest, one fewer unique index, and the design already treats email as the identity anchor ("it is how we verify it is you"); (b) add a username to registration step 1 with a live availability check; (c) auto-derive one and let users edit it. **Recommendation: (a).** The Account screen already treats "Username" as a display name, which fits cleanly.

2. **How many languages at launch.** *(Biggest scope risk.)* 87 languages across UI, 49 tips, 3 long articles and ~115 lesson steps is months of work, and machine-translating financial-literacy content is genuinely risky — a mistranslated sentence about debt burden ratios is worse than no translation. **Recommendation: English plus Arabic** (RTL, and the market's second language) **at launch, with only shipped languages in the picker.** Offering 87 and delivering 2 is worse than offering 2. Architect for more; add them as translations land.

3. **Historical FX: pin or float.** **Recommendation: pin at month close.** Financial history that changes retroactively is a bug users will report as one.

4. **Account deletion.** *(Blocking submission.)* Needs a design, an endpoint, and a hard-delete-vs-grace-period decision. **Recommendation: 30-day soft delete, then hard erase** — a way back from a mistake, and it satisfies the guideline.

5. **Offline expense entry.** The core loop is logging a spend in the moment, often with no signal. **Recommendation: a local write queue that drains on reconnect**, not full bidirectional sync — it covers the real scenario at a fraction of the cost.

6. **Salary and "saved": one source of truth each.** *(Now two defects, not one.)* **Salary:** Home hardcodes `8000` AED and never reads the user's figure, while Account defaults its base to INR — so the app can show two different incomes and compute "% of pay" against the wrong one. **Saved:** the Home screen reads `state.saved` as a given and the design never shows the user entering it; the Reports facts grid implies it's computed. Both need one server-owned value, and if `saved` is computed it must agree with the budget engine or two cards on the same screen will disagree.

7. **Dark mode.** Every screen declares a light `theme-color`; the palette is light-first. **Recommendation: ship light-only, but use semantic colour names in the asset catalogue from the start** so adding it later is a palette swap, not a rewrite.

8. **Additional Income and the budget.** Extra income currently lifts every allowance, so a freelance windfall silently raises the wants budget — possibly undermining the savings goal in the month it was most achievable. Worth a deliberate decision.

9. **Monetisation.** **[NEW in v3]** §A.4. **Recommendation: launch free, no StoreKit, and reword "Free to start."** It promises a paid tier that doesn't exist.

10. **Launch market.** **[NEW in v3]** §A.3. Every figure and regulator in the content is UAE-specific, so a second market means new content, not translation. Worth confirming this is UAE-first by design.

## C.2 Delivery phases

Sequenced so each phase ends with something usable, and nothing waits on the Apple approval clock unnecessarily.

| Phase | Scope | Resolves |
|---|---|---|
| **0 — Foundations** | Backend scaffold, content extraction, CI, Atlas, Render staging + production, Cloudflare DNS, `/health` green end to end. Apple enrolment in parallel. | — |
| **1 — Identity** | Register (3 steps), sign in, refresh, logout, password reset by email, server-side security-question verification, **account deletion**. | Q1, Q4 |
| **2 — Money in and out** | Expense entries, fixed costs and utility lines, category taxonomy and pick lists, the budget engine, FX ingestion. Home and Expenses become real. | Q3, Q6 |
| **3 — Learning** | Curriculum service, progress persistence, server-owned streak, XP. Learn becomes real. *(If you choose freemium, entitlements land here — before the content they gate.)* | — |
| **4 — History** | Month rollover job, archive API, Reports screen. Staging first, with the idempotency test as the gate. | — |
| **5 — Retention and polish** | Push notifications, launch-set localisation, Sentry dashboards and alert routing, App Store metadata, privacy declarations, submission. | Q2, Q7 |

## C.3 Explicitly out of scope

Decisions, not omissions:

- **Bank account linking / open banking.** Nothing in the design implies it, and it multiplies the compliance surface enormously.
- **In-app purchases / StoreKit.** Per §A.4, deferred until there's evidence of willingness to pay.
- **Multi-device real-time sync.** Progress syncs on request; live cross-device updates aren't needed here.
- **Web app.** Cloudflare Pages is marketing plus Terms and Privacy only.
- **Leaderboards or social features in Learn.** No design for them, and they'd force server-side grading.
- **Product analytics SDKs.** Sentry plus backend counters cover §A.6, without worsening the App Privacy declaration.
- **Fastlane / manual code signing.** Managed signing suffices until you outgrow it.
- **Kubernetes, containers, IaC.** Render is the right abstraction at this size.

---

*Document version 3. Written against `HisaabWise_6.html` (7 screens) and `Application_Business_Plan_2.docx` (17-step walkthrough, 15 screenshots). Where the plan and the sources disagree, the disagreements are listed in §C.1 rather than silently resolved. Cost figures in §A.5 are indicative and should be verified against current provider pricing.*
