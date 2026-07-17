# BindowsCash Staking Pool

BindowsCash is not only a mixer, but it allows $BINDOWS holders to stake their tokens into the vault.

Security features of the contracts:
- Variables are hardcoded (cannot be changed)
- Addresses are hardcoded (cannot be changed)
- Deposits/withdrawals cannot be paused or cancelled by a third-party
- The contracts cannot self-destruct, and cannot be called via a delegatecall.
- The contracts are not deployed behind a proxy, so they are not immutable and not upgradeable.
- Users can either withdraw their rewards only, or their staked tokens + their rewards within one transaction.
- There is no expiration on deposits/withdrawals. Users can stake or unstake whenever they want.
- All the contracts are public and verified on the blockchains, ensuring transparency and security.

The vault is funded by 2 sources:
- $BINDOWS volume: the token has a 1% buy tax and 3% sell tax, transferred automatically to the staking contract on each transaction. Staking rewards reflect automatically within the dApp.
- Mixing volume: whenever someone mix some tokens into the protocol, a 1% fee is taken on the deposits, transferred to the staking contract.

So whenever someone buys, sells or mix $BINDOWS, a share of the transaction directly funds the stakers, thus allowing non-inflationary farming.

The full source code of BindowsCash contracts is available in Staking.sol file. Here is the official deployment address of the staking contract on BSC:

## BSC Mainnet

    Staking contract: 0x13551B25C11D2A652b34721A96708Cb10B12a55C
