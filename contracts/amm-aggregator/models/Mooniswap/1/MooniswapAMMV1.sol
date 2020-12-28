//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./IMooniswapAMMV1.sol";
import "../../../common/AMM.sol";

contract MooniswapAMMV1 is IMooniswapAMMV1, AMM {

    address private immutable _mooniFactoryAddress;

    constructor(address mooniFactoryAddress) {
        _mooniFactoryAddress = mooniFactoryAddress;
    }

    function factory() public virtual override view returns(address) {
        return _mooniFactoryAddress;
    }

    function info() public virtual override pure returns(string memory name, uint256 version) {
        return ("MooniswapAMM", 1);
    }

    function addLiquidity(LiquidityPoolData memory data) public payable virtual override returns(uint256 amount) {
        Mooniswap mooniswap = _getOrCreateMooniswap(data.tokens[0], data.tokens[1], data.amounts[0], data.amounts[1]);
        amount = _addLiquidityWork(data, mooniswap);
        _flushBack(_sender(data), data.tokens[0], data.tokens[1]);
    }

    function addLiquidityBatch(LiquidityPoolData[] memory data) public payable virtual override returns(uint256[] memory amounts) {
        (address[] memory tokens, uint256 tokensLength, Mooniswap[] memory mooniswap) = _transferToMeAndCheckAllowance(data, true);
        amounts = new uint256[](data.length);
        for(uint256 i = 0; i < data.length; i++) {
            amounts[i] = _addLiquidityWork(data[i], mooniswap[i]);
        }
        _flushBack(_sender(data[0]), tokens, tokensLength);
    }

    function _getOrCreateMooniswap(address token0, address token1, uint256 token0Amount, uint256 token1Amount) private returns (Mooniswap mooniswap) {
        mooniswap = IMooniFactory(_mooniFactoryAddress).pools(IERC20(token0), IERC20(token1));
        if(address(mooniswap) == address(0)) {
            mooniswap = IMooniFactory(_mooniFactoryAddress).deploy(IERC20(token0), IERC20(token1));
        }
        if(token0 != address(0) && token0Amount > 0) {
            _transferToMeAndCheckAllowance(token0, token0Amount, address(mooniswap));
        }
        if(token1 != address(0) && token1Amount > 0) {
            _transferToMeAndCheckAllowance(token1, token1Amount, address(mooniswap));
        }
    }

    function _transferToMeAndCheckAllowance(LiquidityPoolData[] memory data, bool add) private returns(address[] memory tokens, uint256 length, Mooniswap[] memory mooniswap) {
        tokens = new address[](200);
        mooniswap = new Mooniswap[](data.length);
        for(uint256 i = 0; i < data.length; i++) {
            if(!add) {
                if(_tokenValuesToTransfer[data[i].liquidityPoolAddress] == 0) {
                    tokens[length++] = data[i].liquidityPoolAddress;
                }
                _tokenValuesToTransfer[data[i].liquidityPoolAddress] += data[i].liquidityPoolAmount;
                continue;
            }
            address[] memory tokensInput = data[i].tokens;
            uint256[] memory amounts = data[i].amounts;
            for(uint256 j = 0; j < tokensInput.length; j++) {
                if(_tokenValuesToTransfer[tokensInput[j]] == 0) {
                    tokens[length++] = tokensInput[j];
                }
                _tokenValuesToTransfer[tokensInput[j]] += amounts[j];
            }
            mooniswap[i] = _getOrCreateMooniswap(data[i].tokens[0], data[i].tokens[1], data[i].amounts[0], data[i].amounts[1]);
        }
        _transferToMeCheckAllowanceAndClear(tokens, length, address(0));
    }

    function _addLiquidityWork(LiquidityPoolData memory data, Mooniswap mooniswap) internal virtual returns(uint256 amount) {
        require(data.receiver != address(0), "Receiver cannot be void address");
        (IERC20 t1, IERC20 t2) = _sortTokens(IERC20(data.tokens[0]), IERC20(data.tokens[1]));
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = t1;
        tokens[1] = t2;
        uint256[] memory minAmounts = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = address(t1) == data.tokens[0] ? data.amounts[0] : data.amounts[1];
        amounts[1] = address(t2) == data.tokens[1] ? data.amounts[1] : data.amounts[0];

        if(data.tokens[0] != address(0) && data.tokens[1] != address(0)) {
            mooniswap.deposit(amounts, minAmounts);
        } else {
            mooniswap.deposit{value : data.tokens[0] == address(0) ? amounts[0] : amounts[1]}(amounts, minAmounts);
        }
        amount = _flushBack(_receiver(data), address(mooniswap));
    }

    function removeLiquidity(LiquidityPoolData memory data) public virtual override returns(uint256[] memory amounts) {
        _transferToMeAndCheckAllowance(data, address(0), false);
        amounts = _removeLiquidityWork(data);
        _flushBack(_sender(data), data.liquidityPoolAddress);
    }

    function removeLiquidityBatch(LiquidityPoolData[] memory data) public virtual override returns(uint256[][] memory amounts) {
        (address[] memory tokens, uint256 tokensLength) = _transferToMeAndCheckAllowance(data, address(0), false);
        amounts = new uint256[][](data.length);
        for(uint256 i = 0; i < data.length; i++) {
            amounts[i] = _removeLiquidityWork(data[i]);
        }
        _flushBack(_sender(data[0]), tokens, tokensLength);
    }

    function _removeLiquidityWork(LiquidityPoolData memory data) internal virtual returns (uint256[] memory amounts) {
        require(data.receiver != address(0), "Receiver cannot be void address");
        Mooniswap mooniswap = Mooniswap(data.liquidityPoolAddress);
        mooniswap.withdraw(data.liquidityPoolAmount, new uint256[](2));
        IERC20[] memory tokens = mooniswap.getTokens();
        amounts = new uint256[](tokens.length);
        for(uint256 i = 0 ; i < tokens.length; i++) {
            amounts[i] = _flushBack(_receiver(data), address(tokens[i]));
        }
    }

    function swapLiquidity(LiquidityToSwap memory data) public payable virtual override {
        _transferToMeAndCheckAllowance(data.tokens[0], data.amount, address(0));
        _swapLiquidityWork(data);
        _flushBack(_sender(data), data.tokens, data.tokens.length);
    }

    function swapLiquidityBatch(LiquidityToSwap[] memory data) public payable virtual override {
        (address[] memory tokens, uint256 tokensLength) = _transferToMeAndCheckAllowance(data, address(0));
        for(uint256 i = 0; i < data.length; i++) {
            _swapLiquidityWork(data[i]);
        }
        _flushBack(_sender(data[0]), tokens, tokensLength);
    }

    function _swapLiquidityWork(LiquidityToSwap memory data) internal virtual {
        require(data.receiver != address(0), "Receiver cannot be void address");
        Mooniswap mooniswap = _getOrCreateMooniswap(data.tokens[0], data.tokens[1], 0, 0);
        uint256 result = 0;
        if(data.enterInETH) {
            result = mooniswap.swap{value : data.amount}(IERC20(data.tokens[0]), IERC20(data.tokens[1]), data.amount, 1, address(0));
        } else {
            result = mooniswap.swap(IERC20(data.tokens[0]), IERC20(data.tokens[1]), data.amount, 1, address(0));
        }
        if(data.exitInETH) {
            payable(data.receiver).transfer(result);
        } else {
            _safeTransfer(data.tokens[1], data.receiver, result);
        }
    }

    function tokens(address liquidityPoolAddress) public override view returns(address[] memory tokenAddresses) {
        IERC20[] memory liquidityPoolTokens = Mooniswap(liquidityPoolAddress).getTokens();
        tokenAddresses = new address[](liquidityPoolTokens.length);

        for(uint256 i = 0; i < liquidityPoolTokens.length; i++) {
            tokenAddresses[i] = address(liquidityPoolTokens[i]);
        }
    }
}