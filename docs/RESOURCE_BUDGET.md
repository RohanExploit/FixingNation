# Firebase Spark Resource Budget

## Daily target envelope
- Reads: <= 30,000/day
- Writes: <= 15,000/day
- Deletes: <= 2,000/day

## Design controls
- Feed pagination: 10 posts/page
- No unbounded listeners
- Denormalized counters for comments/upvotes
- City-scoped queries + indexed ordering
