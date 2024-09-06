// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Strings.sol";
import "./Game721NFT.sol";

contract DiceNFT is Game721NFT {

    // weights of the dice, 
    mapping(uint256 => uint256[6]) private _weights;

    // nonce to generate random number
    uint256 private _randomNonce;

    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI,
        uint256 maxAmount,
        uint256 startTime,
        uint256 endTime,
        uint256 userLimit,
        address acceptCurrency,
        uint256 mintPrice,
        address signer,
        bool needVerify
    ) public Game721NFT(name, symbol, baseURI, maxAmount, startTime, endTime, userLimit, acceptCurrency, mintPrice, signer, needVerify) {

    }

    function tokenURI(uint256 tokenId) override public view returns (string memory) {
        string[13] memory parts;
        parts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="black" /><text x="10" y="20" class="base">';

        parts[1] = Strings.toString(_weights[tokenId][0]);

        parts[2] = '</text><text x="10" y="40" class="base">';

        parts[3] = Strings.toString(_weights[tokenId][1]);

        parts[4] = '</text><text x="10" y="60" class="base">';

        parts[5] = Strings.toString(_weights[tokenId][2]);

        parts[6] = '</text><text x="10" y="80" class="base">';

        parts[7] = Strings.toString(_weights[tokenId][3]);

        parts[8] = '</text><text x="10" y="100" class="base">';

        parts[9] = Strings.toString(_weights[tokenId][4]);

        parts[10] = '</text><text x="10" y="120" class="base">';

        parts[11] = Strings.toString(_weights[tokenId][5]);

        parts[12] = '</text></svg>';

        string memory output = string(abi.encodePacked(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6], parts[7], parts[8]));
        output = string(abi.encodePacked(output, parts[9], parts[10], parts[11], parts[12]));
        
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "Dice for Loot #', Strings.toString(tokenId), '", "description": "An assortment of random dice for various on chain games", "image": "data:image/svg+xml;base64,', Base64.encode(bytes(output)), '"}'))));
        output = string(abi.encodePacked('data:application/json;base64,', json));

        return output;
    }

    function mint(
        uint256 _nonce,
        bytes memory _signature
    ) public override payable returns (uint256) {
        uint256 tokenId = super.mint(_nonce, _signature);
        _initWeights(tokenId);
        return tokenId;
    }

    function mint() public override payable returns (uint256) {
        uint256 tokenId = super.mint();
        _initWeights(tokenId);
        return tokenId;
    }

    function _initWeights(uint256 tokenId) internal {
        _randomNonce++;
        uint256 randomHash = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, tokenId, _randomNonce)));

        for (uint i = 0; i < 6; i++) {
            _weights[tokenId][i] = randomHash % 20 + 1;
            randomHash = randomHash >> 4;
        }

        _randomNonce += _weights[tokenId][0];
    }

    function getWeights(uint256 tokenId) public view returns (uint256[6] memory) {
        return _weights[tokenId];
    }

    // roll the dice to get a number in [1, 6]
    // generate a random number in [0, 60 + _weights[tokenId][luckyNumber - 1])
    //       random number     ------>      result
    //       [ 0,  9)                         1
    //       [10, 19)                         2
    //       [20, 29)                         3
    //       [30, 39)                         4
    //       [40, 49)                         5
    //       [50, 59)                         6
    //       >= 60                            lucky number
    function roll(uint256 tokenId, uint256 luckyNumber) public returns (uint256) {
        require(luckyNumber > 0 && luckyNumber < 7, "lucky number should be 1 ~ 6");

        _randomNonce++;
        uint256 randomHash = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, tokenId, _randomNonce)));
        uint256 random = randomHash % (60 + _weights[tokenId][luckyNumber - 1]);
        uint256 result;
        if (random >= 60) {
            result = luckyNumber; 
        } else {
            result = random / 10 + 1;
        }
        _randomNonce += result;
        return result;
    }
}

/// [MIT License]
/// @title Base64
/// @notice Provides a function for encoding some bytes in base64
/// @author Brecht Devos <brecht@loopring.org>
library Base64 {
    bytes internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /// @notice Encodes some bytes to the base64 representation
    function encode(bytes memory data) internal pure returns (string memory) {
        uint256 len = data.length;
        if (len == 0) return "";

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((len + 2) / 3);

        // Add some extra buffer at the end
        bytes memory result = new bytes(encodedLen + 32);

        bytes memory table = TABLE;

        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)

            for {
                let i := 0
            } lt(i, len) {

            } {
                i := add(i, 3)
                let input := and(mload(add(data, i)), 0xffffff)

                let out := mload(add(tablePtr, and(shr(18, input), 0x3F)))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(12, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(6, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(input, 0x3F))), 0xFF))
                out := shl(224, out)

                mstore(resultPtr, out)

                resultPtr := add(resultPtr, 4)
            }

            switch mod(len, 3)
            case 1 {
                mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
            }
            case 2 {
                mstore(sub(resultPtr, 1), shl(248, 0x3d))
            }

            mstore(result, encodedLen)
        }

        return string(result);
    }
}