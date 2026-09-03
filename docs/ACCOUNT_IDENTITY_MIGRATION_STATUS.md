# MeYou Connect — Account Identity Migration Status

**Date:** 2026-09-03  
**Business account target:** `meyouconnect.official@gmail.com`  
**Migration batch:** `MYC-MIG-000001`  
**Status:** `IN_PROGRESS_OFFICIAL_MCP_ACTIVE`

## Principle

Move business ownership/access to the MeYou Connect business identity while preserving existing technical assets, stable `MYC-*` business IDs, repository history, Supabase project identity, and provider IDs wherever practical.

Do not recreate working systems solely to change account email.

Target operating model:
- **Primary / Operational Google account:** `meyouconnect.official@gmail.com`
- **Primary Drive root:** `1B45lICTcE_ADlh9JOYr96yB6__kcXdBO` (`MeYou Connect Systems AI`)
- **Personal account:** `jompol.srisaman@gmail.com`
- **Personal account role after stabilization:** controlled recovery identity + off-account backup destination
- **Off-account backup root:** `1j9lHYVy5azmmizayBLzw7oAsfXizqrqX`

## Google Drive — Current Verified State

Current connected Drive MCP identity: **`meyouconnect.official@gmail.com` — VERIFIED**.

Primary destination root:
- ID: `1B45lICTcE_ADlh9JOYr96yB6__kcXdBO`
- title: `MeYou Connect Systems AI`
- owner: `meyouconnect.official@gmail.com`
- current content at verification: empty

Completed:
- created pre-migration freeze snapshot `MYC_BACKUP_20260903_ACCOUNT_MIGRATION_FREEZE` under the old personal-account Backup Snapshot Exports;
- snapshotted 9 critical assets before ownership work;
- logged backup run `MYC-BK-000008`;
- shared critical Tier-A/architecture assets to `meyouconnect.official@gmail.com` as Writer;
- verified Data Hub and Control Index retain original source File IDs and are visible to Official as Shared-with-me files;
- prepared personal-account off-account backup root `MEYOU_CONNECT_OFF_ACCOUNT_BACKUP_FROM_OFFICIAL` (`1j9lHYVy5azmmizayBLzw7oAsfXizqrqX`);
- prepared Tier-A, weekly, monthly, restore-test and manifest/checksum backup subfolders;
- updated `MYC-MIG-000001` with Official root ID/URL and status `IN_PROGRESS_OFFICIAL_MCP_ACTIVE`;
- verified current Gmail connector remains on the personal account; Google app connections are separate and Gmail/Calendar/Contacts must be changed separately when desired.

### Migration Rehearsal

`MYC-RT-000002 = PASS_TEST`

A temporary copy of `MEYOU_CONNECT_MVP_DATA_HUB_V1` was created inside the Official Primary root.

Verified:
- copied file owner = `meyouconnect.official@gmail.com`;
- source workbook = 27 tabs;
- rehearsal copy = 27 tabs;
- sheet IDs/titles/grid dimensions matched source metadata;
- controlled-copy migration therefore works technically;
- copy method creates a new Provider File ID and therefore requires `Legacy Drive ID → Current Drive ID` mapping during a real migration.

The temporary rehearsal copy was deleted after verification; no test artifact remains.

### Current Blocker

The old personal-account root `01.MeYou Connect` (`1PytkPLmEsUlbWtoSTBWD-P_S4AMSikD9`) is **not visible** to the Official MCP.

Official can currently see only the critical files that were shared individually.

Founder action required before full-tree migration:
1. sign in to `jompol.srisaman@gmail.com` in Google Drive UI;
2. share folder `01.MeYou Connect` with `meyouconnect.official@gmail.com` as **Editor**;
3. do not delete/move the old root yet;
4. after sharing, the Architect will inventory the complete tree and choose transfer-ownership vs controlled-copy per asset, then reconcile links/IDs before Primary cutover.

Connector limitation: current Drive MCP cannot set Google Drive API `transferOwnership`, so ownership transfer itself must be done through Google UI where chosen.

## Backup Direction

Canonical direction after cutover:

`meyouconnect.official@gmail.com / Primary → jompol.srisaman@gmail.com / Off-account Backup`

The personal backup location is not an Operational Source of Truth and must never become a parallel writable master.

A real off-account backup must ultimately be owned/controlled independently by the personal recovery account, not merely stored in a folder while still owned by Official.

Planned cadence:
- Tier-A structured data: daily target when automation is available;
- weekly controlled snapshot;
- monthly full export;
- restore-test sample monthly and after material migration/change;
- preserve original evidence bytes where possible.

## GitHub

Repository remains `jompol-srisaman/MeYou-Connect`.

Decision: keep repository intact. Do not copy/recreate it.

Current authenticated GitHub user belongs to no GitHub Organizations.

Pending user-side:
- create a GitHub Organization for MeYou Connect if desired;
- add the business GitHub identity/account with appropriate ownership;
- later transfer the existing repository into the organization rather than copying it.

No repo transfer should occur until the organization exists and ownership/recovery settings are verified.

## Supabase

Keep existing TEST project `pgjmxdeafzogzsyawejs` and migration history intact.

Current Supabase organization: `jompol-srisaman's Org` (`jjsqclyslqeqbgxpbhac`).

Pending user-side:
- create/sign in to Supabase with the business identity;
- invite that identity to the existing Supabase organization as an appropriate admin/owner role through Supabase dashboard;
- enable MFA/recovery;
- verify business identity can access TEST before reducing reliance on the personal identity.

Do not create a replacement Supabase project only to change email ownership.

## Vercel

No MeYou Connect Vercel project exists yet. Therefore no migration is required.

When the Founder Console/Web App is created, create/deploy it under the intended MeYou Connect business/team ownership from the start.

## LINE / Meta

No live LINE/Meta production adapters are bound yet. Create future LINE Official Account / Messaging API and Meta Business/Page assets under the MeYou Connect business identity, then store provider secrets only in approved secret/environment stores.

## Completion Criteria

Migration remains incomplete until:
1. Official account controls/owns the intended Primary Drive assets;
2. complete old Drive tree has been inventoried and reconciled;
3. Primary root `1B45lICTcE_ADlh9JOYr96yB6__kcXdBO` contains the verified canonical structure;
4. File-ID changes, if any, are mapped and source links updated;
5. a real off-account backup exists under personal account ownership and a sample restore is verified;
6. business identity has admin/owner access to GitHub/Supabase as intended;
7. personal identity remains a controlled recovery path during stabilization;
8. no canonical `MYC-*` business ID changes because of account migration.
