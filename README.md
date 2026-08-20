# pre-req-vault

An Anchor SOL vault. The `withdraw` instruction was extended so that withdrawing also
registers the caller with Turbin3's registration program through a CPI.

| | |
|---|---|
| Vault program | [`HZbxjG93btfbrLs9r55hDSg3et4tX3Ktm5uLAVJjwmsw`](https://explorer.solana.com/address/HZbxjG93btfbrLs9r55hDSg3et4tX3Ktm5uLAVJjwmsw?cluster=devnet) |
| Registration tx | [`43uiqRQi…dmdj93sC`](https://explorer.solana.com/tx/43uiqRQiTCEp4sgENZzZ9DYEgmXsPxpwtyQZKSg5W26Zh9ryE7fhVLHXyjrQKbmE3TchVGt2krbwSf8gdmdj93sC?cluster=devnet) |
| GitHub handle recorded | `Anshumancanrock` |
| Cluster | devnet, Anchor 1.1.2 |

## The CPI

```rust
let registration_accounts = Initialize {
    user: self.user.to_account_info(),
    account: self.application_account.to_account_info(),
    system_program: self.system_program.to_account_info(),
};

let registration_ctx = CpiContext::new(self.application_program.key(), registration_accounts);

initialize(registration_ctx, GITHUB_USERNAME.to_string())?;
```

Full file: [`withdraw.rs`](programs/pre-req-vault/src/instructions/withdraw.rs). Two things
that are easy to get wrong here:

**No `with_signer`.** The SOL transfer just above it needs one, because it debits a PDA.
This call does not. `user` already signed the outer transaction and that signature
propagates through the invoke, so the registration program can use it as the payer for
its `init`.

**Anchor 1.x takes a `Pubkey`, not an `AccountInfo`.** The signature is
`CpiContext::new(program_id: Pubkey, accounts: T)`, hence `.key()`. Most tutorials still
show the old 0.2x form.

The handle is a `#[constant]` rather than an instruction argument, which leaves the
`withdraw` signature and the provided tests unchanged.

### Proof it ran

From the devnet transaction linked above. Bracketed numbers are invocation depth, so
`TRBZ…` at `[2]` underneath `HZbx…` is the registration happening *inside* this program
rather than as a direct call:

```
Program HZbxjG93btfbrLs9r55hDSg3et4tX3Ktm5uLAVJjwmsw invoke [1]
Program log: Instruction: Withdraw
Program 11111111111111111111111111111111 invoke [2]
Program 11111111111111111111111111111111 success
Program TRBZyQHB3m68FGeVsqTK39Wm4xejadjVhP5MAZaKWDM invoke [2]
Program log: Instruction: Initialize
Program 11111111111111111111111111111111 invoke [3]
Program 11111111111111111111111111111111 success
Program TRBZyQHB3m68FGeVsqTK39Wm4xejadjVhP5MAZaKWDM success
Program log: Registered GitHub handle `Anshumancanrock`
Program HZbxjG93btfbrLs9r55hDSg3et4tX3Ktm5uLAVJjwmsw success
```

## How the vault works

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/architecture-dark.png">
  <img src="docs/architecture-light.png" alt="Architecture diagram: the user signs a transaction to the pre-req-vault program, which owns the vault_state and vault PDAs, invokes the System Program to move lamports, and invokes the registration program to create the application account.">
</picture>

Every wallet gets its own vault. There is no admin key and no access-control check, because
both addresses are PDAs derived from seeds containing the user's public key, so only that
user's vault can ever be derived.

Three accounts:

- **`vault_state`**, seeds `["state", user]`. Stores the two bumps so later instructions
  read them back instead of re-deriving, which costs compute.
- **`vault`**, seeds `["vault", vault_state]`. Holds the lamports. Seeded by the
  *vault_state address*, not the user's key, so derivation chains user to state to vault.
- **`application_account`**, seeds `["prereqs", user]`, owned by the registration program.
  Created by the CPI. This program only passes it through.

The four instructions are `initialize`, `deposit`, `withdraw` and `close`. The distinction
that matters is who authorises each SOL movement. `deposit` moves lamports out of the
user's own wallet, so their signature is enough. `withdraw` and `close` move lamports out
of a PDA, which has no private key, so the program proves authority by passing the seeds
that derive the address:

```rust
CpiContext::new_with_signer(System::id(), cpi_accounts, &[&seeds[..]])
```

[`docs/architecture.html`](docs/architecture.html) has the full diagram with the account
derivations and call tree drawn out.

## Running it

```bash
pnpm install
anchor build
anchor keys sync          # required on a fresh clone, see Notes
solana config set --url devnet
solana airdrop 3          # ~2.3 SOL is actually needed
anchor deploy
anchor test --skip-deploy
```

Or `./scripts/deploy-devnet.sh`, which does the same with guard rails: it stops if the
wallet is already registered, reports buffers stranded by a failed deploy, and passes
`--use-rpc` so the chunk writes avoid validator TPUs.

Check the result with `pnpm exec ts-node scripts/check-registration.ts`, which decodes the
`ApplicationAccount` straight off the cluster.

To rehearse without spending the one-shot registration, run a local validator with the
real registration program cloned into it:

```bash
solana-test-validator --reset \
  --url https://api.devnet.solana.com \
  --clone-upgradeable-program TRBZyQHB3m68FGeVsqTK39Wm4xejadjVhP5MAZaKWDM

anchor test --provider.cluster localnet --skip-local-validator
```

That tests against the genuine registration bytecode instead of a mock.

## Notes

**`withdraw` only works once per wallet.** The registration program creates the account
with `init` and the CPI is unconditional, so every later `withdraw` reverts. I checked
whether that traps funds: it does not, because `close` performs no CPI and still drains
the vault and refunds the rent. Guarding the CPI with `data_is_empty()` would keep
`withdraw` reusable, but then the instruction would silently behave differently depending
on history, so I left it failing loudly.

**The test now checks the CPI, not just balances.** The provided test asserted balances
only. I built a copy of the program with the CPI stripped out and it still passed, so the
test could not detect the one thing this task is about. It now decodes the
`ApplicationAccount` and compares the handle against the constant in the IDL.

**A fresh clone cannot deploy this as-is.** The program keypair lives under gitignored
`target/`, so `anchor build` mints a new one. The IDL would still advertise the deployed
address while `anchor deploy` targets the new key, and the tests follow the IDL, so
everything would appear to pass while your SOL paid for an orphan copy. Run
`anchor keys sync` first.

**Left as found:** `pnpm lint` fails because the repo pins prettier 2 while the sources
were formatted by prettier 3. The LiteSVM test in `test_initialize.rs` ships fully
commented out, so `cargo test` runs zero tests. `constants.rs` and `error.rs` still carry
unrelated counter scaffolding from the original template.

**The handle is hardcoded**, so any wallet calling this deployed program gets registered as
`Anshumancanrock`. It costs the caller their own registration and gains them nothing, and
it follows from the design the task specifies.
