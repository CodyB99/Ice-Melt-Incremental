# QA and Release Checklist

## Functional

- New profile completes full loop.
- Existing profile migrates and loads.
- Heat cannot go negative or become NaN/infinite.
- Upgrade costs/effects match configuration.
- Tool and zone gates reject invalid requests.
- Thaw reset retains only intended fields.
- Discoveries save before reveal UI depends on them.
- Codes cannot be redeemed twice.

## Persistence

- Leave/rejoin after each major purchase.
- Force client disconnect during melt and purchase flows.
- Test server shutdown with multiple players.
- Test duplicate session/profile lock behavior.
- Test corrupted/missing fields and schema migration.
- Use a separate test universe/data store from production.

## Monetization

- Receipt duplicate test grants once.
- Receipt with absent player returns NotProcessedYet.
- Unknown product returns NotProcessedYet and logs an error.
- Pass benefits activate on join and after purchase.
- UI uses live price/product information.
- No required gameplay depends on purchase callbacks from the client.

## Exploit tests

- Spam melt remote.
- Send impossible zone/cell/position claims.
- Send negative/huge/NaN values.
- Request locked tool, zone, upgrade, Thaw, reward, and code.
- Attempt to replay sequence numbers.
- Attempt to trigger chain rewards beyond cap.

## Device and input

- Small phone landscape
- tablet
- 16:9 desktop
- ultrawide sanity check
- keyboard/mouse
- touch
- controller

## Performance

- Test largest field and chain reaction with multiple clients.
- Check server script time, memory, network receive/send, part count, particle count, and audio spam.
- Confirm pooling prevents sustained instance churn.
- Low effects mode remains readable and satisfying.

## Release gates

- No red errors during a 30-minute multiplayer soak.
- No known data-loss or duplicate-purchase bug.
- Onboarding can be completed without developer explanation.
- Icon, description, screenshots, age/content questionnaire, localization baseline, and monetization assets are ready.
- Production IDs and data store names are separated from test configuration.
