# pre-req-vault

A per-wallet SOL vault built with Anchor. The `withdraw` instruction was extended so that
a successful withdrawal also registers the caller with Turbin3's registration program
through a CPI.

| | |
|---|---|
| Vault program | [`HZbxjG93btfbrLs9r55hDSg3et4tX3Ktm5uLAVJjwmsw`](https://explorer.solana.com/address/HZbxjG93btfbrLs9r55hDSg3et4tX3Ktm5uLAVJjwmsw?cluster=devnet) |
| Registration program | [`TRBZyQHB3m68FGeVsqTK39Wm4xejadjVhP5MAZaKWDM`](https://explorer.solana.com/address/TRBZyQHB3m68FGeVsqTK39Wm4xejadjVhP5MAZaKWDM?cluster=devnet) |
| Registration tx | [`43uiqRQi…dmdj93sC`](https://explorer.solana.com/tx/43uiqRQiTCEp4sgENZzZ9DYEgmXsPxpwtyQZKSg5W26Zh9ryE7fhVLHXyjrQKbmE3TchVGt2krbwSf8gdmdj93sC?cluster=devnet) |
| GitHub handle recorded | `Anshumancanrock` |
| Cluster | devnet |
| Anchor / Solana CLI | 1.1.2 / 3.1.10 |

## Architecture

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/architecture-dark.png">
  <img src="docs/architecture-light.png" alt="Architecture diagram: the user signs a transaction to the pre-req-vault program, which owns the vault_state and vault PDAs, invokes the System Program to move lamports, and invokes the registration program to create the application account.">
</picture>

[`docs/architecture.html`](docs/architecture.html) is the same diagram as a standalone page.

## How the vault works

Every wallet gets its own SOL holding account that only that wallet can withdraw from.
There is no shared pool and no admin key. Access control falls out of how the addresses
are derived rather than being enforced by a check.

Solana programs hold no state of their own, so everything lives in accounts passed into
each instruction. This program owns two of them and passes a third through to the
registration program.

### The accounts

**`vault_state`**, seeds `["state", user]`, owned by the vault program. The user's record.
It stores two bytes:

```rust
pub struct VaultState {
    pub vault_bump: u8,
    pub state_bump: u8,
}
```

Both are bumps. Finding a canonical bump on-chain means looping until the derived address
falls off the ed25519 curve, which costs compute. `initialize` does that once and stores
the result, and every later instruction reads it back with `bump = vault_state.vault_bump`
instead of searching again.

**`vault`**, seeds `["vault", vault_state]`, a `SystemAccount` holding the lamports. Note
the seed is the *vault_state address*, not the user's key, so the derivation chains from
user to state to vault. It has no data, so the System Program can move lamports out of it
directly once the vault program authorises the move.

**`application_account`**, seeds `["prereqs", user]`, owned by the registration program.
This is what the CPI creates. It is typed `UncheckedAccount` because this program never
reads or writes it, only passes it along. The `seeds::program = application_program.key()`
constraint still pins the address to the right derivation under the registration program.

### The instructions

| Instruction | Effect | Authorised by |
|---|---|---|
| `initialize` | Creates `vault_state`, stores both bumps | n/a, no transfer |
| `deposit(amount)` | Moves `amount` from user to vault | the user's signature |
| `withdraw(amount)` | Moves `amount` from vault to user, then registers the user | the `vault` PDA |
| `close` | Drains the vault and closes `vault_state`, refunding rent | the `vault` PDA |

That last column is the interesting part. `deposit` takes lamports out of the user's own
wallet, so their signature on the transaction is enough:

```rust
let cpi_ctx = CpiContext::new(System::id(), cpi_accounts);
```

`withdraw` and `close` take lamports out of a PDA. No private key exists for a PDA, so the
program proves authority by handing the runtime the seeds that derive the address:

```rust
let seeds = &[b"vault", self.vault_state.to_account_info().key.as_ref(), &[self.vault_state.vault_bump]];
let cpi_ctx = CpiContext::new_with_signer(System::id(), cpi_accounts, &[&seeds[..]]);
```

The runtime re-derives the address from those seeds. If it matches the account being
debited, the invoking program counts as its signer. Since the seeds contain the user's
public key, only that user's vault can ever be derived, which is why two users can never
reach each other's funds.

One sharp edge, inherited from the original design. The `vault` is a system account, so it
must end every transaction either empty or rent-exempt. Withdrawing an amount that leaves
it holding between 1 and 890,879 lamports fails with `insufficient funds for rent`.
Draining it completely is what `close` is for.

### State over time

```
(nothing)
   | initialize      vault_state created, bumps stored, vault at 0 lamports
   v
   | deposit(1 SOL)  vault holds 1 SOL
   v
   | withdraw(0.5)   vault holds 0.5 SOL, user up 0.5,
   |                 application_account created (once only)
   v
   | close           vault drained, vault_state closed, rent refunded
   v
(nothing. initialize can run again, registration cannot)
```

## The CPI

`withdraw` shipped with two accounts it never used, `application_account` and
`application_program`. The change wires them into a cross-program invocation to the
registration program's `initialize`, which records a GitHub handle.

The interface comes from [`idls/registration.json`](idls/registration.json).
`declare_program!` reads that IDL at compile time and generates typed Rust bindings, so
the call is checked by the compiler instead of being assembled by hand:

```rust
declare_program!(registration);
use registration::cpi::{accounts::Initialize, initialize};
```

The added call, in [`withdraw.rs`](programs/pre-req-vault/src/instructions/withdraw.rs):

```rust
let registration_accounts = Initialize {
    user: self.user.to_account_info(),
    account: self.application_account.to_account_info(),
    system_program: self.system_program.to_account_info(),
};

let registration_ctx = CpiContext::new(self.application_program.key(), registration_accounts);

initialize(registration_ctx, GITHUB_USERNAME.to_string())?;
```

Two details.

**There is no `with_signer` on this call.** The transfer above it needs one because it
debits a PDA. This one does not. `user` already signed the outer transaction and a
signature propagates down through invokes, so the registration program can use it as the
payer for its `init`. The `application_account` belongs to the registration program, which
signs for its own account's creation internally.

**Anchor 1.x takes a `Pubkey`, not an `AccountInfo`.** The signature here is
`CpiContext::new(program_id: Pubkey, accounts: T)`, hence `self.application_program.key()`.
Anchor 0.2x took an `AccountInfo`, which is what most tutorials online still show.

The GitHub handle is a `#[constant]` in
[`constants.rs`](programs/pre-req-vault/src/constants.rs) rather than an instruction
argument. That keeps the `withdraw` signature unchanged, and with it the provided tests.

### The call tree on-chain

Logs from the devnet withdrawal linked at the top of this file. The bracketed numbers are
invocation depth. `TRBZ…` sitting at depth `[2]` underneath `HZbx…` is what shows the
registration went through this program rather than a direct call to theirs.

```
Program HZbxjG93btfbrLs9r55hDSg3et4tX3Ktm5uLAVJjwmsw invoke [1]
Program log: Instruction: Withdraw
Program 11111111111111111111111111111111 invoke [2]
Program 11111111111111111111111111111111 success
Program TRBZyQHB3m68FGeVsqTK39Wm4xejadjVhP5MAZaKWDM invoke [2]
Program log: Instruction: Initialize
Program 11111111111111111111111111111111 invoke [3]
Program 11111111111111111111111111111111 success
Program TRBZyQHB3m68FGeVsqTK39Wm4xejadjVhP5MAZaKWDM consumed 12966 of 184781 compute units
Program TRBZyQHB3m68FGeVsqTK39Wm4xejadjVhP5MAZaKWDM success
Program log: Registered GitHub handle `Anshumancanrock`
Program HZbxjG93btfbrLs9r55hDSg3et4tX3Ktm5uLAVJjwmsw consumed 28918 of 200000 compute units
Program HZbxjG93btfbrLs9r55hDSg3et4tX3Ktm5uLAVJjwmsw success
```

Depth `[2]` is the transfer and the registration call. Depth `[3]` is the registration
program creating its own PDA.

### withdraw only works once

The registration program creates the account with `init`, and the CPI is unconditional.
So `withdraw` succeeds exactly once per wallet. Every later call reverts when the inner
`init` hits an account that already exists.

That is not visible in the diff, so I measured what it costs. Deposit 2 SOL, withdraw 0.5,
then try again:

```
deposited. vault = 2 SOL
withdraw #1 OK (registered). vault = 1.5 SOL
withdraw #2 FAILED as predicted
still in vault: 1.5 SOL
close OK. vault now = 0
user recovered 1.50095548 SOL -> funds NOT trapped
```

The vault degrades from "deposit and withdraw freely" to "deposit, withdraw once, then
close". Nothing gets stranded, because `close` performs no CPI and still drains the
balance and refunds the rent.

I left the call unconditional on purpose. Wrapping it in
`if self.application_account.data_is_empty()` would keep `withdraw` reusable, but the task
asks for a CPI to `initialize` on withdraw, and skipping it based on account state would
make the instruction behave differently depending on history without saying so. Failing
loudly is easier to reason about, and `close` is the intended exit anyway.

### The test now checks the CPI, not just balances

The provided withdraw test only asserted balances. I built a copy of the program with the
`initialize` call stripped out and ran it against that: three tests green, no complaint.
The test could not detect a missing CPI, which is the one thing this task is about.

It now decodes the `ApplicationAccount` after the withdrawal and checks the recorded user
and handle. The expected handle is read from the IDL rather than hardcoded a second time,
since Anchor surfaces `#[constant]` values there, so the assertion compares the chain
against the program's own source:

```
✔ Initialize the vault
✔ Deposilt 1 Sol in to the vault
    registered github: Anshumancanrock
✔  Withdraw 0.5 Sol from the vault
✔  Close the vault and withdraw all the funds
```

Against the CPI-less build the same assertion fails with `the CPI did not create the
application account: expected null not to be null`.

The `confirmTx(tx)` calls in deposit, withdraw and close were also missing their `await`,
which races the balance reads on a real cluster.

## Running it

### Prerequisites

```bash
sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"
cargo install --git https://github.com/solana-foundation/anchor avm --force
avm install 1.1.2 && avm use 1.1.2
npm i -g pnpm
```

### Build and deploy

```bash
pnpm install
anchor build
anchor keys sync          # required on a fresh clone, see below
solana config set --url devnet
solana airdrop 3
anchor deploy
anchor test --skip-deploy
```

Budget roughly 2.3 SOL: 1.24 for the program account's rent, about 0.03 for the on-chain
IDL, and 1 SOL of working capital for the deposit test, which comes back at `close`.

`scripts/deploy-devnet.sh` runs that whole sequence with guard rails. It refuses to start
if the wallet is already registered, reports buffers stranded by an earlier failed deploy,
and passes `--use-rpc` so the chunk writes go through the RPC rather than validator TPUs,
which is the usual failure mode behind home NAT.

> **A fresh clone cannot deploy this program as-is.** The program keypair lives under
> `target/`, which is gitignored, as keypairs should be. So `anchor build` on a fresh clone
> mints a new one. You end up with a build whose IDL advertises `HZbxjG93…wmsw` (taken
> from `declare_id!`) while `anchor deploy` targets the address it just generated. The
> tests follow the IDL, so they would talk to the already deployed program while your SOL
> paid for an orphan copy elsewhere, and everything would appear to pass. Run
> `anchor keys sync` first so both point at your own key.
>
> To verify this submission rather than rebuild it, use the explorer links at the top.

Confirm the registration landed:

```bash
pnpm exec ts-node scripts/check-registration.ts
```

It reads the `ApplicationAccount` PDA straight off the cluster and decodes it:

```
applicationAccount:  BcuKkq7a5X1SgEJf6tGWcTuMGnuhFdCTdRB2N9jEYqpH
owner:               TRBZyQHB3m68FGeVsqTK39Wm4xejadjVhP5MAZaKWDM
REGISTERED: { user: '2Qx5…AFia', bump: 252, preReqTs: false, preReqRs: false, github: 'Anshumancanrock' }
```

### Rehearsing locally

Since the devnet run is one-shot, I tested against a local validator with the real
registration program cloned into it:

```bash
solana-test-validator --reset \
  --url https://api.devnet.solana.com \
  --clone-upgradeable-program TRBZyQHB3m68FGeVsqTK39Wm4xejadjVhP5MAZaKWDM

anchor test --provider.cluster localnet --skip-local-validator
```

That runs against the genuine registration bytecode instead of a mock, so a pass locally
means the CPI is actually correct. Use a fresh wallet per run (`--provider.wallet <path>`)
or `--reset` the validator, because the one-registration rule applies locally too.

## Known issues

**`pnpm lint` fails, and did before this change.** The repo pins `prettier@^2`, whose
`trailingComma` default is `es5`, but the existing sources were formatted by prettier 3
with `trailingComma: all`. The starter's lint script rejects the starter's own files.
Reformatting for prettier 2 would strip trailing commas across code I did not write, so I
matched the existing style instead. A `.prettierrc` setting `"trailingComma": "all"` fixes
it properly.

**The LiteSVM test is commented out.** `programs/pre-req-vault/tests/test_initialize.rs`
arrived fully commented, so `cargo test` compiles and runs zero tests. Reviving it would
also mean loading the registration program into LiteSVM, and the brief says to focus on
the TypeScript tests, so I left it as found.

**Dead template scaffolding.** `constants.rs` still carries `COUNTER_SEED`,
`HELLO_WORLD_LAMPORTS` and `MAX_COUNT`, and `error.rs` two counter errors, all leftovers
from whatever template this came from. Deleting them is correct but it is a separate
change, and I would rather submit a diff that does one thing.

**The program registers anyone who calls it, under my handle.** The GitHub name is a
compile-time constant, so any wallet that finds the deployed program and calls `withdraw`
gets recorded as `Anshumancanrock`. It costs the caller their own one-time registration
and gains them nothing, and it follows from the design the task specifies, so I have not
defended against it. It is still a real property of hardcoding the value instead of taking
it as an instruction argument.

## Layout

```
programs/pre-req-vault/src/
  lib.rs                    program entrypoints
  state.rs                  VaultState
  constants.rs              GITHUB_USERNAME
  instructions/
    initialize.rs           create vault_state, cache bumps
    deposit.rs              user to vault
    withdraw.rs             vault to user, then the registration CPI
    close.rs                drain vault, close vault_state
idls/registration.json      registration interface, read by declare_program!
tests/pre-req-vault.ts      integration tests
scripts/check-registration.ts
scripts/deploy-devnet.sh
docs/                       architecture diagram
```
