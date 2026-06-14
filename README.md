# 🔄 Pharos Token Swapper

> **A Pharos Skill Engine extension for safe, slippage-protected token swapping on Pharos DEXes.**
> Natural language in → on-chain swap out.

[![Built on Pharos Skill Engine](https://img.shields.io/badge/Pharos-Skill%20Engine%20v0.1.0-blue)](https://docs.pharos.xyz/tooling-and-infrastructure/pharos-skill-engine-guide)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange)](https://getfoundry.sh)
[![License: MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## What Is This?

The **Pharos Token Swapper** is a skill package built on top of the [Pharos Skill Engine](https://docs.pharos.xyz/tooling-and-infrastructure/pharos-skill-engine-guide). It lets an AI agent (Claude, Cursor, Claude Code) execute token swaps on Pharos DEXes through natural language commands — with automatic safety checks built into every step.

**You say:** `"Swap 50 USDC to PHRS with 1% slippage"`
**The agent:** checks balance → checks allowance → gets a quote → calculates slippage → approves → swaps → monitors → shows you the result.

---

## Features

| Feature | Description |
|---------|-------------|
| ✅ Balance checks | Confirms you have enough tokens before attempting a swap |
| ✅ Allowance checks | Detects missing approvals automatically and runs them first |
| ✅ Price quotes | Previews expected output before committing |
| ✅ Slippage protection | Configurable slippage (default 1%) with automatic `amountOutMin` calculation |
| ✅ Deadline enforcement | Transactions auto-expire if not confirmed within 20 minutes |
| ✅ Swap history | Query past swaps via `SwapExecuted` event logs |
| ✅ ERC20 ↔ ERC20 | Any token pair with a liquidity pool |
| ✅ ERC20 ↔ PHRS | Swap between ERC20s and native PHRS |
| ✅ Full event emission | Every swap, approval, and state change emits a log |
| ✅ Verified on Pharos Scan | Source code publicly verifiable |

---

## Quick Start

### 1. Install

```bash
git clone https://github.com/JimmyOgb/pharos-token-swapper
cd pharos-token-swapper
```

Or with npx (if published):
```bash
npx skills add https://github.com/JimmyOgb/pharos-token-swapper
```

### 2. Install Foundry

```bash
which cast || (curl -L https://foundry.paradigm.xyz | bash && source ~/.zshenv && foundryup)
cast --version && forge --version
```

### 3. Configure

```bash
export PRIVATE_KEY=0xYOUR_PRIVATE_KEY_HERE
export RPC=https://rpc.pharos.xyz
export CHAIN_ID=688689
export DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)
```

### 4. Build

```bash
forge build
```

### 5. Use (Natural Language)

Point your AI agent at this repo and say things like:

- `"Swap 50 USDC to PHRS with 1% slippage"`
- `"What's my USDC balance?"`
- `"Check if I have enough allowance to swap 100 USDC"`
- `"Get me a quote for swapping 10 PHRS to USDC"`
- `"Show my swap history"`
- `"Deploy the swapper contract"`

---

## Supported Frameworks

| Framework | Supported |
|-----------|-----------|
| [Pharos Skill Engine](https://docs.pharos.xyz) | ✅ Native |
| [Claude Code](https://claude.ai/code) | ✅ |
| [Cursor](https://cursor.sh) | ✅ |
| OpenClaw | ✅ |
| Codex | ✅ |

---

## Project Structure

```
pharos-token-swapper/
│
├── SKILL.md                          ← AI agent entry point (read this first)
│
├── assets/
│   └── tokens.json                   ← Token addresses & router config
│
├── references/
│   └── swap.md                       ← Full command reference for all swap ops
│
├── src/
│   └── swap/
│       └── TokenSwapper.sol          ← Main swap contract
│
├── script/
│   └── DeployTokenSwapper.s.sol      ← Foundry deploy script
│
└── foundry.toml                      ← Compiler config
```

---

## Safety Model

Every write operation (swap, approval, deploy) follows a mandatory pre-check sequence:

```
1. ✓ Private key is set
2. ✓ Wallet address confirmed
3. ✓ Correct network (chain ID matches)
4. ✓ Sufficient PHRS balance for gas
   + Balance ≥ swap amount
   + Allowance ≥ swap amount (or runs approval first)
   + Quote previewed and confirmed
   + Slippage applied to amountOutMin
   + Deadline set 20 minutes ahead
```

---

## Swap Flow

```
User Request
     │
     ▼
check-balance ──► Insufficient? → STOP, inform user
     │
     ▼
check-allowance ──► Missing? → approve-token → wait for confirmation
     │
     ▼
get-quote ──► Show user expected output
     │
     ▼
slippage-protection ──► Calculate amountOutMin
     │
     ▼
execute-swap ──► Broadcast transaction
     │
     ▼
monitor-transaction ──► Show tx hash + explorer link
```

---

## Networks

| Network | RPC | Chain ID | Explorer |
|---------|-----|----------|----------|
| Atlantic Testnet | `https://rpc.pharos.xyz` | 688689 | [atlantic.pharosscan.xyz](https://atlantic.pharosscan.xyz) |
| Pacific Mainnet | `https://mainnet.pharos.xyz` | 747 | [pharosscan.xyz](https://pharosscan.xyz) |

---

## Built With

- [Pharos Skill Engine v0.1.0](https://docs.pharos.xyz/tooling-and-infrastructure/pharos-skill-engine-guide)
- [Foundry](https://getfoundry.sh) (`cast` + `forge`)
- Solidity `^0.8.20`
- Uniswap V2-compatible router interface

---

## License

MIT
