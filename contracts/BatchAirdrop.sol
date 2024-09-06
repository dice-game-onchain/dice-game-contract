pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;
import "./Governable.sol";

contract BatchAirdrop is Governable {
    mapping(address => uint256) private userRewards;
    mapping(address => bool) private admins;
    struct TopUserReward {
        address user;
        uint256 reward;
    }
    TopUserReward[10] private Top10;

    modifier needAdmins() {
        require(msg.sender == governor || admins[msg.sender]);
        _;
    }

    constructor() public {
        super.initialize(msg.sender);
    }

    function getUserRewards(address user) external returns (uint256) {
        return userRewards[user];
    }

    function getTop10() external returns (TopUserReward[10] memory) {
        return Top10;
    }

    function setAdmins(address admin_, bool value_) external governance {
        admins[admin_] = value_;
    }

    function setTop10(
        address[] memory users,
        uint256[] memory values
    ) external needAdmins {
        require(users.length == values.length, "length different");
        for (uint i = 0; i < users.length; i++) {
            TopUserReward storage uR;
            uR.user = users[i];
            uR.reward = values[i];
            Top10[i] = uR;
        }
    }

    function toAirdrop(
        address payable[] memory users,
        uint256[] memory values
    ) external payable needAdmins {
        require(users.length == values.length, "length different");
        for (uint i = 0; i < users.length; i++) {
            users[i].transfer(values[i]);
            userRewards[users[i]] += values[i];
        }
    }
}
