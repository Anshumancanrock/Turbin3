use anchor_lang::prelude::*;

#[constant]
pub const COUNTER_SEED: &[u8] = b"counter";

#[constant]
pub const HELLO_WORLD_LAMPORTS: u64 = 1;

#[constant]
pub const MAX_COUNT: u64 = 10;

/// GitHub handle recorded in the registration program's ApplicationAccount by
/// the CPI in `withdraw`. The registration program creates that account with
/// `init`, so it can only ever be written once per wallet.
#[constant]
pub const GITHUB_USERNAME: &str = "Anshumancanrock";
