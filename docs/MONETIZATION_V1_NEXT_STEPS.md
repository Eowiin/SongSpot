# SongSpot Monetization V1 Next Steps

## Current State

- `Daily Mix` is the free default mode.
- `Genre`, `Decade`, and `Hardcore` are room-wide coin-funded modes.
- A correct daily guess currently awards `5` to `8` coins depending on snippet.
- Paid modes can be unlocked by room contribution and stay available until the next daily reset.

## Economy Rebalance

The previous pricing of `120 / 120 / 160` was too aggressive against the current earn rate.

At `5-8` coins per good daily win:

- `120` coins means roughly `15-24` strong wins for one unlock
- that is too slow for a one-day room mode
- the feature risks feeling unreachable instead of aspirational

### New Recommended Prices

- `Genre`: `60` coins
- `Decade`: `60` coins
- `Hardcore`: `80` coins

### Why These Numbers

- A solo player can reasonably unlock `Genre` or `Decade` after about `8-12` good wins.
- A room with even light contribution can unlock special modes much more often.
- `Hardcore` stays premium relative to `Genre` and `Decade`, but not so expensive that it becomes irrelevant.

## Naming Recommendation

The current names are understandable in code, but not ideal from a product point of view.

`Daily Genre` and `Daily Decade` sound like permanent daily entitlements, while they are actually optional room-wide activations for the current day.

### Recommended User-Facing Naming

- `Genre Mode`
- `Decade Mode`
- `Hardcore`

Alternative if keeping the "today" framing:

- `Today's Genre`
- `Today's Decade`

For now, pricing should be fixed first. Naming can be changed in a second pass.

## What To Build Next

### 1. Add Product Analytics

Track at least:

- mode sheet opened
- mode contribution started
- contribution amount submitted
- mode unlocked
- mode played
- mode completed
- coin shop opened after failed contribution
- coin purchase after failed contribution

Without this, pricing decisions will be guesswork.

### 2. Improve Contribution UX

Current numeric entry works, but the best next step is faster contribution actions:

- quick chips: `+10`, `+20`, `+50`, `Max`
- "coins remaining" emphasis
- contributor avatars or usernames
- a stronger room activity feed message when someone contributes or unlocks

This matters because social spending is the core of this system.

### 3. Clarify The Offer In Copy

The UI should consistently communicate:

- `Unlock for everyone in the room`
- `Available until next reset`
- `X coins remaining`

That reduces confusion around ownership, duration, and value.

### 4. Decide Whether To Prevent Cross-Mode Duplicate Songs

Right now each mode is its own daily lane.

That means `Mix`, `Genre`, `Decade`, and `Hardcore` are selected independently. They are not intentionally linked, but they can still coincidentally land on the same track.

Recommended follow-up:

- guarantee that paid modes do not repeat the same song as another mode in the same room/day

That makes special modes feel more premium.

### 5. Run A Small Pricing Test

Do not keep tweaking blindly.

Test for 1-2 weeks:

- how many rooms open the mode sheet
- how many rooms contribute
- how many unlock
- average contribution amount
- how many users buy coins afterward
- whether unlocked-mode rooms come back more often the next day

If unlock rate is still too low, lower `Genre` and `Decade` to `50`.

## Recommended Order

1. Ship the new prices.
2. Add analytics events.
3. Improve contribution UX with quick amount chips.
4. Decide on naming changes.
5. Decide on cross-mode duplicate prevention.

## Notes For Later

Do not add subscription, cosmetics, or more sinks until this system is validated.

V1 should answer one question clearly:

`Will players spend coins together to unlock room-wide special modes often enough to support coin purchases?`
