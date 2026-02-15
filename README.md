# Simple Escrow (Move Stylus)

A minimal **escrow** smart contract for [Arbitrum Stylus](https://docs.arbitrum.io/stylus/gentle-introduction), written in **Move** and compiled with [move-stylus](https://github.com/rather-labs/move-stylus).

## What it does

- **Buyer** creates an escrow deal with `create(seller, amount)` (and in production sends `amount` as `msg.value`).
- **Seller** can call `release(escrow)` to confirm and receive funds.
- **Buyer** can call `refund(escrow)` to cancel and get funds back.

Only one of release or refund can happen; the contract enforces buyer/seller roles and pending state.

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

## API (entrypoints)

| Function | Who | Description |
|----------|-----|-------------|
| `create(seller, amount)` | Buyer | Creates a new escrow (buyer = sender). |
| `release(escrow)` | Seller | Marks deal as released (funds to seller). |
| `refund(escrow)` | Buyer | Marks deal as refunded (funds to buyer). |

Views: `buyer(escrow)`, `seller(escrow)`, `amount(escrow)`, `status(escrow)`, `is_pending(escrow)`.

## Note on transfers

This contract tracks **state** (pending / released / refunded). Actual ETH transfer on release/refund would be done via the Stylus host (e.g. cross-contract call with value). The Move code is ready for integration with such a native once available.

## License

MIT or Apache-2.0.
