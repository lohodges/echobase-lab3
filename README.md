# Lab 3

## Deployment Order

The modules must be deployed and destroyed in a specific order due to cross-region dependencies.

### Apply

1. `tokyo` and `saopaulo` (can be applied in parallel)
2. `interlink` (depends on resources from both regions)

### Destroy

1. `interlink` (must be destroyed first)
2. `tokyo` and `saopaulo` (can be destroyed in parallel after interlink is gone)
