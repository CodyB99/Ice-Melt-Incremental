# Analytics Plan

All events are emitted from the server in published builds. Keep event names stable and custom fields low-cardinality.

## Funnel: first session

1. Spawned
2. FirstIceMelted
3. FirstUpgradeAffordable
4. FirstUpgradePurchased
5. FirstToolUnlocked
6. FirstZoneUnlocked
7. FirstDiscoveryFound
8. ThawScreenOpened
9. FirstThawCompleted

Record elapsed seconds as supported event values/custom data.

## Economy events

Sources:

- IceMelt
- CriticalMelt
- ChainReaction
- DiscoveryReward
- DailyReward
- PlaytimeReward
- ProductGrant

Sinks:

- UpgradePurchase
- ToolUnlock
- ZoneUnlock
- OptionalReroll only if added later

Currencies: Heat and Embers.

## Custom events

- SessionQualitySelected
- TutorialStepSkipped
- DiscoveryIndexOpened
- ShopOpened
- OfferViewed
- PurchasePrompted
- MeltPulseRejected with reason category
- PerformanceFallbackTriggered

## Launch review cadence

Review at minimum:

- onboarding funnel completion
- median time to first upgrade/tool/zone/Thaw
- session duration and return retention
- upgrade distribution and economy sources/sinks
- conversion by offer and prompt context
- device/platform performance and crash/error reports

Do not optimize monetization before identifying major onboarding or retention failures.
