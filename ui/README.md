# Escrow test UI

Simple React UI to create, read, release, and refund escrows against a deployed Move Stylus escrow contract.

## Prerequisites

1. **Deploy the escrow contract** (e.g. on Arbitrum Nitro devnode):

   ```bash
   cd /path/to/move-stylus-escrow
   move-stylus build
   move-stylus deploy --contract-name escrow --private-key 0x... --endpoint http://localhost:8547
   ```

2. **Start the devnode** so RPC is available at `http://localhost:8547` (or your RPC URL).

## Run the UI

```bash
cd ui
npm install
npm run dev
```

Open http://localhost:5173.

## Config in the UI

- **RPC URL**: e.g. `http://localhost:8547` (Arbitrum Nitro devnode).
- **Chain ID**: e.g. `412346` for Nitro devnode.
- **Contract address**: the deployed escrow contract address from `move-stylus deploy`.
- **Private key**: needed for **Create**, **Release**, and **Refund**. Use a dev key (e.g. the one pre-funded on devnode). Read operations work without a key.

## Test flow

1. Set RPC, Chain ID, contract address, and private key (buyer).
2. **Create**: set seller address, amount, deadline (0 = none), memo, arbitrator (0x0 = none). Click Create. Copy the “Created escrow ID” (bytes32).
3. **Read**: paste the escrow ID and click Read to see buyer, seller, amount, status, deadline, memo, arbitrator, isPending.
4. **Release**: as seller (or arbitrator), paste escrow ID and click Release.
5. **Refund**: as buyer (or arbitrator), paste escrow ID and click Refund.

Repeat Read after Release or Refund to see status change (Released / Refunded).
