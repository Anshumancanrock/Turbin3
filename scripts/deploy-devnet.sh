#!/usr/bin/env bash
#
# Deploys the vault to devnet and runs the test suite, which performs the
# registration CPI. Safe to re-run up to (but not through) the point where the
# registration succeeds — see the note at the bottom.
#
#   ./scripts/deploy-devnet.sh
#
set -euo pipefail

export PATH="$HOME/.cargo/bin:$HOME/.local/share/solana/install/active_release/bin:$PATH"
cd "$(dirname "$0")/.."

PROGRAM_ID=$(solana address -k target/deploy/pre_req_vault-keypair.json 2>/dev/null || true)
WALLET=$(solana address)

echo "wallet:     $WALLET"
echo "program:    ${PROGRAM_ID:-<not built yet>}"
echo "cluster:    devnet"
echo

# --- 1. funding -------------------------------------------------------------
# Deploying costs ~1.24 SOL of rent for the program account, and transiently
# about the same again for the buffer (which is reclaimed). 3 SOL is comfortable.
BAL=$(solana balance -u devnet | awk '{print $1}')
echo "balance:    $BAL SOL"

if (( $(echo "$BAL < 2.6" | bc -l) )); then
  echo
  echo "Not enough SOL to deploy. Top up, then re-run:"
  echo "  solana airdrop 2 -u devnet          # often rate-limited"
  echo "  https://faucet.solana.com           # paste $WALLET"
  exit 1
fi

# --- 2. build + deploy ------------------------------------------------------
echo
echo "==> anchor build"
anchor build

echo
echo "==> anchor deploy"
anchor deploy --provider.cluster devnet

# --- 3. test (this is what performs the CPI) --------------------------------
echo
echo "==> anchor test --skip-deploy"
anchor test --provider.cluster devnet --skip-deploy

# --- 4. verify --------------------------------------------------------------
echo
echo "==> verifying registration on devnet"
pnpm exec ts-node scripts/check-registration.ts https://api.devnet.solana.com

cat <<'EOF'

Done. The registration account now exists on devnet and holds the GitHub handle
from programs/pre-req-vault/src/constants.rs.

Re-running this script will now FAIL at the withdraw test with
"Allocate: account ... already in use" (custom program error 0x0). That is
expected and correct: the registration program creates the account with `init`,
so there is exactly one registration per wallet, forever.
EOF
