# Escrow (Move Stylus)

An **escrow** smart contract for [Arbitrum Stylus](https://docs.arbitrum.io/stylus/gentle-introduction), written in **Move** and compiled with [move-stylus](https://github.com/rather-labs/move-stylus).

## What it does

- **Buyer** creates an escrow with `create(seller, amount, deadline, memo, arbitrator)` (and in production sends `amount` as `msg.value`).
- **Seller** can call `release(escrow)` to confirm and receive funds (fails if past deadline).
- **Buyer** can call `refund(escrow)` to cancel and get funds back.
- **Arbitrator** (optional): if set, can call `release` or `refund` to resolve disputes.
- **Deadline**: if non-zero (Unix timestamp), seller cannot release after it; buyer can always refund.
- **Events**: `EscrowCreated`, `EscrowReleased`, `EscrowRefunded` for indexing and UIs.

Only one of release or refund can happen; the contract enforces roles and pending state.

## Prerequisites

- [Rust](https://rustup.rs/) (toolchain 1.88.0 for move-stylus)
- [move-stylus](https://github.com/rather-labs/move-stylus) CLI

```bash
git clone https://github.com/rather-labs/move-stylus && cd move-stylus
cargo install --locked --path crates/move-cli
```

## Build & test

```bash
move-stylus build
move-stylus test
```

Or from the move-stylus repo:

```bash
cargo run -p move-cli -- build -p /path/to/move-stylus-escrow
cargo run -p move-cli -- test -p /path/to/move-stylus-escrow
```

## API

### Entrypoints

| Function | Who | Description |
|----------|-----|-------------|
| `create(seller, amount, deadline, memo, arbitrator)` | Buyer | Creates a new escrow. `deadline`: 0 = none, else Unix timestamp. `memo`: optional bytes. `arbitrator`: 0x0 = none. |
| `release(escrow)` | Seller or Arbitrator | Marks deal as released (funds to seller). Fails if past deadline. |
| `refund(escrow)` | Buyer or Arbitrator | Marks deal as refunded (funds to buyer). |

### Views

`buyer`, `seller`, `amount`, `status`, `deadline`, `memo`, `arbitrator`, `is_pending`, `is_expired(escrow, current_timestamp)`.

### Events

- **EscrowCreated**: `escrow_id`, `buyer`, `seller`, `amount`
- **EscrowReleased**: `escrow_id`, `seller`
- **EscrowRefunded**: `escrow_id`, `buyer`

## Note on transfers

This contract tracks **state** (pending / released / refunded). Actual ETH transfer on release/refund would be done via the Stylus host (e.g. cross-contract call with value). The Move code is ready for integration with such a native once available.

## License

MIT or Apache-2.0.
