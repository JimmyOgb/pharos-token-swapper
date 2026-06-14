# Pharos Token Swapper — Skill Entry Point

> v1.0.0 · Pharos Skill Engine Extension · Atlantic Testnet & Pacific Mainnet
> Built on: Pharos Skill Engine v0.1.0 · Requires Foundry (cast + forge)

---

## Prerequisites

Before any swap operation, the agent must confirm:

1. **Foundry installed** — run `which cast && which forge`. If missing, install via `curl -L https://foundry.paradigm.xyz | bash && foundryup`
2. **Private key set** — `echo $PRIVATE_KEY` must return a non-empty value
3. **RPC reachable** — `cast block-number --rpc-url $RPC` must return a block number
4. **Token addresses known** — read from `assets/tokens.json` or ask the user to supply the contract address

---

## Network Configuration

| Network          | RPC URL                        | Chain ID | Explorer                          |
|------------------|--------------------------------|----------|-----------------------------------|
| Atlantic Testnet | https://rpc.pharos.xyz         | 688689   | https://atlantic.pharosscan.xyz   |
| Pacific Mainnet  | https://mainnet.pharos.xyz     | 747      | https://pharosscan.xyz            |

```bash
# Testnet (default for this skill)
export RPC=https://rpc.pharos.xyz
export CHAIN_ID=688689
export EXPLORER=https://atlantic.pharosscan.xyz

# Derive deployer address from private key
export DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)
```

---

## Capability Index

> The agent scans this table to match the user's natural language request to the correct reference section.

| User Need | Capability | Detailed Instructions |
|-----------|------------|-----------------------|
| Swap X for Y / exchange tokens / trade USDC to PHRS / convert tokens | ERC20 token swap via DEX router | → references/swap.md#execute-swap |
| Swap with slippage / set max slippage / safe swap / protect against price impact | Slippage-protected swap | → references/swap.md#slippage-protection |
| Check swap quote / get swap price / how much will I get / preview swap | Read-only price quote from router | → references/swap.md#get-quote |
| Approve token / allow DEX to spend / set allowance | ERC20 approval before swap | → references/swap.md#approve-token |
| Check allowance / how much is approved / is token approved | Read current ERC20 allowance | → references/swap.md#check-allowance |
| Check token balance / how much X do I have / wallet balance | ERC20 or native balance check | → references/swap.md#check-balance |
| Monitor swap / did my swap go through / check transaction | Transaction status + receipt | → references/swap.md#monitor-transaction |
| Swap history / past swaps / show swap events | Query SwapExecuted events | → references/swap.md#query-events |
| Deploy swapper / set up swap contract / install swapper | Deploy TokenSwapper contract | → references/swap.md#deploy-contract |
| Verify swapper contract / confirm source code on explorer | forge verify-contract | → references/swap.md#verify-contract |

---

## Write Operation Pre-Check Sequence

**Every swap, approval, and deployment must run all four checks before executing.**

```bash
# Check 1 — Private key is set
echo $PRIVATE_KEY | grep -q "0x" && echo "✓ PRIVATE_KEY set" || echo "✗ Run: export PRIVATE_KEY=0x..."

# Check 2 — Derive and confirm wallet address
cast wallet address --private-key $PRIVATE_KEY

# Check 3 — Confirm correct network
cast chain-id --rpc-url $RPC

# Check 4 — Confirm sufficient PHRS balance for gas
cast balance $DEPLOYER --rpc-url $RPC --ether
```

> ⚠️ **CRITICAL:** `cast` and `forge` do NOT read `$PRIVATE_KEY` from the environment automatically. Always pass `--private-key $PRIVATE_KEY` explicitly in every command.

---

## Security Reminders

- Never log or print the raw private key value
- Never hardcode private keys in any generated script
- Always run `check-allowance` before approving — do not double-approve
- Always run `get-quote` before swapping — confirm the output amount is acceptable
- Always check token balance before swap — do not attempt swaps with insufficient funds
- Slippage default is **1%** — prompt the user if they want to change it
- Deadline default is **20 minutes** from current block timestamp

---

## Token Registry

Token addresses are in `assets/tokens.json`. Common tokens on Atlantic Testnet:

| Symbol | Address (Testnet) |
|--------|-------------------|
| PHRS   | Native (0x0000...0000 / use `--value`) |
| USDC   | 0xE0BE08c77f415F577A1B3A9aD7a1Df1479564ec8 |
| USDT   | (check assets/tokens.json) |

> If a token is not in the registry, ask the user to provide the contract address. Never guess.

---

## Quick Setup

```bash
# 1. Clone the skill
git clone https://github.com/JimmyOgb/pharos-token-swapper
cd pharos-token-swapper

# 2. Install Foundry if needed
which cast || (curl -L https://foundry.paradigm.xyz | bash && source ~/.zshenv && foundryup)

# 3. Set env vars
export PRIVATE_KEY=0xYOUR_PRIVATE_KEY_HERE
export RPC=https://rpc.pharos.xyz
export CHAIN_ID=688689
export DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)

# 4. Build contracts
forge build

# 5. Start swapping (natural language)
# "Swap 50 USDC to PHRS with 1% slippage"
```
