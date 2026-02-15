import { useState, useCallback } from "react";
import {
  createPublicClient,
  createWalletClient,
  http,
  type Address,
  type Hash,
  type Hex,
  getContract,
  zeroAddress,
  toHex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { escrowAbi } from "./abi/escrow";

// Arbitrum Nitro devnode default
const DEV_CHAIN_ID = 412346;

const STATUS_LABELS: Record<number, string> = {
  0: "Pending",
  1: "Released",
  2: "Refunded",
};

function App() {
  const [rpcUrl, setRpcUrl] = useState("http://localhost:8547");
  const [chainId, setChainId] = useState(DEV_CHAIN_ID);
  const [contractAddress, setContractAddress] = useState<Address | "">("");
  const [connectedAddress, setConnectedAddress] = useState<Address | null>(null);
  const [privKey, setPrivKey] = useState("");
  const [escrowId, setEscrowId] = useState<Hex | "">("");
  const [lastCreatedId, setLastCreatedId] = useState<Hex | "">("");
  const [readResult, setReadResult] = useState<Record<string, unknown> | null>(null);
  const [txHash, setTxHash] = useState<Hash | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  // Create form
  const [seller, setSeller] = useState("");
  const [amount, setAmount] = useState("1000");
  const [deadline, setDeadline] = useState("0");
  const [memo, setMemo] = useState("");
  const [arbitrator, setArbitrator] = useState("");

  const getWalletAndPublic = useCallback(() => {
    if (!contractAddress) throw new Error("Set contract address");
    const transport = http(rpcUrl);
    const publicClient = createPublicClient({ transport, chain: { id: chainId, name: "Dev", nativeCurrency: { decimals: 18, name: "ETH", symbol: "ETH" }, rpcUrls: { default: { http: [rpcUrl] } } } });
    if (!privKey) throw new Error("Set private key for write operations (create/release/refund)");
    const account = privateKeyToAccount(privKey as Hex);
    const walletClient = createWalletClient({
      account,
      transport: http(rpcUrl),
      chain: { id: chainId, name: "Dev", nativeCurrency: { decimals: 18, name: "ETH", symbol: "ETH" }, rpcUrls: { default: { http: [rpcUrl] } } },
    });
    return { publicClient, walletClient };
  }, [contractAddress, rpcUrl, privKey, chainId]);

  const connect = useCallback(async () => {
    setError(null);
    try {
      const ethereum = (window as unknown as { ethereum?: { request: (args: unknown) => Promise<string[]> } }).ethereum;
      if (!ethereum) {
        setError("MetaMask not found");
        return;
      }
      const [addr] = await ethereum.request({ method: "eth_requestAccounts" });
      setConnectedAddress(addr as Address);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Connect failed");
    }
  }, []);

  const readOnlyClient = useCallback(() => {
    return createPublicClient({
      transport: http(rpcUrl),
      chain: { id: chainId, name: "Dev", nativeCurrency: { decimals: 18, name: "ETH", symbol: "ETH" }, rpcUrls: { default: { http: [rpcUrl] } } },
    });
  }, [rpcUrl, chainId]);

  const createEscrow = useCallback(async () => {
    if (!contractAddress) {
      setError("Set contract address");
      return;
    }
    setError(null);
    setLoading(true);
    setTxHash(null);
    setLastCreatedId("");
    try {
      const { publicClient, walletClient } = getWalletAndPublic();
      const account = walletClient.account!;

      const memoBytes = new TextEncoder().encode(memo);
      const memoHex = toHex(memoBytes) as Hex;
      const hash = await walletClient.writeContract({
        address: contractAddress,
        abi: escrowAbi,
        functionName: "create",
        args: [
          seller as Address,
          BigInt(amount),
          BigInt(deadline),
          memoHex,
          (arbitrator || zeroAddress) as Address,
        ],
        account,
      });
      setTxHash(hash);

      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      // First log is typically NewUID; topics[1] is the escrow object ID (bytes32)
      const uid = receipt.logs[0]?.topics[1];
      if (uid) {
        setLastCreatedId(uid as Hex);
        setEscrowId(uid as Hex);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [contractAddress, seller, amount, deadline, memo, arbitrator, getWalletAndPublic]);

  const readEscrow = useCallback(async () => {
    if (!contractAddress || !escrowId) {
      setError("Set contract address and escrow ID");
      return;
    }
    setError(null);
    setLoading(true);
    setReadResult(null);
    try {
      const publicClient = privKey ? getWalletAndPublic().publicClient : readOnlyClient();
      const c = getContract({
        address: contractAddress,
        abi: escrowAbi,
        client: publicClient,
      });
      const [buyer, sellerAddr, amountVal, statusVal, deadlineVal, memoVal, arbitratorVal, isPendingVal] =
        await Promise.all([
          c.read.buyer([escrowId as Hex]),
          c.read.seller([escrowId as Hex]),
          c.read.amount([escrowId as Hex]),
          c.read.status([escrowId as Hex]),
          c.read.deadline([escrowId as Hex]),
          c.read.memo([escrowId as Hex]),
          c.read.arbitrator([escrowId as Hex]),
          c.read.isPending([escrowId as Hex]),
        ]);
      let memoStr = "";
      if (typeof memoVal === "string" && memoVal.startsWith("0x")) {
        const hex = memoVal.slice(2);
        const bytes = new Uint8Array(hex.length / 2);
        for (let i = 0; i < hex.length; i += 2) bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16);
        memoStr = new TextDecoder().decode(bytes);
      } else {
        memoStr = String(memoVal ?? "");
      }
      setReadResult({
        buyer,
        seller: sellerAddr,
        amount: amountVal.toString(),
        status: Number(statusVal),
        statusLabel: STATUS_LABELS[Number(statusVal)] ?? "Unknown",
        deadline: deadlineVal.toString(),
        memo: memoStr,
        arbitrator: arbitratorVal,
        isPending: isPendingVal,
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [contractAddress, escrowId, getWalletAndPublic]);

  const release = useCallback(async () => {
    if (!contractAddress || !escrowId) {
      setError("Set contract address and escrow ID");
      return;
    }
    setError(null);
    setLoading(true);
    setTxHash(null);
    try {
      const { walletClient } = getWalletAndPublic();
      const account = walletClient.account!;
      const hash = await walletClient.writeContract({
        address: contractAddress,
        abi: escrowAbi,
        functionName: "release",
        args: [escrowId as Hex],
        account,
      });
      setTxHash(hash);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [contractAddress, escrowId, getWalletAndPublic]);

  const refund = useCallback(async () => {
    if (!contractAddress || !escrowId) {
      setError("Set contract address and escrow ID");
      return;
    }
    setError(null);
    setLoading(true);
    setTxHash(null);
    try {
      const { walletClient } = getWalletAndPublic();
      const account = walletClient.account!;
      const hash = await walletClient.writeContract({
        address: contractAddress,
        abi: escrowAbi,
        functionName: "refund",
        args: [escrowId as Hex],
        account,
      });
      setTxHash(hash);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [contractAddress, escrowId, getWalletAndPublic]);

  return (
    <div style={{ maxWidth: 720, margin: "0 auto", padding: 24, fontFamily: "system-ui" }}>
      <h1>Escrow (Move Stylus) – Test UI</h1>

      <section style={{ marginBottom: 24 }}>
        <h2>Config</h2>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <label>
            RPC URL
            <input
              value={rpcUrl}
              onChange={(e) => setRpcUrl(e.target.value)}
              style={{ display: "block", width: "100%", marginTop: 4, padding: 8 }}
            />
          </label>
          <label>
            Chain ID (e.g. 412346 for Arbitrum Nitro devnode)
            <input
              type="number"
              value={chainId}
              onChange={(e) => setChainId(Number(e.target.value) || DEV_CHAIN_ID)}
              style={{ display: "block", width: "100%", marginTop: 4, padding: 8 }}
            />
          </label>
          <label>
            Contract address
            <input
              value={contractAddress}
              onChange={(e) => setContractAddress(e.target.value as Address)}
              placeholder="0x..."
              style={{ display: "block", width: "100%", marginTop: 4, padding: 8 }}
            />
          </label>
          <label>
            Private key (optional – for scripted tests; otherwise use Connect)
            <input
              type="password"
              value={privKey}
              onChange={(e) => setPrivKey(e.target.value)}
              placeholder="0x..."
              style={{ display: "block", width: "100%", marginTop: 4, padding: 8 }}
            />
          </label>
          {!privKey && (
            <button type="button" onClick={connect} style={{ padding: "8px 16px" }}>
              Connect wallet
            </button>
          )}
          {(connectedAddress || privKey) && (
            <span style={{ color: "green" }}>
              {privKey ? "Using private key" : `Connected: ${connectedAddress?.slice(0, 10)}...`}
            </span>
          )}
        </div>
      </section>

      {error && (
        <div style={{ padding: 12, background: "#fee", marginBottom: 24 }}>{error}</div>
      )}
      {txHash && (
        <div style={{ padding: 12, background: "#efe", marginBottom: 24 }}>
          Tx: {txHash}
        </div>
      )}

      <section style={{ marginBottom: 24 }}>
        <h2>Create escrow</h2>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <input placeholder="Seller address" value={seller} onChange={(e) => setSeller(e.target.value)} style={{ padding: 8 }} />
          <input placeholder="Amount" value={amount} onChange={(e) => setAmount(e.target.value)} style={{ padding: 8 }} />
          <input placeholder="Deadline (0 = none)" value={deadline} onChange={(e) => setDeadline(e.target.value)} style={{ padding: 8 }} />
          <input placeholder="Memo" value={memo} onChange={(e) => setMemo(e.target.value)} style={{ padding: 8 }} />
          <input placeholder="Arbitrator (0x0 = none)" value={arbitrator} onChange={(e) => setArbitrator(e.target.value)} style={{ padding: 8 }} />
          <button type="button" onClick={createEscrow} disabled={loading} style={{ padding: "8px 16px" }}>
            Create
          </button>
          {lastCreatedId && (
            <div style={{ fontSize: 12, wordBreak: "break-all" }}>
              Created escrow ID: {lastCreatedId}
            </div>
          )}
        </div>
      </section>

      <section style={{ marginBottom: 24 }}>
        <h2>Read escrow</h2>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <input
            placeholder="Escrow ID (bytes32 hex)"
            value={escrowId}
            onChange={(e) => setEscrowId(e.target.value as Hex)}
            style={{ padding: 8 }}
          />
          <button type="button" onClick={readEscrow} disabled={loading} style={{ padding: "8px 16px" }}>
            Read
          </button>
          {readResult && (
            <pre style={{ background: "#f5f5f5", padding: 12, overflow: "auto" }}>
              {JSON.stringify(readResult, null, 2)}
            </pre>
          )}
        </div>
      </section>

      <section style={{ marginBottom: 24 }}>
        <h2>Actions</h2>
        <div style={{ display: "flex", gap: 8 }}>
          <button type="button" onClick={release} disabled={loading || !escrowId} style={{ padding: "8px 16px" }}>
            Release (seller/arbitrator)
          </button>
          <button type="button" onClick={refund} disabled={loading || !escrowId} style={{ padding: "8px 16px" }}>
            Refund (buyer/arbitrator)
          </button>
        </div>
      </section>

      <p style={{ color: "#666", fontSize: 14 }}>
        Deploy the escrow contract first (e.g. move-stylus deploy). Then set RPC and contract address above. Use Create to open an escrow and copy the escrow ID from the log to Read or Actions.
      </p>
    </div>
  );
}

export default App;
