// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/IERC20.sol";
import "../lib/safeMath.sol";
import "../lib/Context.sol";
import "../lib/Ownable.sol";
import "../lib/IUniswapV2Router02.sol";
import "../lib/IUniswapV2Factory.sol";

contract UIC is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;

    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private constant MAX = ~uint256(0);

    //Total Supply
    uint8 private _decimals = 18;
    uint256 private _tTotal = 21000000 * 10**18;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 public _tTaxFeeTotal;

    string private _name = "UIC";
    string private _symbol = "UIC";

    mapping(address => bool) public _isExcludedFee;
    mapping(address => bool) public _foundation;
    address[] private _excluded;

    uint256 presaleEndTime = block.timestamp + 86400 * 30;
    
    bool private feeIt = true;
    address public burnAddress =
        address(0x000000000000000000000000000000000000dEaD);

    mapping(address => bool) public includeUniswapV2Pair;
    address[] private uniswapV2Pair;
    // LP Provider part
    IUniswapV2Router02 public uniswapV2Router;

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    constructor(
        address _uniswapV2Router,
        address[] memory tokens
    ) {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        _tOwned[_msgSender()] = _tTotal;
        _rOwned[_msgSender()] = _rTotal;
        // aditional tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            // Create a uniswap pair for this new token
            address _uniswapSubV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), tokens[i]);
            setExcludedFee(_uniswapSubV2Pair);
            setPancakePair(_uniswapSubV2Pair);
        }

        // ADD WETH LP
        
        // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        setExcludedFee(_uniswapV2Pair);
        setPancakePair(_uniswapV2Pair);
        setExcludedFee(_msgSender());
        setExcludedFee(burnAddress);
        setExcludedFee(address(this));

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcludedFee[account]) return _tOwned[account];
        else return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    // config
    function setUniswapV2Router(address _uniswapV2Router) public onlyOwner {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
    }

    function setPresaleEndTime(uint256 _time) public onlyOwner{
        presaleEndTime = _time;
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) {
            removeAllFee();
        }
        bool _buy = includeUniswapV2Pair[sender]?true:false;
        bool _sell = includeUniswapV2Pair[recipient]?true:false;
        bool _isTransfer = !_buy&&!_sell?true:false;

        if(block.timestamp < presaleEndTime){
          if(_buy){
            require(_foundation[recipient], "only foundation can buy");
          }
        }

        if (takeFee) {
            if(_buy){
              if(_isExcludedFee[recipient]){
                _transferBothExcluded(sender, recipient, amount);
              }else{
                _transferForBuy(sender, recipient, amount);
              }
            }
            if(_sell){
              if(_isExcludedFee[sender]){
                _transferBothExcluded(sender, recipient, amount);
              }else{
                _transferForSell(sender, recipient, amount);
              }
            }
            if(_isTransfer){
              if (_isExcludedFee[sender] && !_isExcludedFee[recipient]) {
                  _transferFromExcluded(sender, recipient, amount);
              } else if (!_isExcludedFee[sender] && _isExcludedFee[recipient]) {
                  _transferToExcluded(sender, recipient, amount);
              } else if (!_isExcludedFee[sender] && !_isExcludedFee[recipient]) {
                  _transferStandard(sender, recipient, amount);
              } else if (_isExcludedFee[sender] && _isExcludedFee[recipient]) {
                  _transferBothExcluded(sender, recipient, amount);
              } else {
                  _transferStandard(sender, recipient, amount);
              }
            }
        } else {
            _transferBothExcluded(sender, recipient, amount);
        }

        if (!takeFee) {
            restoreAllFee();
        }
    }

    // sell
    function _transferForSell(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 tTransferAmount,
            uint256 tBurn
        ) = _getSellTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tTransferAmount,
            0,
            _getRate()
        );
        _rOwned[sender] = _rOwned[sender].sub(rAmount, "sub2 rAmount");
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        if (rFee > 0) {
            _reflectFee(rFee);
        }
        if (tBurn > 0) {
            _takeBurn(sender, tBurn);
        }
        emit Transfer(sender, recipient, tTransferAmount);
    }

    // buy
    function _transferForBuy(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (uint256 tTransferAmount, uint256 tFee) = _getBuyTValues(tAmount);
        // uint256 tFee = 0;
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tTransferAmount,
            tFee,
            _getRate()
        );
        _tOwned[sender] = _tOwned[sender].sub(tAmount, "sub3 tAmount");
        _rOwned[sender] = _rOwned[sender].sub(rAmount, "sub3 rAmount");


        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        if (rFee > 0) {
            _reflectFee(rFee);
        }
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 tTransferAmount, uint256 tFee) = _getTransferTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tTransferAmount, tFee, _getRate());
        _rOwned[sender] = _rOwned[sender].sub(rAmount, "sub1 rAmount");
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (uint256 tTransferAmount, uint256 tFee) = _getTransferTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tTransferAmount,
            tFee,
            _getRate()
        );
        _tOwned[sender] = _tOwned[sender].sub(tAmount, "sub3 tAmount");
        _rOwned[sender] = _rOwned[sender].sub(rAmount, "sub3 rAmount");
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        if (rFee > 0) {
            _reflectFee(rFee);
        }
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 tTransferAmount,
            uint256 tFee
        ) = _getTransferTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tTransferAmount,
            tFee,
            _getRate()
        );
        _rOwned[sender] = _rOwned[sender].sub(rAmount, "sub2 rAmount");
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        if (rFee > 0) {
            _reflectFee(rFee);
        }
        emit Transfer(sender, recipient, tTransferAmount);
    }

    // transfer
    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        uint256 tTransferAmount = tAmount;
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tTransferAmount,
            0,
            _getRate()
        );
        _tOwned[sender] = _tOwned[sender].sub(tAmount, "sub4 tAmount");
        _rOwned[sender] = _rOwned[sender].sub(rAmount, "sub4 rAmount");
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        if (rFee > 0) {
            _reflectFee(rFee);
        }
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    receive() external payable {}

    function _reflectFee(uint256 rFee) private {
        _rTotal = _rTotal.sub(rFee, "reflect fee");
    }

    //Get the actual transfer amount
    function _getBuyTValues(uint256 tAmount)
        private
        view
        returns (uint256 tTransferAmount, uint256 tFee)
    {
        if (!feeIt) {
            return (tAmount, 0);
        }
        tFee = tAmount.mul(3).div(100); // buy 3%
        tTransferAmount = tAmount.sub(tFee, "get buy tvalue");
    }

    function _getTransferTValues(uint256 tAmount)
        private
        view
        returns (uint256 tTransferAmount, uint256 tFee)
    {
        if (!feeIt) {
            return (tAmount, 0);
        }
        tFee = tAmount.mul(3).div(100); // buy 3%
        tTransferAmount = tAmount.sub(tFee, "get buy tvalue");
    }

    function _getSellTValues(uint256 tAmount)
        private
        view
        returns (
            uint256 tTransferAmount,
            uint256 tBurn
        )
    {
        if (!feeIt) {
            return (tAmount, 0);
        }
        tBurn = tAmount.mul(3).div(100); // sell 3%
        tTransferAmount = tAmount.sub(tBurn, "sub tBurn err");
    }

    //Get the transfer amount of the reflection address
    function _getRValues(
        uint256 tAmount,
        uint256 tTransferAmount,
        uint256 tFee,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rTransferAmount = tTransferAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        return (rAmount, rTransferAmount, rFee);
    }

    //Get current actual / reflected exchange rate
    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]], "sub rSupply");
            tSupply = tSupply.sub(_tOwned[_excluded[i]], "sub tSupply");
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function removeAllFee() private {
        if (!feeIt) return;
        feeIt = false;
    }

    function restoreAllFee() private {
        feeIt = true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        // uint tradeType = 1;// 1 buy 2 sell 0 transfer
        bool takeFee = true;
        _tokenTransfer(from, to, amount, takeFee);
    }

    function _takeBurn(address sender, uint256 tBurn) private {
        uint256 currentRate = _getRate();
        uint256 rBurn = tBurn.mul(currentRate);
        _rOwned[burnAddress] = _rOwned[burnAddress].add(rBurn);
        emit Transfer(sender, burnAddress, tBurn);
    }

    function _burn(address account, uint256 tBurn) internal {
        uint256 currentRate = _getRate();
        uint256 rBurn = tBurn.mul(currentRate);
        require(account != address(0), "BEP20: burn from the zero address");
        _rOwned[account] = _rOwned[account].sub(
            rBurn,
            "BEP20: burn amount exceeds balance"
        );
        _tTotal = _tTotal.sub(tBurn, "tburn err");
        emit Transfer(account, address(0), tBurn);
    }

    function burn(uint256 amount) public onlyOwner {
        _burn(burnAddress, amount);
    }

    //The administrator executes the address where dividends are not allowed
    function setExcludedFee(address account) public onlyOwner {
        require(!_isExcludedFee[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcludedFee[account] = true;
        _excluded.push(account);
    }

    function setExcludedFees(address[] memory accounts) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            require(!_isExcludedFee[account], "Account is already excluded");
            if (_rOwned[account] > 0) {
                _tOwned[account] = tokenFromReflection(_rOwned[account]);
            }
            _isExcludedFee[account] = true;
            _excluded.push(account);
        }
    }

    //The administrator can add the address of dividends, that is, delete the address where dividends are not allowed
    function removeExcludedFee(address account) public onlyOwner {
        require(_isExcludedFee[account], "Account is already included");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcludedFee[account] = false;
                _excluded.pop();
                break;
            }
        }
    }
    // foundation
    function setFoundation(address account) public onlyOwner {
        require(!_foundation[account], "Account is already in foundation");
        _foundation[account] = true;
        if(!_isExcludedFee[account]){
          setExcludedFee(account);
        }
    }

   
    //The administrator can add the address of dividends, that is, delete the address where dividends are not allowed
    function removeFoundation(address account) external onlyOwner {
        require(_foundation[account], "Account is already remove from foundation");
        _foundation[account] = false;
        if(_isExcludedFee[account]){
          removeExcludedFee(account);
        }
    }

    //The administrator executes the address where dividends are not allowed
    function setPancakePair(address pair) public onlyOwner {
        require(!includeUniswapV2Pair[pair], "Pair is added");
        includeUniswapV2Pair[pair] = true;
        uniswapV2Pair.push(pair);
    }

    //The administrator can add the address of dividends, that is, delete the address where dividends are not allowed
    function removePancakePair(address pair) external onlyOwner {
        require(includeUniswapV2Pair[pair], "Pair is removed");
        for (uint256 i = 0; i < uniswapV2Pair.length; i++) {
            if (uniswapV2Pair[i] == pair) {
                uniswapV2Pair[i] = uniswapV2Pair[uniswapV2Pair.length - 1];
                includeUniswapV2Pair[pair] = false;
                uniswapV2Pair.pop();
                break;
            }
        }
    }

    function totalPair() public view returns (uint256) {
        return uniswapV2Pair.length;
    }
}
