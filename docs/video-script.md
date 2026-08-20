# Video

Share `docs/diagram.png` full screen. Do not open `diagram.html` — it is not in the repo.

Talk from the beats. Point at the box you are naming. If a practice run is over 2:50, drop the deposit/withdraw contrast to one sentence.

Unlisted or Public. Captions on. Cut if the file is over 3:00.

---

**0:00 — program box**

Hi, I'm Anshuman. This is my vault program. Each wallet gets its own SOL vault. I extended withdraw so a successful withdrawal also registers me with Turbin3's registration program through a CPI.

**0:15 — user, then the four names on the program box**

The user wallet at the top is the only signer. Four instructions: initialize, deposit, withdraw, close. The program is just code. State lives in the accounts.

**0:35 — vault_state, then vault**

vault_state is a PDA, seeds `state` plus the user. It stores the bumps. vault is a PDA, seeds `vault` plus vault_state. That's where the SOL sits. The user's key is in those seeds, so you cannot derive someone else's vault.

**1:00 — System Program**

Deposit moves SOL from the user into the vault. That spends from their wallet, so their signature is enough. Withdraw and close spend from the vault, which has no private key, so the program signs with the vault seeds and calls the System Program.

**1:25 — registration, then application_account**

What I added is on withdraw. First the transfer, signed by the vault. Then a CPI to the registration program's initialize, with the handle Anshumancanrock. That creates application_account, seeds `prereqs` plus the user. That second call needs no extra signer — the user already signed the transaction. If the CPI fails, the whole withdraw reverts.

**1:55 — close edge on vault_state**

Registration uses `init`, and I always call it, so withdraw works once per wallet. Close does not do that CPI, so leftover SOL still comes out. That's the flow.

---

YouTube Studio → Subtitles → Add → paste the spoken text → Auto-sync. Read the captions once.
