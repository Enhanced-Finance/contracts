# Enhanced EVM Options & Strategy

Language: **English**

This repository contains an EVM options protocol with two product lines:
- **Options**: execution gateway for option lifecycle (`src/core/EnhancedOptions.sol`)
- **Strategy**: cycle-based strategy vault with NFT fund positions (`src/periphery/strategy/EnhancedStrategy.sol`)

## Current status

- OTC is intentionally disabled (`revert("not support")`).
- Flash-loan redeem is intentionally disabled (`revert("not support")`).
- Trusted position path is restricted by `taker == msg.sender`.

## Quick start

```bash
forge install
forge build --via-ir
```

## Common commands

```bash
make upgrade_enhanced_strategy
```

## Documentation

- English docs: [`docs/en`](./docs/en/00-docs-index.md)

## License

MIT
