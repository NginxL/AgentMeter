#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# A plain Swift executable keeps the checks independent of XCTest installation.
swift run MeterChecks "$@"
swift run MeterProviderChecks
swift run AgentMeter --self-check
