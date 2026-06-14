# Token Swap Operation Instructions

> Network Configuration: RPC is read from `assets/networks.json` or `$RPC` env var.
> Private Key: Always pass explicitly via `--private-key $PRIVATE_KEY`.
> Chain ID (Testnet): 688689 · Chain ID (Mainnet): 747

---

## check-balance

### Overview
Check the ERC20 or native PHRS balance of the connected wallet before initiating any swap. This is a free read-only operation — no gas required.

### Command Template

```bash
# Native PHRS balance
cast balance $DEPLOYER --rpc-url $RPC --ether

# ERC20 token balance (returns raw uint256 — divide by decimals)
cast call <token_address> "balanceOf(address)(uint256)" $DEPLOYER --rpc-url $RPC
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `token_address` | address | Yes (ERC20 only) | Contract address of the ERC20 token |
| `DEPLOYER` | address | Yes | Wallet address derived from `$PRIVATE_KEY` |

### Output Parsing
| Field | Description |
|-------|-------------|
| Native balance | Returned in ETH units directly (e.g. `1.5`) |
| ERC20 raw value | Divide by `10^decimals` to get human amount (e.g. `50000000` ÷ `10^6` = `50 USDC`) |

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `Empty return` | No contract at that address | Verify token address in `assets/tokens.json` |
| `connection refused` | Missing `--rpc-url` | Always pass `--rpc-url $RPC` |

> **Agent Guidelines**:
> 1. Always run balance check before any swap
> 2. Compare balance to requested swap amount; if insufficient, stop and inform user
> 3. For ERC20: read decimals first with `cast call <token> "decimals()(uint8)" --rpc-url $RPC`

---

## check-allowance

### Overview
Read the current ERC20 allowance granted to the DEX router. If the allowance is less than the swap amount, an approval transaction must be sent first.

### Command Template

```bash
cast call <token_address> \
  "allowance(address,address)(uint256)" \
  $DEPLOYER <router_address> \
  --rpc-url $RPC
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `token_address` | address | Yes | ERC20 token to be sold |
| `DEPLOYER` | address | Yes | Wallet/owner address |
| `router_address` | address | Yes | DEX router address (see `assets/tokens.json`) |

### Output Parsing
| Field | Description |
|-------|-------------|
| Returned uint256 | Current approved amount in raw token units. Divide by `10^decimals` for human value. `0` means no approval exists. |

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `Empty return` | Wrong token or router address | Verify both addresses |

> **Agent Guidelines**:
> 1. Run this before every swap involving an ERC20 input token
> 2. If `allowance < swap_amount`, proceed to `approve-token` section
> 3. If `allowance >= swap_amount`, skip approval and go directly to `execute-swap`

---

## approve-token

### Overview
Send an ERC20 `approve` transaction to allow the DEX router to spend the input token on your behalf. Required before every ERC20 swap unless a sufficient allowance already exists.

### Command Template

```bash
cast send <token_address> \
  "approve(address,uint256)" \
  <router_address> <amount_in_wei> \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `token_address` | address | Yes | ERC20 token to approve |
| `router_address` | address | Yes | DEX router address |
| `amount_in_wei` | uint256 | Yes | Amount in raw token units. For `type(uint256).max` (unlimited approval): `115792089237316195423570985008687907853269984665640564039457584007913129639935` |

### Output Parsing
| Field | Description |
|-------|-------------|
| `transactionHash` | Approval tx hash — show with explorer link |
| `status` | `0x1` = success, `0x0` = reverted |

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `execution reverted` | Token contract rejected approval | Check token address is correct |
| `insufficient funds` | Not enough PHRS for gas | Top up wallet with PHRS |
| `PRIVATE_KEY not set` | Env var missing | Run `export PRIVATE_KEY=0x...` |

> **Agent Guidelines**:
> 1. Run all four Write Operation Pre-checks (see SKILL.md)
> 2. Calculate `amount_in_wei = human_amount × 10^decimals`
> 3. Send the approval tx and wait for confirmation
> 4. Show tx hash with explorer link: `https://atlantic.pharosscan.xyz/tx/<hash>`
> 5. Proceed to `execute-swap` only after confirmation

---

## get-quote

### Overview
Read a price quote from the DEX router without sending a transaction. Use this to preview how many output tokens the user will receive before committing to a swap.

### Command Template

```bash
# getAmountsOut — returns expected output for a given input
cast call <router_address> \
  "getAmountsOut(uint256,address[])(uint256[])" \
  <amount_in_wei> "[<token_in_address>,<token_out_address>]" \
  --rpc-url $RPC
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `router_address` | address | Yes | DEX router (Uniswap V2-compatible) |
| `amount_in_wei` | uint256 | Yes | Input amount in raw token units |
| `token_in_address` | address | Yes | Token being sold |
| `token_out_address` | address | Yes | Token being bought |

### Output Parsing
| Field | Description |
|-------|-------------|
| `uint256[]` array | Index 0 = input amount, Index 1 = expected output amount in raw units. Divide by output token decimals for human value. |

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `INSUFFICIENT_LIQUIDITY` | No liquidity pool exists for this pair | Inform user; suggest a different pair |
| `Empty return` | Router address wrong or unsupported function | Verify router address in `assets/tokens.json` |

> **Agent Guidelines**:
> 1. Always run get-quote before execute-swap
> 2. Display the quote to the user: "You will receive approximately X [TOKEN]"
> 3. Apply slippage to calculate `amountOutMin`: `amountOutMin = quote × (1 - slippage/100)`
> 4. Ask user to confirm before proceeding to execute-swap

---

## slippage-protection

### Overview
Slippage protection sets the minimum output (`amountOutMin`) the user will accept. If the DEX can only give less than this, the transaction reverts automatically — protecting the user from price manipulation and sandwich attacks.

### Slippage Calculation

```bash
# Example: swap 50 USDC → PHRS with 1% slippage
# Step 1: Get quote
QUOTE=$(cast call <router> "getAmountsOut(uint256,address[])(uint256[])" \
  50000000 "[<USDC>,<WPHRS>]" --rpc-url $RPC | awk -F'[\\[,\\]]' '{print $2}')

# Step 2: Calculate amountOutMin (1% slippage = multiply by 99/100)
# For 1% slippage:
AMOUNT_OUT_MIN=$(echo "$QUOTE * 99 / 100" | bc)

# For 0.5% slippage:
# AMOUNT_OUT_MIN=$(echo "$QUOTE * 995 / 1000" | bc)
```

### Slippage Reference Table
| Slippage % | Multiplier | Use Case |
|------------|------------|----------|
| 0.1% | × 0.999 | Stablecoin pairs (low volatility) |
| 0.5% | × 0.995 | Standard pairs |
| 1.0% | × 0.990 | Default — recommended for most swaps |
| 2.0% | × 0.980 | High volatility pairs |
| 5.0% | × 0.950 | New/low-liquidity tokens |

> **Agent Guidelines**:
> 1. Default slippage is **1%** unless user specifies otherwise
> 2. Always inform the user what slippage is being applied
> 3. Never set slippage above 10% without explicit user confirmation
> 4. Use `amountOutMin` calculated here in the `execute-swap` command

---

## execute-swap

### Overview
Send the actual token swap transaction to the DEX router. This transfers the input token and receives the output token in a single atomic transaction. Requires prior approval if input is an ERC20.

### Command Template

```bash
# ERC20 → ERC20 swap (e.g. USDC → USDT)
cast send <router_address> \
  "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)" \
  <amount_in_wei> <amount_out_min> "[<token_in>,<token_out>]" $DEPLOYER <deadline> \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC

# ERC20 → Native PHRS (e.g. USDC → PHRS)
cast send <router_address> \
  "swapExactTokensForETH(uint256,uint256,address[],address,uint256)" \
  <amount_in_wei> <amount_out_min> "[<token_in>,<WPHRS_address>]" $DEPLOYER <deadline> \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC

# Native PHRS → ERC20 (e.g. PHRS → USDC)
cast send <router_address> \
  "swapExactETHForTokens(uint256,address[],address,uint256)" \
  <amount_out_min> "[<WPHRS_address>,<token_out>]" $DEPLOYER <deadline> \
  --value <amount_in_wei> \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `router_address` | address | Yes | DEX router address |
| `amount_in_wei` | uint256 | Yes | Exact input amount in raw token units |
| `amount_out_min` | uint256 | Yes | Minimum output after slippage (from `slippage-protection`) |
| `token_in` | address | Yes | Input token contract address |
| `token_out` / `WPHRS_address` | address | Yes | Output token (or wrapped PHRS for native swaps) |
| `DEPLOYER` | address | Yes | Recipient of output tokens (your wallet) |
| `deadline` | uint256 | Yes | Unix timestamp — must be in the future. Use: `$(date -d '+20 minutes' +%s)` |

### Deadline Calculation

```bash
# Set deadline 20 minutes from now
DEADLINE=$(date -d '+20 minutes' +%s)

# On macOS use:
DEADLINE=$(date -v+20M +%s)
```

### Output Parsing
| Field | Description |
|-------|-------------|
| `transactionHash` | Swap tx hash |
| `status` | `0x1` = success, `0x0` = reverted |
| `logs` | Contains `Swap` event with actual amounts in/out |

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `INSUFFICIENT_OUTPUT_AMOUNT` | Price moved beyond slippage tolerance | Increase slippage or retry |
| `EXPIRED` | Deadline passed before tx confirmed | Regenerate deadline and retry |
| `TransferFrom failed` | Approval missing or insufficient | Run `approve-token` first |
| `insufficient funds` | Not enough PHRS for gas | Top up wallet |
| `execution reverted: STF` | SafeTransferFrom failed — approval issue | Re-run `approve-token` |

> **Agent Guidelines**:
> 1. Run all four Write Operation Pre-checks (SKILL.md)
> 2. Confirm balance ≥ swap amount (`check-balance`)
> 3. Confirm allowance ≥ swap amount (`check-allowance`) — run `approve-token` if not
> 4. Run `get-quote` and show user the expected output
> 5. Calculate `amount_out_min` using `slippage-protection`
> 6. Generate deadline: `$(date -d '+20 minutes' +%s)` (Linux) or `$(date -v+20M +%s)` (macOS)
> 7. Send swap tx and show tx hash with explorer link
> 8. Proceed to `monitor-transaction` to confirm success

---

## monitor-transaction

### Overview
Check the status of a submitted swap transaction. Use the tx hash returned from `execute-swap` or `approve-token`.

### Command Template

```bash
# Get transaction details
cast tx <tx_hash> --rpc-url $RPC

# Get receipt (includes status + logs)
cast receipt <tx_hash> --rpc-url $RPC

# Check if confirmed (status field)
cast receipt <tx_hash> --rpc-url $RPC | grep "status"
```

### Output Parsing
| Field | Description |
|-------|-------------|
| `status` | `1` = confirmed success, `0` = reverted |
| `blockNumber` | Block the tx was included in |
| `gasUsed` | Actual gas consumed |
| `logs` | Event data — contains actual swap amounts |

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `transaction not found` | Node hasn't synced yet | Wait 5 seconds and retry |
| `status: 0` | Transaction reverted | Check revert reason in `logs` field |

> **Agent Guidelines**:
> 1. Wait at least 3 seconds after submission before polling
> 2. Show explorer link: `https://atlantic.pharosscan.xyz/tx/<hash>`
> 3. If `status: 0`, extract and explain the revert reason to the user
> 4. If confirmed, show actual amounts swapped from the event logs

---

## query-events

### Overview
Query past `SwapExecuted` events to show the user their swap history. Read-only, free, no gas.

### Command Template

```bash
# Query all SwapExecuted events from the deployed TokenSwapper contract
cast logs \
  --from-block 0 \
  --address <swapper_contract_address> \
  "SwapExecuted(address,address,address,uint256,uint256)" \
  --rpc-url $RPC

# Filter by user address (topic 1 = indexed sender)
cast logs \
  --from-block 0 \
  --address <swapper_contract_address> \
  "SwapExecuted(address,address,address,uint256,uint256)" \
  $DEPLOYER \
  --rpc-url $RPC
```

### Output Parsing
| Field | Description |
|-------|-------------|
| `topics[1]` | Indexed sender address (who did the swap) |
| `topics[2]` | Indexed tokenIn address |
| `topics[3]` | Indexed tokenOut address |
| `data` | ABI-encoded `amountIn` + `amountOut` (two uint256 values) |

> **Agent Guidelines**:
> 1. Decode `data` field: first 32 bytes = `amountIn`, next 32 bytes = `amountOut`
> 2. Divide amounts by respective token decimals for human-readable values
> 3. Display as a table: Date | TokenIn | AmountIn | TokenOut | AmountOut

---

## deploy-contract

### Overview
Deploy the `TokenSwapper` contract to Pharos. Only needs to be done once per network. The deployed address is then used for all swap operations.

### Command Template

```bash
# Pre-checks
cast wallet address --private-key $PRIVATE_KEY
cast balance $DEPLOYER --rpc-url $RPC --ether

# Deploy
forge script script/DeployTokenSwapper.s.sol:DeployTokenSwapper \
  --rpc-url $RPC \
  --private-key $PRIVATE_KEY \
  --broadcast

# Wait for indexer, then verify
sleep 10
forge verify-contract <deployed_address> src/swap/TokenSwapper.sol:TokenSwapper \
  --chain-id 688689 \
  --verifier-url https://api.socialscan.io/pharos-atlantic-testnet/v1/explorer/command_api/contract \
  --verifier blockscout \
  --constructor-args $(cast abi-encode "constructor(address)" <router_address>)
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `router_address` | address | Yes | DEX router address passed to constructor |

### Output Parsing
| Field | Description |
|-------|-------------|
| `Deployed to:` | Contract address — save this as `$SWAPPER` |
| `Transaction hash:` | Deployment tx hash |

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `forge build` fails | Solidity compilation error | Run `forge build` first and fix errors |
| `psycopg2` / SQL error on verify | Verified too soon after deploy | `sleep 10` then retry verify |
| `insufficient funds` | Not enough PHRS for deployment gas | Top up wallet |

> **Agent Guidelines**:
> 1. Run all four Write Operation Pre-checks (SKILL.md)
> 2. Run `forge build` first — only deploy if build passes cleanly
> 3. After deploy, save the contract address as `export SWAPPER=<address>`
> 4. Wait 10 seconds before verifying
> 5. Show Pharos Scan link to verified contract

---

## verify-contract

### Overview
Verify the `TokenSwapper` contract source code on Pharos Scan. Must be run after deployment.

### Command Template

```bash
sleep 10
forge verify-contract <contract_address> \
  src/swap/TokenSwapper.sol:TokenSwapper \
  --chain-id 688689 \
  --verifier-url https://api.socialscan.io/pharos-atlantic-testnet/v1/explorer/command_api/contract \
  --verifier blockscout \
  --constructor-args $(cast abi-encode "constructor(address)" <router_address>)
```

### Error Handling
| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `Already verified` | Contract is already verified | No action needed |
| `psycopg2` / SQL error | Too soon after deploy | Wait 10 seconds and retry |
| `Bytecode mismatch` | Source doesn't match deployed bytecode | Ensure same compiler version and settings |

> **Agent Guidelines**:
> 1. Always wait at least 10 seconds after deployment before verifying
> 2. Pass `--constructor-args` with the exact router address used during deployment
> 3. Confirm green verified badge at: `https://atlantic.pharosscan.xyz/address/<address>`
