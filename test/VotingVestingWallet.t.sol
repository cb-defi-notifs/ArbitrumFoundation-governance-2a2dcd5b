// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/VotingVestingWallet.sol";
import "../src/L2ArbitrumToken.sol";
import "../src/L2ArbitrumGovernor.sol";
import "../src/TokenDistributor.sol";
import "../src/ArbitrumTimelock.sol";
import "../src/Util.sol";

import "./util/TestUtil.sol";

import "forge-std/Test.sol";

contract VotingVestingWalletTest is Test {
    address beneficiary = address(1);
    uint64 secondsPerYear = 60 * 60 * 24 * 365;
    uint64 startTimestamp = secondsPerYear * 2; // starts at 2 years
    uint64 durationSeconds = secondsPerYear * 3; // lasts a further 3 years
    uint256 beneficiaryClaim = 200_000_000_000_000;

    uint256 claimPeriodStart = 210;
    uint256 claimPeriodEnd = claimPeriodStart + 20;

    uint256 initialSupply = 10 * 1_000_000_000 * (10 ** 18);
    address l1Token = address(1_234_578);
    address owner = address(12_345_789);
    address payable sweepTo = payable(address(123_457_891));
    address delegatee = address(138);

    function deployDeps() public returns (L2ArbitrumToken, L2ArbitrumGovernor, TokenDistributor) {
        address token = TestUtil.deployProxy(address(new L2ArbitrumToken()));
        L2ArbitrumToken(token).initialize(l1Token, initialSupply, owner);
        TokenDistributor td = new TokenDistributor(
            IERC20VotesUpgradeable(token), sweepTo, owner, claimPeriodStart, claimPeriodEnd
        );
        vm.prank(owner);
        L2ArbitrumToken(token).transfer(address(td), beneficiaryClaim * 2);

        address payable timelock = payable(TestUtil.deployProxy(address(new ArbitrumTimelock())));
        address[] memory proposers;
        address[] memory executors;
        ArbitrumTimelock(timelock).initialize(20, proposers, executors);

        address payable governor = payable(TestUtil.deployProxy(address(new L2ArbitrumGovernor())));
        L2ArbitrumGovernor(governor).initialize(IVotesUpgradeable(token), ArbitrumTimelock(timelock));

        vm.roll(claimPeriodStart);

        return (L2ArbitrumToken(token), L2ArbitrumGovernor(governor), td);
    }

    function deploy() public returns (VotingVestingWallet, L2ArbitrumToken, L2ArbitrumGovernor, TokenDistributor) {
        (L2ArbitrumToken token, L2ArbitrumGovernor gov, TokenDistributor td) = deployDeps();
        VotingVestingWallet wallet = new VotingVestingWallet(
            beneficiary,
            startTimestamp,
            durationSeconds,
            address(td),
            address(token),
            payable(address( gov))
        );

        address[] memory recipients = new address[](1);
        recipients[0] = address(wallet);
        uint256[] memory claims = new uint256[](1);
        claims[0] = beneficiaryClaim;
        vm.prank(owner);
        td.setRecipients(recipients, claims);

        return (wallet, token, gov, td);
    }

    function testDoesDeploy() external {
        (VotingVestingWallet wallet, L2ArbitrumToken token, L2ArbitrumGovernor gov, TokenDistributor td) = deploy();

        assertEq(wallet.distributor(), address(td), "Distributor");
        assertEq(wallet.governor(), address(gov), "Governor");
        assertEq(wallet.token(), address(token), "Token");
        assertEq(wallet.start(), startTimestamp, "Start time");
        assertEq(wallet.duration(), durationSeconds, "Duration");
        assertEq(wallet.released(address(token)), 0, "Released");
    }

    function testDeployZeroDistributor() external {
        (L2ArbitrumToken token, L2ArbitrumGovernor gov,) = deployDeps();
        vm.expectRevert("VotingVestingWallet: zero distributor");
        new VotingVestingWallet(
            beneficiary,
            startTimestamp,
            durationSeconds,
            address(0),
            address(token),
            payable(address( gov))
        );
    }

    function testDeployZeroToken() external {
        (, L2ArbitrumGovernor gov, TokenDistributor td) = deployDeps();
        vm.expectRevert("VotingVestingWallet: zero token");
        new VotingVestingWallet(
            beneficiary,
            startTimestamp,
            durationSeconds,
            address(td),
            address(0),
            payable(address(gov))
        );
    }

    function testDeployZeroGovernor() external {
        (L2ArbitrumToken token,, TokenDistributor td) = deployDeps();
        vm.expectRevert("VotingVestingWallet: zero governor");
        new VotingVestingWallet(
            beneficiary,
            startTimestamp,
            durationSeconds,
            address(td),
            address(token),
            payable(address(0))
        );
    }

    function testClaim() external {
        (VotingVestingWallet wallet, L2ArbitrumToken token,, TokenDistributor td) = deploy();
        vm.prank(beneficiary);
        wallet.claim();

        assertEq(token.balanceOf(address(wallet)), beneficiaryClaim, "Claim");
        assertEq(td.claimableTokens(address(wallet)), 0, "Claim left");
    }

    function testClaimFailsForNonBeneficiary() external {
        (VotingVestingWallet wallet,,,) = deploy();
        vm.expectRevert("VotingVestingWallet: not beneficiary");
        wallet.claim();
    }

    function deployAndClaim()
        public
        returns (VotingVestingWallet, L2ArbitrumToken, L2ArbitrumGovernor, TokenDistributor)
    {
        (VotingVestingWallet wallet, L2ArbitrumToken token, L2ArbitrumGovernor gov, TokenDistributor td) = deploy();
        vm.prank(beneficiary);
        wallet.claim();

        return (wallet, token, gov, td);
    }

    function testDelegate() external {
        (VotingVestingWallet wallet, L2ArbitrumToken token,,) = deployAndClaim();

        vm.prank(beneficiary);
        wallet.delegate(delegatee);

        assertEq(token.delegates(address(wallet)), delegatee, "Delegatee");
    }

    function testDelegateFailsForNonBeneficiary() external {
        (VotingVestingWallet wallet,,,) = deployAndClaim();

        vm.expectRevert("VotingVestingWallet: not beneficiary");
        wallet.delegate(delegatee);
    }

    function deployClaimAndDelegate()
        public
        returns (VotingVestingWallet, L2ArbitrumToken, L2ArbitrumGovernor, TokenDistributor)
    {
        (VotingVestingWallet wallet, L2ArbitrumToken token, L2ArbitrumGovernor gov, TokenDistributor td) =
            deployAndClaim();

        vm.prank(beneficiary);
        wallet.delegate(delegatee);

        return (wallet, token, gov, td);
    }

    function testCastVote() external {
        (VotingVestingWallet wallet,, L2ArbitrumGovernor gov,) = deployClaimAndDelegate();

        address[] memory targets = new address[](1);
        targets[0] = address(5);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;
        bytes[] memory data = new bytes[](1);
        data[0] = "";

        uint256 propId = gov.propose(targets, amounts, data, "Test prop");
        vm.roll(gov.proposalSnapshot(propId) + 1);

        assertEq(gov.hasVoted(propId, address(wallet)), false, "Has not voted");
        vm.prank(beneficiary);
        wallet.castVote(propId, 1);
        assertEq(gov.hasVoted(propId, address(wallet)), true, "Has voted");
    }

    function testCastVoteFailsForNonBeneficiary() external {
        (VotingVestingWallet wallet,, L2ArbitrumGovernor gov,) = deployClaimAndDelegate();

        address[] memory targets = new address[](1);
        targets[0] = address(5);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;
        bytes[] memory data = new bytes[](1);
        data[0] = "";

        uint256 propId = gov.propose(targets, amounts, data, "Test prop");
        vm.roll(gov.proposalSnapshot(propId) + 1);

        assertEq(gov.hasVoted(propId, address(wallet)), false, "Has not voted");
        vm.expectRevert("VotingVestingWallet: not beneficiary");
        wallet.castVote(propId, 1);
    }

    uint64 constant SECONDS_PER_YEAR = 60 * 60 * 24 * 365;
    uint64 constant SECONDS_PER_MONTH = SECONDS_PER_YEAR / 12;

    function testVestedAmountStart() external {
        (VotingVestingWallet wallet, L2ArbitrumToken token,,) = deployAndClaim();

        assertEq(wallet.vestedAmount(address(token), startTimestamp - 1), 0, "Vested zero");
        assertEq(wallet.vestedAmount(address(token), startTimestamp), beneficiaryClaim / 4, "Vested cliff");
        assertEq(wallet.vestedAmount(address(token), startTimestamp + 1), beneficiaryClaim / 4, "Vested cliff after");
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_MONTH - 1),
            beneficiaryClaim / 4,
            "Vested one month minus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_MONTH),
            (beneficiaryClaim / 4) + (beneficiaryClaim / 48),
            "Vested at 1 month"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_MONTH + 1),
            (beneficiaryClaim / 4) + (beneficiaryClaim / 48),
            "Vested at 1 month plus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_YEAR - 1),
            (beneficiaryClaim / 4) + ((beneficiaryClaim * 11) / 48),
            "Vested one year minus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_YEAR),
            beneficiaryClaim / 2,
            "Vested one year"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_YEAR + 1),
            beneficiaryClaim / 2,
            "Vested one year plus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_YEAR + SECONDS_PER_MONTH - 1),
            beneficiaryClaim / 2,
            "Vested one year and one month minus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_YEAR + SECONDS_PER_MONTH),
            (beneficiaryClaim / 2) + (beneficiaryClaim / 48),
            "Vested one year and one month"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_YEAR + SECONDS_PER_MONTH + 1),
            (beneficiaryClaim / 2) + (beneficiaryClaim / 48),
            "Vested one year and one month plus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + (SECONDS_PER_YEAR * 3) - 1),
            ((beneficiaryClaim * 47) / 48),
            "Three years minus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + (SECONDS_PER_YEAR * 3)),
            (beneficiaryClaim),
            "Three years"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + (SECONDS_PER_YEAR * 3) + 1),
            (beneficiaryClaim),
            "Three years plus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + (SECONDS_PER_YEAR * 10)),
            (beneficiaryClaim),
            "Way into the future"
        );
    }
}
