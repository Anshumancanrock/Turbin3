use anchor_lang::prelude::*;

#[constant]
pub const COUNTER_SEED: &[u8] = b"counter";

#[constant]
pub const HELLO_WORLD_LAMPORTS: u64 = 1;

#[constant]
pub const MAX_COUNT: u64 = 10;

/// GitHub handle recorded in the registration program's ApplicationAccount by
/// the CPI in `withdraw`. That program creates the account with `init`, so the
/// account exists once per wallet and a second `withdraw` fails. Its IDL also
/// exposes `update(github)`, so treat the account as create-once, not the
/// string as write-once.
#[constant]
pub const GITHUB_USERNAME: &str = "Anshumancanrock";
