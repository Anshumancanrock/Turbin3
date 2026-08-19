#!/usr/bin/env bash
#
# Deploys the vault to devnet and runs the test suite, which performs the
# registration CPI.
#
#   ./scripts/deploy-devnet.sh
#
# Each stage checks whether it has already been done, so this is safe to re-run
# after a network failure without paying to deploy twice.
#
set -euo pipefail

export PATH="$HOME/.cargo/bin:$HOME/.local/share/solana/install/active_release/bin:$PATH"
cd "$(dirname "$0")/.."

URL=https://api.devnet.solana.com
KEYPAIR=target/deploy/pre_req_vault-keypair.json

if [ ! -f "$KEYPAIR" ]; then
  echo "No program keypair at $KEYPAIR — run 'anchor build' first."
  echo "If you have the backup, restore it BEFORE building, or the program ID changes:"
  echo "  cp ~/.config/solana/pre_req_vault-program-keypair.json $KEYPAIR"
  exit 1
fi

PROGRAM_ID=$(solana address -k "$KEYPAIR")
WALLET=$(solana address)

echo "wallet:   $WALLET"
echo "program:  $PROGRAM_ID"
echo "cluster:  devnet"
echo

# --- 0. don't burn the one-shot registration ---------------------------------
# The registration program creates the ApplicationAccount with `init`, so there
# is exactly one registration per wallet, forever. If it already exists there is
# nothing left to do and re-running the tests would only produce a red failure.
if pnpm exec ts-node scripts/check-registration.ts "$URL" >/dev/null 2>&1; then
  echo "This wallet is ALREADY registered. Nothing to do."
  echo
  pnpm exec ts-node scripts/check-registration.ts "$URL"
  exit 0
fi

# --- 1. recover anything stranded by a previous failed deploy ----------------
BUFFERS=$(solana program show --buffers -u "$URL" 2>/dev/null | tail -n +3 || true)
if [ -n "$BUFFERS" ]; then
  echo "Stranded deploy buffers are holding SOL:"
  echo "$BUFFERS"
  echo "Reclaim them with:  solana program close --buffers -u $URL"
  echo
fi

# --- 2. funding -------------------------------------------------------------
# Measured, not guessed: the program data account is exactly the size of the
# .so (deploy does not over-allocate), which is 1.2357 SOL of rent at 177 KB.
# On top of that: ~0.001 for the program account, ~0.03 for the on-chain IDL,
# 1 SOL of working capital for the deposit test (returned by `close`), and fees.
BAL=$(solana balance -u "$URL" | awk '{print $1}')
echo "balance:  $BAL SOL"

if (( $(echo "$BAL < 2.6" | bc -l) )); then
  cat <<EOF

Not enough SOL — need ~2.3, want 3 for headroom.

The devnet faucet limits per IP per day, so the quickest fix is usually to
change IP: tether to mobile data and run

  solana airdrop 2 -u $URL

Otherwise https://faucet.solana.com (GitHub login) — paste $WALLET
EOF
  exit 1
fi

# --- 3. deploy --------------------------------------------------------------
echo
echo "==> anchor build"
anchor build

if solana program show "$PROGRAM_ID" -u "$URL" >/dev/null 2>&1; then
  echo
  echo "==> program already deployed, skipping deploy"
else
  echo
  echo "==> anchor deploy"
  # --use-rpc routes the ~175 chunk writes through the RPC instead of straight
  # to validator TPUs over QUIC, which is what usually fails behind home NAT.
  # The priority fee and extra sign attempts guard against devnet congestion.
  if ! anchor deploy --provider.cluster devnet -- \
        --use-rpc --with-compute-unit-price 5000 --max-sign-attempts 200; then
    cat <<EOF

Deploy failed. Your SOL is most likely sitting in a buffer account, not lost:

  solana program show --buffers -u $URL
  solana program close --buffers -u $URL     # reclaim, then re-run this script

EOF
    exit 1
  fi
fi

# --- 4. test (this is what performs the CPI) --------------------------------
echo
echo "==> anchor test --skip-deploy"
anchor test --provider.cluster devnet --skip-deploy

# --- 5. verify --------------------------------------------------------------
echo
echo "==> verifying registration on devnet"
pnpm exec ts-node scripts/check-registration.ts "$URL"

cat <<EOF

Done. Explorer links:

  program:  https://explorer.solana.com/address/$PROGRAM_ID?cluster=devnet
  wallet:   https://explorer.solana.com/address/$WALLET?cluster=devnet

Re-running now would fail at the withdraw test with "already in use" — that is
correct, not a bug. One registration per wallet, forever.
EOF
