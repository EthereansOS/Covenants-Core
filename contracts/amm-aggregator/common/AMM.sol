//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

import "./IAMM.sol";
import "../util/IERC20.sol";

abstract contract AMM is IAMM {

    mapping(address => uint256) internal _tokenValuesToTransfer;

    receive() external virtual payable {
    }

    function ethereumAddress() public override virtual view returns(address) {
        return address(0);
    }

    function inPercentage(address liquidityPoolAddress, uint256 numerator, uint256 denominator) public override view returns (uint256, uint256[] memory) {
        return this.inPercentage(liquidityPoolAddress, numerator, denominator, 0);
    }

    function byLiquidityPoolAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount) public override view returns(uint256[] memory) {
        return this.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount, 0);
    }

    function inPercentage(address liquidityPoolAddress, uint256 numerator, uint256 denominator, uint256 normalizeToDecimals) public virtual override view returns (uint256 providerAmount, uint256[] memory tokenAmounts) {
        providerAmount = (IERC20(liquidityPoolAddress).totalSupply() * numerator) / denominator;

        address[] memory liquidityPoolTokens = this.tokens(liquidityPoolAddress);

        tokenAmounts = new uint256[](liquidityPoolTokens.length);
        for(uint256 i = 0; i < tokenAmounts.length; i++) {
            tokenAmounts[i] = _normalizeTokenAmountToTheseDecimals(liquidityPoolTokens[i], (IERC20(liquidityPoolTokens[i]).balanceOf(liquidityPoolAddress) * numerator) / denominator, normalizeToDecimals);
        }
    }

    function byLiquidityPoolAmount(address liquidityPoolAddress, uint256 liquidityPoolAmount, uint256 normalizeToDecimals) public virtual override view returns(uint256[] memory tokenAmounts) {
        IERC20 pair = IERC20(liquidityPoolAddress);

        uint256 numerator = liquidityPoolAmount != 0 ? liquidityPoolAmount : pair.balanceOf(msg.sender);
        uint256 denominator = pair.totalSupply();

        address[] memory liquidityPoolTokens = this.tokens(liquidityPoolAddress);

        tokenAmounts = new uint256[](liquidityPoolTokens.length);
        for(uint256 i = 0; i < tokenAmounts.length; i++) {
            tokenAmounts[i] = _normalizeTokenAmountToTheseDecimals(liquidityPoolTokens[i], (IERC20(liquidityPoolTokens[i]).balanceOf(liquidityPoolAddress) * numerator) / denominator, normalizeToDecimals);
        }
    }

    function _receiver(LiquidityPoolData memory liquidityPoolData) internal virtual returns(address payable) {
        return payable(liquidityPoolData.receiver != address(0) ? liquidityPoolData.receiver : msg.sender);
    }

    function _receiver(LiquidityToSwap memory liquidityToSwap) internal virtual returns(address payable) {
        return payable(liquidityToSwap.receiver != address(0) ? liquidityToSwap.receiver : msg.sender);
    }

    function _flushBack(address payable sender, address[] memory tokens, uint256 tokensLength) internal virtual returns(uint256[] memory balances) {
        balances = new uint256[](tokensLength + 1);
        for(uint256 i = 0; i < tokensLength; i++) {
            if(tokens[i] != address(0)) {
                balances[i] = _flushBack(sender, tokens[i]);
            }
        }
        balances[tokensLength] = _flushBack(sender, address(0));
    }

    function _flushBack(address payable sender, address tokenA, address tokenB) internal virtual returns(uint256 balance0, uint256 balance1, uint256 balanceETH) {
        if(tokenA != address(0)) {
            balance0 = _flushBack(sender, tokenA);
        }
        if(tokenB != address(0)) {
            balance1 = _flushBack(sender, tokenB);
        }
        balanceETH = _flushBack(sender, address(0));
    }

    function _flushBack(address payable sender, address tokenAddress) internal virtual returns (uint256 balance) {
        balance = tokenAddress == address(0) ? address(this).balance : IERC20(tokenAddress).balanceOf(address(this));

        if(balance == 0) {
            return balance;
        }

        if(tokenAddress == address(0)) {
            sender.transfer(balance);
        } else {
            _safeTransfer(tokenAddress, sender, balance);
        }
    }

    function _transferToMeAndCheckAllowance(LiquidityPoolData memory data, address operator, bool add) internal virtual {
        if(!add) {
            return _transferToMeAndCheckAllowance(data.liquidityPoolAddress, data.liquidityPoolAmount, msg.sender, operator);
        }
        _transferToMeAndCheckAllowance(data.tokens, data.amounts, msg.sender, operator);
    }

    function _transferToMeAndCheckAllowance(LiquidityPoolData[] memory data, address operator, bool add) internal virtual returns (address[] memory tokens, uint256 length) {
        tokens = new address[](200);
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
        }
        _transferToMeCheckAllowanceAndClear(tokens, length, msg.sender, operator);
    }

    function _transferToMeAndCheckAllowance(LiquidityToSwap[] memory data, address operator) internal virtual returns (address[] memory tokens, uint256 length) {
        tokens = new address[](data.length);
        for(uint256 i = 0; i < data.length; i++) {
            if(_tokenValuesToTransfer[data[i].tokens[0]] == 0) {
                tokens[length++] = data[i].tokens[0];
            }
            _tokenValuesToTransfer[data[i].tokens[0]] += data[i].amount;
        }
        _transferToMeCheckAllowanceAndClear(tokens, length, msg.sender, operator);
    }

    function _transferToMeCheckAllowanceAndClear(address[] memory tokens, uint256 length, address from, address operator) internal virtual {
        for(uint256 i = 0; i < length; i++) {
            if(_tokenValuesToTransfer[tokens[i]] > 0) {
                _transferToMeAndCheckAllowance(tokens[i], _tokenValuesToTransfer[tokens[i]], from, operator);
            }
            delete _tokenValuesToTransfer[tokens[i]];
        }
    }

    function _transferToMeAndCheckAllowance(address[] memory tokens, uint256[] memory amounts, address from, address operator) internal virtual {
        for(uint256 i = 0; i < tokens.length; i++) {
            _transferToMeAndCheckAllowance(tokens[i], amounts[i], from, operator);
        }
    }

    function _transferToMeAndCheckAllowance(address tokenAddress, uint256 value, address from, address operator) internal virtual {
        _transferToMe(tokenAddress, from, value);
        _checkAllowance(tokenAddress, value, operator);
    }

    function _transferToMe(address tokenAddress, address from, uint256 value) internal virtual {
        if(tokenAddress == address(0)) {
            return;
        }
        _safeTransferFrom(tokenAddress, from, address(this), value);
    }

    function _checkAllowance(address tokenAddress, uint256 value, address operator) internal virtual {
        if(tokenAddress == address(0) || operator == address(0)) {
            return;
        }
        IERC20 token = IERC20(tokenAddress);
        if(token.allowance(address(this), operator) <= value) {
            _safeApprove(tokenAddress, operator, token.totalSupply());
        }
    }

    function _safeApprove(address erc20TokenAddress, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'APPROVE_FAILED');
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }

    function _safeTransferFrom(address erc20TokenAddress, address from, address to, uint256 value) internal virtual {
        (bool success, bytes memory data) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFERFROM_FAILED');
    }

    function _sortTokens(IERC20 tokenA, IERC20 tokenB) internal virtual pure returns(IERC20, IERC20) {
        if (tokenA < tokenB) {
            return (tokenA, tokenB);
        }
        return (tokenB, tokenA);
    }

    function _normalizeTokenAmountsToTheseDecimals(address[] memory tokenAddresses, uint256[] memory amounts, uint256 decimals) internal virtual view returns (uint256[] memory) {
        if(decimals == 0) {
            return amounts;
        }
        uint256[] memory newAmounts = new uint256[] (amounts.length);
        for(uint256 i = 0; i < newAmounts.length; i++) {
            newAmounts[i] = _normalizeTokenAmountToTheseDecimals(tokenAddresses[i], amounts[i], decimals);
        }
        return newAmounts;
    }

    function _normalizeTokenAmountToTheseDecimals(address tokenAddress, uint256 amount, uint256 decimals) internal virtual view returns(uint256) {
        if(decimals == 0) {
            return amount;
        }
        uint256 remainingDecimals = decimals;
        IERC20 token = IERC20(tokenAddress);
        remainingDecimals -= token.decimals();

        if(remainingDecimals == 0) {
            return amount;
        }

        return amount * (remainingDecimals == 0 ? 1 : (10**remainingDecimals));
    }

    function byTokenAmount(address liquidityPoolAddress, address tokenAddress, uint256 tokenAmount, uint256 normalizeTokenAmountsToTheseDecimals) public override view returns(uint256 liquidityPoolAmount, uint256[] memory tokenAmounts) {
        address[] memory lpTokens = this.tokens(liquidityPoolAddress);
        (uint256 lpTotalAmount, uint256[] memory lpTokenTotalAmounts) = this.amounts(liquidityPoolAddress);
        uint256 i = 0;
        for(i; i < lpTokens.length; i++) {
            if(lpTokens[i] == tokenAddress) {
                break;
            }
        }
        uint256 denominator = lpTokenTotalAmounts[i];
        tokenAmounts = new uint256[](lpTokenTotalAmounts.length);
        liquidityPoolAmount = (lpTotalAmount * tokenAmount) / denominator;
        for(uint256 z = 0; z < lpTokenTotalAmounts.length; z++) {
            if(z == i) {
                tokenAmounts[z] = tokenAmount;
                continue;
            }
            tokenAmounts[z] = (lpTokenTotalAmounts[z] * tokenAmount) / denominator;
        }

        if(normalizeTokenAmountsToTheseDecimals != 0) {
            tokenAmounts = _normalizeTokenAmountsToTheseDecimals(lpTokens, tokenAmounts, normalizeTokenAmountsToTheseDecimals);
        }
    }

    function byTokenAmount(address liquidityPoolAddress, address tokenAddress, uint256 tokenAmount) public override view returns(uint256, uint256[] memory) {
        return byTokenAmount(liquidityPoolAddress, tokenAddress, tokenAmount, 0);
    }
}