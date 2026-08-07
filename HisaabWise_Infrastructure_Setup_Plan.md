# HisaabWise Infrastructure Setup Plan

**Version 2 — revised against the `HisaabWise_6.html` interactive design (7 screens, stitched prototype).**
Supersedes v1, which was written before any app features existed.

---

## 1. Context

HisaabWise is an iOS app with a Node.js backend, MongoDB database, and a Cloudflare-managed domain. Two repos exist:
[HisaabWiseIOS](https://github.com/makinananya-cyber/HisaabWiseIOS) and
[HisaabWiseBackend](https://github.com/makinananya-cyber/HisaabWiseBackend).

**What changed since v1.** v1 planned a hosting + database + CI/CD skeleton for an app with no defined features, so it assumed one thing the backend had to do: answer `GET /health` and hold whatever data turned up later. The design file changes that assumption substantially. HisaabWise is now a seven-screen product with:

- a three-step registration flow with security questions and a savings-goal calculator,
- a **multi-currency display engine** (`HWMoney`) covering 160 currencies that converts every figure in the app at render time,
- a **gamified learning course** — 5 units, 15 lessons, ~115 steps, with hearts, XP, combos and a day streak,
- an **immutable monthly report archive** that snapshots a completed month's salary, goal, savings and every logged entry,
- an adaptive **50/30/20 budgeting engine** shared by the Expenses and Reports screens,
- editorial content: 49 rotating tips and 3 long-form researched articles,
- a settings screen offering **87 app languages**.

Each of those is a backend responsibility, a scheduled job, a content pipeline, or a compliance obligation that v1 did not budget for. This document restates the whole plan with those requirements folded in, and marks each material change with **[NEW in v2]** or **[CHANGED in v2]**.

**Key finding carried over from v1 (unchanged and still binding):** MongoDB's Atlas Data API — the REST route into MongoDB from edge runtimes like Cloudflare Workers — was shut down on 30 September 2025. Workers can open raw TCP sockets now, but the native MongoDB driver over that path is not production-ready under Workers' ephemeral execution model (connection pooling and cold-start behaviour). So: **the backend runs as a normal long-lived Node.js server**, and **Cloudflare is used for DNS, CDN, TLS, WAF and caching only** — never as the database client.

---

## 2. What the design file actually requires

This section is the evidence base for the rest of the plan. It is a walk through the prototype, screen by screen, listing what each screen needs from the infrastructure.

### 2.1 Landing (`landing`)
Static hero, rotating strapline, single "Get Started" CTA. No backend. Worth noting only because the four straplines and the "Free to start · No card required" line are marketing copy that should live in the app bundle, not on the server.

### 2.2 Auth (`auth`) — sign in + 3-step registration
| Step | Fields collected |
|---|---|
| Sign in | **username** + password, "Keep me signed in" toggle, "Forgot password?" |
| Register 1 | Full name, email, phone (dial code chosen from **251 countries**, stored as E.164), date of birth, password + confirm, Terms & Privacy consent |
| Register 2 | Currency (**160 ISO-4217 currencies**), monthly salary, **two security questions** chosen from a 14-question bank, plus answers |
| Register 3 | Monthly savings goal, pre-filled with 20% of salary, with a "Skip for now" that accepts the suggestion |

Infrastructure consequences:

- **Sign-in identifier is `username`, not email.** The prototype signs in with a username but never collects one during registration — registration collects full name, email and phone only. **This is an unresolved gap in the design** and it changes the user schema. Decision needed before the auth endpoints are built (see §9, Open Questions).
- **Password rules:** minimum 8 characters at registration, with a 4-level strength meter (length ≥8, ≥12, mixed case, digit + symbol). The sign-in form accepts 6+. Server must enforce one consistent rule — take the stricter one.
- **Security answers must never reach the client.** The design says so itself, twice: *"hash these on the server — never store or send a raw answer."* But the Account screen's password-reset flow verifies answers **locally**, using a fuzzy matcher (accent strip, punctuation strip, filler-word removal, plural tolerance, Levenshtein distance ≤ 1 on words of 5+ characters). That matcher has to be **reimplemented server-side**, and the stored value has to be a hash of the *normalised key words*, not of the raw string — otherwise fuzzy matching is impossible against a hash. **[NEW in v2]**
- **Age gate at 13.** The DOB field caps at today-minus-13 and rejects anything younger. That drives the App Store age rating and pulls in children's-privacy obligations in several markets.
- **Terms & Privacy Policy must exist at a public URL** before the first TestFlight external build and before App Store submission.
- **"Forgot password?" is unimplemented** — the prototype only toasts *"We'll email you a reset link — feature coming next."* That means a transactional email provider is now a hard dependency. **[NEW in v2]**
- Rate limiting is required on sign-in, registration, password reset and security-question verification. The prototype already counts failed security-question attempts and, after three, suggests contacting support — so lockout/backoff behaviour is part of the design, and it belongs on the server.

### 2.3 Home (`home`) — dashboard
- Spending donut by category, with a distinct **first-run empty state** (grey ring + a single "Add Expenses" CTA).
- Savings meter: saved vs goal, with a sliding pin and a percentage pill.
- **Tip of the day** — 49 tips selected by day-of-year so the rotation is deterministic and changes at midnight. Tips contain `{c}` tokens that are replaced with the live currency symbol, and inline `<b>`/`<i>` markup.
- **Streak + XP mini-card** reading `streak` and `nextLesson` from the Learn domain.
- **"Read more" articles** — 3 long-form pieces (scam awareness, remittances, debt management) with sections, key-value lists, numbered steps, callouts and **external source links** to u.ae, the Central Bank of the UAE rulebook, Al Etihad Credit Bureau explainers and others.

Infrastructure consequences: tips and articles are **editorial content that will change more often than the app ships**. They need to be served from the backend and cached at the CDN, not compiled into the binary. They also need to be translatable (§2.7). **[NEW in v2]**

### 2.4 Expenses (`expenses`)
Two levels: a category list with a monthly summary, and a per-category detail page.

Seven categories across three structural kinds:

| Kind | Categories | Behaviour |
|---|---|---|
| `log` | Groceries, Transport, Entertainment, Other, **Additional Income** | Append-only entries with amount, label, timestamp; individually deletable |
| `lines` | Utilities | Several named monthly bills (Electricity, Water, Phone/data), each editable, addable and removable |
| `fixed` | Rent | One editable monthly amount |

- Transport offers a 22-option pick list; Other offers 20 options plus a **"Something else…"** free-text escape hatch.
- **Additional Income is money in**, excluded from the spending donut, rendered in a distinct treatment, and it **increases every budget allowance**.
- The **adaptive 50/30/20 engine**: needs = rent + utilities + groceries; wants = transport + entertainment + other. While needs fit inside 50% of income, the plain rule applies (30% wants / 20% savings). Once needs exceed half of income the rule can't hold, so whatever is left after needs is split evenly between wants and savings. This exact logic appears in **both** the Expenses and Reports screens.
- Amounts are **typed in the display currency and stored in a base currency** (`M.from(value, BASE)`).

Infrastructure consequences: the budgeting engine must live in **one** place — the backend — and be served as computed values, not reimplemented in Swift and in the report generator, or the two will drift. The category taxonomy and both pick lists should be server-served so they can be extended without an app release. **[NEW in v2]**

### 2.5 Learn (`learn`) — the gamified course
- **5 units, 15 lessons, ~115 steps.** Step types: `teach` (headline, paragraphs, optional key-value list, worked example, "Remember it" tip) and `q` (question).
- Question kinds: `choice` (50), `num` (14, numeric with tolerance ±0.5, optional currency prefix), `multi` (2, all-correct-required).
- **Hearts:** 3 per run; a wrong answer costs one; at zero, an "Out of hearts" dialog offers retry or exit.
- **XP:** 10 per correct answer + 20 completion bonus.
- **Combos:** streak counter within a lesson, celebrated every 3rd consecutive correct answer.
- **Day streak:** increments once per calendar day on the day a lesson is finished, tracked via a `lastActive` day key.
- **Partial progress:** leaving mid-lesson saves the count of correct answers so the node's progress ring persists.
- **Sequential unlocking:** a lesson opens only once the previous one is complete.
- Completion screen shows XP earned, accuracy %, day streak and a seven-day week strip.

Infrastructure consequences, all new:

- Curriculum is **versioned content**, ~156 KB of it in the prototype and growing. It must be server-served and CDN-cached, with a version/etag so the app can cache aggressively and revalidate cheaply.
- Learner progress (`xp`, `streak`, `lastActive`, `done{}`, `progress{}`) needs a persistence API and must survive reinstall and sync across devices.
- **The day streak has a timezone problem.** The prototype computes the day key from the device clock, so changing the device timezone or clock manipulates the streak. The server must own the streak boundary using a stored per-user timezone. **[NEW in v2]**
- **XP is client-computed.** For a single-player app the fraud risk is low, but leaderboards or rewards later would require server-side grading. Recommendation: keep grading on the client for launch, but have the client submit *which questions were answered how*, so the server can recompute XP and detect impossible submissions.
- Streaks are the main reason to add **push notifications** (§4.6). **[NEW in v2]**

### 2.6 Reports (`reports`)
- An archive with **one immutable record per completed month**, whose shape deliberately mirrors the Expenses screen (`fixed` + `log`) "so a finished month can be filed here untouched when it rolls over."
- Each record carries that month's `salary`, `goal` and `saved` — values that change over time, so they must be snapshotted, not looked up.
- Level 1: savings-goal trend chart (bars coloured by hit/near/miss against a dashed goal line), grouped by year with per-year savings totals, plus per-month proportion bars.
- Level 2, per month: totals with fixed/variable/extra-in split, the Home donut for that month, the savings meter, the wants-budget card, a needs/wants/savings/unspent split bar, an accordion of every logged entry, and a "For the record" facts grid.

Infrastructure consequences:

- **A month-rollover job is now a required piece of backend infrastructure.** At each user's local month boundary, the current month must be closed, snapshotted immutably into the archive, and the live month reset. This is the single largest addition in v2, and it needs a scheduler, idempotency (a retried job must not double-write), and per-user timezone awareness. **[NEW in v2]**
- **Historical FX must be pinned.** The prototype converts the whole archive at *today's* rate, which means switching currency silently rewrites financial history. A February report should not change because the dirham moved in August. Each monthly snapshot must store the base amounts **and** the FX rate in effect at close, and render history at that pinned rate. **[NEW in v2 — this is a correctness decision, not just an infra one.]**

### 2.7 Account & Settings (`account`)
- Profile header with initials avatar, name, email.
- **Personal Information** — username and salary and phone are editable; **email is deliberately locked** ("it is how we verify it is you").
- **Language** — a searchable list of **87 languages**, with the promise: *"Every screen, label and report will be written in the language you pick."*
- **Currency** — searchable list of 160; picking one broadcasts to every screen, which converts and repaints in step.
- **Password change** — three steps: current password → both security questions (fuzzy-matched) → new password with strength meter.
- **Log Out** with a confirmation dialog.

Infrastructure consequences:

- **The 87-language list is the biggest scope risk in the design.** It promises full localisation of UI, content and reports — tips, 3 long articles, 15 lessons and ~115 lesson steps — in 87 languages, including RTL languages (Arabic, Hebrew, Urdu, Persian). Delivering that is a translation-operations programme, not a settings screen. Recommendation in §9. **[NEW in v2]**
- **There is no "Delete account".** App Store Review Guideline 5.1.1(v) requires apps that support account creation to also support **in-app account deletion**. As designed, this app will be rejected. This needs a screen, an endpoint and a data-erasure path. **[NEW in v2 — blocking for App Store submission.]**

### 2.8 Cross-cutting: the `HWMoney` runtime
The shell injects a currency runtime into every screen. Every figure is authored in a base currency (`AED` in most screens, the signup currency for salary) and rendered through `HWMoney`, which converts, rounds by magnitude (nearest 100 above 100k, nearest 10 above 10k), spaces multi-letter codes (`AED 500` vs `₹500`), and broadcasts changes so all screens repaint together.

Rates are a **static snapshot of 160 currencies**, with an explicit note in the source: *"Rates are an indicative static snapshot. Point conv() at a live feed and nothing else has to change."*

**That live feed is now a backend service.** **[NEW in v2]** And it matters more than usual here: one of the app's own articles teaches users to compare a provider's rate against the mid-market rate and treat the gap as the true cost. An app that does that while showing months-old rates undercuts its own credibility.

---

## 3. Decisions locked in

| Area | v1 decision | v2 decision | Why it changed |
|---|---|---|---|
| Backend hosting | Render, **free tier** | Render, **Starter (paid) Web Service** | Free instances sleep after ~15 min idle; the next request pays a cold start of roughly a minute. Unacceptable for a consumer app opened in a shop to log a purchase. |
| Database | Atlas **M0 free** | Atlas **M10 (or Flex), with continuous backup** | M0 has no backups and no point-in-time restore. This app holds a household's financial history; losing it is unrecoverable in a way that a to-do list isn't. |
| Scheduled jobs | none | **Render Cron Jobs** — FX refresh, month rollover, streak reminders | Reports and multi-currency require them. Cron Jobs are a paid Render feature. |
| Domain / DNS | Cloudflare DNS + proxy | Unchanged, **plus WAF rate limiting, cache rules, and Cloudflare Pages** for the marketing site and Terms/Privacy | Auth endpoints need rate limiting; content endpoints benefit hugely from CDN caching; the App Store requires a hosted privacy policy. |
| Environments | **Production only** | **Staging + Production** | A buggy month-rollover job destroys data irreversibly. That class of job must be exercised somewhere that isn't production. |
| Backend CI/CD | GitHub Actions → Render deploy hook | Unchanged, plus **migration and job-dry-run steps** | |
| iOS CI/CD | Xcode Cloud → TestFlight | Unchanged | |
| Monitoring | **out of scope** | **Sentry (backend + iOS), uptime check, log drain, job-failure alerts** | A silently failing rollover job is invisible until a user notices a month is missing. |
| Email | not considered | **Transactional email provider** (Resend / Postmark / SES) | Password reset and email verification. |
| Push | not considered | **APNs**, via an auth key (.p8) | Streak reminders are the app's core retention mechanic. |
| FX rates | not considered | **Provider + daily ingestion + Mongo cache + pinned historical rates** | The whole app renders through a currency conversion layer. |
| Auth tokens | not considered | **Short-lived access JWT + rotating refresh token**, refresh stored in iOS Keychain | "Keep me signed in" is in the design. |

---

## 4. Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│  iOS App (HisaabWiseIOS) — SwiftUI, 5-tab shell                         │
│  Home · Expenses · Learn · Reports · Account                            │
│                                                                          │
│  · Keychain: refresh token          · Local cache: offline expense entry │
│  · Content cache: curriculum, tips, articles, FX (ETag-revalidated)     │
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
│                │      │ · month:rollover hrly │   │ · Email (Resend/…) │
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

### 4.1 Screen-to-Swift mapping
The prototype is seven standalone HTML documents stitched together in iframes with `postMessage`. That is a prototyping device, not an architecture. In the iOS app:

- The shell's `ORDER` array and `postMessage` navigation become a `TabView` with a `NavigationStack` per tab.
- The two-level list→detail pattern (Expenses, Reports, Account) becomes `NavigationLink` push.
- The `HWMoney` broadcast becomes an observable app-level currency object; every view formats through it.
- The bottom sheets (country, currency, language, pick lists) become `.sheet` with a searchable list.
- The Learn player becomes a full-screen cover.

### 4.2 The base-currency rule
One rule, applied everywhere, or the money will be wrong:

> **Every monetary value is stored as `{ amount, currency }` — never as a bare number.**

The prototype already hints at why: salary is held in `signupCurrency` and separately re-based, while expenses are held in `AED`. Storing amount-plus-currency makes currency changes a display concern rather than a migration.

### 4.3 FX rates
- One daily cron job pulls mid-market rates for the 160 supported currencies and writes a dated document to `fx_rates`.
- `GET /fx/rates` serves the newest set, cached at Cloudflare for ~1 hour.
- `GET /fx/rates/:yyyy-mm` serves the set pinned at that month's close, for the report archive. Immutable, cached for a year.
- If ingestion fails, the previous set stays live and an alert fires. Rates never fall back to hardcoded values silently.
- Surface the rate date in the UI wherever converted totals are shown in a non-base currency.

### 4.4 Month rollover
- Runs hourly; each run selects users whose local time has just crossed into a new month.
- Writes a `month_archives` document: month key, salary, goal, saved, the full `fixed` + `log` payload, and the FX rate set id.
- Idempotent on `(userId, monthKey)` with a unique index, so a retry cannot double-write.
- Resets the live month: `log` entries cleared, `fixed` costs (rent, utility lines) carried forward unchanged.
- Emits a structured log line and a metric per user processed; alerts if the count is zero on a day when it shouldn't be.

### 4.5 Localisation
- UI strings live in the iOS app (String Catalogs, `.xcstrings`).
- Content strings (tips, articles, curriculum) are served by the backend, keyed by locale, selected via `Accept-Language` with fallback to `en`.
- RTL support is a layout concern in SwiftUI (leading/trailing rather than left/right) — cheap if done from the start, expensive to retrofit.
- Ship a small launch set of languages, not 87 (§9).

### 4.6 Push notifications
- APNs auth key (.p8) in backend secrets; device tokens stored per user per device.
- Launch scope: one streak reminder, sent in the user's evening local time, only if no lesson was completed that day, and only if the user opted in.
- The daily `streak:remind` cron job does the selection.

---

## 5. What I'll set up directly (in-session, in-repo)

### 5.1 Backend scaffold — `HisaabWiseBackend/`
Everything from v1, plus the structure the new domains need.

- `package.json` — Express, Mongoose, dotenv, cors, helmet, plus **argon2** (password + security-answer hashing), **jsonwebtoken**, **zod** (request validation), **pino** (structured logs), **express-rate-limit**. Scripts: `start`, `dev`, `lint`, `test`, `migrate`.
- `src/server.js` — app entrypoint, reads `PORT`.
- `src/db.js` — Mongoose connection from `MONGODB_URI`, fails fast with a clear error if absent.
- `GET /health` — returns `{status:"ok"}` plus a DB-reachable flag. Used by Render's health check and the uptime monitor.
- **Route modules** for each domain in §4, initially returning `501 Not Implemented` with the intended contract documented. This gets the shape agreed before the logic is written, and gives the iOS team something to code against.
- **`src/domain/budget.js`** — the adaptive 50/30/20 engine, ported verbatim from the prototype (it appears twice there, identically), with unit tests covering both branches: needs under half of income, and needs over.
- **`src/domain/money.js`** — the `HWMoney` conversion and rounding rules as a server module, so the app and the reports agree to the last digit.
- **`src/domain/securityAnswers.js`** — the normalise-and-compare matcher (accent strip, punctuation strip, filler removal, plural tolerance, Levenshtein ≤ 1 on 5+ char words), ported from the Account screen, with the prototype's own worked cases as tests: `Biscuit`/`biscuit` ✓, `Biscuit`/` BISCUIT! ` ✓, `St Mary's`/`st marys` ✓, `Jaipur`/`Jodhpur` ✗.
- **Mongoose schemas** for the collections in §4, with the `{amount, currency}` money rule enforced by a shared sub-schema.
- **`src/jobs/`** — `fxRefresh.js`, `monthRollover.js`, `streakRemind.js`, each runnable as `node src/jobs/<name>.js` so Render Cron Jobs can invoke them directly and so they can be dry-run locally.
- `.env.example` (no real secrets) and a Swift/Node `.gitignore`.
- ESLint config so the CI lint step has something to run.
- `.github/workflows/ci.yml`:
  - triggers on `push` and `pull_request` to `main`
  - job 1: checkout → setup Node → `npm ci` → `npm run lint` → `npm test`
  - job 2 (only on `push` to `main`, needs job 1 green): `curl -X POST $RENDER_DEPLOY_HOOK_URL`
- `docs/api.md` — the endpoint contract, so iOS work isn't blocked on backend completion.

### 5.2 Content extraction — `HisaabWiseBackend/content/`
The prototype carries roughly 350 KB of editorial content inline. I'll extract it into structured, seedable JSON:

- `tips.en.json` — the 49 tips, `{c}` tokens preserved.
- `articles.en.json` — the 3 articles with their full section/list/steps/callout/sources structure.
- `curriculum.en.json` — 5 units, 15 lessons, ~115 steps, with question kinds and answer keys intact.
- `reference/countries.json` (251), `currencies.json` (160), `languages.json` (87).
- `picklists.json` — the 22 transport modes and 20 "Other" types.
- A `npm run seed` script that loads these into Mongo, versioned so the app can cache on ETag.

**Note on answer keys:** the curriculum JSON contains correct answers. If it is served whole, a determined user can read them. That is acceptable for a self-paced financial-literacy course — the incentive to cheat is nil — and it buys full offline lesson support. Flagging it as a conscious choice rather than an oversight.

### 5.3 iOS repo — `HisaabWiseIOS/`
- A standard Swift/Xcode `.gitignore` (DerivedData, `.xcuserstate`, `xcuserdata/`, build products, `.swiftpm`), so the first Xcode project commit is clean.
- `docs/design-tokens.md` — the palette (`galaxy #081F5C`, `planetary #334EAC`, `universe #7096D1`, `venus #BAD6EB`, `sky #D0E3FF`, `meteor #F7F2EB`, `milky #FFF9F0`), the two easing curves, the category colour slots 1–6, and the accent names used by the Learn units (`sun`, `mint`, `coral`, `sky`, `violet`) — extracted from the prototype CSS so the Swift asset catalogue matches it exactly.
- `docs/screen-inventory.md` — the seven screens with their states, sheets, dialogs and empty states, as a build checklist.
- **No `.xcodeproj` from me.** Creating a real Xcode project needs Xcode's GUI (`File > New > Project`), which can't be driven from a CLI. That is a one-time manual step (§6.6); after it, app code is fair game.

---

## 6. What you'll need to do manually

Dashboard and account actions I can't perform. Ordered so nothing blocks on something later in the list.

### Backend and data
1. **MongoDB Atlas** — create the account/project. **[CHANGED in v2]** Start on **M10** (or Flex if you want to defer cost), not M0, and turn on **continuous backup**. Create a DB user scoped to the app database only, never admin. Network Access: because Render's Starter tier has no static outbound IPs, allow `0.0.0.0/0`, secured by a long generated password — standard for this stage. Revisit if you move to a Render tier with static egress. Create **two** databases or two projects, `hisaabwise-staging` and `hisaabwise-prod`. Copy both connection strings.
2. **Render — production** — connect the `HisaabWiseBackend` repo. Create a **Starter Web Service**: build `npm ci`, start `npm start`, health check path `/health`. Turn **off** Render's own auto-deploy-on-push (GitHub Actions triggers deploys after tests pass instead). Copy the **Deploy Hook URL**.
3. **Render — staging** — **[NEW in v2]** the same service on a free or Starter instance, pointed at the staging database, auto-deploying from a `staging` branch. This is where rollover jobs get tested.
4. **Render Cron Jobs** — **[NEW in v2]** three jobs against the production service:
   - `fx:refresh` — daily, `node src/jobs/fxRefresh.js`
   - `month:rollover` — hourly, `node src/jobs/monthRollover.js`
   - `streak:remind` — daily, `node src/jobs/streakRemind.js`
5. **FX rate provider** — **[NEW in v2]** create an account with a mid-market rate provider (openexchangerates.org, exchangerate.host, Fixer, or the ECB feed if EUR-based is acceptable). Confirm the free tier covers 160 currencies and one call per day; most do. Copy the API key.
6. **Transactional email** — **[NEW in v2]** create an account (Resend, Postmark or SES), verify the sending domain in Cloudflare (SPF, DKIM, DMARC records), and copy the API key. Without this, password reset cannot ship.
7. **Sentry** — **[NEW in v2]** one organisation, two projects: `hisaabwise-backend` (Node) and `hisaabwise-ios` (Apple). Copy both DSNs.
8. **GitHub repo secrets** — on `HisaabWiseBackend`, under Settings → Secrets and variables → Actions: `RENDER_DEPLOY_HOOK_URL`. Everything else goes in Render's own environment variables (§7), not GitHub.
9. **Cloudflare** — **[CHANGED in v2]**
   - `CNAME api` → the `.onrender.com` hostname Render gives you, proxy **ON** (orange cloud).
   - SSL/TLS mode **Full (strict)**, to avoid redirect loops with Render's certificate.
   - **Rate limiting rules** on `/auth/*` (login, register, reset, security-question verify). Cloudflare's free plan includes a limited number of rate-limiting and custom WAF rules — check the current allowance and, if it's too tight for the routes above, either upgrade or fall back to `express-rate-limit` in the app. Either way, the app-level limiter stays as defence in depth.
   - **Cache rules**: cache `GET /content/*`, `/curriculum*` and `/fx/rates` at the edge; **bypass cache** for everything under `/auth/*`, `/me*`, `/expenses*`, `/reports*` and `/learn/progress*`. Get this wrong in the permissive direction and you will serve one user's financial data to another — treat it as a security control, and verify it (§8).
   - **Cloudflare Pages** — a small static site for the marketing page, **Terms of Service** and **Privacy Policy**. The privacy policy URL is mandatory for App Store submission.
   - Email authentication records for the provider in step 6.

### iOS and TestFlight (sequential — each step depends on the last)
10. **Enrol in the Apple Developer Program** — developer.apple.com, ~$99/year, approval can take 24–48h. Nothing below works until it's active, so start here.
11. **Create the Xcode project** — Xcode → `File > New > Project` → iOS App → save inside `HisaabWiseIOS/` with a real bundle ID (e.g. `com.hisaabwise.ios`). Commit and push. The one bootstrap step nothing can substitute for.
12. **Create the App Store Connect app record** — appstoreconnect.apple.com → My Apps → New App, matching the bundle ID.
13. **APNs auth key** — **[NEW in v2]** Certificates, Identifiers & Profiles → Keys → new key with **Apple Push Notifications service** enabled. Download the `.p8` **once** — it cannot be re-downloaded. Note the Key ID and your Team ID.
14. **Enable Xcode Cloud** — Xcode → `Product > Xcode Cloud > Create Workflow`. This installs Xcode Cloud's own GitHub App on `HisaabWiseIOS` (approve when prompted), so it triggers on pushes without you managing tokens. The Developer Program includes a monthly compute-hour allowance (25 hours at the time of writing) — enough for internal builds; check current terms.
15. **Configure the workflow** — trigger: push to `main`; action: Archive; post-action: **TestFlight Internal Testing**. Xcode Cloud handles signing via managed signing — no Fastlane Match, no manual certificates.
16. **Add internal testers** — App Store Connect → TestFlight → Internal Testing → your Apple ID and anyone else, so builds are installable immediately after each successful run.
17. **App Privacy declarations** — **[NEW in v2]** App Store Connect → App Privacy. This app collects name, email, phone, date of birth and **financial information**, so the declarations are substantive and Apple checks them. Also add a **privacy manifest** (`PrivacyInfo.xcprivacy`) to the app target declaring required-reason API use, and confirm any third-party SDK you add (Sentry included) ships its own signed manifest.
18. **Age rating** — set to reflect the 13+ gate in the registration flow.

---

## 7. Environment variables

`.env.example` will carry this list with empty values. Real values go in Render's environment settings per service (staging and production separately) — never in the repo.

| Variable | Purpose |
|---|---|
| `NODE_ENV` | `production` / `staging` |
| `PORT` | provided by Render |
| `MONGODB_URI` | Atlas connection string (per environment) |
| `JWT_ACCESS_SECRET` | signs short-lived access tokens |
| `JWT_REFRESH_SECRET` | signs rotating refresh tokens |
| `ACCESS_TOKEN_TTL` / `REFRESH_TOKEN_TTL` | e.g. `15m` / `60d` |
| `FX_PROVIDER_API_KEY` | mid-market rate feed |
| `FX_BASE_CURRENCY` | `USD` (the prototype's rate table is USD-based) |
| `EMAIL_PROVIDER_API_KEY` | transactional email |
| `EMAIL_FROM` | e.g. `no-reply@<yourdomain>.com` |
| `APNS_KEY_P8` | the `.p8` contents (multi-line secret) |
| `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID` | push identifiers |
| `SENTRY_DSN` | backend error reporting |
| `CORS_ORIGINS` | allowed origins (marketing site; the iOS app needs none) |
| `RATE_LIMIT_WINDOW_MS`, `RATE_LIMIT_MAX` | app-level limiter |
| `LOG_LEVEL` | pino level |

---

## 8. Verification

Every item is a thing you can actually run and see, not a checkbox.

**Local**
- `npm install && npm run dev` in `HisaabWiseBackend/`, hit `http://localhost:<port>/health`, confirm `{status:"ok"}` and a successful Mongo connection in the terminal log.
- `npm test` — the budget engine's two branches, the money rounding rules, and the four documented security-answer cases all pass.
- `npm run seed` then `GET /content/tips` returns 49 tips; `GET /curriculum` returns 5 units and 15 lessons.

**CI**
- Open a throwaway PR against `HisaabWiseBackend`; confirm lint + test run and pass in the Actions tab.
- Push a deliberately failing test to a branch; confirm the deploy job does **not** fire.

**Deploy**
- Push to `main`; confirm the deploy-hook job fires in Actions and Render shows a new deploy.
- Confirm Render's health check goes green and stays green.

**Domain**
- `curl https://api.<yourdomain>.com/health` returns `{status:"ok"}` over HTTPS.
- `curl -I` the same URL twice and confirm no redirect loop (the Full-strict check).

**Cache correctness — do this one carefully** **[NEW in v2]**
- `curl` a content endpoint twice; second response shows a Cloudflare cache HIT.
- Sign in as two different users and `curl /me` for each with their own tokens; confirm **different** bodies and `cf-cache-status: BYPASS` or `DYNAMIC` on both. A HIT here is a data leak, not a performance win.

**FX** **[NEW in v2]**
- Run `node src/jobs/fxRefresh.js` manually; confirm a dated document lands in `fx_rates` with all 160 codes.
- `GET /fx/rates` returns it; the response carries the rate date.
- Break the provider key deliberately and re-run; confirm the previous rates stay live, the job exits non-zero, and an alert reaches you.

**Month rollover** **[NEW in v2]**
- On **staging**, seed a user with a month of expenses, run `node src/jobs/monthRollover.js` with a forced boundary; confirm a `month_archives` document appears with the salary, goal, saved and full entry payload, and the live month is cleared while rent and utility lines carry forward.
- Run it **twice**; confirm the second run writes nothing (idempotency).
- Open the Reports screen against staging and confirm the archived month renders with the same totals it had when live.
- Change the display currency and confirm the archived month's figures convert but its **story** doesn't change — the goal-hit verdict stays what it was.

**iOS**
- After the Xcode Cloud workflow is configured, push to `main`; confirm a build starts (Xcode's Report Navigator or App Store Connect → Xcode Cloud), completes, and appears under TestFlight → Internal Testing within a few minutes.
- Install via TestFlight on a real device to confirm end-to-end delivery.
- Sign in, force-quit, reopen: still signed in (Keychain refresh token works).
- Airplane mode: the app opens, cached content renders, a logged expense queues and syncs when connectivity returns.

**Monitoring** **[NEW in v2]**
- Throw a deliberate error in a staging route; confirm it appears in Sentry with a usable stack trace.
- Stop the staging service; confirm the uptime monitor alerts you.

---

## 9. Open questions and scope risks

These need your decision. Each one changes what gets built, so they're worth resolving before the corresponding code is written rather than after.

1. **Username vs email as the sign-in identifier.** *(Blocking for the auth schema.)* The sign-in form asks for a username; registration never collects one. Three options: (a) sign in with **email** and drop the username field — simplest, one fewer unique index, and the design already treats email as the identity anchor ("it is how we verify it is you"); (b) **add** a username field to registration step 1 with a live availability check; (c) auto-derive a username and let users edit it later in Account. **Recommendation: (a), sign in with email.** The Account screen already labels the editable field "Username" as a display name, which fits (a) cleanly.

2. **How many languages at launch.** *(Biggest scope risk in the design.)* 87 languages across UI, 49 tips, 3 long articles and ~115 lesson steps is a translation programme measured in months, and machine translation of financial-literacy content in a regulated space is a genuine risk — a mistranslated sentence about debt burden ratios is worse than no translation. **Recommendation: ship English plus Arabic (RTL, and the primary market's second language) at launch, and show only shipped languages in the picker.** Offering 87 and delivering 2 is worse than offering 2. Architect for more from day one; add them as translations land.

3. **Historical FX: pin or float.** Covered in §2.6. **Recommendation: pin at month close.** Financial history that changes retroactively is a bug users will report as one.

4. **Account deletion.** *(Blocking for App Store submission.)* Needs a design, an endpoint, and a decision on hard-delete versus a grace period. **Recommendation: 30-day soft delete, then hard erase**, which gives users a way back from a mistake and still satisfies the guideline.

5. **Offline expense entry.** The core loop is logging a spend in the moment — often in a shop basement with no signal. Full offline-first sync is real work. **Recommendation: a local write queue that drains on reconnect** (not full bidirectional sync), which covers the actual scenario at a fraction of the cost.

6. **Where "saved" comes from.** The Home screen reads `state.saved` as a given and the design never shows the user entering it. Is it computed (income − everything spent), self-reported, or bank-linked? The Reports facts grid implies computed. **This needs answering before the savings meter can be built**, and if it's computed, the answer must match the budget engine or the two cards will disagree on the same screen.

7. **Dark mode.** Every screen declares a light `theme-color` and the palette is light-first. iOS users increasingly expect dark mode. **Recommendation: ship light-only, but use semantic colour names in the asset catalogue from the start** so adding it later is a palette swap rather than a rewrite.

8. **Additional Income and the budget.** Extra income currently lifts every allowance, so a freelance windfall silently raises the wants budget. That may be the intent, or it may quietly undermine the savings goal in exactly the month the user could most easily hit it. Worth a deliberate decision.

---

## 10. Delivery phases

Sequenced so each phase ends with something you can actually use, and nothing waits on the Apple approval clock unnecessarily.

**Phase 0 — foundations (this plan).** Backend scaffold, content extraction, CI, Atlas, Render staging + production, Cloudflare DNS, `/health` green end to end. Apple enrolment started in parallel.

**Phase 1 — identity.** Register (3 steps), sign in, refresh, logout, password reset by email, security-question verification, account deletion. Resolves open questions 1 and 4.

**Phase 2 — money in and out.** Expense entries, fixed costs and utility lines, category taxonomy and pick lists, the budget engine, FX ingestion. Home and Expenses become real. Resolves questions 3 and 6.

**Phase 3 — learning.** Curriculum service, progress persistence, server-owned streak, XP. Learn becomes real.

**Phase 4 — history.** Month rollover job, archive API, Reports screen. Exercised on staging first, with the idempotency test in §8 as the gate.

**Phase 5 — retention and polish.** Push notifications and streak reminders, localisation for the launch language set, Sentry dashboards and alert routing, App Store metadata, privacy declarations, submission.

---

## 11. Explicitly out of scope

Still deliberately excluded, with the reasoning, so these are decisions rather than omissions:

- **Bank account linking / open banking.** Nothing in the design implies it, and it multiplies the compliance surface enormously.
- **Multi-device real-time sync.** Progress syncs on request; live cross-device updates aren't needed for a single-user finance app.
- **Web app.** The Cloudflare Pages site is marketing plus Terms and Privacy only.
- **Leaderboards or social features in Learn.** No design for them, and they would force server-side grading (§2.5).
- **Analytics beyond crash reporting.** Add product analytics when there are users to learn from.
- **Fastlane / manual code signing.** Xcode Cloud's managed signing covers this until you outgrow it.
- **Kubernetes, containers, IaC.** Render's managed platform is the right level of abstraction at this size; revisit if you outgrow it.

---

*Document version 2. Written against `HisaabWise_6.html` (7 screens: landing, auth, home, expenses, learn, reports, account). Where this plan and the prototype disagree, the disagreements are listed in §9 rather than silently resolved.*
