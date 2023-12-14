// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IRouter.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IPositionRouter.sol";

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../peripherals/interfaces/ITimelock.sol";
import "./BasePositionManager.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "./interfaces/ICircuitBreaker.sol";

contract PositionRouter is BasePositionManager, IPositionRouter {
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct IncreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 amountIn;
        uint256 minOut;
        uint256 sizeDelta;
        bool isLong;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
        bool hasCollateralInETH;
        address callbackTarget;
    }

    // Reduced subset of `IncreasePositionRequest` to be passed by the user as arguments
    struct IncreasePositionParams {
        address[] path;
        address indexToken;
        uint256 sizeDelta;
        bool isLong;
        uint256 acceptablePrice;
        uint256 minOut;
        uint256 executionFee;
        bytes32 referralCode;
        address callbackTarget;
        bytes[] priceData;
    }


    struct DecreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        address receiver;
        uint256 acceptablePrice;
        uint256 minOut;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
        bool withdrawETH;
        address callbackTarget;
    }

    struct DecreasePositionParams {
        address[] path;
        address indexToken;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        address receiver;
        uint256 acceptablePrice;
        uint256 minOut;
        uint256 executionFee;
        bool withdrawETH;
        address callbackTarget;
        bytes[] priceData;
    }

    uint256 public minExecutionFee;

    uint256 public minBlockDelayKeeper;
    uint256 public minTimeDelayPublic;
    uint256 public maxTimeDelay;

    bool public isLeverageEnabled;

    bytes32[] public increasePositionRequestKeys;
    bytes32[] public decreasePositionRequestKeys;

    uint256 public override increasePositionRequestKeysStart;
    uint256 public override decreasePositionRequestKeysStart;

    uint256 public callbackGasLimit;

    mapping (address => bool) public isPositionKeeper;

    mapping (address => uint256) public increasePositionsIndex;
    mapping (bytes32 => IncreasePositionRequest) public increasePositionRequests;

    mapping (address => uint256) public decreasePositionsIndex;
    mapping (bytes32 => DecreasePositionRequest) public decreasePositionRequests;

    IPyth pythOracle;

    ICircuitBreaker public circuitBreaker;

    event CreateIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 index,
        uint256 queueIndex
    );

    event ExecuteIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 executionPrice,
        uint256 blockGap,
        uint256 timeGap
    );

    event CancelIncreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 amountIn,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event CreateDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 executionFee,
        uint256 index,
        uint256 queueIndex
    );

    event ExecuteDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 executionPrice,
        uint256 amountOut,
        uint256 blockGap,
        uint256 timeGap
    );

    event CancelDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event SetPositionKeeper(address indexed account, bool isActive);
    event SetMinExecutionFee(uint256 minExecutionFee);
    event SetIsLeverageEnabled(bool isLeverageEnabled);
    event SetDelayValues(uint256 minBlockDelayKeeper, uint256 minTimeDelayPublic, uint256 maxTimeDelay);
    event SetRequestKeysStartValues(uint256 increasePositionRequestKeysStart, uint256 decreasePositionRequestKeysStart);
    event SetCallbackGasLimit(uint256 callbackGasLimit);
    event Callback(address callbackTarget, bool success);

    modifier onlyPositionKeeper() {
        require(isPositionKeeper[msg.sender], "403");
        _;
    }

    function initialize(
        address _vault,
        address _router,
        address _weth,
        address _shortsTracker,
        uint256 _depositFee,
        uint256 _minExecutionFee,
        IPyth _pythOracle
    ) public initializer  {
        __BasePositionManager_init(_vault, _router, _shortsTracker, _weth, _depositFee);
        minExecutionFee = _minExecutionFee;
        isLeverageEnabled = true;
        pythOracle = _pythOracle;
    }

    function setCircuitBreaker(ICircuitBreaker _circuitBreaker) external onlyAdmin {
        circuitBreaker = _circuitBreaker;
    }

    function setPositionKeeper(address _account, bool _isActive) external onlyAdmin {
        isPositionKeeper[_account] = _isActive;
        emit SetPositionKeeper(_account, _isActive);
    }

    function setCallbackGasLimit(uint256 _callbackGasLimit) external onlyAdmin {
        callbackGasLimit = _callbackGasLimit;
        emit SetCallbackGasLimit(_callbackGasLimit);
    }

    function setMinExecutionFee(uint256 _minExecutionFee) external onlyAdmin {
        minExecutionFee = _minExecutionFee;
        emit SetMinExecutionFee(_minExecutionFee);
    }

    function setIsLeverageEnabled(bool _isLeverageEnabled) external onlyAdmin {
        isLeverageEnabled = _isLeverageEnabled;
        emit SetIsLeverageEnabled(_isLeverageEnabled);
    }

    function setDelayValues(uint256 _minBlockDelayKeeper, uint256 _minTimeDelayPublic, uint256 _maxTimeDelay) external onlyAdmin {
        minBlockDelayKeeper = _minBlockDelayKeeper;
        minTimeDelayPublic = _minTimeDelayPublic;
        maxTimeDelay = _maxTimeDelay;
        emit SetDelayValues(_minBlockDelayKeeper, _minTimeDelayPublic, _maxTimeDelay);
    }

    function setRequestKeysStartValues(uint256 _increasePositionRequestKeysStart, uint256 _decreasePositionRequestKeysStart) external onlyAdmin {
        increasePositionRequestKeysStart = _increasePositionRequestKeysStart;
        decreasePositionRequestKeysStart = _decreasePositionRequestKeysStart;

        emit SetRequestKeysStartValues(_increasePositionRequestKeysStart, _decreasePositionRequestKeysStart);
    }

    function executeIncreasePositions(uint256 _endIndex, address payable _executionFeeReceiver) external override onlyPositionKeeper {
        uint256 index = increasePositionRequestKeysStart;
        uint256 length = increasePositionRequestKeys.length;

        if (index >= length) { return; }

        if (_endIndex > length) {
            _endIndex = length;
        }

        while (index < _endIndex) {
            bytes32 key = increasePositionRequestKeys[index];

            // if the request was executed then delete the key from the array
            // if the request was not executed then break from the loop, this can happen if the
            // minimum number of blocks has not yet passed
            // an error could be thrown if the request is too old or if the slippage is
            // higher than what the user specified, or if there is insufficient liquidity for the position
            // in case an error was thrown, cancel the request
            try this.executeIncreasePosition(key, _executionFeeReceiver) returns (bool _wasExecuted) {
                if (!_wasExecuted) { break; }
            } catch {
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try this.cancelIncreasePosition(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) { break; }
                } catch {}
            }

            delete increasePositionRequestKeys[index];
            index++;
        }

        increasePositionRequestKeysStart = index;
    }

    function executeDecreasePositions(uint256 _endIndex, address payable _executionFeeReceiver) external override onlyPositionKeeper {
        uint256 index = decreasePositionRequestKeysStart;
        uint256 length = decreasePositionRequestKeys.length;

        if (index >= length) { return; }

        if (_endIndex > length) {
            _endIndex = length;
        }

        while (index < _endIndex) {
            bytes32 key = decreasePositionRequestKeys[index];

            // if the request was executed then delete the key from the array
            // if the request was not executed then break from the loop, this can happen if the
            // minimum number of blocks has not yet passed
            // an error could be thrown if the request is too old
            // in case an error was thrown, cancel the request
            try this.executeDecreasePosition(key, _executionFeeReceiver) returns (bool _wasExecuted) {
                if (!_wasExecuted) { break; }
            } catch {
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try this.cancelDecreasePosition(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) { break; }
                } catch {}
            }

            delete decreasePositionRequestKeys[index];
            index++;
        }

        decreasePositionRequestKeysStart = index;
    }

    function createIncreasePosition(
        IncreasePositionParams calldata _params,
        uint256 _amountIn
    ) external payable nonReentrant returns (bytes32) {
        require(_params.executionFee >= minExecutionFee, "execution fee too low");
        require(_params.path.length == 1 || _params.path.length == 2, "invalid path length");

        uint256 updateFee = _updatePythOracle(_params.priceData);
        require(msg.value >= _params.executionFee + updateFee, "msg.value too low");

        _transferInETH(msg.value - updateFee);
        _setTraderReferralCode(_params.referralCode);

        if (_amountIn > 0) {
            IRouter(router).pluginTransfer(_params.path[0], msg.sender, address(this), _amountIn);
        }

        return _createIncreasePosition(
            msg.sender,
            false,
            _amountIn,
            _params
        );
    }

    function createIncreasePositionETH(
        IncreasePositionParams calldata _params
    ) external payable nonReentrant returns (bytes32) {
        require(_params.executionFee >= minExecutionFee, "execution fee too low");

        uint256 updateFee = _updatePythOracle(_params.priceData);
        require(msg.value >= _params.executionFee + updateFee, "msg.value too low");

        require(_params.path.length == 1 || _params.path.length == 2, "invalid path length");
        require(_params.path[0] == weth, "first token in path must be weth");

        _transferInETH(msg.value - updateFee);
        _setTraderReferralCode(_params.referralCode);

        uint256 amountIn = msg.value - _params.executionFee;

        return _createIncreasePosition(
            msg.sender,
            true,
            amountIn,
            _params
        );
    }

    function createDecreasePosition(
        DecreasePositionParams calldata _params
    ) external payable nonReentrant returns (bytes32) {
        require(_params.executionFee >= minExecutionFee, "execution fee too low");

        uint256 updateFee = _updatePythOracle(_params.priceData);
        require(msg.value >= _params.executionFee + updateFee, "msg.value too low");

        require(_params.path.length == 1 || _params.path.length == 2, "invalid path length");

        if (_params.withdrawETH) {
            require(_params.path[_params.path.length - 1] == weth, "last token in path must be weth");
        }

        _transferInETH(msg.value - updateFee);

        return _createDecreasePosition(
            msg.sender,
            _params
        );
    }

    function getRequestQueueLengths() external view returns (uint256, uint256, uint256, uint256) {
        return (
            increasePositionRequestKeysStart,
            increasePositionRequestKeys.length,
            decreasePositionRequestKeysStart,
            decreasePositionRequestKeys.length
        );
    }

    function executeIncreasePosition(bytes32 _key, address payable _executionFeeReceiver) external nonReentrant returns (bool) {
        IncreasePositionRequest memory request = increasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeIncreasePositions loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        circuitBreaker.validateCircuitBreaker(request.indexToken, request.sizeDelta, request.isLong);

        bool shouldExecute = _validateExecution(request.blockNumber, request.blockTime, request.account);
        if (!shouldExecute) { return false; }

        delete increasePositionRequests[_key];

        if (request.amountIn > 0) {
            uint256 amountIn = request.amountIn;

            if (request.path.length > 1) {
                IERC20Upgradeable(request.path[0]).safeTransfer(vault, request.amountIn);
                amountIn = _swap(request.path, request.minOut, address(this));
            }

            uint256 afterFeeAmount = _collectFees(msg.sender, request.path, amountIn, request.indexToken, request.isLong, request.sizeDelta);
            IERC20Upgradeable(request.path[request.path.length - 1]).safeTransfer(vault, afterFeeAmount);
        }

        uint256 executionPrice = _increasePosition(request.account, request.path[request.path.length - 1], request.indexToken, request.sizeDelta, request.isLong, request.acceptablePrice);

        _transferOutETHWithGasLimitIgnoreFail(request.executionFee, _executionFeeReceiver);

        emit ExecuteIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountIn,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.executionFee,
            executionPrice,
            block.number - request.blockNumber,
            block.timestamp - request.blockTime
        );

        return true;
    }

    function cancelIncreasePosition(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        IncreasePositionRequest memory request = increasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeIncreasePositions loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        bool shouldCancel = _validateCancellation(request.blockNumber, request.blockTime, request.account);
        if (!shouldCancel) { return false; }

        delete increasePositionRequests[_key];

        if (request.hasCollateralInETH) {
            _transferOutETHWithGasLimitIgnoreFail(request.amountIn, payable(request.account));
        } else {
            IERC20Upgradeable(request.path[0]).safeTransfer(request.account, request.amountIn);
        }

       _transferOutETHWithGasLimitIgnoreFail(request.executionFee, _executionFeeReceiver);

        emit CancelIncreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.amountIn,
            request.sizeDelta,
            request.isLong,
            request.acceptablePrice,
            request.executionFee,
            block.number - request.blockNumber,
            block.timestamp - request.blockTime
        );

        return true;
    }

    function executeDecreasePosition(bytes32 _key, address payable _executionFeeReceiver) external nonReentrant returns (bool) {
        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeDecreasePositions loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        bool shouldExecute = _validateExecution(request.blockNumber, request.blockTime, request.account);
        if (!shouldExecute) { return false; }

        delete decreasePositionRequests[_key];

        (uint256 amountOut, uint256 executionPrice) = _decreasePosition(request.account, request.path[0], request.indexToken, request.collateralDelta, request.sizeDelta, request.isLong, address(this), request.acceptablePrice);

        if (amountOut > 0) {
            if (request.path.length > 1) {
                IERC20Upgradeable(request.path[0]).safeTransfer(vault, amountOut);
                amountOut = _swap(request.path, request.minOut, address(this));
            }

            if (request.withdrawETH) {
               _transferOutETHWithGasLimitIgnoreFail(amountOut, payable(request.receiver));
            } else {
               IERC20Upgradeable(request.path[request.path.length - 1]).safeTransfer(request.receiver, amountOut);
            }
        }

       _transferOutETHWithGasLimitIgnoreFail(request.executionFee, _executionFeeReceiver);

        uint blockGap = block.number - request.blockNumber;
        uint timeGap = block.timestamp - request.blockTime;

        emit ExecuteDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.executionFee,
            amountOut,
            executionPrice,
            blockGap,
            timeGap
        );

        return true;
    }

    function cancelDecreasePosition(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeDecreasePositions loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        bool shouldCancel = _validateCancellation(request.blockNumber, request.blockTime, request.account);
        if (!shouldCancel) { return false; }

        delete decreasePositionRequests[_key];

       _transferOutETHWithGasLimitIgnoreFail(request.executionFee, _executionFeeReceiver);

        emit CancelDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.executionFee,
            block.number - request.blockNumber,
            block.timestamp - request.blockTime
        );

        return true;
    }

    function getRequestKey(address _account, uint256 _index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _index));
    }

    function getIncreasePositionRequestPath(bytes32 _key) public view returns (address[] memory) {
        IncreasePositionRequest memory request = increasePositionRequests[_key];
        return request.path;
    }

    function getDecreasePositionRequestPath(bytes32 _key) public view returns (address[] memory) {
        DecreasePositionRequest memory request = decreasePositionRequests[_key];
        return request.path;
    }

    function _setTraderReferralCode(bytes32 _referralCode) internal {
        if (_referralCode != bytes32(0) && referralStorage != address(0)) {
            IReferralStorage(referralStorage).setTraderReferralCode(msg.sender, _referralCode);
        }
    }

    function _validateExecution(uint256 _positionBlockNumber, uint256 _positionBlockTime, address _account) internal view returns (bool) {
        if (_positionBlockTime + maxTimeDelay <= block.timestamp) {
            revert("expired");
        }

        bool isKeeperCall = msg.sender == address(this) || isPositionKeeper[msg.sender];

        if (!isLeverageEnabled && !isKeeperCall) {
            revert("403");
        }

        if (isKeeperCall) {
            return _positionBlockNumber + minBlockDelayKeeper <= block.number;
        }

        require(msg.sender == _account, "403");

        require(_positionBlockTime + minTimeDelayPublic <= block.timestamp, "delay");

        return true;
    }

    function _validateCancellation(uint256 _positionBlockNumber, uint256 _positionBlockTime, address _account) internal view returns (bool) {
        bool isKeeperCall = msg.sender == address(this) || isPositionKeeper[msg.sender];

        if (!isLeverageEnabled && !isKeeperCall) {
            revert("403");
        }

        if (isKeeperCall) {
            return _positionBlockNumber + minBlockDelayKeeper <= block.number;
        }

        require(msg.sender == _account, "403");

        require(_positionBlockTime + minTimeDelayPublic <= block.timestamp, "delay");

        return true;
    }

    function _createIncreasePosition(
        address _account,
        bool _hasCollateralInETH,
        uint256 _amountIn,
        IncreasePositionParams calldata _params
    ) internal returns (bytes32) {
        IncreasePositionRequest memory request = IncreasePositionRequest(
            _account,
            _params.path,
            _params.indexToken,
            _amountIn,
            _params.minOut,
            _params.sizeDelta,
            _params.isLong,
            _params.acceptablePrice,
            _params.executionFee,
            block.number,
            block.timestamp,
            _hasCollateralInETH,
            _params.callbackTarget
        );

        (uint256 index, bytes32 requestKey) = _storeIncreasePositionRequest(request);
        emit CreateIncreasePosition(
            _account,
            _params.path,
            _params.indexToken,
            _amountIn,
            _params.minOut,
            _params.sizeDelta,
            _params.isLong,
            _params.acceptablePrice,
            _params.executionFee,
            index,
            increasePositionRequestKeys.length - 1
        );

        return requestKey;
    }

    function _storeIncreasePositionRequest(IncreasePositionRequest memory _request) internal returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = increasePositionsIndex[account] + 1;
        increasePositionsIndex[account] = index;
        bytes32 key = getRequestKey(account, index);

        increasePositionRequests[key] = _request;
        increasePositionRequestKeys.push(key);

        return (index, key);
    }

    function _storeDecreasePositionRequest(DecreasePositionRequest memory _request) internal returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = decreasePositionsIndex[account] + 1;
        decreasePositionsIndex[account] = index;
        bytes32 key = getRequestKey(account, index);

        decreasePositionRequests[key] = _request;
        decreasePositionRequestKeys.push(key);

        return (index, key);
    }

    function _createDecreasePosition(
        address _account,
        DecreasePositionParams calldata _params
    ) internal returns (bytes32) {
        DecreasePositionRequest memory request = DecreasePositionRequest(
            _account,
            _params.path,
            _params.indexToken,
            _params.collateralDelta,
            _params.sizeDelta,
            _params.isLong,
            _params.receiver,
            _params.acceptablePrice,
            _params.minOut,
            _params.executionFee,
            block.number,
            block.timestamp,
            _params.withdrawETH,
            _params.callbackTarget
        );

        (uint256 index, bytes32 requestKey) = _storeDecreasePositionRequest(request);
        emit CreateDecreasePosition(
            request.account,
            request.path,
            request.indexToken,
            request.collateralDelta,
            request.sizeDelta,
            request.isLong,
            request.receiver,
            request.acceptablePrice,
            request.minOut,
            request.executionFee,
            index,
            decreasePositionRequestKeys.length - 1
        );
        return requestKey;
    }

    function _updatePythOracle(bytes[] calldata priceUpdateData) internal returns (uint256) {
        if(priceUpdateData.length == 0) {
            return 0;
        }
        uint256 fee = pythOracle.getUpdateFee(priceUpdateData);
        require(fee <= msg.value, "msg.value too low for pyth update");
        pythOracle.updatePriceFeeds{ value: fee }(priceUpdateData);
        return fee;
    }

}