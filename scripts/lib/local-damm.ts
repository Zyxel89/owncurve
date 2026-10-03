// Solo para CLUSTER=local: crea una config de DAMM v2 apta para migraciones de DBC
// (en devnet/mainnet Meteora ya las tiene creadas; ver DAMM_V2_MIGRATION_FEE_ADDRESS).
// Requisitos que valida DBC para el modo Customizable: pool_creator_authority = pool authority de DBC.
import { BN } from "@anchor-lang/core";
import { createDammV2Program, deriveDbcPoolAuthority } from "@meteora-ag/dynamic-bonding-curve-sdk";
import { PublicKey, SystemProgram } from "@solana/web3.js";
import type { Net } from "./net";

const DAMM_V2 = new PublicKey("cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG");

export async function createLocalDammV2Config(net: Net): Promise<PublicKey> {
  const program = createDammV2Program(net.conn) as any;
  const admin = net.payer.publicKey;
  const [operator] = PublicKey.findProgramAddressSync([Buffer.from("operator"), admin.toBuffer()], DAMM_V2);
  const index = new BN(7);
  const [config] = PublicKey.findProgramAddressSync([Buffer.from("config"), index.toArrayLike(Buffer, "le", 8)], DAMM_V2);
  if (await net.conn.getAccountInfo(config)) return config;

  const createOperator = await program.methods
    .createOperatorAccount(new BN(1)) // permiso CreateConfigKey
    .accountsPartial({
      operator,
      whitelistedAddress: admin,
      signer: admin,
      payer: admin,
      systemProgram: SystemProgram.programId,
    })
    .instruction();

  // DBC en modo Customizable migra con initialize_pool_with_dynamic_config → config "dinámica".
  const createConfig = await program.methods
    .createDynamicConfig(index, {
      poolCreatorAuthority: deriveDbcPoolAuthority(),
      permission: new BN(1), // CreatePoolWithoutMintValidation
    })
    .accountsPartial({ config, operator, payer: admin, signer: admin })
    .instruction();

  await net.send("damm_v2 operator + config (local)", [createOperator, createConfig], []);
  return config;
}
