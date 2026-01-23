# Tinder-Like Features Design for Zemra Ime

**Date:** 2026-01-22
**Status:** Draft
**Scope:** MVP - Full discover → match → chat loop

---

## Overview

This document outlines the design for adding Tinder-like swipe-based discovery and matching features to Zemra Ime (LittleGrape), an Albanian dating platform.

### Key Decisions

| Component | Decision |
|-----------|----------|
| Discovery model | Swipe-based card stack |
| Matching | Mutual likes required |
| After match | Instant messaging opens |
| Algorithm | Smart ranking (preferences, interests, languages, activity) |
| Interactions | Simple like/pass only |
| Cultural features | Standard experience (community is the differentiator) |
| Notifications | Active engagement (matches, messages, nudges) |
| Monetization | Deferred for later |
| MVP scope | Full loop: Discover → Match → Chat |

---

## Database Design

### New Tables

#### `swipes`

Records every like/pass action.

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | `bigint` | Primary key |
| `user_id` | `bigint` | Foreign key → users, not null |
| `target_user_id` | `bigint` | Foreign key → users, not null |
| `action` | `string` | "like" or "pass", not null |
| `inserted_at` | `utc_datetime` | not null |

**Indexes:**
- Unique index on `(user_id, target_user_id)` - can only swipe once per person
- Index on `(target_user_id, action)` - for "who liked me" queries

#### `matches`

Created when two users mutually like each other.

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | `bigint` | Primary key |
| `user_a_id` | `bigint` | Foreign key → users, not null (lower ID) |
| `user_b_id` | `bigint` | Foreign key → users, not null (higher ID) |
| `matched_at` | `utc_datetime` | not null |
| `inserted_at` | `utc_datetime` | not null |
| `updated_at` | `utc_datetime` | not null |

**Indexes:**
- Unique index on `(user_a_id, user_b_id)` - one match per pair
- Index on `user_a_id` and `user_b_id` separately - for "my matches" queries

**Note:** Users are stored in consistent order (lower ID = `user_a_id`) to simplify queries and prevent duplicate match records.

#### `conversations`

One conversation per match, created automatically.

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | `bigint` | Primary key |
| `match_id` | `bigint` | Foreign key → matches, unique, not null |
| `inserted_at` | `utc_datetime` | not null |
| `updated_at` | `utc_datetime` | not null |

#### `messages`

Chat messages within a conversation.

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | `bigint` | Primary key |
| `conversation_id` | `bigint` | Foreign key → conversations, not null |
| `sender_id` | `bigint` | Foreign key → users, not null |
| `content` | `text` | not null, max 2000 characters |
| `read_at` | `utc_datetime` | nullable (null = unread) |
| `inserted_at` | `utc_datetime` | not null |

**Indexes:**
- Index on `(conversation_id, inserted_at)` - for message ordering
- Index on `(conversation_id, sender_id, read_at)` - for unread counts

#### `blocks` (optional)

For user blocking functionality.

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | `bigint` | Primary key |
| `blocker_id` | `bigint` | Foreign key → users, not null |
| `blocked_id` | `bigint` | Foreign key → users, not null |
| `inserted_at` | `utc_datetime` | not null |

**Indexes:**
- Unique index on `(blocker_id, blocked_id)`

---

## Module Architecture

### `LittleGrape.Discovery`

Responsible for fetching and ranking swipe candidates.

**Functions:**
- `get_candidates(user, limit \\ 20)` - Returns ranked list of profile candidates
- `refresh_candidates(user)` - Fetches next batch when running low

### `LittleGrape.Swipes`

Handles swipe actions and match detection.

**Functions:**
- `create_swipe(user, target_user_id, action)` - Records a swipe
- `check_for_match(user, target_user_id)` - Checks if mutual like exists
- `get_swipe(user, target_user_id)` - Returns existing swipe if any

### `LittleGrape.Matches`

Manages matches and match-related queries.

**Functions:**
- `create_match(user_a_id, user_b_id)` - Creates match and conversation
- `list_matches(user)` - Returns all matches for a user
- `get_match(user, match_id)` - Gets match if user is participant
- `unmatch(user, match_id)` - Removes a match (soft delete)

### `LittleGrape.Messaging`

Handles conversations and messages.

**Functions:**
- `get_conversation(user, match_id)` - Gets conversation for a match
- `list_messages(conversation, opts)` - Paginated message list
- `send_message(user, conversation_id, content)` - Sends a message
- `mark_as_read(user, conversation_id)` - Marks messages as read
- `unread_count(user)` - Total unread across all conversations
- `unread_count(user, conversation_id)` - Unread for specific conversation

### `LittleGrape.Notifications`

Manages in-app notifications and engagement.

**Functions:**
- `notify_match(user_a, user_b)` - Broadcasts match notification
- `notify_message(recipient, message)` - Broadcasts new message
- `get_notifications(user)` - Lists recent notifications
- `mark_read(user, notification_id)` - Marks notification as read

---

## Discovery Algorithm

### Hard Filters

Candidates MUST pass all of these:

1. Not already swiped by this user
2. Not the user themselves
3. Not blocked by or blocking this user
4. Has a completed profile:
   - At least one profile photo
   - First name set
   - Birthdate set
   - Gender set
5. Matches user's `preferred_gender` preference
6. User matches candidate's `preferred_gender` (mutual compatibility)

### Soft Scoring

Candidates are ranked by weighted composite score:

| Factor | Weight | Logic |
|--------|--------|-------|
| Age in preferred range | High (30%) | Both users within each other's `preferred_age_min/max` |
| Country match | Medium (20%) | Same `preferred_country` or both flexible |
| Shared interests | Medium (20%) | Count overlapping items in `interests` array |
| Shared languages | Low (10%) | Overlapping `languages` spoken |
| Religion alignment | Low (10%) | Same religion (if not "prefer_not_to_say") |
| Profile freshness | Low (5%) | Recently active users ranked slightly higher |
| Already liked you | Boost (5%) | If they liked you, bump them up |

### Randomization

Add slight randomization (±10%) to prevent deterministic ordering and keep the experience fresh across sessions.

### Batch Loading

- Fetch 20 profiles at a time
- When user has 5 cards remaining, prefetch next batch in background
- Cache candidate IDs client-side to prevent re-fetching

---

## Swipe & Match Flow

### Recording a Swipe

```
User swipes right (like) or left (pass)
    ↓
Frontend sends LiveView event: {"swipe", %{target_id: 123, action: "like"}}
    ↓
Server inserts Swipe record
    ↓
If action == "like":
    Check for reciprocal: SELECT * FROM swipes
                          WHERE user_id = target_id
                          AND target_user_id = current_user
                          AND action = 'like'
    ↓
    If reciprocal exists:
        Create Match (ordered by user ID)
        Create Conversation
        Broadcast "match" event to both users via PubSub
    ↓
Frontend removes card, shows next (or "It's a Match!" modal)
```

### Match Modal

When a match occurs, both users see:
- "It's a Match!" heading
- The other person's profile photo and name
- Two buttons: "Send Message" | "Keep Swiping"

---

## Messaging System

### Real-Time Architecture

Uses Phoenix PubSub for live updates:

1. **On mount:** Subscribe to `conversation:#{conversation_id}`
2. **Sending:** Insert message → Broadcast to topic
3. **Receiving:** Handle broadcast → Append to message list
4. **Read receipts:** On view → Update `read_at` → Broadcast read status

### Message Flow

```
User types message and clicks Send
    ↓
LiveView event: {"send_message", %{content: "Hello!"}}
    ↓
Server validates (non-empty, < 2000 chars, user in conversation)
    ↓
Insert Message record
    ↓
Broadcast to "conversation:#{id}" topic
    ↓
Both clients receive and render new message
```

### Read Receipts

```
Recipient opens conversation
    ↓
Query unread messages: WHERE read_at IS NULL AND sender_id != current_user
    ↓
Bulk update: SET read_at = NOW()
    ↓
Broadcast read status to conversation topic
```

---

## User Interface

### Navigation (Logged-in Users)

```
[Logo] [Discover] [Matches (badge)] [Profile] [Settings]
```

- **Discover:** Swipe stack icon
- **Matches:** Heart icon with unread message count badge

### Discover Page (`/discover`)

```
┌─────────────────────────────────┐
│  ┌───────────────────────────┐  │
│  │                           │  │
│  │     [Profile Photo]       │  │
│  │                           │  │
│  │                           │  │
│  │  ─────────────────────    │  │
│  │  Name, Age                │  │
│  │  City, Country            │  │
│  └───────────────────────────┘  │
│                                 │
│  [Bio, interests, details...]   │
│                                 │
│      [ ✕ ]          [ ♥ ]       │
│       Pass           Like       │
└─────────────────────────────────┘
```

**Interactions:**
- Swipe right or tap ♥ → Like
- Swipe left or tap ✕ → Pass
- Tap card → Expand to see full profile details

**Empty State:**
- "No more profiles right now"
- "Try broadening your preferences or check back later"

### Matches Page (`/matches`)

```
┌─────────────────────────────────┐
│  Your Matches                   │
├─────────────────────────────────┤
│  ┌─────┐  Anna, 28         (2) │  ← unread badge
│  │photo│  "Hey! How are you..."│
│  └─────┘                        │
├─────────────────────────────────┤
│  ┌─────┐  Maria, 25             │
│  │photo│  "Nice to meet you"   │
│  └─────┘                        │
├─────────────────────────────────┤
│  ┌─────┐  NEW MATCH ✨          │
│  │photo│  Elira, 30            │
│  └─────┘  Start a conversation  │
└─────────────────────────────────┘
```

- New matches highlighted at top
- Each row shows: photo, name, last message preview, unread count
- Tap to open conversation

### Chat Page (`/chat/:match_id`)

```
┌─────────────────────────────────┐
│  ← Back    [Photo] Anna         │  ← tap name to view profile
├─────────────────────────────────┤
│                                 │
│        Hi! Nice to match 😊      │  ← their message (left)
│                         2:30pm  │
│                                 │
│  Hey Anna! How's it going?      │  ← your message (right)
│  2:32pm                         │
│                                 │
│        Pretty good! What do     │
│        you do for work?         │
│                         2:35pm  │
│                                 │
├─────────────────────────────────┤
│  [Type a message...    ] [Send] │
└─────────────────────────────────┘
```

---

## Notifications

### Notification Types

| Event | In-App | Push (Future) |
|-------|--------|---------------|
| New Match | Modal + badge | Yes |
| New Message | Badge update | Yes |
| Unread Reminder (4h) | - | Yes |
| New Profiles Available | - | Yes |
| Inactive Nudge (3+ days) | - | Yes |

### PubSub Topics

- `user:#{user_id}:notifications` - General notifications for a user
- `conversation:#{id}` - Messages in a specific conversation
- `user:#{user_id}:matches` - Match count updates

---

## Edge Cases & Error Handling

### Profile Requirements

Users cannot access `/discover` until they have:
- At least one profile photo
- First name, birthdate, and gender set
- `preferred_gender` preference set

Redirect incomplete profiles to `/profile` with completion prompt.

### Handling Edge Cases

| Scenario | Handling |
|----------|----------|
| User deletes account | Soft-delete: hide from discovery, show "Deleted User" in existing matches |
| User blocks another | `blocks` table; blocked users excluded from all queries |
| Empty swipe stack | Friendly empty state, suggest broadening preferences |
| Rapid double-swipe | Unique constraint prevents duplicates; disable buttons during request |
| Message to unmatched user | Authorization check; return 403 |
| Very long message | Validate max 2000 characters server-side |

### Data Privacy

- Users only see profiles filtered by discovery algorithm
- Chat history only accessible to participants
- Swipes are private - no one knows who passed on them

---

## Testing Strategy

### Unit Tests

- Algorithm scoring calculations
- Match detection logic
- Authorization/permission checks
- Message validation

### Integration Tests

- Full swipe → match → conversation creation flow
- PubSub message broadcasting
- Read receipt updates

### LiveView Tests

- Card swipe interactions
- Real-time message delivery
- Badge count updates
- Empty state rendering

---

## Future Considerations (Out of Scope for MVP)

These features were discussed but deferred:

- **Monetization:** "See who liked you" premium feature, subscription tiers
- **Super Like:** Limited daily "super likes" that notify the recipient
- **Rewind:** Undo last swipe
- **Boost:** Temporarily appear at top of others' stacks
- **Video chat:** In-app video calling
- **Photo verification:** Selfie verification to confirm identity
- **Advanced filters:** Filter by specific attributes in discovery

---

## Implementation Order

Suggested order for building this feature set:

1. **Database migrations** - Create all new tables
2. **Core schemas** - Swipe, Match, Conversation, Message Ecto schemas
3. **Swipes module** - Recording swipes
4. **Discovery module** - Basic candidate fetching (filters only, then add scoring)
5. **Matches module** - Match creation and queries
6. **Discover LiveView** - Card stack UI with swipe gestures
7. **Matches LiveView** - Matches list page
8. **Messaging module** - Send/receive messages
9. **Chat LiveView** - Real-time conversation UI
10. **Notifications** - Match and message notifications
11. **Polish** - Empty states, loading states, error handling
