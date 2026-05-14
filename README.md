## BondingCurve


## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Deploy

```shell
# With verification
forge script script/Deploy.s.sol:Deploy --sig 'run()' \
--chain-id $CHAIN_ID \
--rpc-url $ETH_RPC_URL \
--private-key $PRIVATE_KEY \
--broadcast --ffi -vvvv

forge script script/Deploy.s.sol:Deploy --sig 'deployImplementations()' \
--chain-id $CHAIN_ID \
--rpc-url $ETH_RPC_URL \
--private-key $PRIVATE_KEY \
--broadcast --ffi -vvvv
```