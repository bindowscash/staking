# BindowsCash Staking Pool

BindowsCash is not only a mixer, but it allows $BINDOWS holders to stake their tokens into the vault.

Key Features & Specifications of the staking contract:
- Post-Deployment Token Binding: The staking token address is initialized once by the developer after deployment.
- Real-Time Global Ratio Accounting: Uses an optimized Synthetix-style algorithm (O(1) gas complexity) to track and 
  distribute incoming reward transfers proportionally without looping through users.
- Automatic Compound & Claims: Unstaking (withdrawing) automatically claims and transfers any accrued rewards.
- Double-Spend & Reentrancy Protection: Implements a strict Check-Effects-Interactions pattern, deducting user balances
  before executing external transfers, combined with an active reentrancy guard.
- Developer Fee: A 5% protocol fee is automatically deducted from all claimed rewards (during direct claims or withdrawals)
  and sent directly to the development fund.

Security features of the contracts:
- Variables are hardcoded (cannot be changed)
- Addresses are hardcoded (cannot be changed)
- Deposits/withdrawals cannot be paused or cancelled by a third-party
- The contracts cannot self-destruct, and cannot be called via a delegatecall.
- The contracts are not deployed behind a proxy, so they are not immutable and not upgradeable.
- Users can either withdraw their rewards only, or their staked tokens + their rewards within one transaction.
- Reentrancy guard enabled
- There is no expiration on deposits/withdrawals. Users can stake or unstake whenever they want.
- All the contracts are public and verified on the blockchains, ensuring transparency and security.

The vault is funded by 2 sources:
- $BINDOWS volume: the token has a 1% buy tax and 3% sell tax, transferred automatically to the staking contract on each transaction. Staking rewards reflect automatically within the dApp.
- Mixing volume: whenever someone mix some tokens into the protocol (using one of the $BINDOWS mixing pools), half of the 1% fee taken from the deposits is transferred to the staking contract.

So whenever someone buys, sells or mix $BINDOWS, a share of the transaction directly funds the stakers, thus allowing non-inflationary farming.

The full source code of BindowsCash contracts is available in Staking.sol file. Here is the official deployment address of the staking contract on BSC:

## BSC Mainnet

    Staking contract: 0x13551B25C11D2A652b34721A96708Cb10B12a55C
