use crate::constants::GITHUB_USERNAME;
use crate::state::VaultState;
use anchor_lang::{
    prelude::*,
    system_program::{transfer, Transfer},
};

declare_program!(registration);

use registration::cpi::{accounts::Initialize, initialize};

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut)]
    pub user: Signer<'info>,

    #[account(
    mut,
    seeds = [b"vault", vault_state.key().as_ref()],
    bump = vault_state.vault_bump,
  )]
    pub vault: SystemAccount<'info>,

    #[account(
    seeds = [b"state", user.key().as_ref()],
    bump = vault_state.state_bump
  )]
    pub vault_state: Account<'info, VaultState>,

    /// CHECK: application account will be initialized by the cpi call to the application program
    #[account(
    mut,
    seeds = [b"prereqs", user.key().as_ref()],
    seeds::program = application_program.key(),
    bump
    )]
    pub application_account: UncheckedAccount<'info>,

    pub application_program: Program<'info, registration::program::Q3PreReqsRs>,

    system_program: Program<'info, System>,
}

impl<'info> Withdraw<'info> {
    pub fn withdraw(&mut self, amount: u64) -> Result<()> {
        let cpi_accounts = Transfer {
            from: self.vault.to_account_info(),
            to: self.user.to_account_info(),
        };

        let seeds = &[
            b"vault",
            self.vault_state.to_account_info().key.as_ref(),
            &[self.vault_state.vault_bump],
        ];

        let signer_seeds = &[&seeds[..]];

        let cpi_ctx = CpiContext::new_with_signer(System::id(), cpi_accounts, signer_seeds);

        transfer(cpi_ctx, amount)?;

        // Register the caller with the application program. Unlike the transfer above this
        // needs no `with_signer`: `user` already signed the outer transaction and that
        // signature carries through the invoke, and `application_account` is a PDA of the
        // registration program, which signs for its own creation internally.
        let registration_accounts = Initialize {
            user: self.user.to_account_info(),
            account: self.application_account.to_account_info(),
            system_program: self.system_program.to_account_info(),
        };

        let registration_ctx =
            CpiContext::new(self.application_program.key(), registration_accounts);

        initialize(registration_ctx, GITHUB_USERNAME.to_string())?;

        msg!("Registered GitHub handle `{}`", GITHUB_USERNAME);

        Ok(())
    }
}
