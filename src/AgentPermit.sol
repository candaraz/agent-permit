// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title SPACE ID Agent ID registry (BNB Chain, ERC-721, soulbound)
/// @dev Only two members are used: `balanceOf` to test whether an address holds an
///      Agent ID, and `handleOf` to read its `.ai` handle for display only.
///      This contract never resolves a handle back to an address.
interface ISpaceIdAgentID {
    function balanceOf(address account) external view returns (uint256);
    function handleOf(address account) external view returns (string memory);
}

/// @title AgentPermit
/// @notice Standing spend permits between Binance Agent ID (.ai) holders on BNB Chain.
/// @dev A permit lets an Agent ID holder (the principal) cap how much another Agent ID
///      holder (the spender) may send it, for a bounded window. The permit is not a
///      custody contract: no funds are ever held by this contract, and the only value
///      movement possible is BNB sent by the spender to the principal, bounded by the
///      permit cap and expiry.
///
///      PERMISSIONS DISCLOSURE: this contract has NO owner, NO admin, NO fee, NO pause,
///      NO upgrade path, NO blacklist, NO tax, NO arbitrary transfer function and NO
///      ability to move a third party's funds. The Agent ID registry address and the
///      supply cap are immutable. A permit can only ever move BNB from its own spender
///      to its own principal, and only while it is active and under cap.
///
///      Agent ID is load-bearing, not decorative:
///        - minting the badge requires the caller to hold an Agent ID;
///        - creating a permit requires BOTH the principal and the spender to hold one;
///        - spending under a permit requires the caller (the spender) to hold one.
contract AgentPermit is ERC721Enumerable {
    using Strings for uint256;

    /// @notice SPACE ID Agent ID registry on BNB Chain.
    address public immutable AGENT_ID_REGISTRY;

    /// @notice Hard cap on badges. Never increases.
    uint256 public constant MAX_BADGES = 5000;

    /// @notice Longest permit lifetime.
    uint64 public constant MAX_PERMIT_DURATION = 30 days;

    /// @notice Shortest permit lifetime.
    uint64 public constant MIN_PERMIT_DURATION = 1 hours;

    /// @notice badgeOf[account] is the tokenId of that account's badge, or 0 if none.
    mapping(address => uint256) public badgeOf;

    /// @notice Struct describing one standing permit.
    struct Permit {
        address principal; // holds the Agent ID, receives the funds
        address spender; // holds the Agent ID, sends the funds
        string spenderHandle; // .ai handle of the spender, for display only
        uint256 cap; // maximum total wei the spender may send under this permit
        uint256 spent; // wei already sent under this permit
        uint64 expiry; // unix seconds; spending is impossible at or after this
        uint64 createdAt; // unix seconds
        bool revoked; // principal pulled the permit
    }

    uint256 public permitCount;
    mapping(uint256 => Permit) public permits;

    /// @notice Number of permits ever created by each principal.
    mapping(address => uint256) public permitsCreated;

    /// @dev Live permit ids per principal, kept as a packed array so `permitsOf`
    ///      is O(n) reads and O(1) writes instead of a full-contract scan.
    mapping(address => uint256[]) private _principalPermits;

    /// @dev 1-based slot of a permit inside its principal's array. Zero = not listed.
    mapping(uint256 => uint256) private _permitSlot;

    event BadgeMinted(address indexed account, uint256 indexed tokenId, string handle);
    event PermitCreated(
        uint256 indexed permitId,
        address indexed principal,
        address indexed spender,
        uint256 cap,
        uint64 expiry
    );
    event PermitSpent(uint256 indexed permitId, address indexed spender, address indexed principal, uint256 amount);
    event PermitRevoked(uint256 indexed permitId, address indexed principal);

    error NotAgentId(address account);
    error AlreadyHasBadge(address account);
    error BadgeSupplyExhausted();
    error PermitNotFound(uint256 permitId);
    error NotPrincipal(uint256 permitId, address caller);
    error NotSpender(uint256 permitId, address caller);
    error PermitRevokedError(uint256 permitId);
    error PermitExpired(uint256 permitId);
    error PermitExhausted(uint256 permitId, uint256 cap, uint256 spent);
    error InvalidSpender(address spender);
    error InvalidCap();
    error InvalidDuration();
    error NoValueSent();

    constructor(address agentIdRegistry) ERC721("Agent Permit Badge", "APERMIT") {
        require(agentIdRegistry != address(0), "registry zero");
        AGENT_ID_REGISTRY = agentIdRegistry;
    }

    // ------------------------------------------------------------------ views

    /// @notice True when `account` holds a Binance Agent ID.
    function holdsAgentId(address account) public view returns (bool) {
        return ISpaceIdAgentID(AGENT_ID_REGISTRY).balanceOf(account) > 0;
    }

    /// @notice The .ai handle of `account`, for display only. Empty when none.
    function handleOf(address account) public view returns (string memory) {
        return ISpaceIdAgentID(AGENT_ID_REGISTRY).handleOf(account);
    }

    /// @notice Remaining wei the spender may still send under `permitId`.
    function remaining(uint256 permitId) public view returns (uint256) {
        Permit storage p = permits[permitId];
        if (p.cap == 0) return 0;
        if (p.revoked) return 0;
        if (p.expiry <= block.timestamp) return 0;
        return p.cap - p.spent;
    }

    /// @notice True when the permit can still be spent under right now.
    function isActive(uint256 permitId) public view returns (bool) {
        Permit storage p = permits[permitId];
        if (p.cap == 0 || p.revoked) return false;
        if (p.expiry <= block.timestamp) return false;
        return p.spent < p.cap;
    }

    /// @notice Read a permit as a plain tuple. The public mapping getter returns the
    ///         raw struct, which is awkward for front-ends and tests.
    function permitInfo(uint256 permitId)
        external
        view
        returns (address principal, address spender, string memory spenderHandle, uint256 cap, uint256 spent, uint64 expiry, bool revoked)
    {
        Permit storage p = permits[permitId];
        return (p.principal, p.spender, p.spenderHandle, p.cap, p.spent, p.expiry, p.revoked);
    }

    /// @notice All permit ids created by `principal`.
    function permitsOf(address principal) external view returns (uint256[] memory) {
        return _principalPermits[principal];
    }

    // ------------------------------------------------------------------ badge

    /// @notice Mint the one badge an Agent ID holder is entitled to. Free, gas only.
    function mintBadge() external returns (uint256 tokenId) {
        if (!holdsAgentId(msg.sender)) revert NotAgentId(msg.sender);
        if (badgeOf[msg.sender] != 0) revert AlreadyHasBadge(msg.sender);
        if (totalSupply() >= MAX_BADGES) revert BadgeSupplyExhausted();

        tokenId = totalSupply() + 1;
        badgeOf[msg.sender] = tokenId;
        _safeMint(msg.sender, tokenId);

        emit BadgeMinted(msg.sender, tokenId, handleOf(msg.sender));
    }

    /// @notice Fully on-chain metadata: the holder's .ai handle, rendered as an SVG
    ///         inside the standard ERC-721 JSON metadata document. No IPFS, no
    ///         external image host, nothing to change later.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "unknown token");
        address owner = ownerOf(tokenId);
        string memory handle = handleOf(owner);

        string memory svg = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600" viewBox="0 0 600 600">',
            '<rect width="600" height="600" fill="#0d0f14"/>',
            '<rect x="24" y="24" width="552" height="552" fill="none" stroke="#1f6feb" stroke-width="3"/>',
            '<text x="300" y="250" fill="#e6edf3" font-family="monospace" font-size="44" text-anchor="middle">',
            handle,
            "</text>",
            '<text x="300" y="320" fill="#7d8590" font-family="monospace" font-size="22" text-anchor="middle">',
            "agent permit",
            "</text>",
            '<text x="300" y="380" fill="#7d8590" font-family="monospace" font-size="18" text-anchor="middle">',
            "seat #",
            tokenId.toString(),
            "</text>",
            "</svg>"
        );

        string memory json = string.concat(
            '{"name":"Agent Permit #',
            tokenId.toString(),
            '","description":"A standing spend permit, anchored to a Binance Agent ID. Badge holder: ',
            handle,
            '","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '","attributes":[{"trait_type":"agent_id","value":"',
            handle,
            '"},{"trait_type":"seat","value":',
            tokenId.toString(),
            "}]}"
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    // ---------------------------------------------------------------- permits

    /// @notice Create a standing permit allowing `spender` to send up to `cap` wei
    ///         to the caller, for `duration` seconds. Both sides must hold an Agent ID.
    function createPermit(address spender, uint256 cap, uint64 duration) external returns (uint256 permitId) {
        // Input validation first, so a malformed call reports the malformed input
        // rather than an Agent ID gate result.
        if (spender == address(0) || spender == msg.sender) revert InvalidSpender(spender);
        if (cap == 0) revert InvalidCap();
        if (duration < MIN_PERMIT_DURATION || duration > MAX_PERMIT_DURATION) revert InvalidDuration();
        if (!holdsAgentId(msg.sender)) revert NotAgentId(msg.sender);
        if (!holdsAgentId(spender)) revert NotAgentId(spender);

        permitId = ++permitCount;
        permits[permitId] = Permit({
            principal: msg.sender,
            spender: spender,
            spenderHandle: handleOf(spender),
            cap: cap,
            spent: 0,
            expiry: uint64(block.timestamp) + duration,
            createdAt: uint64(block.timestamp),
            revoked: false
        });
        permitsCreated[msg.sender] += 1;
        _principalPermits[msg.sender].push(permitId);
        _permitSlot[permitId] = _principalPermits[msg.sender].length;

        emit PermitCreated(permitId, msg.sender, spender, cap, permits[permitId].expiry);
    }

    /// @notice Spend under a permit: sends `msg.value` wei from the spender to the
    ///         principal. The spender must still hold an Agent ID.
    function spend(uint256 permitId) external payable {
        Permit storage p = permits[permitId];
        if (p.cap == 0) revert PermitNotFound(permitId);
        if (msg.sender != p.spender) revert NotSpender(permitId, msg.sender);
        if (p.revoked) revert PermitRevokedError(permitId);
        if (p.expiry <= block.timestamp) revert PermitExpired(permitId);
        if (msg.value == 0) revert NoValueSent();
        if (p.spent + msg.value > p.cap) revert PermitExhausted(permitId, p.cap, p.spent);
        if (!holdsAgentId(msg.sender)) revert NotAgentId(msg.sender);

        p.spent += msg.value;
        (bool ok, ) = payable(p.principal).call{value: msg.value}("");
        require(ok, "transfer failed");

        emit PermitSpent(permitId, msg.sender, p.principal, msg.value);
    }

    /// @notice Revoke a permit. Only the principal may revoke.
    function revoke(uint256 permitId) external {
        Permit storage p = permits[permitId];
        if (p.cap == 0) revert PermitNotFound(permitId);
        if (msg.sender != p.principal) revert NotPrincipal(permitId, msg.sender);
        if (p.revoked) revert PermitRevokedError(permitId);
        p.revoked = true;
        _removePermitSlot(msg.sender, permitId);
        emit PermitRevoked(permitId, msg.sender);
    }

    // --------------------------------------------------------------- internals

    /// @dev Drop a permit from its principal's packed array by swapping in the
    ///      last element. O(1), and the permit id stays valid for lookups.
    function _removePermitSlot(address principal, uint256 permitId) internal {
        uint256 slot = _permitSlot[permitId];
        if (slot == 0) return;
        uint256[] storage arr = _principalPermits[principal];
        uint256 last = arr.length;
        if (slot != last) {
            uint256 moved = arr[last];
            arr[slot] = moved;
            _permitSlot[moved] = slot;
        }
        arr.pop();
        delete _permitSlot[permitId];
    }
}
