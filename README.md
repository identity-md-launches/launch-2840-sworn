# Sworn (SWORN)

A fixed-supply ERC-20 token for an IMD custom-token launch on Ethereum (chain id 1).

| Property | Value |
| --- | --- |
| Solidity contract | `SwornToken` (`src/SwornToken.sol`) |
| `name()` | `Sworn` |
| `symbol()` | `SWORN` |
| `decimals()` | `18` |
| `totalSupply()` | `1000000000000000000000000000` (1,000,000,000 × 10^18) |
| Constructor arguments | none |
| Compiler | solc 0.8.26, optimizer 200 runs, `bytecode_hash = "none"` |

## Behaviour

- The constructor mints the whole supply, once, to `msg.sender` (the deployer, which in the launch is
  IMD's factory). The supply is stored as an immutable and can never change.
- Standard ERC-20 `transfer`, `approve`, `transferFrom`, `allowance`, `balanceOf`. An allowance of
  `type(uint256).max` is treated as infinite and is not decreased.
- Failures revert with custom errors: `InvalidReceiver` (transfer to the zero address),
  `InvalidSpender` (approve the zero address), `InsufficientBalance`, `InsufficientAllowance`.
- No owner, no admin, no mint, no burn, no pause, no blacklist, no fee or tax on transfer, no
  upgradeability, no external calls, no `delegatecall`/`selfdestruct`. Every transfer moves exactly the
  amount it says, so the factory → distributor, distributor → claimant, pool seed and swap flows are exact.

## Assumptions

- The deployer receiving the supply is the launch factory, which distributes it per the launch terms
  (10% to the swarm's MerkleDistributor, 80% seeding the IMD-paired Uniswap v4 pool, the remainder to
  the requester's `remainderTo`). The token itself knows nothing about these flows and needs no exemptions.
- `approve` overwrites the allowance (classic ERC-20 semantics); integrators who care about the
  well-known approve race should set to 0 first or use exact allowances.

## Deployment parameters

None. The contract takes no constructor arguments; deploy the creation code as built.
`script/DeploySworn.s.sol` is a reference script for local review (`deploy()` is what tests call);
the production launch is performed by IMD's factory, not by this script.

## Operational responsibilities

- There are no privileged roles, so there is nothing to administer after launch and no keys to guard.
- There are no "After launch" settings: the token needs no configuration.
- Mistakenly sent tokens (including to the token contract itself) cannot be recovered by anyone.
- Tests passing are not a security audit; an independent review is recommended before release.

## Development

```sh
forge build
forge test
forge fmt --check
```

`lib/forge-std` is vendored as ordinary files (forge-std v1.9.7, MIT/Apache-2.0).
