import fs from "fs";
import path from "path";

// ====================================================================
// ALTERNATIVA MODERNA A __dirname COMPATIBLE CON TYPESCRIPT ESTRICTO
// ====================================================================
const ROOT_DIR = process.cwd();

const BROADCAST_PATH = path.join(
    ROOT_DIR,
    "broadcast",
    "DeployAll.s.sol",
    "421614",
    "run-latest.json",
);
const OUT_PATH = path.join(ROOT_DIR, "contracts", "out");
const FRONTEND_DESTINATION_PATH = path.join(
    ROOT_DIR,
    "frontend",
    "src",
    "contracts",
);
const OUTPUT_FILE_PATH = path.join(
    FRONTEND_DESTINATION_PATH,
    "deployedContracts.ts",
);

const TARGET_CONTRACTS = [
    "CrownPropertyCollection",
    "CrownPropertyMarketplace",
    "CrownPropertyToken",
    "Presale",
];

const CHAIN_ID = "421614"; // Arbitrum Sepolia

function syncContracts() {
    console.log("🔄 Sincronizando artefactos Web3 para tu Frontend Next.js...");

    // Asegurar que la carpeta destino en Next.js exista
    if (!fs.existsSync(FRONTEND_DESTINATION_PATH)) {
        fs.mkdirSync(FRONTEND_DESTINATION_PATH, {recursive: true});
    }

    const addresses: Record<string, Record<string, string>> = {[CHAIN_ID]: {}};
    const abis: Record<string, any> = {};

    // ==========================================
    // 1. LEER DIRECCIONES (Broadcast de Foundry)
    // ==========================================
    if (!fs.existsSync(BROADCAST_PATH)) {
        console.error(
            `❌ Error: No se encontró el historial de despliegue en: ${BROADCAST_PATH}`,
        );
        console.error(
            "Por favor, asegúrate de haber ejecutado tu script de despliegue on-chain primero.",
        );
        throw new Error("Broadcast file missing"); // Alternativa limpia y estándar a process.exit()
    }

    const broadcastData = JSON.parse(fs.readFileSync(BROADCAST_PATH, "utf8"));

    broadcastData.transactions.forEach((tx: any) => {
        if (
            tx.transactionType === "CREATE" &&
            TARGET_CONTRACTS.includes(tx.contractName)
        ) {
            addresses[CHAIN_ID][tx.contractName] = tx.contractAddress;
        }
    });

    console.log("✅ Direcciones capturadas desde Foundry Broadcast.");

    // ==========================================
    // 2. LEER ABIS (Compilación de Forge)
    // ==========================================
    TARGET_CONTRACTS.forEach((contractName) => {
        const artifactPath = path.join(
            OUT_PATH,
            `${contractName}.sol`,
            `${contractName}.json`,
        );

        if (fs.existsSync(artifactPath)) {
            const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
            abis[contractName] = artifact.abi;
        } else {
            console.warn(
                `⚠️ Advertencia: Falta el artefacto de compilación para ${contractName} en ${artifactPath}`,
            );
        }
    });

    console.log("✅ ABIs procesados y limpiados.");

    // ==========================================
    // 3. GENERAR EL ARCHIVO TYPESCRIPT ESTRICTO
    // ==========================================
    const typescriptTemplate = `// ====================================================================
// ARCHIVO GENERADO AUTOMÁTICAMENTE POR SYNC-CONTRACTS.TS
// NO LO EDITES MANUALMENTE - SE SOBREESCRIBIRÁ EN CADA DEPLOY
// ====================================================================

export const CONTRACT_ADDRESSES = ${JSON.stringify(addresses, null, 2)} as const;

export const ABIS = ${JSON.stringify(abis, null, 2)} as const;

// Tipados de utilidad para desarrollo estricto en Next.js + Wagmi/Viem
export type SupportedChainId = keyof typeof CONTRACT_ADDRESSES;
export type ContractName = keyof typeof ABIS;
`;

    fs.writeFileSync(OUTPUT_FILE_PATH, typescriptTemplate, "utf8");
    console.log(
        `🚀 Éxito: Artefactos inyectados correctamente en tu aplicación:\n👉 ${OUTPUT_FILE_PATH}\n`,
    );
}

syncContracts();
