# Phase 09 — Monetization

## Objective
Implement ethical passes, products, live-price shop UI, and durable idempotent receipt handling.

## Tasks

- Require real IDs in MonetizationConfig for enabled production offers; keep disabled placeholders safe.
- Implement server pass ownership caching/refresh.
- Implement one ProcessReceipt callback and per-product grant handlers.
- Make grants idempotent by PurchaseId with bounded durable history/records.
- Return NotProcessedYet whenever durable grant cannot be guaranteed.
- Implement live product/pass info and regional/dynamic price display.
- Build shop categories and contextual offers respecting onboarding rules.
- Add purchase/economy analytics.

## Acceptance criteria

- Duplicate receipt invocation grants once.
- Missing player/profile receipt remains pending.
- Unknown/disabled IDs never grant arbitrary rewards.
- Pass benefits are server-derived and update after purchase.
- No Robux price is hard-coded in visible UI.
- Free players retain a complete viable progression path.
