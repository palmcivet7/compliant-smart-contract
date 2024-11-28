// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract CompliantProxy is TransparentUpgradeableProxy {
    constructor(address initialImplementation, address proxyAdmin)
        TransparentUpgradeableProxy(initialImplementation, proxyAdmin, "")
    {}

    function getProxyAdmin() external view returns (address) {
        return _proxyAdmin();
    }
}
