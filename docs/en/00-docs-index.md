# Documentation Index (EN)

Language: **EN**

## Contents

1. [Options documentation](./options.md)
2. [Strategy documentation](./strategy.md)

## Options (Product)

### Recommended reading order

1. [Requirements](./options.md#2-requirements)
2. [Operation flow](./options.md#3-operation-flow)
3. [Permission model](./options.md#4-permission-model)
4. [User journey & algorithms](./options.md#5-user-journey--algorithms)
5. [Frontend/backend integration](./options.md#6-frontendbackend-integration)
6. [API reference](./options.md#7-api-reference)
7. [Error reference](./options.md#8-error-reference)

## Strategy (Product)

### Recommended reading order

1. [Requirements](./strategy.md#2-requirements)
2. [Operation flow](./strategy.md#3-operation-flow)
3. [Permission model](./strategy.md#4-permission-model)
4. [User journey & scaling algorithms](./strategy.md#5-user-journey--scaling-algorithms)
5. [Frontend/backend integration](./strategy.md#6-frontendbackend-integration)
6. [API reference](./strategy.md#7-api-reference)
7. [Error reference](./strategy.md#8-error-reference)

## Scope

These docs are aligned to:
- `src/core/EnhancedOptions.sol`
- `src/periphery/strategy/EnhancedStrategy.sol`

## Product status

- Options core lifecycle: enabled
- OTC: disabled (`revert("not support")`)
- Flash-loan redeem: disabled (`revert("not support")`)
- Strategy lifecycle + buyback: enabled
