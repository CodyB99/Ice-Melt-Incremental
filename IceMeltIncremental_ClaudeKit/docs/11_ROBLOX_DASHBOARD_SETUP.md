# Roblox Dashboard Owner Setup

## Before Phase 09

1. Publish the test experience under the intended owner/group.
2. Create passes and developer products from the tables in `docs/05_MONETIZATION.md`.
3. Record IDs in `src/shared/Config/MonetizationConfig.luau`.
4. Upload product icons designed to remain readable in circular crops.
5. Keep the experience private or restricted during receipt testing.

## Data safety

Use a separate test experience/universe or explicit environment-specific data store names. Studio access can touch live data when enabled, so never point ordinary Studio tests at production data.

## Analytics

Activate Creator Dashboard analytics when eligible. Publish test builds to validate economy, funnel, and custom events because Studio/client-only events do not populate production dashboards.

## Launch content

Prepare:

- concise title and description
- icon
- 3–5 thumbnails
- controls and accessibility description
- group/community link if used
- update/event plan
- content maturity questionnaire
