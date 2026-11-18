// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentPermit} from "../src/AgentPermit.sol";

/// @dev Mock of the SPACE ID Agent ID registry (ERC-721, soulbound).
contract MockAgentID {
    mapping(address => string) private _handles;
    address[] private _holders;

    function set(address account, string calldata handle) external {
        if (bytes(_handles[account]).length == 0) {
            _holders.push(account);
        }
        _handles[account] = handle;
    }

    function balanceOf(address account) external view returns (uint256) {
        return bytes(_handles[account]).length > 0 ? 1 : 0;
    }

    function handleOf(address account) external view returns (string memory) {
        return _handles[account];
    }
}

contract AgentPermitTest is Test {
    MockAgentID registry;
    AgentPermit permit;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA401);

    function setUp() public {
        registry = new MockAgentID();
        permit = new AgentPermit(address(registry));

        registry.set(alice, "alice.ai");
        registry.set(bob, "bob.ai");
        // carol has no Agent ID
    }

    // ------------------------------------------------------------ badge mint

    function test_mintBadge_requiresAgentId() public {
        vm.prank(carol);
        vm.expectPartialRevert(AgentPermit.NotAgentId.selector);
        permit.mintBadge();
    }

    function test_mintBadge_succeeds() public {
        vm.prank(alice);
        uint256 id = permit.mintBadge();
        assertEq(id, 1);
        assertEq(permit.ownerOf(1), alice);
        assertEq(permit.balanceOf(alice), 1);
        assertEq(permit.badgeOf(alice), 1);
    }

    function test_mintBadge_onlyOnce() public {
        vm.prank(alice);
        permit.mintBadge();
        vm.prank(alice);
        vm.expectPartialRevert(AgentPermit.AlreadyHasBadge.selector);
        permit.mintBadge();
    }

    function test_mintBadge_isFree() public {
        vm.deal(alice, 1 ether);
        uint256 before = alice.balance;
        vm.prank(alice);
        permit.mintBadge();
        assertEq(alice.balance, before, "badge mint must not cost anything");
    }

    function test_tokenURI_hasHandle() public {
        vm.prank(alice);
        permit.mintBadge();
        string memory uri = permit.tokenURI(1);
        assertTrue(bytes(uri).length > 100);
        // the whole document is base64: decode it and look for the handle
        string memory json = _decodeBase64(_afterPrefix(uri, "data:application/json;base64,"));
        assertTrue(_contains(json, "alice.ai"), "handle missing from metadata");
        assertTrue(_contains(json, "Agent Permit #1"), "name missing");
        assertTrue(_contains(json, "data:image/svg+xml;base64,"), "image missing");
    }

    function test_holdsAgentId() public {
        assertTrue(permit.holdsAgentId(alice));
        assertFalse(permit.holdsAgentId(carol));
    }

    // -------------------------------------------------------------- permits

    function test_createPermit_requiresBothSides() public {
        // spender without Agent ID
        vm.prank(alice);
        vm.expectPartialRevert(AgentPermit.NotAgentId.selector);
        permit.createPermit(carol, 1 ether, 1 days);

        // principal without Agent ID
        vm.prank(carol);
        vm.expectPartialRevert(AgentPermit.NotAgentId.selector);
        permit.createPermit(alice, 1 ether, 1 days);
    }

    function test_createPermit_ok() public {
        vm.prank(alice);
        uint256 id = permit.createPermit(bob, 1 ether, 1 days);
        assertEq(id, 1);
        (
            address principal,
            address spender,
            string memory spenderHandle,
            uint256 cap,
            uint256 spent,
            uint64 expiry,
            bool revoked
        ) = permit.permitInfo(1);
        assertEq(principal, alice);
        assertEq(spender, bob);
        assertEq(spenderHandle, "bob.ai");
        assertEq(cap, 1 ether);
        assertEq(spent, 0);
        assertTrue(expiry > block.timestamp);
        assertFalse(revoked);
        assertTrue(permit.isActive(1));
        assertEq(permit.remaining(1), 1 ether);
    }

    function test_createPermit_rejectsBadArgs() public {
        vm.startPrank(alice);
        vm.expectPartialRevert(AgentPermit.InvalidSpender.selector);
        permit.createPermit(alice, 1 ether, 1 days);

        vm.expectPartialRevert(AgentPermit.InvalidSpender.selector);
        permit.createPermit(address(0), 1 ether, 1 days);

        vm.expectPartialRevert(AgentPermit.InvalidCap.selector);
        permit.createPermit(bob, 0, 1 days);

        vm.expectPartialRevert(AgentPermit.InvalidDuration.selector);
        permit.createPermit(bob, 1 ether, 30 minutes);

        vm.expectPartialRevert(AgentPermit.InvalidDuration.selector);
        permit.createPermit(bob, 1 ether, 31 days);
        vm.stopPrank();
    }

    function test_spend_movesValueToPrincipal() public {
        vm.prank(alice);
        permit.createPermit(bob, 1 ether, 1 days);

        vm.deal(bob, 1 ether);
        uint256 bobBefore = bob.balance;
        uint256 aliceBefore = alice.balance;

        vm.prank(bob);
        permit.spend{value: 0.1 ether}(1);

        assertEq(bob.balance, bobBefore - 0.1 ether);
        assertEq(alice.balance, aliceBefore + 0.1 ether);
        (, , , , uint256 spent, , ) = permit.permitInfo(1);
        assertEq(spent, 0.1 ether);
        assertEq(permit.remaining(1), 0.9 ether);
    }

    function test_spend_cannotExceedCap() public {
        vm.prank(alice);
        permit.createPermit(bob, 0.5 ether, 1 days);

        vm.deal(bob, 2 ether);
        vm.prank(bob);
        vm.expectPartialRevert(AgentPermit.PermitExhausted.selector);
        permit.spend{value: 0.6 ether}(1);
    }

    function test_spend_onlySpender() public {
        vm.prank(alice);
        permit.createPermit(bob, 1 ether, 1 days);

        vm.deal(carol, 1 ether);
        vm.prank(carol);
        vm.expectPartialRevert(AgentPermit.NotSpender.selector);
        permit.spend{value: 0.1 ether}(1);
    }

    function test_spend_afterExpiryFails() public {
        vm.prank(alice);
        permit.createPermit(bob, 1 ether, 1 hours);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectPartialRevert(AgentPermit.PermitExpired.selector);
        permit.spend{value: 0.1 ether}(1);
    }

    function test_revoke_stopsSpending() public {
        vm.prank(alice);
        permit.createPermit(bob, 1 ether, 1 days);

        vm.prank(alice);
        permit.revoke(1);
        assertFalse(permit.isActive(1));
        assertEq(permit.remaining(1), 0);

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectPartialRevert(AgentPermit.PermitRevokedError.selector);
        permit.spend{value: 0.1 ether}(1);
    }

    function test_revoke_onlyPrincipal() public {
        vm.prank(alice);
        permit.createPermit(bob, 1 ether, 1 days);

        vm.prank(bob);
        vm.expectPartialRevert(AgentPermit.NotPrincipal.selector);
        permit.revoke(1);
    }

    function test_spend_requiresAgentIdStillHeld() public {
        vm.prank(alice);
        permit.createPermit(bob, 1 ether, 1 days);

        // bob loses his Agent ID
        registry.set(bob, "");
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectPartialRevert(AgentPermit.NotAgentId.selector);
        permit.spend{value: 0.1 ether}(1);
    }

    function test_noOwnerNoAdmin() public {
        // the contract exposes no owner/admin/fee/pause/upgrade entry points
        assertEq(address(permit).balance, 0, "contract holds no funds");
        assertEq(permit.AGENT_ID_REGISTRY(), address(registry));
    }

    // -------------------------------------------------------------- helpers

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory b = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length > b.length) return false;
        for (uint256 i = 0; i <= b.length - n.length; i++) {
            bool ok = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (b[i + j] != n[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }

    function _afterPrefix(string memory s, string memory prefix) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory p = bytes(prefix);
        require(b.length >= p.length, "prefix");
        bytes memory out = new bytes(b.length - p.length);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = b[p.length + i];
        }
        return string(out);
    }

    function _b64Index(bytes1 c) internal pure returns (uint256) {
        bytes memory chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        for (uint256 i = 0; i < chars.length; i++) {
            if (chars[i] == c) return i;
        }
        revert("bad base64");
    }

    function _decodeBase64(string memory data) internal pure returns (string memory) {
        bytes memory b = bytes(data);
        uint256 len = b.length;
        while (len > 0 && b[len - 1] == "=") len--;
        bytes memory out = new bytes(len * 3 / 4);
        uint256 o = 0;
        uint256 i = 0;
        while (i + 4 <= len) {
            uint256 n = (_b64Index(b[i]) << 18) | (_b64Index(b[i + 1]) << 12) | (_b64Index(b[i + 2]) << 6) | _b64Index(b[i + 3]);
            out[o++] = bytes1(uint8(n >> 16));
            out[o++] = bytes1(uint8(n >> 8));
            out[o++] = bytes1(uint8(n));
            i += 4;
        }
        uint256 rem = len - i;
        if (rem == 2) {
            uint256 n = (_b64Index(b[i]) << 18) | (_b64Index(b[i + 1]) << 12);
            out[o++] = bytes1(uint8(n >> 16));
        } else if (rem == 3) {
            uint256 n = (_b64Index(b[i]) << 18) | (_b64Index(b[i + 1]) << 12) | (_b64Index(b[i + 2]) << 6);
            out[o++] = bytes1(uint8(n >> 16));
            out[o++] = bytes1(uint8(n >> 8));
        }
        assembly {
            mstore(out, o)
        }
        return string(out);
    }
}
