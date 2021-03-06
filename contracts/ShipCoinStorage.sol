pragma solidity ^0.4.24;

import "./base/MultiOwnable.sol";
import "./base/String.sol";
import "./lib/SafeMath.sol";
import "./IStorage.sol";


/**
 * @title Whitelist
 * @dev The Whitelist contract has a whitelist of addresses, and provides basic authorization control functions.
 * @dev This simplifies the implementation of "user permissions".
 */
contract ShipCoinStorage is IStorage, MultiOwnable, String {
  using SafeMath for uint256;

  /* Events */
  event WhitelistAddressAdded(address addr);
  event WhitelistAddressRemoved(address addr);
  event AddPayment(address addr);
  event GotPreSaleBonus(address addr);
  event EditUserPayments(address addr, uint payId);
  event RefundPayment(address addr, uint payId);
  event ReceivedCoin(address addr);
  event Refund(address addr);
  event ChangeMainWallet(address addr);

  struct PaymentData {
    uint time;
    bytes32 pType;
    uint currencyUSD;
    uint payValue;
    uint totalToken;
    uint tokenWithoutBonus;
    uint tokenBonus;
    uint bonusPercent;
    uint usdAbsRaisedInCents;
  }

  struct StorageData {
    bool active;
    mapping(bytes32 => uint) payInCurrency;
    uint totalToken;
    uint tokenWithoutBonus;
    uint tokenBonus;
    uint usdAbsRaisedInCents;
    mapping(uint => PaymentData) paymentInfo;
    address mainWallet;
    address[] wallet;
  }
  // uId = { }
  mapping(uint => StorageData) private contributorList;
  // wallet = uId
  mapping(address => uint) private contributorIds;
  // i++ = uId
  mapping(uint => uint) private contributorIndexes;
  //uId = payIds
  mapping(uint => uint[]) private contributorPayIds;
  uint public nextContributorIndex;

  bytes32[] private currencyTicker;
  // uId
  mapping(uint => uint) private receivedPreSaleBonus;
  // uId
  mapping(uint => bool) private receivedCoin;
  //payIds
  mapping(uint => bool) private payIds;
  //payIds
  mapping(uint => bool) private refundPayIds;
  //uId
  mapping(uint => bool) private refundUserIds;

  uint private startGenId = 100000;

  bool public supportChangeMainWallet = true;

  /**
   * @dev Calculate contributors appoint presale bonus
   */
  function processPreSaleBonus(uint minTotalUsdAmountInCents, uint bonusPercent, uint _start, uint _limit) external onlyMultiOwnersType(12) returns(uint) {
    require(minTotalUsdAmountInCents > 10000);
    require(bonusPercent > 20 && bonusPercent < 50);
    require(_limit >= 10);

    uint start = _start;
    uint limit = _limit;
    uint bonusTokenAll = 0;
    for (uint i = start; i < limit; i++) {
      uint uId = contributorIndexes[i];
      if (contributorList[uId].active && !checkPreSaleReceivedBonus(uId) && contributorList[uId].usdAbsRaisedInCents >= minTotalUsdAmountInCents) {
        uint bonusToken = contributorList[uId].tokenWithoutBonus.mul(bonusPercent).div(100);

        contributorList[uId].totalToken += bonusToken;
        contributorList[uId].tokenBonus = bonusToken;
        receivedPreSaleBonus[uId] = bonusToken;
        bonusTokenAll += bonusToken;
        emit GotPreSaleBonus(contributorList[uId].mainWallet);
      }
    }

    return bonusTokenAll;
  }

  /**
   * @dev Checks contributors who have not received their presale bonuses
   */
  function checkNeedProcessPreSaleBonus(uint minTotalUsdAmountInCents) external view returns(bool) {
    require(minTotalUsdAmountInCents > 10000);
    bool processed = false;
    for (uint i = 0; i < nextContributorIndex; i++) {
      if (processed) {
        break;
      }
      uint uId = contributorIndexes[i];
      if (contributorList[uId].active && !refundUserIds[uId] && !checkPreSaleReceivedBonus(uId) && contributorList[uId].usdAbsRaisedInCents >= minTotalUsdAmountInCents) {
        processed = true;
      }
    }
    return processed;
  }

  /**
   * @dev Returns the number of contributors who have not received their presale bonuses
   */
  function getCountNeedProcessPreSaleBonus(uint minTotalUsdAmountInCents, uint start, uint limit) external view returns(uint) {
    require(minTotalUsdAmountInCents > 10000);
    require(start >= 0 && limit >= 10);
    uint processed = 0;
    for (uint i = start; i < (limit > nextContributorIndex ? nextContributorIndex : limit); i++) {
      uint uId = contributorIndexes[i];
      if (contributorList[uId].active && !refundUserIds[uId] && !checkPreSaleReceivedBonus(uId) && contributorList[uId].usdAbsRaisedInCents >= minTotalUsdAmountInCents) {
        processed++;
      }
    }
    return processed;
  }

  /**
   * @dev Checks contributors who have not received their SHPC
   */
  function checkNeedSendSHPC(bool proc) external view returns(bool) {
    bool processed = false;
    if (proc) {
      for (uint i = 0; i < nextContributorIndex; i++) {
        if (processed) {
          break;
        }
        uint uId = contributorIndexes[i];
        if (contributorList[uId].active && !refundUserIds[uId] && !checkReceivedCoins(uId) && contributorList[uId].totalToken > 0) {
          processed = true;
        }
      }
    }
    return processed;
  }

  /**
   * @dev Returns the number of contributors who have not received their SHPC
   */
  function getCountNeedSendSHPC(uint start, uint limit) external view returns(uint) {
    require(start >= 0 && limit >= 10);
    uint processed = 0;
    for (uint i = start; i < (limit > nextContributorIndex ? nextContributorIndex : limit); i++) {
      uint uId = contributorIndexes[i];
      if (contributorList[uId].active && !refundUserIds[uId] && !checkReceivedCoins(uId) && contributorList[uId].totalToken > 0) {
        processed++;
      }
    }
    return processed;
  }

  /**
   * @dev Checks contributors who have not received their ETH when refund
   */
  function checkETHRefund(bool proc) external view returns(bool) {
    bool processed = false;
    if (proc) {
      for (uint i = 0; i < nextContributorIndex; i++) {
        if (processed) {
          break;
        }
        uint uId = contributorIndexes[i];
        if (contributorList[uId].active && !refundUserIds[uId] && getEthPaymentContributor(uId) > 0) {
          processed = true;
        }
      }
    }
    return processed;
  }

  /**
   * @dev Returns the number of contributors who have not received their ETH when refund
   */
  function getCountETHRefund(uint start, uint limit) external view returns(uint) {
    require(start >= 0 && limit >= 10);
    uint processed = 0;
    for (uint i = start; i < (limit > nextContributorIndex ? nextContributorIndex : limit); i++) {
      uint uId = contributorIndexes[i];
      if (contributorList[uId].active && !refundUserIds[uId] && getEthPaymentContributor(uId) > 0) {
        processed++;
      }
    }
    return processed;
  }

  /**
   * @dev Returns uId by index;
   */
  function getContributorIndexes(uint index) external onlyMultiOwnersType(7) view returns(uint) {
    return contributorIndexes[index];
  }

  /**
   * @dev Recalculation contributors presale bonus
   */
  function reCountUserPreSaleBonus(uint _uId, uint minTotalUsdAmountInCents, uint bonusPercent, uint maxPayTime) external onlyMultiOwnersType(13) returns(uint, uint) {
    require(_uId > 0);
    require(contributorList[_uId].active);
    require(!refundUserIds[_uId]);
    require(minTotalUsdAmountInCents > 10000);
    require(bonusPercent > 20 && bonusPercent < 50);
    uint bonusToken = 0;
    uint uId = _uId;
    uint beforeBonusToken = receivedPreSaleBonus[uId];

    if (beforeBonusToken > 0) {
      contributorList[uId].totalToken -= beforeBonusToken;
      contributorList[uId].tokenBonus -= beforeBonusToken;
      receivedPreSaleBonus[uId] = 0;
    }

    if (contributorList[uId].usdAbsRaisedInCents >= minTotalUsdAmountInCents) {
      if (maxPayTime > 0) {
        for (uint i = 0; i < contributorPayIds[uId].length; i++) {
          PaymentData memory _payment = contributorList[uId].paymentInfo[contributorPayIds[uId][i]];
          if (!refundPayIds[contributorPayIds[uId][i]] && _payment.bonusPercent == 0 && _payment.time < maxPayTime) {
            bonusToken += _payment.tokenWithoutBonus.mul(bonusPercent).div(100);
          }
        }
      } else {
        bonusToken = contributorList[uId].tokenWithoutBonus.mul(bonusPercent).div(100);
      }

      if (bonusToken > 0) {
        contributorList[uId].totalToken += bonusToken;
        contributorList[uId].tokenBonus += bonusToken;
        receivedPreSaleBonus[uId] = bonusToken;
        emit GotPreSaleBonus(contributorList[uId].mainWallet);
      }
    }
    return (beforeBonusToken, bonusToken);
  }

  /**
   * @dev add user and wallet to whitelist
   */
  function addWhiteList(uint uId, address addr) public onlyMultiOwnersType(1) returns(bool success) {
    require(addr != address(0), "1");
    require(uId > 0, "2");
    require(!refundUserIds[uId]);

    if (contributorIds[addr] > 0 && contributorIds[addr] != uId) {
      success = false;
      revert("3");
    }

    if (contributorList[uId].active != true) {
      contributorList[uId].active = true;
      contributorIndexes[nextContributorIndex] = uId;
      nextContributorIndex++;
      contributorList[uId].mainWallet = addr;
    }

    if (inArray(contributorList[uId].wallet, addr) != true && contributorList[uId].wallet.length < 3) {
      contributorList[uId].wallet.push(addr);
      contributorIds[addr] = uId;
      emit WhitelistAddressAdded(addr);
      success = true;
    } else {
      success = false;
    }
  }

  /**
   * @dev remove user wallet from whitelist
   */
  function removeWhiteList(uint uId, address addr) public onlyMultiOwnersType(2) returns(bool success) {
    require(contributorList[uId].active, "1");
    require(addr != address(0), "2");
    require(uId > 0, "3");
    require(inArray(contributorList[uId].wallet, addr));

    if (contributorPayIds[uId].length > 0 || contributorList[uId].mainWallet == addr) {
      success = false;
      revert("5");
    }


    contributorList[uId].wallet = removeValueFromArray(contributorList[uId].wallet, addr);
    delete contributorIds[addr];

    emit WhitelistAddressRemoved(addr);
    success = true;
  }

  /**
   * @dev Change contributor mainWallet
   */
  function changeMainWallet(uint uId, address addr) public onlyMultiOwnersType(3) returns(bool) {
    require(supportChangeMainWallet);
    require(addr != address(0));
    require(uId > 0);
    require(contributorList[uId].active);
    require(!refundUserIds[uId]);
    require(inArray(contributorList[uId].wallet, addr));

    contributorList[uId].mainWallet = addr;
    emit ChangeMainWallet(addr);
    return true;
  }

  /**
   * @dev Change the right to change mainWallet
   */
  function changeSupportChangeMainWallet(bool support) public onlyMultiOwnersType(21) returns(bool) {
    supportChangeMainWallet = support;
    return supportChangeMainWallet;
  }

  /**
   * @dev Returns all contributor info by uId
   */
  function getContributionInfoById(uint _uId) public onlyMultiOwnersType(4) view returns(
      bool active,
      string payInCurrency,
      uint totalToken,
      uint tokenWithoutBonus,
      uint tokenBonus,
      uint usdAbsRaisedInCents,
      uint[] paymentInfoIds,
      address mainWallet,
      address[] wallet,
      uint preSaleReceivedBonus,
      bool receivedCoins,
      bool refund
    )
  {
    uint uId = _uId;
    return getContributionInfo(contributorList[uId].mainWallet);
  }

  /**
   * @dev Returns all contributor info by address
   */
  function getContributionInfo(address _addr)
    public
    view
    returns(
      bool active,
      string payInCurrency,
      uint totalToken,
      uint tokenWithoutBonus,
      uint tokenBonus,
      uint usdAbsRaisedInCents,
      uint[] paymentInfoIds,
      address mainWallet,
      address[] wallet,
      uint preSaleReceivedBonus,
      bool receivedCoins,
      bool refund
    )
  {

    address addr = _addr;
    StorageData memory storData = contributorList[contributorIds[addr]];

    (preSaleReceivedBonus, receivedCoins, refund) = getInfoAdditionl(addr);

    return(
    storData.active,
    (contributorPayIds[contributorIds[addr]].length > 0 ? getContributorPayInCurrency(contributorIds[addr]) : "[]"),
    storData.totalToken,
    storData.tokenWithoutBonus,
    storData.tokenBonus,
    storData.usdAbsRaisedInCents,
    contributorPayIds[contributorIds[addr]],
    storData.mainWallet,
    storData.wallet,
    preSaleReceivedBonus,
    receivedCoins,
    refund
    );
  }

  /**
   * @dev Returns contributor id by address
   */
  function getContributorId(address addr) public onlyMultiOwnersType(5) view returns(uint) {
    return contributorIds[addr];
  }

  /**
   * @dev Returns contributors address by uId
   */
  function getContributorAddressById(uint uId) public onlyMultiOwnersType(6) view returns(address) {
    require(uId > 0);
    require(contributorList[uId].active);
    return contributorList[uId].mainWallet;
  }

  /**
   * @dev Check wallet exists by address
   */
  function checkWalletExists(address addr) public view returns(bool result) {
    result = false;
    if (contributorList[contributorIds[addr]].wallet.length > 0) {
      result = inArray(contributorList[contributorIds[addr]].wallet, addr);
    }
  }

  /**
   * @dev Check userId is exists
   */
  function checkUserIdExists(uint uId) public onlyMultiOwnersType(8) view returns(bool) {
    return contributorList[uId].active;
  }

  /**
   * @dev Add payment by address
   */
  function addPayment(
    address _addr,
    string pType,
    uint _value,
    uint usdAmount,
    uint currencyUSD,
    uint tokenWithoutBonus,
    uint tokenBonus,
    uint bonusPercent,
    uint payId
  )
  public
  onlyMultiOwnersType(9)
  returns(bool)
  {
    require(_value > 0);
    require(usdAmount > 0);
    require(tokenWithoutBonus > 0);
    require(bytes(pType).length > 0);
    assert((payId == 0 && stringsEqual(pType, "ETH")) || (payId > 0 && !payIds[payId]));

    address addr = _addr;
    uint uId = contributorIds[addr];

    assert(addr != address(0));
    assert(checkWalletExists(addr));
    assert(uId > 0);
    assert(contributorList[uId].active);
    assert(!refundUserIds[uId]);
    assert(!receivedCoin[uId]);

    if (payId == 0) {
      payId = genId(addr, _value, 0);
    }

    bytes32 _pType = stringToBytes32(pType);
    PaymentData memory userPayment;
    uint totalToken = tokenWithoutBonus.add(tokenBonus);

    //userPayment.payId = payId;
    userPayment.time = block.timestamp;
    userPayment.pType = _pType;
    userPayment.currencyUSD = currencyUSD;
    userPayment.payValue = _value;
    userPayment.totalToken = totalToken;
    userPayment.tokenWithoutBonus = tokenWithoutBonus;
    userPayment.tokenBonus = tokenBonus;
    userPayment.bonusPercent = bonusPercent;
    userPayment.usdAbsRaisedInCents = usdAmount;

    if (!inArray(currencyTicker, _pType)) {
      currencyTicker.push(_pType);
    }
    if (payId > 0) {
      payIds[payId] = true;
    }

    contributorList[uId].usdAbsRaisedInCents += usdAmount;
    contributorList[uId].totalToken += totalToken;
    contributorList[uId].tokenWithoutBonus += tokenWithoutBonus;
    contributorList[uId].tokenBonus += tokenBonus;

    contributorList[uId].payInCurrency[_pType] += _value;
    contributorList[uId].paymentInfo[payId] = userPayment;
    contributorPayIds[uId].push(payId);

    emit AddPayment(addr);
    return true;
  }

  /**
   * @dev Add payment by uId
   */
  function addPayment(
    uint uId,
    string pType,
    uint _value,
    uint usdAmount,
    uint currencyUSD,
    uint tokenWithoutBonus,
    uint tokenBonus,
    uint bonusPercent,
    uint payId
  )
  public
  returns(bool)
  {
    require(contributorList[uId].active);
    require(contributorList[uId].mainWallet != address(0));
    return addPayment(contributorList[uId].mainWallet, pType, _value, usdAmount, currencyUSD, tokenWithoutBonus, tokenBonus, bonusPercent, payId);
  }

  /**
   * @dev Edit user payment info
   */
  function editPaymentByUserId(
    uint uId,
    uint payId,
    uint _payValue,
    uint _usdAmount,
    uint _currencyUSD,
    uint _totalToken,
    uint _tokenWithoutBonus,
    uint _tokenBonus,
    uint _bonusPercent
  )
  public
  onlyMultiOwnersType(10)
  returns(bool)
  {
    require(contributorList[uId].active);
    require(inArray(contributorPayIds[uId], payId));
    require(!refundPayIds[payId]);
    require(!refundUserIds[uId]);
    require(!receivedCoin[uId]);

    PaymentData memory oldPayment = contributorList[uId].paymentInfo[payId];

    contributorList[uId].usdAbsRaisedInCents -= oldPayment.usdAbsRaisedInCents;
    contributorList[uId].totalToken -= oldPayment.totalToken;
    contributorList[uId].tokenWithoutBonus -= oldPayment.tokenWithoutBonus;
    contributorList[uId].tokenBonus -= oldPayment.tokenBonus;
    contributorList[uId].payInCurrency[oldPayment.pType] -= oldPayment.payValue;

    contributorList[uId].paymentInfo[payId] = PaymentData(
      oldPayment.time,
      oldPayment.pType,
      _currencyUSD,
      _payValue,
      _totalToken,
      _tokenWithoutBonus,
      _tokenBonus,
      _bonusPercent,
      _usdAmount
    );

    contributorList[uId].usdAbsRaisedInCents += _usdAmount;
    contributorList[uId].totalToken += _totalToken;
    contributorList[uId].tokenWithoutBonus += _tokenWithoutBonus;
    contributorList[uId].tokenBonus += _tokenBonus;
    contributorList[uId].payInCurrency[oldPayment.pType] += _payValue;

    emit EditUserPayments(contributorList[uId].mainWallet, payId);

    return true;
  }

  /**
   * @dev Refund user payment
   */
  function refundPaymentByUserId(uint uId, uint payId) public onlyMultiOwnersType(20) returns(bool) {
    require(contributorList[uId].active);
    require(inArray(contributorPayIds[uId], payId));
    require(!refundPayIds[payId]);
    require(!refundUserIds[uId]);
    require(!receivedCoin[uId]);

    PaymentData memory oldPayment = contributorList[uId].paymentInfo[payId];

    assert(oldPayment.pType != stringToBytes32("ETH"));

    contributorList[uId].usdAbsRaisedInCents -= oldPayment.usdAbsRaisedInCents;
    contributorList[uId].totalToken -= oldPayment.totalToken;
    contributorList[uId].tokenWithoutBonus -= oldPayment.tokenWithoutBonus;
    contributorList[uId].tokenBonus -= oldPayment.tokenBonus;
    contributorList[uId].payInCurrency[oldPayment.pType] -= oldPayment.payValue;

    refundPayIds[payId] = true;

    emit RefundPayment(contributorList[uId].mainWallet, payId);

    return true;
  }

  /**
   * @dev Reutrns user payment info by uId and paymentId
   */
  function getUserPaymentById(uint _uId, uint _payId) public onlyMultiOwnersType(11) view returns(
    uint time,
    bytes32 pType,
    uint currencyUSD,
    uint bonusPercent,
    uint payValue,
    uint totalToken,
    uint tokenBonus,
    uint tokenWithoutBonus,
    uint usdAbsRaisedInCents,
    bool refund
  )
  {
    uint uId = _uId;
    uint payId = _payId;
    require(contributorList[uId].active);
    require(inArray(contributorPayIds[uId], payId));

    PaymentData memory payment = contributorList[uId].paymentInfo[payId];

    return (
      payment.time,
      payment.pType,
      payment.currencyUSD,
      payment.bonusPercent,
      payment.payValue,
      payment.totalToken,
      payment.tokenBonus,
      payment.tokenWithoutBonus,
      payment.usdAbsRaisedInCents,
      refundPayIds[payId] ? true : false
    );
  }

  /**
   * @dev Reutrns user payment info by address and payment id
   */
  function getUserPayment(address addr, uint _payId) public view returns(
    uint time,
    string pType,
    uint currencyUSD,
    uint bonusPercent,
    uint payValue,
    uint totalToken,
    uint tokenBonus,
    uint tokenWithoutBonus,
    uint usdAbsRaisedInCents,
    bool refund
  )
  {
    address _addr = addr;
    require(contributorList[contributorIds[_addr]].active);
    require(inArray(contributorPayIds[contributorIds[_addr]], _payId));

    uint payId = _payId;

    PaymentData memory payment = contributorList[contributorIds[_addr]].paymentInfo[payId];

    return (
      payment.time,
      bytes32ToString(payment.pType),
      payment.currencyUSD,
      payment.bonusPercent,
      payment.payValue,
      payment.totalToken,
      payment.tokenBonus,
      payment.tokenWithoutBonus,
      payment.usdAbsRaisedInCents,
      refundPayIds[payId] ? true : false
    );
  }

  /**
   * @dev Returns payment in ETH from address
   */
  function getEthPaymentContributor(address addr) public view returns(uint) {
    return contributorList[contributorIds[addr]].payInCurrency[stringToBytes32("ETH")];
  }

  /**
   * @dev Returns SHPC from address
   */
  function getTotalCoin(address addr) public view returns(uint) {
    return contributorList[contributorIds[addr]].totalToken;
  }

  /**
   * @dev Check user get pre sale bonus by address
   */
  function checkPreSaleReceivedBonus(address addr) public view returns(bool) {
    return receivedPreSaleBonus[contributorIds[addr]] > 0 ? true : false;
  }

  /**
   * @dev Check payment refund by payment id
   */
  function checkPaymentRefund(uint payId) public view returns(bool) {
    return refundPayIds[payId];
  }

  /**
   * @dev Check user refund by address
   */
  function checkRefund(address addr) public view returns(bool) {
    return refundUserIds[contributorIds[addr]];
  }

  /**
   * @dev Set start number generate payment id when user pay in eth
   */
  function setStartGenId(uint startId) public onlyMultiOwnersType(14) {
    require(startId > 0);
    startGenId = startId;
  }

  /**
   * @dev Set contributer got SHPC
   */
  function setReceivedCoin(uint uId) public onlyMultiOwnersType(15) returns(bool) {
    require(contributorList[uId].active);
    require(!refundUserIds[uId]);
    require(!receivedCoin[uId]);
    receivedCoin[uId] = true;
    emit ReceivedCoin(contributorList[uId].mainWallet);
    return true;
  }

  /**
   * @dev Set contributer got refund ETH
   */
  function setRefund(uint uId) public onlyMultiOwnersType(16) returns(bool) {
    require(contributorList[uId].active);
    require(!refundUserIds[uId]);
    require(!receivedCoin[uId]);
    refundUserIds[uId] = true;
    emit Refund(contributorList[uId].mainWallet);
    return true;
  }

  /**
   * @dev Check contributor got SHPC
   */
  function checkReceivedCoins(address addr) public view returns(bool) {
    return receivedCoin[contributorIds[addr]];
  }

  /**
   * @dev Check contributor got ETH
   */
  function checkReceivedEth(address addr) public view returns(bool) {
    return refundUserIds[contributorIds[addr]];
  }

  /**
   * @dev Returns all contributor currency amount in json
   */
  function getContributorPayInCurrency(uint uId) private view returns(string) {
    require(uId > 0);
    require(contributorList[uId].active);
    string memory payInCurrency = "{";
    for (uint i = 0; i < currencyTicker.length; i++) {
      payInCurrency = strConcat(payInCurrency, strConcat("\"", bytes32ToString(currencyTicker[i]), "\":\""), uint2str(contributorList[uId].payInCurrency[currencyTicker[i]]), (i+1 < currencyTicker.length) ? "\"," : "\"}");
    }
    return payInCurrency;
  }

  /**
   * @dev Check receives presale bonud by uId
   */
  function checkPreSaleReceivedBonus(uint uId) private view returns(bool) {
    return receivedPreSaleBonus[uId] > 0 ? true : false;
  }

  /**
   * @dev Check refund by uId
   */
  function checkRefund(uint uId) private view returns(bool) {
    return refundUserIds[uId];
  }

  /**
   * @dev  Check received SHPC by uI
   */
  function checkReceivedCoins(uint id) private view returns(bool) {
    return receivedCoin[id];
  }

  /**
   * @dev Check received eth by uId
   */
  function checkReceivedEth(uint id) private view returns(bool) {
    return refundUserIds[id];
  }

  /**
   * @dev Returns new uniq payment id
   */
  function genId(address addr, uint ammount, uint rand) private view returns(uint) {
    uint id = startGenId + uint8(keccak256(abi.encodePacked(addr, blockhash(block.number), ammount, rand))) + contributorPayIds[contributorIds[addr]].length;
    if (!payIds[id]) {
      return id;
    } else {
      return genId(addr, ammount, id);
    }
  }

  /**
   * @dev Returns payment in ETH from uid
   */
  function getEthPaymentContributor(uint uId) private view returns(uint) {
    return contributorList[uId].payInCurrency[stringToBytes32("ETH")];
  }

  /**
   * @dev Returns adittional info by contributor address
   */
  function getInfoAdditionl(address addr) private view returns(uint, bool, bool) {
    return(receivedPreSaleBonus[contributorIds[addr]], receivedCoin[contributorIds[addr]], refundUserIds[contributorIds[addr]]);
  }

  /**
   * @dev Returns payments info by userId in json
   */
  function getArrayjsonPaymentInfo(uint uId) private view returns (string) {
    string memory _array = "{";
    for (uint i = 0; i < contributorPayIds[uId].length; i++) {
      _array = strConcat(_array, getJsonPaymentInfo(contributorList[uId].paymentInfo[contributorPayIds[uId][i]], contributorPayIds[uId][i]), (i+1 == contributorPayIds[uId].length) ? "}" : ",");
    }
    return _array;
  }

  /**
   * @dev Returns payment info by payment data in json
   */
  function getJsonPaymentInfo(PaymentData memory _obj, uint payId) private view returns (string) {
    return strConcat(
      strConcat("\"", uint2str(payId), "\":{", strConcat("\"", "time", "\":"), uint2str(_obj.time)),
      strConcat(",\"pType\":\"", bytes32ToString(_obj.pType), "\",\"currencyUSD\":", uint2str(_obj.currencyUSD), ",\"payValue\":\""),
      strConcat(uint2str(_obj.payValue), "\",\"totalToken\":\"", uint2str(_obj.totalToken), "\",\"tokenWithoutBonus\":\"", uint2str(_obj.tokenWithoutBonus)),
      strConcat("\",\"tokenBonus\":\"", uint2str(_obj.tokenBonus), "\",\"bonusPercent\":", uint2str(_obj.bonusPercent)),
      strConcat(",\"usdAbsRaisedInCents\":\"", uint2str(_obj.usdAbsRaisedInCents), "\",\"refund\":\"", (refundPayIds[payId] ? "1" : "0"), "\"}")
    );
  }

  /**
   * @dev Check if value contains array
   */
  function inArray(address[] _array, address _value) private pure returns(bool result) {
    if (_array.length == 0 || _value == address(0)) {
      return false;
    }
    result = false;
    for (uint i = 0; i < _array.length; i++) {
      if (_array[i] == _value) {
        result = true;
        return true;
      }
    }
  }

  /**
   * @dev Check if value contains array
   */
  function inArray(uint[] _array, uint _value) private pure returns(bool result) {
    if (_array.length == 0 || _value == 0) {
      return false;
    }
    result = false;
    for (uint i = 0; i < _array.length; i++) {
      if (_array[i] == _value) {
        result = true;
        return true;
      }
    }
  }

  /**
   * @dev Check if value contains array
   */
  function inArray(bytes32[] _array, bytes32 _value) private pure returns(bool result) {
    if (_array.length == 0 || _value.length == 0) {
      return false;
    }
    result = false;
    for (uint i = 0; i < _array.length; i++) {
      if (_array[i] == _value) {
        result = true;
        return true;
      }
    }
  }

  /**
   * @dev Remove value from arary
   */
  function removeValueFromArray(address[] _array, address _value) private pure returns(address[]) {
    address[] memory arrayNew = new address[](_array.length-1);
    if (arrayNew.length == 0) {
      return arrayNew;
    }
    uint i1 = 0;
    for (uint i = 0; i < _array.length; i++) {
      if (_array[i] != _value) {
        arrayNew[i1++] = _array[i];
      }
    }
    return arrayNew;
  }

}
