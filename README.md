# Enhanced Protocol Contracts

This repository contains 2 main contracts:

- [`EnhancedOptions`](src/core/EnhancedOptions.sol) execution gateway for option lifecycle.
- [`EnhancedVault`](src/periphery/vault/EnhancedVault.sol) runs cycle-based option vaults with queued deposits and withdrawals, premium distribution, optional premium buyback, and operator-driven order execution.


## Development

Requirements: [Foundry](https://book.getfoundry.sh/) and Git.

```bash
forge install
git submodule update --init --recursive
forge build --via-ir
forge test
forge fmt --check
```

The compiler and optimizer configuration is in [`foundry.toml`](foundry.toml). The project currently targets Solidity `0.8.28` and builds with IR enabled.

For deployment or upgrades, use the scripts under [`script`](script) and the targets in [`Makefile`](Makefile). 

## License

MIT
