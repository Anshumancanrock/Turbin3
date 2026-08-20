/**
 * pnpm exec ts-node scripts/check-registration.ts [cluster-url] [wallet-pubkey]
 */
import { Connection, PublicKey, Keypair } from "@solana/web3.js";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

const REGISTRATION_PROGRAM = new PublicKey(
  "TRBZyQHB3m68FGeVsqTK39Wm4xejadjVhP5MAZaKWDM",
);

function applicationAccountDiscriminator(): number[] {
  const idl = JSON.parse(
    fs.readFileSync(path.join(__dirname, "../idls/registration.json"), "utf8"),
  );
  return idl.accounts.find((a) => a.name === "ApplicationAccount").discriminator;
}

// 8 disc | 32 user | 1 bump | 1 ts | 1 rs | 4 len + github
function decodeApplicationAccount(data: Buffer) {
  const expected = Buffer.from(applicationAccountDiscriminator());
  if (!data.subarray(0, 8).equals(expected)) {
    throw new Error(
      `not an ApplicationAccount: discriminator was [${[...data.subarray(0, 8)]}], ` +
        `expected [${[...expected]}]`,
    );
  }

  const githubLen = data.readUInt32LE(43);
  return {
    user: new PublicKey(data.subarray(8, 40)).toBase58(),
    bump: data.readUInt8(40),
    preReqTs: data.readUInt8(41) === 1,
    preReqRs: data.readUInt8(42) === 1,
    github: data.subarray(47, 47 + githubLen).toString("utf8"),
  };
}

async function main() {
  const url = process.argv[2] ?? "https://api.devnet.solana.com";

  let user: PublicKey;
  if (process.argv[3]) {
    user = new PublicKey(process.argv[3]);
  } else {
    const keypairPath = path.join(os.homedir(), ".config/solana/id.json");
    const secret = Uint8Array.from(
      JSON.parse(fs.readFileSync(keypairPath, "utf8")),
    );
    user = Keypair.fromSecretKey(secret).publicKey;
  }

  const [applicationAccount] = PublicKey.findProgramAddressSync(
    [Buffer.from("prereqs"), user.toBuffer()],
    REGISTRATION_PROGRAM,
  );

  console.log(`cluster:             ${url}`);
  console.log(`wallet:              ${user.toBase58()}`);
  console.log(`applicationAccount:  ${applicationAccount.toBase58()}`);

  const info = await new Connection(url, "confirmed").getAccountInfo(
    applicationAccount,
  );

  if (!info) {
    console.log("\nNOT REGISTERED — the account does not exist on this cluster.");
    process.exit(1);
  }

  console.log(`owner:               ${info.owner.toBase58()}`);
  console.log("\nREGISTERED:");
  console.log(decodeApplicationAccount(info.data));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
