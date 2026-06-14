// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);

    function WETH() external pure returns (address);
}

/**
 * @title TokenSwapper
 * @notice Safe token swapping skill for Pharos DEXes.
 *         Includes balance checks, allowance checks, slippage protection,
 *         and full event emission for monitoring.
 * @dev    Built on Pharos Skill Engine v0.1.0
 */
contract TokenSwapper {
    // ─── State ────────────────────────────────────────────────────────────────

    address public immutable router;
    address public immutable owner;
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 100; // 1% in basis points

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted on every successful swap
    event SwapExecuted(
        address indexed sender,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /// @notice Emitted when a token approval is sent through this contract
    event TokenApproved(
        address indexed token,
        address indexed spender,
        uint256 amount
    );

    // ─── Errors ───────────────────────────────────────────────────────────────

    error InsufficientBalance(uint256 required, uint256 available);
    error InsufficientAllowance(uint256 required, uint256 current);
    error SlippageTooHigh(uint256 bps);
    error DeadlineExpired(uint256 deadline, uint256 current);
    error ZeroAmount();
    error InvalidPath();

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(address _router) {
        require(_router != address(0), "Router cannot be zero address");
        router = _router;
        owner = msg.sender;
    }

    // ─── Read Functions ───────────────────────────────────────────────────────

    /// @notice Get expected output for a given swap
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        uint256[] memory amounts = IUniswapV2Router(router).getAmountsOut(amountIn, path);
        return amounts[1];
    }

    /// @notice Get current ERC20 balance of an address
    function getTokenBalance(address token, address account) external view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }

    /// @notice Get current allowance granted to this contract or any spender
    function getAllowance(address token, address tokenOwner, address spender)
        external view returns (uint256)
    {
        return IERC20(token).allowance(tokenOwner, spender);
    }

    // ─── Write Functions ──────────────────────────────────────────────────────

    /**
     * @notice Swap ERC20 → ERC20 with slippage protection
     * @param tokenIn  Token to sell
     * @param tokenOut Token to buy
     * @param amountIn Exact amount of tokenIn to sell (in raw units)
     * @param slippageBps Slippage tolerance in basis points (100 = 1%)
     * @param deadline Unix timestamp after which tx reverts
     */
    function swapTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippageBps,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        if (tokenIn == address(0) || tokenOut == address(0)) revert InvalidPath();
        if (slippageBps > 1000) revert SlippageTooHigh(slippageBps); // max 10%
        if (deadline <= block.timestamp) revert DeadlineExpired(deadline, block.timestamp);

        // Balance check
        uint256 balance = IERC20(tokenIn).balanceOf(msg.sender);
        if (balance < amountIn) revert InsufficientBalance(amountIn, balance);

        // Allowance check
        uint256 allowance = IERC20(tokenIn).allowance(msg.sender, address(this));
        if (allowance < amountIn) revert InsufficientAllowance(amountIn, allowance);

        // Get quote and calculate amountOutMin
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        uint256[] memory quote = IUniswapV2Router(router).getAmountsOut(amountIn, path);
        uint256 amountOutMin = (quote[1] * (10000 - slippageBps)) / 10000;

        // Pull tokens from sender
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Approve router
        IERC20(tokenIn).approve(router, amountIn);

        // Execute swap
        uint256[] memory amounts = IUniswapV2Router(router).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            msg.sender,
            deadline
        );

        amountOut = amounts[1];
        emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /**
     * @notice Swap ERC20 → Native PHRS with slippage protection
     * @param tokenIn   Token to sell
     * @param amountIn  Exact input amount in raw token units
     * @param slippageBps Slippage tolerance in basis points
     * @param deadline  Unix timestamp deadline
     */
    function swapTokensForPHRS(
        address tokenIn,
        uint256 amountIn,
        uint256 slippageBps,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        if (slippageBps > 1000) revert SlippageTooHigh(slippageBps);
        if (deadline <= block.timestamp) revert DeadlineExpired(deadline, block.timestamp);

        uint256 balance = IERC20(tokenIn).balanceOf(msg.sender);
        if (balance < amountIn) revert InsufficientBalance(amountIn, balance);

        uint256 allowance = IERC20(tokenIn).allowance(msg.sender, address(this));
        if (allowance < amountIn) revert InsufficientAllowance(amountIn, allowance);

        address wphrs = IUniswapV2Router(router).WETH();
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = wphrs;

        uint256[] memory quote = IUniswapV2Router(router).getAmountsOut(amountIn, path);
        uint256 amountOutMin = (quote[1] * (10000 - slippageBps)) / 10000;

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(router, amountIn);

        uint256[] memory amounts = IUniswapV2Router(router).swapExactTokensForETH(
            amountIn,
            amountOutMin,
            path,
            msg.sender,
            deadline
        );

        amountOut = amounts[1];
        emit SwapExecuted(msg.sender, tokenIn, wphrs, amountIn, amountOut);
    }

    /**
     * @notice Swap Native PHRS → ERC20 with slippage protection
     * @param tokenOut   Token to receive
     * @param slippageBps Slippage tolerance in basis points
     * @param deadline   Unix timestamp deadline
     */
    function swapPHRSForTokens(
        address tokenOut,
        uint256 slippageBps,
        uint256 deadline
    ) external payable returns (uint256 amountOut) {
        if (msg.value == 0) revert ZeroAmount();
        if (slippageBps > 1000) revert SlippageTooHigh(slippageBps);
        if (deadline <= block.timestamp) revert DeadlineExpired(deadline, block.timestamp);

        address wphrs = IUniswapV2Router(router).WETH();
        address[] memory path = new address[](2);
        path[0] = wphrs;
        path[1] = tokenOut;

        uint256[] memory quote = IUniswapV2Router(router).getAmountsOut(msg.value, path);
        uint256 amountOutMin = (quote[1] * (10000 - slippageBps)) / 10000;

        uint256[] memory amounts = IUniswapV2Router(router).swapExactETHForTokens{value: msg.value}(
            amountOutMin,
            path,
            msg.sender,
            deadline
        );

        amountOut = amounts[1];
        emit SwapExecuted(msg.sender, wphrs, tokenOut, msg.value, amountOut);
    }

    // ─── Receive ──────────────────────────────────────────────────────────────

    receive() external payable {}
}
