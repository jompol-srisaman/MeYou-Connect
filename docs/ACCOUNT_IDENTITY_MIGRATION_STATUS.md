# MeYou Connect — Account Identity Migration Status

**Date:** 2026-09-03  
**Business account target:** `meyouconnect.official@gmail.com`  
**Migration batch:** `MYC-MIG-000001`  
**Status:** `IN_PROGRESS`

## Principle

Move business ownership/access to the MeYou Connect business identity while preserving existing technical assets, stable `MYC-*` business IDs, repository history, Supabase project identity, and provider IDs wherever possible.

Do not recreate working systems solely to change account email.

Target operating model:
- **Primary / Operational Google account:** `meyouconnect.official@gmail.com`
- **Primary Drive root:** `1B45lICTcE_ADlh9JOYr96yB6__kcXdBO`
- **Personal account:** `jompol.srisaman@gmail.com`
- **Personal account role after stabilization:** controlled recovery identity + off-account backup destination
- **Off-account backup root:** `1j9lHYVy5azmmizayBLzw7oAsfXizqrqX`

## Google Drive

Current connected Drive identity: `jompol.srisaman@gmail.com`.

Completed:
- created `MYC_BACKUP_20260903_ACCOUNT_MIGRATION_FREEZE` under Backup Snapshot Exports;
- snapshotted 9 critical assets before ownership work;
- logged backup run `MYC-BK-000008`;
- updated `MYC-MIG-000001` to `IN_PROGRESS`;
- shared critical Tier-A/architecture assets to `meyouconnect.official@gmail.com` as Writer;
- verified Data Hub and Control Index retain original File IDs and destination Writer access;
- prepared personal-account off-account backup root `MEYOU_CONNECT_OFF_ACCOUNT_BACKUP_FROM_OFFICIAL` (`1j9lHYVy5azmmizayBLzw7oAsfXizqrqX`);
- prepared backup subfolders for Tier-A critical, weekly snapshots, monthly full exports, restore tests, and manifests/checksums;
- registered the off-account backup target in the Backup Manifest.

Current observation:
- Primary target root supplied by Founder: `1B45lICTcE_ADlh9JOYr96yB6__kcXdBO`.
- Current personal-account MCP cannot access that root yet, confirming MCP has not been re-authenticated to the official account and the new root is not currently visible to the personal connector.

Pending user-side:
- transfer Google Drive ownership where supported;
- accept ownership from `meyouconnect.official@gmail.com`;
- handle root/subfolder ownership from Google Drive UI;
- reconnect ChatGPT Google Drive/Gmail/Calendar/Contacts to the business account;
- after re-authentication, verify canonical File IDs/links and migrate/copy any remaining assets into the new Primary root;
- run post-migration reconciliation;
- create the first real off-account backup from Official Primary to the personal-account backup root;
- run sample restore verification before marking migration complete.

Connector limitation: current Drive MCP cannot set Google Drive API `transferOwnership`, so ownership transfer cannot be completed from ChatGPT.

## Backup direction

After MCP is connected to the official account, the canonical direction is:

`meyouconnect.official@gmail.com / Primary → jompol.srisaman@gmail.com / Off-account Backup`

The personal backup location is not an Operational Source of Truth and must never become a parallel writable master.

Planned cadence:
- Tier-A structured data: daily target when automation is available;
- weekly controlled snapshot;
- monthly full export;
- restore test sample monthly and after material migration/change;
- preserve original evidence bytes where possible.

## GitHub

Repository remains `jompol-srisaman/MeYou-Connect`.

Decision: keep repository intact. Do not copy/recreate it.

Current authenticated GitHub user belongs to no GitHub Organizations.

Pending user-side:
- create a GitHub Organization for MeYou Connect if desired;
- add the business identity/account with appropriate ownership;
- later transfer the existing repository into the organization rather than copying it.

No repo transfer should occur until the organization exists and ownership/recovery settings are verified.

## Supabase

Keep existing TEST project `pgjmxdeafzogzsyawejs` and its migration history intact.

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

## Completion criteria

Migration remains `IN_PROGRESS` until:
1. destination business account owns/controls critical Drive assets;
2. Drive MCP can read canonical sources under the new account;
3. Primary root `1B45lICTcE_ADlh9JOYr96yB6__kcXdBO` is verified and reconciled;
4. an off-account backup exists under personal account root `1j9lHYVy5azmmizayBLzw7oAsfXizqrqX` and a sample restore is verified;
5. business identity has admin/owner access to GitHub/Supabase as intended;
6. old personal identity remains a controlled recovery path during stabilization;
7. no canonical `MYC-*` ID changed because of account migration.
