# MYC PWA V0.1 — Safe Release / Rollback Boundary

Status: Preview only. Production cutover remains a Founder Human Gate.

## Runtime boundaries
- Operational business Source of Truth remains `MEYOU_CONNECT_MVP_DATA_HUB_V1` until approved cutover.
- UI never direct-writes protected Master.
- `/api/**` responses are never cached by the service worker.
- Offline behavior is read-only for previously cached pages. Future queued actions are proposals only and must revalidate online.
- Supabase TEST/shadow data must not be displayed as official operational truth.

## Feature flags / kill switches
Central policy: `lib/platform/feature-flags.ts`.

V0.1 active surfaces: Founder Home, Candidates, Jobs, Inbox, Clients, Partners, System shell.
Planned modules (Finance, Payroll, Accounting, AI Matching, Facebook/Portals) remain OFF until explicitly enabled and contracted.

Kill-switch defaults intentionally block:
- all writes from this preview shell,
- offline mutations,
- AI controlled effects,
- production cutover.

## Contract versioning
Shared read envelope: `lib/platform/contracts.ts` (`contractVersion: v1`).
Modules register an explicit versioned contract in `lib/platform/module-registry.ts`.
New modules must communicate through approved contracts/events rather than direct cross-module table coupling.

## Service-worker update strategy
- New worker installs and waits.
- Founder gets an explicit update prompt.
- `SKIP_WAITING` is sent only when Founder taps Update.
- Controller change triggers a single reload.
- Cache namespace is versioned (`myc-pwa-v0.1.1`).

## Preview rollback
1. Do not merge/deploy to production during Preview Phase.
2. If preview regresses, redeploy the last known-good branch commit in Vercel or revert the offending branch commit.
3. Bump service-worker cache version on forward-fix so stale shell/page caches are removed on activation.
4. Keep feature flags OFF for an unstable module; do not remove canonical data structures as a rollback shortcut.

## Database migration policy
No DB migration is introduced by PWA V0.1.
Future migrations must use expand → migrate → contract and maintain backward compatibility during the application rollout window.

## Preview acceptance gates
- `npm run typecheck`
- `npm test`
- `npm run build`
- Mobile layout check at <= 680px and tablet <= 980px
- PWA manifest/service worker present
- `/api/**` no-cache contract test
- approved MYC brand token contract test
- no fake operational metrics when Official Read Contract is NOT_READY

## Human Gates
Founder approval is required for production cutover, secrets/credentials, domain changes, security-boundary changes, and any new brand direction.
