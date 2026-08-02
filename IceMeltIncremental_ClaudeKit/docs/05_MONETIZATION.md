# Monetization Design

Monetization should improve convenience, expression, or optional acceleration without making free progression feel intentionally broken.

## Proposed passes

IDs remain `0` until created in Creator Dashboard.

| Pass | Suggested initial price | Benefit |
|---|---:|---|
| 2× Heat | 149 Robux | Doubles eligible Heat income |
| 2× Discovery Luck | 99 Robux | Doubles luck contribution, not raw final secret odds |
| Expanded Heat Radius | 199 Robux | +35% final melt radius, server-capped |
| Auto-Melt Plus | 299 Robux | Improves earned Auto-Melt rate and offline-style convenience; does not replace free unlock |
| VIP | 249 Robux | Name tag, cosmetic flame, VIP daily chest, modest +10% Heat |

## Proposed developer products

| Product | Suggested price | Grant |
|---|---:|---|
| Starter Heat Pack | 39 | Context-scaled Heat grant with minimum/maximum |
| Heat Surge | 59 | 2× personal Heat for 10 minutes |
| Luck Surge | 59 | Personal discovery luck boost for 10 minutes |
| Server Heat Wave | 99 | 1.5× Heat for all current players for 10 minutes |
| Chain Reaction Charge | 49 | One optional large validated chain reaction |
| Welcome Bundle | 79 | One-time-account-style bundle enforced server-side despite developer product repeatability |

## Implementation rules

- Use one `MarketplaceService.ProcessReceipt` callback owned by `MonetizationService`.
- Store/grant by `PurchaseId`; duplicate callbacks must not duplicate rewards.
- Return `NotProcessedYet` when the player or durable profile is unavailable.
- Never grant based only on `PromptProductPurchaseFinished`.
- Query current product/pass information for UI pricing.
- Handle regional/dynamic prices.
- Pass ownership checks occur on server join and after purchase events.
- Every purchase grant is logged in analytics with product key, not personally identifying data.
- Do not place purchase prompts during the first 60 seconds or interrupt the first successful upgrade.

## Shop placement

- Persistent but unobtrusive Shop button.
- Contextual offer only after player understands the underlying free mechanic.
- No fake countdowns, misleading close buttons, or accidental purchase placement.
