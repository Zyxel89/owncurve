#!/usr/bin/env bash
# =============================================================================
#  OwnCurve — script de trabajo (se sobreescribe en cada entrega)
#  Fase actual: F4  Producto: interfaz web   (no gasta SOL)
#    4.1 base: Vite + React + wallets (Phantom/Solflare/Backpack) + wallet de prueba
#    4.2 lanzar un raise desde un formulario
#    4.3 página del raise: bóveda de tramos, cifras, garantías verificadas en cadena
#    4.4 acciones: comprar, pasar a tesorería, pedir/objetar/liquidar tramo, desbloquear, redimir
#
#  Uso:   cd ~/owncurve && bash owncurve.sh
#  Al final deja la app corriendo en http://localhost:5173 (Ctrl+C para pararla).
#  Para volver a abrirla otro día:  cd ~/owncurve && npm run app
#  Log: ~/owncurve/logs/F4.log
# =============================================================================
set -Eeuo pipefail

PHASE="F4"
REPO_DIR="$HOME/owncurve"
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$PHASE.log"
: > "$LOG"

G='\033[1;32m'; R='\033[1;31m'; Y='\033[1;33m'; B='\033[1;34m'; N='\033[0m'
ok()   { echo -e "${G}  ✔ $*${N}"; }
warn() { echo -e "${Y}  ! $*${N}"; }
fail() { echo -e "${R}  ✘ $*${N}"; echo -e "${R}    Revisa el log: $LOG${N}"; exit 1; }
step() { echo -e "\n${B}==> $*${N}"; }
run()  {
  local desc="$1"; shift
  echo "+ $*" >> "$LOG"
  if "$@" >> "$LOG" 2>&1; then ok "$desc"; else fail "$desc"; fi
}
trap 'echo -e "${R}Error inesperado en la línea $LINENO. Log: $LOG${N}"' ERR

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
export PATH="$HOME/.local/share/solana/install/active_release/bin:$HOME/.avm/bin:$PATH"

echo -e "${B}OwnCurve · $PHASE · $(date '+%Y-%m-%d %H:%M')${N}"

# =============================================================================
step "1/7 Comprobaciones"
# =============================================================================
for t in solana anchor cargo node npm jq git; do
  command -v "$t" >/dev/null 2>&1 || fail "Falta '$t'. Abre una terminal nueva o 'source ~/.zshrc'"
done
cd "$REPO_DIR"
[ -f target/deploy/owncurve-keypair.json ] || fail "Falta la clave del programa. Ejecuta F1.1"
[ -f scripts/demo.ts ] || fail "Falta el código de F3. Ejecuta primero el script de F3"
ok "Repo listo · node $(node -v)"

# =============================================================================
step "2/7 Código de la interfaz (app/) y cliente compartido"
# =============================================================================
mkdir -p app/src/lib app/src/components app/src/pages tests/e2e scripts/lib
cat > 'package.json' <<'OWNCURVE_EOF'
{
  "name": "owncurve",
  "private": true,
  "type": "commonjs",
  "scripts": {
    "f1": "tsx scripts/f1.ts --migrate",
    "demo": "tsx scripts/demo.ts",
    "test": "CLUSTER=local tsx --test tests/owncurve.test.ts",
    "e2e": "tsx tests/e2e/ui.e2e.ts",
    "app": "vite --config app/vite.config.ts",
    "app:build": "vite build --config app/vite.config.ts"
  },
  "dependencies": {
    "@anchor-lang/core": "1.2.0",
    "@fontsource-variable/bricolage-grotesque": "^5.3.0",
    "@fontsource/public-sans": "^5.3.0",
    "@meteora-ag/dynamic-bonding-curve-sdk": "1.5.12",
    "@solana/spl-token": "0.4.15",
    "@solana/wallet-adapter-base": "^0.9.28",
    "@solana/wallet-adapter-react": "^0.15.40",
    "@solana/web3.js": "1.99.0",
    "bn.js": "5.2.5",
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "@types/node": "^22.20.5",
    "@types/react": "^18.3.31",
    "@types/react-dom": "^18.3.7",
    "@vitejs/plugin-react": "^6.1.1",
    "bs58": "^4.0.1",
    "litesvm": "0.1.0",
    "playwright-core": "^1.63.0",
    "tsx": "4.23.15",
    "typescript": "5.9.3",
    "vite": "^8.3.2",
    "vite-plugin-node-polyfills": "^0.28.0"
  }
}
OWNCURVE_EOF

cat > 'package-lock.json' <<'OWNCURVE_EOF'
{
  "name": "owncurve",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "owncurve",
      "dependencies": {
        "@anchor-lang/core": "1.2.0",
        "@fontsource-variable/bricolage-grotesque": "^5.3.0",
        "@fontsource/public-sans": "^5.3.0",
        "@meteora-ag/dynamic-bonding-curve-sdk": "1.5.12",
        "@solana/spl-token": "0.4.15",
        "@solana/wallet-adapter-base": "^0.9.28",
        "@solana/wallet-adapter-react": "^0.15.40",
        "@solana/web3.js": "1.99.0",
        "bn.js": "5.2.5",
        "react": "^18.3.1",
        "react-dom": "^18.3.1"
      },
      "devDependencies": {
        "@types/node": "^22.20.5",
        "@types/react": "^18.3.31",
        "@types/react-dom": "^18.3.7",
        "@vitejs/plugin-react": "^6.1.1",
        "bs58": "^4.0.1",
        "litesvm": "0.1.0",
        "playwright-core": "^1.63.0",
        "tsx": "4.23.15",
        "typescript": "5.9.3",
        "vite": "^8.3.2",
        "vite-plugin-node-polyfills": "^0.28.0"
      }
    },
    "node_modules/@anchor-lang/borsh": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/@anchor-lang/borsh/-/borsh-1.2.0.tgz",
      "integrity": "sha512-qUC90JezAXyetwCqhLxkxh/r9ofRCd2D0fkEoEex7Vurw3pGDtf1r779v0cM4fsvOEIskK9nja/GkZOnlvJqYw==",
      "license": "Apache-2.0",
      "dependencies": {
        "bn.js": "^5.2.3",
        "buffer-layout": "^1.2.0"
      },
      "engines": {
        "node": ">=10"
      },
      "peerDependencies": {
        "@solana/web3.js": "^1.69.1"
      }
    },
    "node_modules/@anchor-lang/core": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/@anchor-lang/core/-/core-1.2.0.tgz",
      "integrity": "sha512-GpHdhYnwVSEIvdZIeRCL7Q9LK0oTyoJ259r4mtc+a3W9oM3Iz6qezorzZcd92ASCJJ6MYqqdrM/b2JKDZpIzmw==",
      "license": "(MIT OR Apache-2.0)",
      "dependencies": {
        "@anchor-lang/borsh": "^1.2.0",
        "@anchor-lang/errors": "^1.2.0",
        "@noble/hashes": "^1.3.1",
        "@solana/web3.js": "^1.69.1",
        "bn.js": "^5.2.3",
        "bs58": "^4.0.1",
        "buffer-layout": "^1.2.2",
        "eventemitter3": "^4.0.7",
        "pako": "^2.0.3",
        "superstruct": "^0.15.4",
        "toml": "^3.0.0"
      },
      "engines": {
        "node": ">=20.18"
      }
    },
    "node_modules/@anchor-lang/errors": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/@anchor-lang/errors/-/errors-1.2.0.tgz",
      "integrity": "sha512-muEmHFs2UDrcmGUuj+IWiYW2/AazI3tMv6f6OT5KNwOuSLG4j9g4zv8Pqvo+Cj9F6deP4P2c6DWhSUBHdYL4+g==",
      "license": "Apache-2.0",
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/@babel/code-frame": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/code-frame/-/code-frame-7.29.7.tgz",
      "integrity": "sha512-Aup7aUOfpbAUg2ROOJN6Iw5f9DMBlzu0mIkm/malLQFN/YQgO48wCj0Kxa3sEHJvPVFg7siR+qRInwXd2qhQKw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/helper-validator-identifier": "^7.29.7",
        "js-tokens": "^4.0.0",
        "picocolors": "^1.1.1"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/compat-data": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/compat-data/-/compat-data-7.29.7.tgz",
      "integrity": "sha512-locTkQyKvwIEgBzVrn8693ebc97F2U8ZHjbXwDXJ5Fn2TCpNwTlKcaKLkdHop5c/icOFE7qt7Q9JC5hnKNa6Gg==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/core": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/core/-/core-7.29.7.tgz",
      "integrity": "sha512-RgHBCvtjbOK2gXSNBNIkNoEc9qoVEtau3hj8gEqKQuL3HZAibKarWFEI3Lfm6EYKkLalOh8eSrj9b+ch9H/VBA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/code-frame": "^7.29.7",
        "@babel/generator": "^7.29.7",
        "@babel/helper-compilation-targets": "^7.29.7",
        "@babel/helper-module-transforms": "^7.29.7",
        "@babel/helpers": "^7.29.7",
        "@babel/parser": "^7.29.7",
        "@babel/template": "^7.29.7",
        "@babel/traverse": "^7.29.7",
        "@babel/types": "^7.29.7",
        "@jridgewell/remapping": "^2.3.5",
        "convert-source-map": "^2.0.0",
        "debug": "^4.1.0",
        "gensync": "^1.0.0-beta.2",
        "json5": "^2.2.3",
        "semver": "^6.3.1"
      },
      "engines": {
        "node": ">=6.9.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/babel"
      }
    },
    "node_modules/@babel/core/node_modules/semver": {
      "version": "6.3.1",
      "resolved": "https://registry.npmjs.org/semver/-/semver-6.3.1.tgz",
      "integrity": "sha512-BR7VvDCVHO+q2xBEWskxS6DJE1qRnb7DxzUrogb71CWoSficBxYsiAGd+Kl0mmq/MprG9yArRkyrQxTO6XjMzA==",
      "license": "ISC",
      "peer": true,
      "bin": {
        "semver": "bin/semver.js"
      }
    },
    "node_modules/@babel/generator": {
      "version": "7.29.8",
      "resolved": "https://registry.npmjs.org/@babel/generator/-/generator-7.29.8.tgz",
      "integrity": "sha512-gZbepsdh3WDtgZKWL+vTPh71LSBrm/Y4/QDZBVCcYfmeTEEuoOYwlSy+G1StfJg+/Zy550u/3TATbm7qDbbMtg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/parser": "^7.29.8",
        "@babel/types": "^7.29.8",
        "@jridgewell/gen-mapping": "^0.3.12",
        "@jridgewell/trace-mapping": "^0.3.28",
        "jsesc": "^3.0.2"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helper-compilation-targets": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-compilation-targets/-/helper-compilation-targets-7.29.7.tgz",
      "integrity": "sha512-wem6WaBj4NaVYVdNhLPPVacES6ZJ+KBBfSkTMD3YZxbP3rm3Di85tJU5ljaUNhaOynt+Aj0xruhYuzQBt8n71g==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/compat-data": "^7.29.7",
        "@babel/helper-validator-option": "^7.29.7",
        "browserslist": "^4.24.0",
        "lru-cache": "^5.1.1",
        "semver": "^6.3.1"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helper-compilation-targets/node_modules/semver": {
      "version": "6.3.1",
      "resolved": "https://registry.npmjs.org/semver/-/semver-6.3.1.tgz",
      "integrity": "sha512-BR7VvDCVHO+q2xBEWskxS6DJE1qRnb7DxzUrogb71CWoSficBxYsiAGd+Kl0mmq/MprG9yArRkyrQxTO6XjMzA==",
      "license": "ISC",
      "peer": true,
      "bin": {
        "semver": "bin/semver.js"
      }
    },
    "node_modules/@babel/helper-globals": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-globals/-/helper-globals-7.29.7.tgz",
      "integrity": "sha512-3nQVUAtvkKH9zahfWgw96Jc/uFOmjACE1kQz82E2lqWmHBgjzbNlsC22nuQTfahmWeQtTq5nQ/4Nnd2A1wj4zA==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helper-module-imports": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-module-imports/-/helper-module-imports-7.29.7.tgz",
      "integrity": "sha512-ejHwrQQYcm9xnTivShn2IDOlIzInN34AXskvq9QicvCtEzq1Vzclu/tKF8Jq1Cg8JG2GL6/EmjgsCT7lXepE3g==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/traverse": "^7.29.7",
        "@babel/types": "^7.29.7"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helper-module-transforms": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-module-transforms/-/helper-module-transforms-7.29.7.tgz",
      "integrity": "sha512-UPUVSyXbOh627KiCIGQSgwWzGeBKLkaJ9PJEdrngIwMSzxLR4jS4+f1f1jb7VzBbg8nFLaYotvVPFCTqdrmTAg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/helper-module-imports": "^7.29.7",
        "@babel/helper-validator-identifier": "^7.29.7",
        "@babel/traverse": "^7.29.7"
      },
      "engines": {
        "node": ">=6.9.0"
      },
      "peerDependencies": {
        "@babel/core": "^7.0.0"
      }
    },
    "node_modules/@babel/helper-string-parser": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-string-parser/-/helper-string-parser-7.29.7.tgz",
      "integrity": "sha512-Pb5ijPrZ89GDH8223L4UP8i6QApWxs04RbPQJTeWDV0/keR2E36MeKnyr6LYmUUvqRRI+Iv87SuF1W6ErINzYw==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helper-validator-identifier": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-validator-identifier/-/helper-validator-identifier-7.29.7.tgz",
      "integrity": "sha512-qehxGkRj55h/ff8EMaJ+cYhyaKlHIxqYDn682wQD7RNp9UujOQsHog2uS0r2vzr4pW+sXf90NeeayjcNaX3fFg==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helper-validator-option": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-validator-option/-/helper-validator-option-7.29.7.tgz",
      "integrity": "sha512-N9ZErrD+yW5geCDtBqnOoxmR8+tNKiGuxKlDpuJxfsqpa2dFcexaziGAE/qoHLiDDreVNMupxGmSoNlyvsA3gw==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helpers": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helpers/-/helpers-7.29.7.tgz",
      "integrity": "sha512-1k2lAGRMfHTcwuNYcCNUmaUffmQv8KWMfh2iJUUeRlwlwH4FdNG7mfPI10NPfLHJFThE4Tyr4mv7kTNZOiPuBg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/template": "^7.29.7",
        "@babel/types": "^7.29.7"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/parser": {
      "version": "7.29.9",
      "resolved": "https://registry.npmjs.org/@babel/parser/-/parser-7.29.9.tgz",
      "integrity": "sha512-CjXrNHTnvqBVqHgdBysY3vk2T8tpJHb5/RMeHJBTyVa9xgugCB0CJTx/3oO8RV2QRQP391RWpB7D6hLjm8V9uA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/types": "^7.29.8"
      },
      "bin": {
        "parser": "bin/babel-parser.js"
      },
      "engines": {
        "node": ">=6.0.0"
      }
    },
    "node_modules/@babel/runtime": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/runtime/-/runtime-7.29.7.tgz",
      "integrity": "sha512-Nq8OhGWiZIZGV6hLHoyAKLLcJihP/xFeBMGJoUrxTX2psI8dCifzLhZISFb+VWS3wFMRDmCGw5R+dOySCqPLhw==",
      "license": "MIT",
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/template": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/template/-/template-7.29.7.tgz",
      "integrity": "sha512-puq+Gf35oI24FeN11LkoUQFqv9uwNeWpxXZi/Ji3rRIoKAzKnxRaZ+Gkj0vKS9ZCiTESfng1N9LyOyXvo+m+Gg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/code-frame": "^7.29.7",
        "@babel/parser": "^7.29.7",
        "@babel/types": "^7.29.7"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/traverse": {
      "version": "7.29.8",
      "resolved": "https://registry.npmjs.org/@babel/traverse/-/traverse-7.29.8.tgz",
      "integrity": "sha512-I5z7H3bf/41ktsNVLtpN0wAa336HkqIHQ5BuPLEhTkt1jVSyZpeNKIzTgEWmlxjdg81R0IgUCcaE+Ok3NvrfZg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/code-frame": "^7.29.7",
        "@babel/generator": "^7.29.8",
        "@babel/helper-globals": "^7.29.7",
        "@babel/parser": "^7.29.8",
        "@babel/template": "^7.29.7",
        "@babel/types": "^7.29.8",
        "debug": "^4.3.1"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/types": {
      "version": "7.29.8",
      "resolved": "https://registry.npmjs.org/@babel/types/-/types-7.29.8.tgz",
      "integrity": "sha512-Vj1jF3cPfxg7OAfoI7QnVKLoILlm2JF9pnVHrX8qx7AHMiYWT+NDAA7jChlNgRS4WTLc/fD1lXLmPixluj+3Gg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/helper-string-parser": "^7.29.7",
        "@babel/helper-validator-identifier": "^7.29.7"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@coral-xyz/anchor": {
      "version": "0.31.1",
      "resolved": "https://registry.npmjs.org/@coral-xyz/anchor/-/anchor-0.31.1.tgz",
      "integrity": "sha512-QUqpoEK+gi2S6nlYc2atgT2r41TT3caWr/cPUEL8n8Md9437trZ68STknq897b82p5mW0XrTBNOzRbmIRJtfsA==",
      "license": "(MIT OR Apache-2.0)",
      "dependencies": {
        "@coral-xyz/anchor-errors": "^0.31.1",
        "@coral-xyz/borsh": "^0.31.1",
        "@noble/hashes": "^1.3.1",
        "@solana/web3.js": "^1.69.0",
        "bn.js": "^5.1.2",
        "bs58": "^4.0.1",
        "buffer-layout": "^1.2.2",
        "camelcase": "^6.3.0",
        "cross-fetch": "^3.1.5",
        "eventemitter3": "^4.0.7",
        "pako": "^2.0.3",
        "superstruct": "^0.15.4",
        "toml": "^3.0.0"
      },
      "engines": {
        "node": ">=17"
      }
    },
    "node_modules/@coral-xyz/anchor-errors": {
      "version": "0.31.1",
      "resolved": "https://registry.npmjs.org/@coral-xyz/anchor-errors/-/anchor-errors-0.31.1.tgz",
      "integrity": "sha512-NhNEku4F3zzUSBtrYz84FzYWm48+9OvmT1Hhnwr6GnPQry2dsEqH/ti/7ASjjpoFTWRnPXrjAIT1qM6Isop+LQ==",
      "license": "Apache-2.0",
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/@coral-xyz/borsh": {
      "version": "0.31.1",
      "resolved": "https://registry.npmjs.org/@coral-xyz/borsh/-/borsh-0.31.1.tgz",
      "integrity": "sha512-9N8AU9F0ubriKfNE3g1WF0/4dtlGXoBN/hd1PvbNBamBNwRgHxH4P+o3Zt7rSEloW1HUs6LfZEchlx9fW7POYw==",
      "license": "Apache-2.0",
      "dependencies": {
        "bn.js": "^5.1.2",
        "buffer-layout": "^1.2.0"
      },
      "engines": {
        "node": ">=10"
      },
      "peerDependencies": {
        "@solana/web3.js": "^1.69.0"
      }
    },
    "node_modules/@esbuild/aix-ppc64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/aix-ppc64/-/aix-ppc64-0.28.2.tgz",
      "integrity": "sha512-XExcO+dvLKvVtNTibSTBej1NCAbaGhWn9Ww1ZPx80qsahhPFe/8jgWP0IchNe0F3HwkU7n8ejhH8bjonqht8mQ==",
      "cpu": [
        "ppc64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "aix"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/android-arm": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/android-arm/-/android-arm-0.28.2.tgz",
      "integrity": "sha512-kXXoiPVVGQcnIYGOeaovwOURpniDBpSq4A03qkQ+BMQqtGG6HYap3xne9C1O1yo4TR3qxlCX5IqqmX6fFo2Lqg==",
      "cpu": [
        "arm"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "android"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/android-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/android-arm64/-/android-arm64-0.28.2.tgz",
      "integrity": "sha512-5YfKeeI8qWfBZIX+u2xZC3Zlb3Os/gLS2sbEKM+I4ZOcsWmHS2WLysCcQZDAFRslDUU5Oiq44gf6PYN1vGwG5A==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "android"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/android-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/android-x64/-/android-x64-0.28.2.tgz",
      "integrity": "sha512-O387ite7SzUyCcy3JQX4P4bLtEA7bLLkx+esve5JHnyYfNTxcVpXZo9jhdB0lTKN44gztELTdU7nS8Nr16Fs1Q==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "android"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/darwin-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/darwin-arm64/-/darwin-arm64-0.28.2.tgz",
      "integrity": "sha512-n4KqkOQrraxHJcgjM1RvwbigfQKIKJVpM7xp+KsxiyUSrRdIXnt73VhrPAx0fV44hgfmIVKjxMN9J1t5jySVkw==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/darwin-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/darwin-x64/-/darwin-x64-0.28.2.tgz",
      "integrity": "sha512-uq6suIWYP37qzGddBKPw5QEQPi6HiLGsO7UmkpfyaYNQ3D+rN6w6WfwH+nuqcGXWvawGwxOEroO4YGnFh95azw==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/freebsd-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/freebsd-arm64/-/freebsd-arm64-0.28.2.tgz",
      "integrity": "sha512-n+I0BTSRIoy+d6RPKnEVwql5UwBJolytvY4mAOIEJorKlqgPII8ix6slVVrfZ5Tnj7glIZvloylbB/EJPMWEXw==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "freebsd"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/freebsd-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/freebsd-x64/-/freebsd-x64-0.28.2.tgz",
      "integrity": "sha512-78XJTJkvPs0kz2w61301PJjXl4g7q3JqiYMZ/M/yVI73EHBrCRTgkhu9oqG7vPqq+a/yadEW8aD+agKlk5xrmg==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "freebsd"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-arm": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-arm/-/linux-arm-0.28.2.tgz",
      "integrity": "sha512-XlDnu2q5yoqems+xay6wSAcg9DDD7K9RLKZEBOMZm3ckNpJBvOX20tSfby8KfrrhINDyv9V2YVZKY/SpoGJI8w==",
      "cpu": [
        "arm"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-arm64/-/linux-arm64-0.28.2.tgz",
      "integrity": "sha512-pW4AC0P3it8c7do9MVM4p51FzHzdM/TZrerurgRcHJ2WTa1VQ1CIq18xncfpBJw4ojkiZZrKW2yIBWBP92j6Ug==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-ia32": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-ia32/-/linux-ia32-0.28.2.tgz",
      "integrity": "sha512-CYbnj78HsIeA+DhgUKgFCfvNsTHFhMMrinUrMZpDXJXKN8T3XViTZ/+wtHeVxEWY8ewSzTFN+nRmSwO2tZaLUQ==",
      "cpu": [
        "ia32"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-loong64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-loong64/-/linux-loong64-0.28.2.tgz",
      "integrity": "sha512-buwkd8nsph4R+ajRvw0qM5Hja/TXQow3ptzWO2EbG/cqcIkHloRrdlBtQlshyYGTNFvfkfJ5tpPLVkY4DtsPfQ==",
      "cpu": [
        "loong64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-mips64el": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-mips64el/-/linux-mips64el-0.28.2.tgz",
      "integrity": "sha512-ZVykbDyk7519VwiNb9Lcj9m8XM6v5V9uKPvrEMkkEedVewf+0itkhahp4HDpgERXhwLRpWFypsGbG/J8s0QjJA==",
      "cpu": [
        "mips64el"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-ppc64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-ppc64/-/linux-ppc64-0.28.2.tgz",
      "integrity": "sha512-CAXl+Dtd9UUuJd8pKKdwh6MLm3MUMiqMPmhZ3tTSXPqfyQ3vDl6R5hZdZ/kYojK4ofXtdfSv1tFq8XzWx3heNQ==",
      "cpu": [
        "ppc64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-riscv64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-riscv64/-/linux-riscv64-0.28.2.tgz",
      "integrity": "sha512-GeXCej4IQtU1B+QlDV8W/RRvbzI3O/Stss+/bCXv4lZls5WGRtu2a+3JkA3i4qIUlMXpcHebWpF8AkJhATowuA==",
      "cpu": [
        "riscv64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-s390x": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-s390x/-/linux-s390x-0.28.2.tgz",
      "integrity": "sha512-3H1weTYZPxt/WOhByszQZybS9w5lKzUn1FDMsgEChbHWQwHYQQRfBxgCcZvPhjHfKyJjIievvMmEUawJrdY9Dg==",
      "cpu": [
        "s390x"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-x64/-/linux-x64-0.28.2.tgz",
      "integrity": "sha512-4xTZr1FUmSoQW4XIWmit3tzQrUTZM+N3P0XV8xROKYF50XfI7xeO90+1bZvNwxIufQ9hDQVRJH5YhgPVF8A/HQ==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/netbsd-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/netbsd-arm64/-/netbsd-arm64-0.28.2.tgz",
      "integrity": "sha512-sSATRjPeDBg3pdgHoQfoYBob11Kk1FGa9lui5RIHZCoCkJa9QKlvl3/vKz2usCmYYjs7ymJR/2Nnsqe+Hjt5nw==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "netbsd"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/netbsd-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/netbsd-x64/-/netbsd-x64-0.28.2.tgz",
      "integrity": "sha512-lqnzCV+mM0gIADaKihiCg6ifgfU2L3h5E33rNQBN1Y4MaVGnzryzmvvf7UHxprpQdE8hpqLolJ9Rl+SkIRDpyw==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "netbsd"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/openbsd-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/openbsd-arm64/-/openbsd-arm64-0.28.2.tgz",
      "integrity": "sha512-AL2qJILH7lNjrDmCQDvdxMfAUIv8KMNZOvrwAQ8i8//ntL9FflhOyMJ8OZSMBb8/AWXe3/5v5S20y3zCoZWKoQ==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "openbsd"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/openbsd-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/openbsd-x64/-/openbsd-x64-0.28.2.tgz",
      "integrity": "sha512-QtiuPytchRyC4rwUKhexJdQKvDuZ6hWloi3igqPQNUJCS1/v9EiO3UTOXR6A3FoMo4fnAKbWJdqaIwhOzh8qEw==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "openbsd"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/openharmony-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/openharmony-arm64/-/openharmony-arm64-0.28.2.tgz",
      "integrity": "sha512-WkhYDmpTjLvGlScA1rwjRUmhl4k8oXR3cIbtqWmELgU/dFeHHlEllxDvdWcNJV9rbzCexB5vz8gtNewWLgCT7Q==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "openharmony"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/sunos-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/sunos-x64/-/sunos-x64-0.28.2.tgz",
      "integrity": "sha512-GPMSkTOtMnv2U2F8gxe4Io6qmVs+YKyp832Etqqxr0hFngmXQ3rzwytelm3GIn7T4VviRUlf3sOgBOiTdvaf7g==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "sunos"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/win32-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/win32-arm64/-/win32-arm64-0.28.2.tgz",
      "integrity": "sha512-PIhhEkE9uPBleRBrQEJpUn7MBnibZzbGzYWPmY3x+YoVg/95zbjB4CxPPOQ8l5tYYM4mMaCthF8/1DIfBQQyWQ==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/win32-ia32": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/win32-ia32/-/win32-ia32-0.28.2.tgz",
      "integrity": "sha512-YmJbfTlvU7Sdn9BB+4PRES4oB6pxgS37MAONj+hBr/cpXS1aBPKXxNnDbu+QCWPj0o9dgyxeq79g6c5P8KeuYA==",
      "cpu": [
        "ia32"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/win32-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/win32-x64/-/win32-x64-0.28.2.tgz",
      "integrity": "sha512-5ebpxr3nWMzrL/rnUI755Jkuee0bHL/Gq0WTF9lvcpv73wAp5eu8MfBUgWK9bhWvZjj7yX8etf/8tI8Ney695g==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@fontsource-variable/bricolage-grotesque": {
      "version": "5.3.0",
      "resolved": "https://registry.npmjs.org/@fontsource-variable/bricolage-grotesque/-/bricolage-grotesque-5.3.0.tgz",
      "integrity": "sha512-TLi9Q4hJjS2UvoTMRSS2nHu6c4R56lAw60NR9QYtVRCHn0XtsFpiEhNffZ8Glsoxu6wEEwLKBP8lb94J52PNBA==",
      "license": "OFL-1.1",
      "funding": {
        "url": "https://github.com/sponsors/ayuhito"
      }
    },
    "node_modules/@fontsource/public-sans": {
      "version": "5.3.0",
      "resolved": "https://registry.npmjs.org/@fontsource/public-sans/-/public-sans-5.3.0.tgz",
      "integrity": "sha512-kjODI0S3zdv0mBYCIQ8TbBayaiqszpc2UbhJiO3bjIqVVXzcWfHSt2o3WBCLOY3juaGaQoy4MoWCcgmfI5hCuA==",
      "license": "OFL-1.1",
      "funding": {
        "url": "https://github.com/sponsors/ayuhito"
      }
    },
    "node_modules/@isaacs/ttlcache": {
      "version": "1.4.1",
      "resolved": "https://registry.npmjs.org/@isaacs/ttlcache/-/ttlcache-1.4.1.tgz",
      "integrity": "sha512-RQgQ4uQ+pLbqXfOmieB91ejmLwvSgv9nLx6sT6sD83s7umBypgg+OIBOBbEUiJXrfpnp9j0mRhYYdzp9uqq3lA==",
      "license": "ISC",
      "peer": true,
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/@jest/schemas": {
      "version": "29.6.3",
      "resolved": "https://registry.npmjs.org/@jest/schemas/-/schemas-29.6.3.tgz",
      "integrity": "sha512-mo5j5X+jIZmJQveBKeS/clAueipV7KgiX1vMgCxam1RNYiqE1w62n0/tJJnHtjW8ZHcQco5gY85jA3mi0L+nSA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@sinclair/typebox": "^0.27.8"
      },
      "engines": {
        "node": "^14.15.0 || ^16.10.0 || >=18.0.0"
      }
    },
    "node_modules/@jest/types": {
      "version": "29.6.3",
      "resolved": "https://registry.npmjs.org/@jest/types/-/types-29.6.3.tgz",
      "integrity": "sha512-u3UPsIilWKOM3F9CXtrG8LEJmNxwoCQC/XVj4IKYXvvpx7QIi/Kg1LI5uDmDpKlac62NUtX7eLjRh+jVZcLOzw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@jest/schemas": "^29.6.3",
        "@types/istanbul-lib-coverage": "^2.0.0",
        "@types/istanbul-reports": "^3.0.0",
        "@types/node": "*",
        "@types/yargs": "^17.0.8",
        "chalk": "^4.0.0"
      },
      "engines": {
        "node": "^14.15.0 || ^16.10.0 || >=18.0.0"
      }
    },
    "node_modules/@jest/types/node_modules/chalk": {
      "version": "4.1.2",
      "resolved": "https://registry.npmjs.org/chalk/-/chalk-4.1.2.tgz",
      "integrity": "sha512-oKnbhFyRIXpUuez8iBMmyEa4nbj4IOQyuhc/wy9kY7/WVPcwIO9VA668Pu8RkO7+0G76SLROeyw9CpQ061i4mA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ansi-styles": "^4.1.0",
        "supports-color": "^7.1.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/chalk/chalk?sponsor=1"
      }
    },
    "node_modules/@jest/types/node_modules/supports-color": {
      "version": "7.2.0",
      "resolved": "https://registry.npmjs.org/supports-color/-/supports-color-7.2.0.tgz",
      "integrity": "sha512-qpCAvRl9stuOHveKsn7HncJRvv501qIacKzQlO/+Lwxc9+0q2wLyv4Dfvt80/DPn2pqOBsJdDiogXGR9+OvwRw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "has-flag": "^4.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/@jridgewell/gen-mapping": {
      "version": "0.3.13",
      "resolved": "https://registry.npmjs.org/@jridgewell/gen-mapping/-/gen-mapping-0.3.13.tgz",
      "integrity": "sha512-2kkt/7niJ6MgEPxF0bYdQ6etZaA+fQvDcLKckhy1yIQOzaoKjBBjSj63/aLVjYE3qhRt5dvM+uUyfCg6UKCBbA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@jridgewell/sourcemap-codec": "^1.5.0",
        "@jridgewell/trace-mapping": "^0.3.24"
      }
    },
    "node_modules/@jridgewell/remapping": {
      "version": "2.3.5",
      "resolved": "https://registry.npmjs.org/@jridgewell/remapping/-/remapping-2.3.5.tgz",
      "integrity": "sha512-LI9u/+laYG4Ds1TDKSJW2YPrIlcVYOwi2fUC6xB43lueCjgxV4lffOCZCtYFiH6TNOX+tQKXx97T4IKHbhyHEQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@jridgewell/gen-mapping": "^0.3.5",
        "@jridgewell/trace-mapping": "^0.3.24"
      }
    },
    "node_modules/@jridgewell/resolve-uri": {
      "version": "3.1.2",
      "resolved": "https://registry.npmjs.org/@jridgewell/resolve-uri/-/resolve-uri-3.1.2.tgz",
      "integrity": "sha512-bRISgCIjP20/tbWSPWMEi54QVPRZExkuD9lJL+UIxUKtwVJA8wW1Trb1jMs1RFXo1CBTNZ/5hpC9QvmKWdopKw==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=6.0.0"
      }
    },
    "node_modules/@jridgewell/source-map": {
      "version": "0.3.11",
      "resolved": "https://registry.npmjs.org/@jridgewell/source-map/-/source-map-0.3.11.tgz",
      "integrity": "sha512-ZMp1V8ZFcPG5dIWnQLr3NSI1MiCU7UETdS/A0G8V/XWHvJv3ZsFqutJn1Y5RPmAPX6F3BiE397OqveU/9NCuIA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@jridgewell/gen-mapping": "^0.3.5",
        "@jridgewell/trace-mapping": "^0.3.25"
      }
    },
    "node_modules/@jridgewell/sourcemap-codec": {
      "version": "1.6.0",
      "resolved": "https://registry.npmjs.org/@jridgewell/sourcemap-codec/-/sourcemap-codec-1.6.0.tgz",
      "integrity": "sha512-T7jf+5zgsZHwNJ4lvQ7/aezbyk0nNX+zJVWpmHA7VYsEx7a7qr5Rg5IbtJFqkgze5Y2sruq1RUY8Q837Od7iFw==",
      "license": "MIT"
    },
    "node_modules/@jridgewell/trace-mapping": {
      "version": "0.3.31",
      "resolved": "https://registry.npmjs.org/@jridgewell/trace-mapping/-/trace-mapping-0.3.31.tgz",
      "integrity": "sha512-zzNR+SdQSDJzc8joaeP8QQoCQr8NuYx2dIIytl1QeBEZHJ9uW6hebsrYgbz8hJwUQao3TWCMtmfV8Nu1twOLAw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@jridgewell/resolve-uri": "^3.1.0",
        "@jridgewell/sourcemap-codec": "^1.4.14"
      }
    },
    "node_modules/@meteora-ag/dynamic-bonding-curve-sdk": {
      "version": "1.5.12",
      "resolved": "https://registry.npmjs.org/@meteora-ag/dynamic-bonding-curve-sdk/-/dynamic-bonding-curve-sdk-1.5.12.tgz",
      "integrity": "sha512-xMtzUXriajNtNwYgNwk5T9IKxjfj6QP1I4yUKAe9JiGrVgpqoLkwvB2mKy8824nSWrVNVX5CAufHW5Kvjz/FNA==",
      "license": "MIT",
      "dependencies": {
        "@coral-xyz/anchor": "^0.31.0",
        "@solana/spl-token": "^0.4.13",
        "@solana/web3.js": "^1.98.0",
        "bn.js": "^5.2.1",
        "decimal.js": "^10.5.0"
      },
      "peerDependencies": {
        "typescript": "^5"
      }
    },
    "node_modules/@noble/curves": {
      "version": "1.9.7",
      "resolved": "https://registry.npmjs.org/@noble/curves/-/curves-1.9.7.tgz",
      "integrity": "sha512-gbKGcRUYIjA3/zCCNaWDciTMFI0dCkvou3TL8Zmy5Nc7sJ47a0jtOeZoTaMxkuqRo9cRhjOdZJXegxYE5FN/xw==",
      "license": "MIT",
      "dependencies": {
        "@noble/hashes": "1.8.0"
      },
      "engines": {
        "node": "^14.21.3 || >=16"
      },
      "funding": {
        "url": "https://paulmillr.com/funding/"
      }
    },
    "node_modules/@noble/hashes": {
      "version": "1.8.0",
      "resolved": "https://registry.npmjs.org/@noble/hashes/-/hashes-1.8.0.tgz",
      "integrity": "sha512-jCs9ldd7NwzpgXDIf6P3+NrHh9/sD6CQdxHyjQI+h/6rDNo88ypBxxz45UDuZHz9r3tNz7N/VInSVoVdtXEI4A==",
      "license": "MIT",
      "engines": {
        "node": "^14.21.3 || >=16"
      },
      "funding": {
        "url": "https://paulmillr.com/funding/"
      }
    },
    "node_modules/@oxc-project/types": {
      "version": "0.152.0",
      "resolved": "https://registry.npmjs.org/@oxc-project/types/-/types-0.152.0.tgz",
      "integrity": "sha512-oM/5rLBm2tPkg0iBgkH/FOeR3PCDpY19GTgAZjMFM8h9WI9VW7cLgzp6nwtarYKmovavIQZ+Fe/RKX/8C8O/Rw==",
      "dev": true,
      "license": "MIT",
      "funding": {
        "url": "https://github.com/sponsors/oxc-project"
      }
    },
    "node_modules/@react-native/asset-utils": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/@react-native/asset-utils/-/asset-utils-0.87.1.tgz",
      "integrity": "sha512-FeFnbn9ENPs7IVBzZt1bBWfiRGvT4q+CsWwXGFyKVW/1ol3ylBRuTtXBGHIAmcNN4fUR60nSXsCN19pzNHkPgA==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/@react-native/codegen": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/@react-native/codegen/-/codegen-0.87.1.tgz",
      "integrity": "sha512-qbaqEdlUfj2vRgvWTpMoNgHnEqAhAYJLUrpGkb0WC9n0kdtqUvgigpz4bDktZwolM9BemXwgGFgyiAnbs3t0xw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/core": "^7.25.2",
        "@babel/parser": "^7.29.0",
        "hermes-parser": "0.36.1",
        "invariant": "^2.2.4",
        "nullthrows": "^1.1.1",
        "tinyglobby": "^0.2.15",
        "yargs": "^17.6.2"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      },
      "peerDependencies": {
        "@babel/core": "*"
      }
    },
    "node_modules/@react-native/codegen/node_modules/cliui": {
      "version": "8.0.1",
      "resolved": "https://registry.npmjs.org/cliui/-/cliui-8.0.1.tgz",
      "integrity": "sha512-BSeNnyus75C4//NQ9gQt1/csTXyo/8Sb+afLAkzAptFuMsod9HFokGNudZpi/oQV73hnVK+sR+5PVRMd+Dr7YQ==",
      "license": "ISC",
      "peer": true,
      "dependencies": {
        "string-width": "^4.2.0",
        "strip-ansi": "^6.0.1",
        "wrap-ansi": "^7.0.0"
      },
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/@react-native/codegen/node_modules/wrap-ansi": {
      "version": "7.0.0",
      "resolved": "https://registry.npmjs.org/wrap-ansi/-/wrap-ansi-7.0.0.tgz",
      "integrity": "sha512-YVGIj2kamLSTxw6NsZjoBxfSwsn0ycdesmc4p+Q21c5zPuZ1pl+NfxVdxPtdHvmNVOQ6XSYG4AUtyt/Fi7D16Q==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ansi-styles": "^4.0.0",
        "string-width": "^4.1.0",
        "strip-ansi": "^6.0.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/chalk/wrap-ansi?sponsor=1"
      }
    },
    "node_modules/@react-native/codegen/node_modules/y18n": {
      "version": "5.0.8",
      "resolved": "https://registry.npmjs.org/y18n/-/y18n-5.0.8.tgz",
      "integrity": "sha512-0pfFzegeDWJHJIAmTLRP2DwHjdF5s7jo9tuztdQxAhINCdvS+3nGINqPd00AphqJR/0LhANUS6/+7SCb98YOfA==",
      "license": "ISC",
      "peer": true,
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/@react-native/codegen/node_modules/yargs": {
      "version": "17.7.3",
      "resolved": "https://registry.npmjs.org/yargs/-/yargs-17.7.3.tgz",
      "integrity": "sha512-GZtjxm/J/4TSxuL3FNYjCmLktBTnIw/rVmKSIyKeYAZpmJB2ig9VauCC5xsa82GNKVKDAqpOn3KVzNt0zmrU0g==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "cliui": "^8.0.1",
        "escalade": "^3.1.1",
        "get-caller-file": "^2.0.5",
        "require-directory": "^2.1.1",
        "string-width": "^4.2.3",
        "y18n": "^5.0.5",
        "yargs-parser": "^21.1.1"
      },
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/@react-native/codegen/node_modules/yargs-parser": {
      "version": "21.1.1",
      "resolved": "https://registry.npmjs.org/yargs-parser/-/yargs-parser-21.1.1.tgz",
      "integrity": "sha512-tVpsJW7DdjecAiFpbIB1e3qxIQsE6NoPc5/eTdrbbIC4h0LVsWhnoa3g+m2HclBIujHzsxZ4VJVA+GUuc2/LBw==",
      "license": "ISC",
      "peer": true,
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/@react-native/community-cli-plugin": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/@react-native/community-cli-plugin/-/community-cli-plugin-0.87.1.tgz",
      "integrity": "sha512-aGBae6v+ngy8fIpU1EOaVxn/8DOgmJNphEdn5Eb0wTchUCxr8bDjpTJYNdrptyn3qI/elk8r9agQ2OBaFvrRlw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@react-native/asset-utils": "0.87.1",
        "@react-native/dev-middleware": "0.87.1",
        "debug": "^4.4.0",
        "invariant": "^2.2.4",
        "metro": "^0.87.0",
        "semver": "^7.1.3"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      },
      "peerDependencies": {
        "@react-native-community/cli": "*",
        "@react-native/metro-config": "0.87.1"
      },
      "peerDependenciesMeta": {
        "@react-native-community/cli": {
          "optional": true
        },
        "@react-native/metro-config": {
          "optional": true
        }
      }
    },
    "node_modules/@react-native/debugger-frontend": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/@react-native/debugger-frontend/-/debugger-frontend-0.87.1.tgz",
      "integrity": "sha512-RNm7soJB+8YSauLnsCCylA1eVfT6JWaDTPUEF01uu9YwDyZ7remKlZbXtmVbtscbNGcp+hbI4iZUdVOpQWsHuA==",
      "license": "BSD-3-Clause",
      "peer": true,
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/@react-native/debugger-shell": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/@react-native/debugger-shell/-/debugger-shell-0.87.1.tgz",
      "integrity": "sha512-eNbKjcnseJIjy5XCDwyhKOT1ngOg3Dv1fVxTDtnVFqdqjqsbfY4v9JuJG1RZJ7+mFoRRe05HE8GSQU8B7n5xwQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "cross-spawn": "^7.0.6",
        "debug": "^4.4.0",
        "fb-dotslash": "0.5.8"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/@react-native/dev-middleware": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/@react-native/dev-middleware/-/dev-middleware-0.87.1.tgz",
      "integrity": "sha512-KgvAGUaVl6/XrWFAPK8e0ojDRbsdBjr4bnwyn6PC3CwxPQc5iv+i7hMoUwYS8ORSkHKfjt+cV86/mBQ4lG8yfA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@isaacs/ttlcache": "^1.4.1",
        "@react-native/debugger-frontend": "0.87.1",
        "@react-native/debugger-shell": "0.87.1",
        "chrome-launcher": "^0.15.2",
        "chromium-edge-launcher": "^0.3.0",
        "connect": "^3.6.5",
        "debug": "^4.4.0",
        "invariant": "^2.2.4",
        "nullthrows": "^1.1.1",
        "open": "^7.0.3",
        "serve-static": "^1.16.2",
        "ws": "^7.5.10"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/@react-native/gradle-plugin": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/@react-native/gradle-plugin/-/gradle-plugin-0.87.1.tgz",
      "integrity": "sha512-bZ5X2BNxaSlfp2KlDtUM910QqW9G1yTIeZXghuv4ag8SAQLzm5Mf9j5GjJfT6ax2Qo2aRT15Vi3Tro/yLGJstA==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/@react-native/normalize-colors": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/@react-native/normalize-colors/-/normalize-colors-0.87.1.tgz",
      "integrity": "sha512-8+AutemzX+a7cuKgTUyb7JUk3sFYgLyrSnlTLrL6LuW/LKDE+FYE8lJGWYhJPJcE51Ge1D8yRzxgQEdEFZtuIw==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/@rolldown/binding-android-arm-eabi": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-android-arm-eabi/-/binding-android-arm-eabi-1.2.12.tgz",
      "integrity": "sha512-dB/a1214qKfHMXCpgqR4OZT+jS4kTyEXbQGJPqzobt5EwH5rX080pxE37alt3RzvR1bf1Yz/yGqRfrYAxuPw0A==",
      "cpu": [
        "arm"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "android"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-android-arm64": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-android-arm64/-/binding-android-arm64-1.2.12.tgz",
      "integrity": "sha512-7KHFgQ5VJxIHcLlrwrc3Xbds7oTNQT7Pgi9gQCJKrd2VGab/UksIOYp6VD8MzCstGxOKMgNamPwUCfxPdP1OHg==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "android"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-darwin-arm64": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-darwin-arm64/-/binding-darwin-arm64-1.2.12.tgz",
      "integrity": "sha512-3YIhqHD96nA5SaYNRBR16HnGv4oavZvXfD/ayHM+oYZ0WD/8lBAtf6zQua4kEyAvpqrluKXl0lnOBoiNby7x9w==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-darwin-x64": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-darwin-x64/-/binding-darwin-x64-1.2.12.tgz",
      "integrity": "sha512-UuuJ35MFw4gmFOrE9pEqIV+K3syIKveph+Qc1/ljHZVdoDW4pz/JHR/eMVom+TZGl/5OOvGJOWaOCVt3ZfqhxA==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-freebsd-x64": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-freebsd-x64/-/binding-freebsd-x64-1.2.12.tgz",
      "integrity": "sha512-uMvssit0a4W+/7D8CbHUvG719mH3R2jwXAlh/XcPvuHTE0g++LymF88DCGNX0HM2rBOn0xrzgXktIB6fLSJBTQ==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "freebsd"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-arm-gnueabihf": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-arm-gnueabihf/-/binding-linux-arm-gnueabihf-1.2.12.tgz",
      "integrity": "sha512-XcFu0R0xWnwzSf4IQgFH1rJIckPN1pLy2R+4r9IDB7Yfu/ys9cVqfa4pBrMHj7a3gl8mIR4nRNPg0e5IvEVs6g==",
      "cpu": [
        "arm"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-arm64-gnu": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-arm64-gnu/-/binding-linux-arm64-gnu-1.2.12.tgz",
      "integrity": "sha512-260UrKgn8tz39ak+SMDOirKzr7V04M9dWPw5llW00SwBivCZoWcRBKV1d8cXnRkUmSZA3BdiUmBHWk7734Ulpw==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-arm64-musl": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-arm64-musl/-/binding-linux-arm64-musl-1.2.12.tgz",
      "integrity": "sha512-5YK1I9SqDkbPgc1IA8BgDl34suqUS2q0KWnBrirm0E51YjOs6eo6dV6jbQfNE/argHRSvd0QUGgtpIoYx+WWpw==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-ppc64-gnu": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-ppc64-gnu/-/binding-linux-ppc64-gnu-1.2.12.tgz",
      "integrity": "sha512-Rkcrmp7eFRg74yL5fXEU91JEWbdEPLevWwGtXpmhbjlD1StScbWTmO94Bhly+Mo+ketKYkdmM1vNUKeWSlx8cQ==",
      "cpu": [
        "ppc64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-s390x-gnu": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-s390x-gnu/-/binding-linux-s390x-gnu-1.2.12.tgz",
      "integrity": "sha512-qvK4DuAsQc2BSjlx+Xr+IzOIvvxbGZqxFwdWfG6F518Erj0GGISyQbJ6pIappnOxlNPzNHvo/L0BwB30GZ+zVw==",
      "cpu": [
        "s390x"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-x64-gnu": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-x64-gnu/-/binding-linux-x64-gnu-1.2.12.tgz",
      "integrity": "sha512-Q9uLBO53Xd4QIq1WOycVQyPP1O4HhraEV2qqb3uTrnVw6QZih9duY4vNXOivL1xoUS1/z+W8eF4NMfl2a8Sdjw==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-x64-musl": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-x64-musl/-/binding-linux-x64-musl-1.2.12.tgz",
      "integrity": "sha512-3IBxWFMjbOZskDPKv8Lf9BCnahlKuHthWkYnyIxOH/QcJrFcS4EmcenthApkwr/5+nEqZlLzeYbxeMaX7A5u4g==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-openharmony-arm64": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-openharmony-arm64/-/binding-openharmony-arm64-1.2.12.tgz",
      "integrity": "sha512-xtX61xg4LKPkPWilZU1ynKClz5Gj4bf74LML4r3eVLWumKnGjoEr1OSHQhMdbBDoYTi+yjrujvpZe2pUnqCrrA==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "openharmony"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-win32-arm64-msvc": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-win32-arm64-msvc/-/binding-win32-arm64-msvc-1.2.12.tgz",
      "integrity": "sha512-At7fPB6PCaIjzgIhEZFxuT+BBFqiQibJDT4d3PhiR3f4E7bbMZF4aKblbFfEM3sETRDd1YiQx/+U/g/B/ou5Ew==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-win32-x64-msvc": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-win32-x64-msvc/-/binding-win32-x64-msvc-1.2.12.tgz",
      "integrity": "sha512-WIw2haVKwjuYdXkHaoC0mF8Le71TuCBxjrdKqLbJGctbBABj+ClfmNvtbOnzpq3RokNo5+V1qhtSzJyXorsklQ==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/pluginutils": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/@rolldown/pluginutils/-/pluginutils-1.0.1.tgz",
      "integrity": "sha512-2j9bGt5Jh8hj+vPtgzPtl72j0yRxHAyumoo6TNfAjsLB04UtpSvPbPcDcBMxz7n+9CYB0c1GxQFxYRg2jimqGw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@rollup/plugin-inject": {
      "version": "5.0.5",
      "resolved": "https://registry.npmjs.org/@rollup/plugin-inject/-/plugin-inject-5.0.5.tgz",
      "integrity": "sha512-2+DEJbNBoPROPkgTDNe8/1YXWcqxbN5DTjASVIOx8HS+pITXushyNiBV56RB08zuptzz8gT3YfkqriTBVycepg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@rollup/pluginutils": "^5.0.1",
        "estree-walker": "^2.0.2",
        "magic-string": "^0.30.3"
      },
      "engines": {
        "node": ">=14.0.0"
      },
      "peerDependencies": {
        "rollup": "^1.20.0||^2.0.0||^3.0.0||^4.0.0"
      },
      "peerDependenciesMeta": {
        "rollup": {
          "optional": true
        }
      }
    },
    "node_modules/@rollup/pluginutils": {
      "version": "5.4.0",
      "resolved": "https://registry.npmjs.org/@rollup/pluginutils/-/pluginutils-5.4.0.tgz",
      "integrity": "sha512-MfPp06CjRLfXQ3wY0R8vJDYBy/MvVcc9OulEfR0B8Iv9ko+GCNaRZ+EpJYFl27LhKsZK0o420sYCRHCjfCgeUg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/estree": "^1.0.0",
        "estree-walker": "^2.0.2",
        "picomatch": "^4.0.2"
      },
      "engines": {
        "node": ">=14.0.0"
      },
      "peerDependencies": {
        "rollup": "^1.20.0||^2.0.0||^3.0.0||^4.0.0"
      },
      "peerDependenciesMeta": {
        "rollup": {
          "optional": true
        }
      }
    },
    "node_modules/@rollup/pluginutils/node_modules/picomatch": {
      "version": "4.0.7",
      "resolved": "https://registry.npmjs.org/picomatch/-/picomatch-4.0.7.tgz",
      "integrity": "sha512-qcJu88Q2IWqJsDD529JKMdwGm/dvInW4HvQnRwiH9JtihJvzGOscDtHE3x1pBKeUOTysQ8kVmLnJ2kJu7yhcGA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=12"
      },
      "funding": {
        "url": "https://github.com/sponsors/jonschlinkert"
      }
    },
    "node_modules/@sinclair/typebox": {
      "version": "0.27.12",
      "resolved": "https://registry.npmjs.org/@sinclair/typebox/-/typebox-0.27.12.tgz",
      "integrity": "sha512-hhyNJ+nbR6ZR7pToHvllEFun9TL0sbL+tk/ON75lo+Xas054uez98qRbsuNt7MBCyZKK4+8Yli/OAGZhmfBZ/g==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/@solana-mobile/mobile-wallet-adapter-protocol-web3js/-/mobile-wallet-adapter-protocol-web3js-2.3.0.tgz",
      "integrity": "sha512-zeSNc8CcyYlVIF6xOq1ff9tLn+rCkf99eDw9sVg0k5Vrl2YGQj7UsSqhHm7dl7XfVTXj0ca0AnDAiMugwIM/rA==",
      "license": "Apache-2.0",
      "dependencies": {
        "@solana-mobile/mobile-wallet-adapter-protocol": "^2.3.0"
      },
      "peerDependencies": {
        "@solana/web3.js": "^1.98.4"
      }
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js/node_modules/@noble/curves": {
      "version": "2.4.0",
      "resolved": "https://registry.npmjs.org/@noble/curves/-/curves-2.4.0.tgz",
      "integrity": "sha512-P4/62zrgfH33CneE3Dn4WhJVA22YUU0eR51wKIan4NVRvwsA0YnPTwWGpNbpuacSujmSFLvyzpyuR30+fbq2Ew==",
      "license": "MIT",
      "dependencies": {
        "@noble/hashes": "2.4.0"
      },
      "engines": {
        "node": ">= 20.19.0"
      },
      "funding": {
        "url": "https://paulmillr.com/funding/"
      }
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js/node_modules/@noble/hashes": {
      "version": "2.4.0",
      "resolved": "https://registry.npmjs.org/@noble/hashes/-/hashes-2.4.0.tgz",
      "integrity": "sha512-X5XaVWZIBCT7HHZGm5I7ZQXDwLG+bGXuSrMQAW+7Zvl87h1kmc1ZB1VSRJcpUfoUrGQp4Fkoxm5kZ+Ms+aW+eA==",
      "license": "MIT",
      "engines": {
        "node": ">= 20.19.0"
      },
      "funding": {
        "url": "https://paulmillr.com/funding/"
      }
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js/node_modules/@react-native/virtualized-lists": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/@react-native/virtualized-lists/-/virtualized-lists-0.87.1.tgz",
      "integrity": "sha512-qSZjeX3UJrDvyfjf7yc3E68rp1XnzE+5nu8ImklhkVC0+p/XiaHPb/KGkRqDdnQyWHN55BRYSsCMEwgVI6WRNQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "invariant": "^2.2.4",
        "nullthrows": "^1.1.1"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      },
      "peerDependencies": {
        "@types/react": "^19.2.0",
        "react": "*",
        "react-native": "0.87.1"
      },
      "peerDependenciesMeta": {
        "@types/react": {
          "optional": true
        }
      }
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js/node_modules/@solana-mobile/mobile-wallet-adapter-protocol": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/@solana-mobile/mobile-wallet-adapter-protocol/-/mobile-wallet-adapter-protocol-2.3.0.tgz",
      "integrity": "sha512-NqAinVV9t+S65nvdUo41Z1npg4W1JjSp/K02w6xWFv2ywCdahPHpbbHYS177nDenQR2kf/8vshLOXiyV/J6HRw==",
      "license": "Apache-2.0",
      "dependencies": {
        "@noble/curves": "^2.2.0",
        "@noble/hashes": "^2.2.0",
        "@solana/kit": "^7.0.0",
        "@solana/wallet-standard-features": "^1.3.0",
        "@solana/wallet-standard-util": "^1.1.2",
        "@wallet-standard/core": "^1.1.1"
      },
      "peerDependencies": {
        "react-native": ">0.74"
      }
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js/node_modules/@types/react": {
      "version": "19.3.0",
      "resolved": "https://registry.npmjs.org/@types/react/-/react-19.3.0.tgz",
      "integrity": "sha512-N0rFCuH9YoxG9/m61l9MfpJKfmLOVU0em7ipIz6TRgSSkvReLB9vL85GB+yr8Bs5leqpvg96JSwF4ZS1s4viQg==",
      "license": "MIT",
      "optional": true,
      "peer": true,
      "dependencies": {
        "csstype": "^3.2.2"
      }
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js/node_modules/cliui": {
      "version": "8.0.1",
      "resolved": "https://registry.npmjs.org/cliui/-/cliui-8.0.1.tgz",
      "integrity": "sha512-BSeNnyus75C4//NQ9gQt1/csTXyo/8Sb+afLAkzAptFuMsod9HFokGNudZpi/oQV73hnVK+sR+5PVRMd+Dr7YQ==",
      "license": "ISC",
      "peer": true,
      "dependencies": {
        "string-width": "^4.2.0",
        "strip-ansi": "^6.0.1",
        "wrap-ansi": "^7.0.0"
      },
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js/node_modules/react": {
      "version": "19.3.0",
      "resolved": "https://registry.npmjs.org/react/-/react-19.3.0.tgz",
      "integrity": "sha512-E8LUcbtBWt20bbl2YoHfx4ZDBdxVTfOKtCZn9cDSJ4l6/nuoApcpIBcj47t2wZoVX8g2ZHuMHbiShgCR1T5Sog==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js/node_modules/react-native": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/react-native/-/react-native-0.87.1.tgz",
      "integrity": "sha512-DJKG6ANoD7BtrE4z9DewiSD7/RxCX73lK5Pu49aUr85P3333Dm2roTiP0rRjQNDZdVizHSOmstWfwF/o9EjCRA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@react-native/asset-utils": "0.87.1",
        "@react-native/codegen": "0.87.1",
        "@react-native/community-cli-plugin": "0.87.1",
        "@react-native/gradle-plugin": "0.87.1",
        "@react-native/normalize-colors": "0.87.1",
        "@react-native/virtualized-lists": "0.87.1",
        "anser": "^1.4.9",
        "ansi-regex": "^5.0.0",
        "babel-plugin-syntax-hermes-parser": "0.36.1",
        "base64-js": "^1.5.1",
        "commander": "^12.0.0",
        "flow-enums-runtime": "^0.0.6",
        "hermes-compiler": "250829098.0.17",
        "invariant": "^2.2.4",
        "memoize-one": "^5.0.0",
        "metro-runtime": "^0.87.0",
        "metro-source-map": "^0.87.0",
        "nullthrows": "^1.1.1",
        "pretty-format": "^29.7.0",
        "promise": "^8.3.0",
        "react-devtools-core": "^6.1.5",
        "react-refresh": "^0.14.0",
        "regenerator-runtime": "^0.13.2",
        "scheduler": "0.27.0",
        "semver": "^7.1.3",
        "stacktrace-parser": "^0.1.10",
        "tinyglobby": "^0.2.15",
        "whatwg-fetch": "^3.0.0",
        "ws": "^7.5.10",
        "yargs": "^17.6.2"
      },
      "bin": {
        "react-native": "cli.js"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      },
      "peerDependencies": {
        "@types/react": "^19.1.1",
        "react": "^19.2.3"
      },
      "peerDependenciesMeta": {
        "@types/react": {
          "optional": true
        }
      }
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js/node_modules/scheduler": {
      "version": "0.27.0",
      "resolved": "https://registry.npmjs.org/scheduler/-/scheduler-0.27.0.tgz",
      "integrity": "sha512-eNv+WrVbKu1f3vbYJT/xtiF5syA5HPIMtf9IgY/nKg0sWqzAUEvqY/xm7OcZc/qafLx/iO9FgOmeSAp4v5ti/Q==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js/node_modules/wrap-ansi": {
      "version": "7.0.0",
      "resolved": "https://registry.npmjs.org/wrap-ansi/-/wrap-ansi-7.0.0.tgz",
      "integrity": "sha512-YVGIj2kamLSTxw6NsZjoBxfSwsn0ycdesmc4p+Q21c5zPuZ1pl+NfxVdxPtdHvmNVOQ6XSYG4AUtyt/Fi7D16Q==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ansi-styles": "^4.0.0",
        "string-width": "^4.1.0",
        "strip-ansi": "^6.0.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/chalk/wrap-ansi?sponsor=1"
      }
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js/node_modules/y18n": {
      "version": "5.0.8",
      "resolved": "https://registry.npmjs.org/y18n/-/y18n-5.0.8.tgz",
      "integrity": "sha512-0pfFzegeDWJHJIAmTLRP2DwHjdF5s7jo9tuztdQxAhINCdvS+3nGINqPd00AphqJR/0LhANUS6/+7SCb98YOfA==",
      "license": "ISC",
      "peer": true,
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js/node_modules/yargs": {
      "version": "17.7.3",
      "resolved": "https://registry.npmjs.org/yargs/-/yargs-17.7.3.tgz",
      "integrity": "sha512-GZtjxm/J/4TSxuL3FNYjCmLktBTnIw/rVmKSIyKeYAZpmJB2ig9VauCC5xsa82GNKVKDAqpOn3KVzNt0zmrU0g==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "cliui": "^8.0.1",
        "escalade": "^3.1.1",
        "get-caller-file": "^2.0.5",
        "require-directory": "^2.1.1",
        "string-width": "^4.2.3",
        "y18n": "^5.0.5",
        "yargs-parser": "^21.1.1"
      },
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/@solana-mobile/mobile-wallet-adapter-protocol-web3js/node_modules/yargs-parser": {
      "version": "21.1.1",
      "resolved": "https://registry.npmjs.org/yargs-parser/-/yargs-parser-21.1.1.tgz",
      "integrity": "sha512-tVpsJW7DdjecAiFpbIB1e3qxIQsE6NoPc5/eTdrbbIC4h0LVsWhnoa3g+m2HclBIujHzsxZ4VJVA+GUuc2/LBw==",
      "license": "ISC",
      "peer": true,
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile": {
      "version": "0.6.0",
      "resolved": "https://registry.npmjs.org/@solana-mobile/wallet-standard-mobile/-/wallet-standard-mobile-0.6.0.tgz",
      "integrity": "sha512-abytKDEpjo2kRm4y5IChDrhqDUpPznvQJEw4IgK0GjLjC39R0XPUGC5Q0qLWM2pmw/DAQP+63neRiJFG5r7NsQ==",
      "license": "Apache-2.0",
      "dependencies": {
        "@solana-mobile/mobile-wallet-adapter-protocol": "^2.3.0",
        "@solana/wallet-standard-chains": "^1.1.1",
        "@solana/wallet-standard-features": "^1.3.0",
        "@wallet-standard/base": "^1.0.1",
        "@wallet-standard/features": "^1.0.3",
        "@wallet-standard/wallet": "^1.1.0",
        "qrcode": "^1.5.4",
        "tslib": "^2.8.1"
      },
      "optionalDependencies": {
        "@react-native-async-storage/async-storage": "^1.17.7"
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/@noble/curves": {
      "version": "2.4.0",
      "resolved": "https://registry.npmjs.org/@noble/curves/-/curves-2.4.0.tgz",
      "integrity": "sha512-P4/62zrgfH33CneE3Dn4WhJVA22YUU0eR51wKIan4NVRvwsA0YnPTwWGpNbpuacSujmSFLvyzpyuR30+fbq2Ew==",
      "license": "MIT",
      "dependencies": {
        "@noble/hashes": "2.4.0"
      },
      "engines": {
        "node": ">= 20.19.0"
      },
      "funding": {
        "url": "https://paulmillr.com/funding/"
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/@noble/hashes": {
      "version": "2.4.0",
      "resolved": "https://registry.npmjs.org/@noble/hashes/-/hashes-2.4.0.tgz",
      "integrity": "sha512-X5XaVWZIBCT7HHZGm5I7ZQXDwLG+bGXuSrMQAW+7Zvl87h1kmc1ZB1VSRJcpUfoUrGQp4Fkoxm5kZ+Ms+aW+eA==",
      "license": "MIT",
      "engines": {
        "node": ">= 20.19.0"
      },
      "funding": {
        "url": "https://paulmillr.com/funding/"
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/@react-native-async-storage/async-storage": {
      "version": "1.24.0",
      "resolved": "https://registry.npmjs.org/@react-native-async-storage/async-storage/-/async-storage-1.24.0.tgz",
      "integrity": "sha512-W4/vbwUOYOjco0x3toB8QCr7EjIP6nE9G7o8PMguvvjYT5Awg09lyV4enACRx4s++PPulBiBSjL0KTFx2u0Z/g==",
      "license": "MIT",
      "optional": true,
      "dependencies": {
        "merge-options": "^3.0.4"
      },
      "peerDependencies": {
        "react-native": "^0.0.0-0 || >=0.60 <1.0"
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/@react-native/virtualized-lists": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/@react-native/virtualized-lists/-/virtualized-lists-0.87.1.tgz",
      "integrity": "sha512-qSZjeX3UJrDvyfjf7yc3E68rp1XnzE+5nu8ImklhkVC0+p/XiaHPb/KGkRqDdnQyWHN55BRYSsCMEwgVI6WRNQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "invariant": "^2.2.4",
        "nullthrows": "^1.1.1"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      },
      "peerDependencies": {
        "@types/react": "^19.2.0",
        "react": "*",
        "react-native": "0.87.1"
      },
      "peerDependenciesMeta": {
        "@types/react": {
          "optional": true
        }
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/@solana-mobile/mobile-wallet-adapter-protocol": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/@solana-mobile/mobile-wallet-adapter-protocol/-/mobile-wallet-adapter-protocol-2.3.0.tgz",
      "integrity": "sha512-NqAinVV9t+S65nvdUo41Z1npg4W1JjSp/K02w6xWFv2ywCdahPHpbbHYS177nDenQR2kf/8vshLOXiyV/J6HRw==",
      "license": "Apache-2.0",
      "dependencies": {
        "@noble/curves": "^2.2.0",
        "@noble/hashes": "^2.2.0",
        "@solana/kit": "^7.0.0",
        "@solana/wallet-standard-features": "^1.3.0",
        "@solana/wallet-standard-util": "^1.1.2",
        "@wallet-standard/core": "^1.1.1"
      },
      "peerDependencies": {
        "react-native": ">0.74"
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/@types/react": {
      "version": "19.3.0",
      "resolved": "https://registry.npmjs.org/@types/react/-/react-19.3.0.tgz",
      "integrity": "sha512-N0rFCuH9YoxG9/m61l9MfpJKfmLOVU0em7ipIz6TRgSSkvReLB9vL85GB+yr8Bs5leqpvg96JSwF4ZS1s4viQg==",
      "license": "MIT",
      "optional": true,
      "peer": true,
      "dependencies": {
        "csstype": "^3.2.2"
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/cliui": {
      "version": "8.0.1",
      "resolved": "https://registry.npmjs.org/cliui/-/cliui-8.0.1.tgz",
      "integrity": "sha512-BSeNnyus75C4//NQ9gQt1/csTXyo/8Sb+afLAkzAptFuMsod9HFokGNudZpi/oQV73hnVK+sR+5PVRMd+Dr7YQ==",
      "license": "ISC",
      "peer": true,
      "dependencies": {
        "string-width": "^4.2.0",
        "strip-ansi": "^6.0.1",
        "wrap-ansi": "^7.0.0"
      },
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/react": {
      "version": "19.3.0",
      "resolved": "https://registry.npmjs.org/react/-/react-19.3.0.tgz",
      "integrity": "sha512-E8LUcbtBWt20bbl2YoHfx4ZDBdxVTfOKtCZn9cDSJ4l6/nuoApcpIBcj47t2wZoVX8g2ZHuMHbiShgCR1T5Sog==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/react-native": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/react-native/-/react-native-0.87.1.tgz",
      "integrity": "sha512-DJKG6ANoD7BtrE4z9DewiSD7/RxCX73lK5Pu49aUr85P3333Dm2roTiP0rRjQNDZdVizHSOmstWfwF/o9EjCRA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@react-native/asset-utils": "0.87.1",
        "@react-native/codegen": "0.87.1",
        "@react-native/community-cli-plugin": "0.87.1",
        "@react-native/gradle-plugin": "0.87.1",
        "@react-native/normalize-colors": "0.87.1",
        "@react-native/virtualized-lists": "0.87.1",
        "anser": "^1.4.9",
        "ansi-regex": "^5.0.0",
        "babel-plugin-syntax-hermes-parser": "0.36.1",
        "base64-js": "^1.5.1",
        "commander": "^12.0.0",
        "flow-enums-runtime": "^0.0.6",
        "hermes-compiler": "250829098.0.17",
        "invariant": "^2.2.4",
        "memoize-one": "^5.0.0",
        "metro-runtime": "^0.87.0",
        "metro-source-map": "^0.87.0",
        "nullthrows": "^1.1.1",
        "pretty-format": "^29.7.0",
        "promise": "^8.3.0",
        "react-devtools-core": "^6.1.5",
        "react-refresh": "^0.14.0",
        "regenerator-runtime": "^0.13.2",
        "scheduler": "0.27.0",
        "semver": "^7.1.3",
        "stacktrace-parser": "^0.1.10",
        "tinyglobby": "^0.2.15",
        "whatwg-fetch": "^3.0.0",
        "ws": "^7.5.10",
        "yargs": "^17.6.2"
      },
      "bin": {
        "react-native": "cli.js"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      },
      "peerDependencies": {
        "@types/react": "^19.1.1",
        "react": "^19.2.3"
      },
      "peerDependenciesMeta": {
        "@types/react": {
          "optional": true
        }
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/scheduler": {
      "version": "0.27.0",
      "resolved": "https://registry.npmjs.org/scheduler/-/scheduler-0.27.0.tgz",
      "integrity": "sha512-eNv+WrVbKu1f3vbYJT/xtiF5syA5HPIMtf9IgY/nKg0sWqzAUEvqY/xm7OcZc/qafLx/iO9FgOmeSAp4v5ti/Q==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/wrap-ansi": {
      "version": "7.0.0",
      "resolved": "https://registry.npmjs.org/wrap-ansi/-/wrap-ansi-7.0.0.tgz",
      "integrity": "sha512-YVGIj2kamLSTxw6NsZjoBxfSwsn0ycdesmc4p+Q21c5zPuZ1pl+NfxVdxPtdHvmNVOQ6XSYG4AUtyt/Fi7D16Q==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ansi-styles": "^4.0.0",
        "string-width": "^4.1.0",
        "strip-ansi": "^6.0.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/chalk/wrap-ansi?sponsor=1"
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/y18n": {
      "version": "5.0.8",
      "resolved": "https://registry.npmjs.org/y18n/-/y18n-5.0.8.tgz",
      "integrity": "sha512-0pfFzegeDWJHJIAmTLRP2DwHjdF5s7jo9tuztdQxAhINCdvS+3nGINqPd00AphqJR/0LhANUS6/+7SCb98YOfA==",
      "license": "ISC",
      "peer": true,
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/yargs": {
      "version": "17.7.3",
      "resolved": "https://registry.npmjs.org/yargs/-/yargs-17.7.3.tgz",
      "integrity": "sha512-GZtjxm/J/4TSxuL3FNYjCmLktBTnIw/rVmKSIyKeYAZpmJB2ig9VauCC5xsa82GNKVKDAqpOn3KVzNt0zmrU0g==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "cliui": "^8.0.1",
        "escalade": "^3.1.1",
        "get-caller-file": "^2.0.5",
        "require-directory": "^2.1.1",
        "string-width": "^4.2.3",
        "y18n": "^5.0.5",
        "yargs-parser": "^21.1.1"
      },
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/@solana-mobile/wallet-standard-mobile/node_modules/yargs-parser": {
      "version": "21.1.1",
      "resolved": "https://registry.npmjs.org/yargs-parser/-/yargs-parser-21.1.1.tgz",
      "integrity": "sha512-tVpsJW7DdjecAiFpbIB1e3qxIQsE6NoPc5/eTdrbbIC4h0LVsWhnoa3g+m2HclBIujHzsxZ4VJVA+GUuc2/LBw==",
      "license": "ISC",
      "peer": true,
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/@solana/accounts": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/accounts/-/accounts-7.1.1.tgz",
      "integrity": "sha512-7sy9VIFMdmu/7+2kVBRMU6mEvYx/DDjfam8DsBXbh+JszaTNZH3V8FutQYHRxrca3jxiumVfsy5USwKfVg8ElQ==",
      "license": "MIT",
      "dependencies": {
        "@solana/addresses": "7.1.1",
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-strings": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/rpc-spec": "7.1.1",
        "@solana/rpc-types": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/accounts/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/accounts/node_modules/@solana/codecs-numbers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-7.1.1.tgz",
      "integrity": "sha512-TWWrQq6Wp5Yf5bSc6RbxDDYCRUBBmRtRgjvUMHGp0P9K+4uFwxllRjSZFzBPHgXj3UTeZmFJdcoD271QhAgibg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/accounts/node_modules/@solana/codecs-strings": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-strings/-/codecs-strings-7.1.1.tgz",
      "integrity": "sha512-6qWl+atG60D2LmP47GyGapQFhVsG1sVhVrEaM3lV09vwrGOMeOZARZ4ObaQ5m6uQmM04G+f8dY9d17nCMbGHGg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "fastestsmallesttextencoderdecoder": "^1.0.22",
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "fastestsmallesttextencoderdecoder": {
          "optional": true
        },
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/accounts/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/accounts/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/addresses": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/addresses/-/addresses-7.1.1.tgz",
      "integrity": "sha512-/Tk2aTOT7UEcaJrdEcB3+SK09v5cZ/92NWqHBzEobxusTPNoeOFxa3MwV74Q1MgPecWdLz7TPreEhAKpcvV/vw==",
      "license": "MIT",
      "dependencies": {
        "@solana/assertions": "7.1.1",
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-strings": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/nominal-types": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/addresses/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/addresses/node_modules/@solana/codecs-numbers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-7.1.1.tgz",
      "integrity": "sha512-TWWrQq6Wp5Yf5bSc6RbxDDYCRUBBmRtRgjvUMHGp0P9K+4uFwxllRjSZFzBPHgXj3UTeZmFJdcoD271QhAgibg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/addresses/node_modules/@solana/codecs-strings": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-strings/-/codecs-strings-7.1.1.tgz",
      "integrity": "sha512-6qWl+atG60D2LmP47GyGapQFhVsG1sVhVrEaM3lV09vwrGOMeOZARZ4ObaQ5m6uQmM04G+f8dY9d17nCMbGHGg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "fastestsmallesttextencoderdecoder": "^1.0.22",
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "fastestsmallesttextencoderdecoder": {
          "optional": true
        },
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/addresses/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/addresses/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/assertions": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/assertions/-/assertions-7.1.1.tgz",
      "integrity": "sha512-tD07UKuw5i9Tw5xloVH+TUMrLzbHKixaB4DlGXumMEQU+JbYRPtFNqtMlrpVLuVM45nkbPfFp2Da0sXNRIqFHA==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/assertions/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/assertions/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/buffer-layout": {
      "version": "4.0.1",
      "resolved": "https://registry.npmjs.org/@solana/buffer-layout/-/buffer-layout-4.0.1.tgz",
      "integrity": "sha512-E1ImOIAD1tBZFRdjeM4/pzTiTApC0AOBGwyAMS4fwIodCWArzJ3DWdoh8cKxeFM2fElkxBh2Aqts1BPC373rHA==",
      "license": "MIT",
      "dependencies": {
        "buffer": "~6.0.3"
      },
      "engines": {
        "node": ">=5.10"
      }
    },
    "node_modules/@solana/buffer-layout-utils": {
      "version": "0.3.0",
      "resolved": "https://registry.npmjs.org/@solana/buffer-layout-utils/-/buffer-layout-utils-0.3.0.tgz",
      "integrity": "sha512-MuQOCC1j0np1xH9yAv0ZWWfwvr7Bt7Sz4LId11Wi4wDdAmJ+lobE+vHg/mZmGcihF0BIkqVBNxGmlv8QE5DrtA==",
      "license": "Apache-2.0",
      "dependencies": {
        "@solana/buffer-layout": "^4.0.0",
        "@solana/web3.js": "^1.32.0",
        "bigint-buffer": "^1.1.5",
        "bignumber.js": "^9.0.1"
      },
      "engines": {
        "node": ">= 10"
      }
    },
    "node_modules/@solana/codecs": {
      "version": "2.0.0-rc.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs/-/codecs-2.0.0-rc.1.tgz",
      "integrity": "sha512-qxoR7VybNJixV51L0G1RD2boZTcxmwUWnKCaJJExQ5qNKwbpSyDdWfFJfM5JhGyKe9DnPVOZB+JHWXnpbZBqrQ==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "2.0.0-rc.1",
        "@solana/codecs-data-structures": "2.0.0-rc.1",
        "@solana/codecs-numbers": "2.0.0-rc.1",
        "@solana/codecs-strings": "2.0.0-rc.1",
        "@solana/options": "2.0.0-rc.1"
      },
      "peerDependencies": {
        "typescript": ">=5"
      }
    },
    "node_modules/@solana/codecs-core": {
      "version": "2.0.0-rc.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-2.0.0-rc.1.tgz",
      "integrity": "sha512-bauxqMfSs8EHD0JKESaNmNuNvkvHSuN3bbWAF5RjOfDu2PugxHrvRebmYauvSumZ3cTfQ4HJJX6PG5rN852qyQ==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "2.0.0-rc.1"
      },
      "peerDependencies": {
        "typescript": ">=5"
      }
    },
    "node_modules/@solana/codecs-data-structures": {
      "version": "2.0.0-rc.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-data-structures/-/codecs-data-structures-2.0.0-rc.1.tgz",
      "integrity": "sha512-rinCv0RrAVJ9rE/rmaibWJQxMwC5lSaORSZuwjopSUE6T0nb/MVg6Z1siNCXhh/HFTOg0l8bNvZHgBcN/yvXog==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "2.0.0-rc.1",
        "@solana/codecs-numbers": "2.0.0-rc.1",
        "@solana/errors": "2.0.0-rc.1"
      },
      "peerDependencies": {
        "typescript": ">=5"
      }
    },
    "node_modules/@solana/codecs-numbers": {
      "version": "2.0.0-rc.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-2.0.0-rc.1.tgz",
      "integrity": "sha512-J5i5mOkvukXn8E3Z7sGIPxsThRCgSdgTWJDQeZvucQ9PT6Y3HiVXJ0pcWiOWAoQ3RX8e/f4I3IC+wE6pZiJzDQ==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "2.0.0-rc.1",
        "@solana/errors": "2.0.0-rc.1"
      },
      "peerDependencies": {
        "typescript": ">=5"
      }
    },
    "node_modules/@solana/codecs-strings": {
      "version": "2.0.0-rc.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-strings/-/codecs-strings-2.0.0-rc.1.tgz",
      "integrity": "sha512-9/wPhw8TbGRTt6mHC4Zz1RqOnuPTqq1Nb4EyuvpZ39GW6O2t2Q7Q0XxiB3+BdoEjwA2XgPw6e2iRfvYgqty44g==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "2.0.0-rc.1",
        "@solana/codecs-numbers": "2.0.0-rc.1",
        "@solana/errors": "2.0.0-rc.1"
      },
      "peerDependencies": {
        "fastestsmallesttextencoderdecoder": "^1.0.22",
        "typescript": ">=5"
      }
    },
    "node_modules/@solana/errors": {
      "version": "2.0.0-rc.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-2.0.0-rc.1.tgz",
      "integrity": "sha512-ejNvQ2oJ7+bcFAYWj225lyRkHnixuAeb7RQCixm+5mH4n1IA4Qya/9Bmfy5RAAHQzxK43clu3kZmL5eF9VGtYQ==",
      "license": "MIT",
      "dependencies": {
        "chalk": "^5.3.0",
        "commander": "^12.1.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "peerDependencies": {
        "typescript": ">=5"
      }
    },
    "node_modules/@solana/fast-stable-stringify": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/fast-stable-stringify/-/fast-stable-stringify-7.1.1.tgz",
      "integrity": "sha512-eVxOeAXYVBIWOIRfGwvuGQ6gPetQiiiOqSCK0xjwQo/yjXNVlSbpF6wLtQRnd3lbYkWsKdeV99FYe9cVY/g7/Q==",
      "license": "MIT",
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/fixed-points": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/fixed-points/-/fixed-points-7.1.1.tgz",
      "integrity": "sha512-qPj/V7kcFG/P0kuEa1U529+5L6mbkMwRIwvYBTDgBqPOt6wOdk9/c7Qn2VUQgSV0HgCXWxdHUdwaxBrYqO2ibg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/fixed-points/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/fixed-points/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/fixed-points/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/functional": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/functional/-/functional-7.1.1.tgz",
      "integrity": "sha512-AnFohvUHGrqAu3kTxxC0rZyU4JddA08hOUZ1/DT9XogCZWetBpNJktX9uNuXQe+sN4FKTX2MfL//iBFBAsxtDA==",
      "license": "MIT",
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/instruction-plans": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/instruction-plans/-/instruction-plans-7.1.1.tgz",
      "integrity": "sha512-KQGpsjeDflMcbKCdcF4KZVHcotYMS94DveRs0ZiBOsxb45dgkYrFmQ6ExJ/2exUOVF/rlp73knAP5ACrPMIAzA==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1",
        "@solana/instructions": "7.1.1",
        "@solana/keys": "7.1.1",
        "@solana/promises": "7.1.1",
        "@solana/transaction-messages": "7.1.1",
        "@solana/transactions": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/instruction-plans/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/instruction-plans/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/instructions": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/instructions/-/instructions-7.1.1.tgz",
      "integrity": "sha512-VxMpJI++RTwaqSBLIP1GTjOPLtlYOqxOJ93ug6DlSdu9jku8M/or77DiXDUi62VmEh3bbsECR646vTJXUaPArw==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/instructions/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/instructions/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/instructions/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/keys": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/keys/-/keys-7.1.1.tgz",
      "integrity": "sha512-Rx+vzWAXUa/Ko7W6wG1HOG9B3nQFZ5dALz113WoAmBZf7iQvaLG7U4ECDM/ydR+Nbdy6wYww7zQKRIye+1d+Nw==",
      "license": "MIT",
      "dependencies": {
        "@solana/assertions": "7.1.1",
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-strings": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/nominal-types": "7.1.1",
        "@solana/promises": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/keys/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/keys/node_modules/@solana/codecs-numbers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-7.1.1.tgz",
      "integrity": "sha512-TWWrQq6Wp5Yf5bSc6RbxDDYCRUBBmRtRgjvUMHGp0P9K+4uFwxllRjSZFzBPHgXj3UTeZmFJdcoD271QhAgibg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/keys/node_modules/@solana/codecs-strings": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-strings/-/codecs-strings-7.1.1.tgz",
      "integrity": "sha512-6qWl+atG60D2LmP47GyGapQFhVsG1sVhVrEaM3lV09vwrGOMeOZARZ4ObaQ5m6uQmM04G+f8dY9d17nCMbGHGg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "fastestsmallesttextencoderdecoder": "^1.0.22",
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "fastestsmallesttextencoderdecoder": {
          "optional": true
        },
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/keys/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/keys/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/kit": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/kit/-/kit-7.1.1.tgz",
      "integrity": "sha512-By3kv5d8fIMr2SPmvI41hBXUwn0XuDu2MC8B7anaLHtY8MENTKhjg8sSfybf/RTH3387ErxhxmrAijTiHqTy/g==",
      "license": "MIT",
      "dependencies": {
        "@solana/accounts": "7.1.1",
        "@solana/addresses": "7.1.1",
        "@solana/codecs": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/functional": "7.1.1",
        "@solana/instruction-plans": "7.1.1",
        "@solana/instructions": "7.1.1",
        "@solana/keys": "7.1.1",
        "@solana/offchain-messages": "7.1.1",
        "@solana/plugin-core": "7.1.1",
        "@solana/plugin-interfaces": "7.1.1",
        "@solana/program-client-core": "7.1.1",
        "@solana/programs": "7.1.1",
        "@solana/promises": "7.1.1",
        "@solana/rpc": "7.1.1",
        "@solana/rpc-api": "7.1.1",
        "@solana/rpc-parsed-types": "7.1.1",
        "@solana/rpc-spec-types": "7.1.1",
        "@solana/rpc-subscriptions": "7.1.1",
        "@solana/rpc-types": "7.1.1",
        "@solana/signers": "7.1.1",
        "@solana/subscribable": "7.1.1",
        "@solana/sysvars": "7.1.1",
        "@solana/transaction-confirmation": "7.1.1",
        "@solana/transaction-introspection": "7.1.1",
        "@solana/transaction-messages": "7.1.1",
        "@solana/transactions": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/kit/node_modules/@solana/codecs": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs/-/codecs-7.1.1.tgz",
      "integrity": "sha512-1ZErMXzbbz7+jusem58dMO1haVWNlvFYKftc2dPhFu9MqlmZRfPS06GiZDjlLnD/6PHHBy7OKFMASoYw+fBAKg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-data-structures": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/codecs-strings": "7.1.1",
        "@solana/fixed-points": "7.1.1",
        "@solana/options": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/kit/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/kit/node_modules/@solana/codecs-data-structures": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-data-structures/-/codecs-data-structures-7.1.1.tgz",
      "integrity": "sha512-MO+wMAuaatAQ96N3HhTsd7Uno+79rJw88P+OiU2n+pHK/rZuyu1yB2j12veqK4jUNWPR0aOyCuZ4rB2idrDjpg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/kit/node_modules/@solana/codecs-numbers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-7.1.1.tgz",
      "integrity": "sha512-TWWrQq6Wp5Yf5bSc6RbxDDYCRUBBmRtRgjvUMHGp0P9K+4uFwxllRjSZFzBPHgXj3UTeZmFJdcoD271QhAgibg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/kit/node_modules/@solana/codecs-strings": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-strings/-/codecs-strings-7.1.1.tgz",
      "integrity": "sha512-6qWl+atG60D2LmP47GyGapQFhVsG1sVhVrEaM3lV09vwrGOMeOZARZ4ObaQ5m6uQmM04G+f8dY9d17nCMbGHGg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "fastestsmallesttextencoderdecoder": "^1.0.22",
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "fastestsmallesttextencoderdecoder": {
          "optional": true
        },
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/kit/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/kit/node_modules/@solana/options": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/options/-/options-7.1.1.tgz",
      "integrity": "sha512-iuPpfMbnRFjC4IoAIpKNA9UpizomxjW0E3F1LxUYQHXm1vCoF78kThp4qqgx2V3DmDFbhXGtXGSJPwmDdpLoBg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-data-structures": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/codecs-strings": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/kit/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/nominal-types": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/nominal-types/-/nominal-types-7.1.1.tgz",
      "integrity": "sha512-do4rmmOlSplVYN92zV6nROJxkiRn0c7juoH1lka2Pmq+cAC3QhQXKYAwWffTFYDJJDO9qCOh00uv2hhSZi6RDw==",
      "license": "MIT",
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/offchain-messages": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/offchain-messages/-/offchain-messages-7.1.1.tgz",
      "integrity": "sha512-Py0/8HaIF0y+KSXHAWdQYDdZlGNoaqOZonTFuGKyDsrkgvod3wRc0cpZ5I/D/Rei4tVpvjNUfCXLpyoiJAZ7kg==",
      "license": "MIT",
      "dependencies": {
        "@solana/addresses": "7.1.1",
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-data-structures": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/codecs-strings": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/keys": "7.1.1",
        "@solana/nominal-types": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/offchain-messages/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/offchain-messages/node_modules/@solana/codecs-data-structures": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-data-structures/-/codecs-data-structures-7.1.1.tgz",
      "integrity": "sha512-MO+wMAuaatAQ96N3HhTsd7Uno+79rJw88P+OiU2n+pHK/rZuyu1yB2j12veqK4jUNWPR0aOyCuZ4rB2idrDjpg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/offchain-messages/node_modules/@solana/codecs-numbers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-7.1.1.tgz",
      "integrity": "sha512-TWWrQq6Wp5Yf5bSc6RbxDDYCRUBBmRtRgjvUMHGp0P9K+4uFwxllRjSZFzBPHgXj3UTeZmFJdcoD271QhAgibg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/offchain-messages/node_modules/@solana/codecs-strings": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-strings/-/codecs-strings-7.1.1.tgz",
      "integrity": "sha512-6qWl+atG60D2LmP47GyGapQFhVsG1sVhVrEaM3lV09vwrGOMeOZARZ4ObaQ5m6uQmM04G+f8dY9d17nCMbGHGg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "fastestsmallesttextencoderdecoder": "^1.0.22",
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "fastestsmallesttextencoderdecoder": {
          "optional": true
        },
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/offchain-messages/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/offchain-messages/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/options": {
      "version": "2.0.0-rc.1",
      "resolved": "https://registry.npmjs.org/@solana/options/-/options-2.0.0-rc.1.tgz",
      "integrity": "sha512-mLUcR9mZ3qfHlmMnREdIFPf9dpMc/Bl66tLSOOWxw4ml5xMT2ohFn7WGqoKcu/UHkT9CrC6+amEdqCNvUqI7AA==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "2.0.0-rc.1",
        "@solana/codecs-data-structures": "2.0.0-rc.1",
        "@solana/codecs-numbers": "2.0.0-rc.1",
        "@solana/codecs-strings": "2.0.0-rc.1",
        "@solana/errors": "2.0.0-rc.1"
      },
      "peerDependencies": {
        "typescript": ">=5"
      }
    },
    "node_modules/@solana/plugin-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/plugin-core/-/plugin-core-7.1.1.tgz",
      "integrity": "sha512-35h7+QssfnT9Rwq5spUvdGc41WtTVWzJUCbiwvnUHtVwm3z96xSPwj765UtX/enfrcRHJRTDvej2ZjsvO1aeuQ==",
      "license": "MIT",
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/plugin-interfaces": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/plugin-interfaces/-/plugin-interfaces-7.1.1.tgz",
      "integrity": "sha512-2SHkGiftGmxg5xA5esxbwiY5wf+BOUsJG5rxD64/SHadUMaN3L0SDUSJfAXETJq5dCmVWxWGGPf2yVox4RIfdA==",
      "license": "MIT",
      "dependencies": {
        "@solana/accounts": "7.1.1",
        "@solana/addresses": "7.1.1",
        "@solana/instruction-plans": "7.1.1",
        "@solana/keys": "7.1.1",
        "@solana/rpc-spec": "7.1.1",
        "@solana/rpc-subscriptions-spec": "7.1.1",
        "@solana/rpc-types": "7.1.1",
        "@solana/signers": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/program-client-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/program-client-core/-/program-client-core-7.1.1.tgz",
      "integrity": "sha512-zoMq8Qg6psj6tFYpA35xKhSrF/LpdiVflV6nKohxZg3ocwtRqRhQfbY8/mjCA9EfH8vqvsn5il5CnxALRqmJJA==",
      "license": "MIT",
      "dependencies": {
        "@solana/accounts": "7.1.1",
        "@solana/addresses": "7.1.1",
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/instruction-plans": "7.1.1",
        "@solana/instructions": "7.1.1",
        "@solana/plugin-interfaces": "7.1.1",
        "@solana/rpc-api": "7.1.1",
        "@solana/signers": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/program-client-core/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/program-client-core/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/program-client-core/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/programs": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/programs/-/programs-7.1.1.tgz",
      "integrity": "sha512-nWpJKDBxj+cRpzH+lzdp+ztEm6MAothts56s7PIPFIKJe3zGRUpske0G3jIVHOGvtzCgQtmZUMCS1uBRiDRKDQ==",
      "license": "MIT",
      "dependencies": {
        "@solana/addresses": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/programs/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/programs/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/promises": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/promises/-/promises-7.1.1.tgz",
      "integrity": "sha512-d3lhCfiFwiVyTRR6zhy1lcjDIh+l0a5gp1WPe64Vfa2gP0myC8P5C1Tknfjrp4d97DF3uBPqKAb5vV8hahNcNA==",
      "license": "MIT",
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/rpc/-/rpc-7.1.1.tgz",
      "integrity": "sha512-yXEzCrLrWb1m5QqAJEGodJ9cqu5QiwfirSZTUWiMg1JtUl4uXOm1sqWQVLrwBz/+ctvtZTvG8+bQQAemVQiqPA==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1",
        "@solana/fast-stable-stringify": "7.1.1",
        "@solana/functional": "7.1.1",
        "@solana/rpc-api": "7.1.1",
        "@solana/rpc-spec": "7.1.1",
        "@solana/rpc-spec-types": "7.1.1",
        "@solana/rpc-transformers": "7.1.1",
        "@solana/rpc-transport-http": "7.1.1",
        "@solana/rpc-types": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-api": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/rpc-api/-/rpc-api-7.1.1.tgz",
      "integrity": "sha512-ELGIqNbz8apeAxCLdD1PEPAnu6KtgHmWvUbH4VqqNg2jgWquyUOfTI5rblvdflx2Hcb7GK05w8/iiUaknOQKnw==",
      "license": "MIT",
      "dependencies": {
        "@solana/addresses": "7.1.1",
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-strings": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/keys": "7.1.1",
        "@solana/rpc-parsed-types": "7.1.1",
        "@solana/rpc-spec": "7.1.1",
        "@solana/rpc-transformers": "7.1.1",
        "@solana/rpc-types": "7.1.1",
        "@solana/transaction-messages": "7.1.1",
        "@solana/transactions": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-api/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-api/node_modules/@solana/codecs-numbers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-7.1.1.tgz",
      "integrity": "sha512-TWWrQq6Wp5Yf5bSc6RbxDDYCRUBBmRtRgjvUMHGp0P9K+4uFwxllRjSZFzBPHgXj3UTeZmFJdcoD271QhAgibg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-api/node_modules/@solana/codecs-strings": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-strings/-/codecs-strings-7.1.1.tgz",
      "integrity": "sha512-6qWl+atG60D2LmP47GyGapQFhVsG1sVhVrEaM3lV09vwrGOMeOZARZ4ObaQ5m6uQmM04G+f8dY9d17nCMbGHGg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "fastestsmallesttextencoderdecoder": "^1.0.22",
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "fastestsmallesttextencoderdecoder": {
          "optional": true
        },
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-api/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-api/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/rpc-parsed-types": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/rpc-parsed-types/-/rpc-parsed-types-7.1.1.tgz",
      "integrity": "sha512-DiQSj2rNnhOKOTs6YDjQ2y4KuOkv8lh6moLFiQnY0+TvanJrGrQjxLSrHdCUQxymQcUxzrraZL9k6vxNzId4gw==",
      "license": "MIT",
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-spec": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/rpc-spec/-/rpc-spec-7.1.1.tgz",
      "integrity": "sha512-1FwhgL18qasRYlWffdBNIUoxQyGLzdh3YMQW3y33M61vk/q1ldEGJRypV9B/SrXmxwqDiUbQ+m+zgainCTp1ZA==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1",
        "@solana/rpc-spec-types": "7.1.1",
        "@solana/subscribable": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-spec-types": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/rpc-spec-types/-/rpc-spec-types-7.1.1.tgz",
      "integrity": "sha512-FDDgXfAPfq28sQNnGhZr/+2kp5QTTcNZ5m/Q9y9Jrlux6brdPsbf9Sh1Q/lgz7i76arzNW/rzRY125RzqGWANg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-spec-types/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-spec-types/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/rpc-spec/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-spec/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/rpc-subscriptions": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/rpc-subscriptions/-/rpc-subscriptions-7.1.1.tgz",
      "integrity": "sha512-5BaCgzPnf9WSEXBdASnM7iuPWtdrXKtG16qVTfm+9icLHDAkv2y62XF6XMSQQllH2k1RvLH1yOryZazAbaIyHA==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1",
        "@solana/fast-stable-stringify": "7.1.1",
        "@solana/functional": "7.1.1",
        "@solana/promises": "7.1.1",
        "@solana/rpc-spec-types": "7.1.1",
        "@solana/rpc-subscriptions-api": "7.1.1",
        "@solana/rpc-subscriptions-channel-websocket": "7.1.1",
        "@solana/rpc-subscriptions-spec": "7.1.1",
        "@solana/rpc-transformers": "7.1.1",
        "@solana/rpc-types": "7.1.1",
        "@solana/subscribable": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-subscriptions-api": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/rpc-subscriptions-api/-/rpc-subscriptions-api-7.1.1.tgz",
      "integrity": "sha512-QTiQHmw2I/+fzeYsqII1guASiZskS7KZwPCI+6Arfk6Hxo9hBH8APuIu6uS8beSlVfnBCoOMybVDsnPF88fAoQ==",
      "license": "MIT",
      "dependencies": {
        "@solana/addresses": "7.1.1",
        "@solana/keys": "7.1.1",
        "@solana/rpc-subscriptions-spec": "7.1.1",
        "@solana/rpc-transformers": "7.1.1",
        "@solana/rpc-types": "7.1.1",
        "@solana/transaction-messages": "7.1.1",
        "@solana/transactions": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-subscriptions-channel-websocket": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/rpc-subscriptions-channel-websocket/-/rpc-subscriptions-channel-websocket-7.1.1.tgz",
      "integrity": "sha512-DRakQwjJsvbLDMDafMC9hM82YotUwSnrzqUDsrm6+e4YpKvzjXCyWlQ9kDJtrYeAA15sNVRpfs4L9Y7SoiWgrw==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1",
        "@solana/functional": "7.1.1",
        "@solana/rpc-subscriptions-spec": "7.1.1",
        "@solana/subscribable": "7.1.1",
        "ws": "^8.21.0"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-subscriptions-channel-websocket/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-subscriptions-channel-websocket/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/rpc-subscriptions-channel-websocket/node_modules/ws": {
      "version": "8.22.0",
      "resolved": "https://registry.npmjs.org/ws/-/ws-8.22.0.tgz",
      "integrity": "sha512-Ydggc987+RO0AnWtZ/7Wq9FtNvcrL1b/RO0ud9mWjUPgDrsAAwQSF51sm2hm1XofbU/4jkpGEsLFsZZxU+1DOg==",
      "license": "MIT",
      "engines": {
        "node": ">=10.0.0"
      },
      "peerDependencies": {
        "bufferutil": "^4.0.1",
        "utf-8-validate": ">=5.0.2"
      },
      "peerDependenciesMeta": {
        "bufferutil": {
          "optional": true
        },
        "utf-8-validate": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-subscriptions-spec": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/rpc-subscriptions-spec/-/rpc-subscriptions-spec-7.1.1.tgz",
      "integrity": "sha512-yrqd+fV2Ae4hkzXX42aKRmTrz3FwvzKqO4h0ahs88dzSvXpy8l6Svu1k+uRgMlZ64g2P83jfQW+3Pj5fBoxmdw==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1",
        "@solana/promises": "7.1.1",
        "@solana/rpc-spec-types": "7.1.1",
        "@solana/subscribable": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-subscriptions-spec/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-subscriptions-spec/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/rpc-subscriptions/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-subscriptions/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/rpc-transformers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/rpc-transformers/-/rpc-transformers-7.1.1.tgz",
      "integrity": "sha512-k8a/JZFso/nvPBgurOGJ/ZC6sXCtYE3lCvTj95i29pl45C4SgjdetJrAH/pWEEhQXcxaJs7OLBGmCh2enazlJw==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1",
        "@solana/functional": "7.1.1",
        "@solana/nominal-types": "7.1.1",
        "@solana/rpc-spec-types": "7.1.1",
        "@solana/rpc-types": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-transformers/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-transformers/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/rpc-transport-http": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/rpc-transport-http/-/rpc-transport-http-7.1.1.tgz",
      "integrity": "sha512-Tljuh/sSkKMHrTqdYNaguUOkZ0T+Oj4+yHsUjKAzRsyffNLa67jx9gd5CtGfz3tpBpxDLVdNvdIaZgkhFwXk9g==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1",
        "@solana/rpc-spec": "7.1.1",
        "@solana/rpc-spec-types": "7.1.1",
        "undici-types": "^8.10.0"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-transport-http/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-transport-http/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/rpc-transport-http/node_modules/undici-types": {
      "version": "8.11.2",
      "resolved": "https://registry.npmjs.org/undici-types/-/undici-types-8.11.2.tgz",
      "integrity": "sha512-iMVNmWZ0leK/goS6eXMizSzmm9CDWtyphwbaCms3DNLqRxDL+mMoNVcZMTyyVgXP0N+Z8neAMzDoUOUJL8veKg==",
      "license": "MIT"
    },
    "node_modules/@solana/rpc-types": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/rpc-types/-/rpc-types-7.1.1.tgz",
      "integrity": "sha512-yHlSUWgynaaqevuqipGhhcZnmFVNs+F6KIlbUZ0kQY6NMVtaSzx5AQrtQjbtAQzNRsRTDYkKuQg8nOruiDoseQ==",
      "license": "MIT",
      "dependencies": {
        "@solana/addresses": "7.1.1",
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/codecs-strings": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/fixed-points": "7.1.1",
        "@solana/nominal-types": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-types/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-types/node_modules/@solana/codecs-numbers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-7.1.1.tgz",
      "integrity": "sha512-TWWrQq6Wp5Yf5bSc6RbxDDYCRUBBmRtRgjvUMHGp0P9K+4uFwxllRjSZFzBPHgXj3UTeZmFJdcoD271QhAgibg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-types/node_modules/@solana/codecs-strings": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-strings/-/codecs-strings-7.1.1.tgz",
      "integrity": "sha512-6qWl+atG60D2LmP47GyGapQFhVsG1sVhVrEaM3lV09vwrGOMeOZARZ4ObaQ5m6uQmM04G+f8dY9d17nCMbGHGg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "fastestsmallesttextencoderdecoder": "^1.0.22",
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "fastestsmallesttextencoderdecoder": {
          "optional": true
        },
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-types/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc-types/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/rpc/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/rpc/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/signers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/signers/-/signers-7.1.1.tgz",
      "integrity": "sha512-UfWYnAglm21q5hS3Op1bU5mYiWfx0VesovZcIur0uYPc3EJlfBVikl8pf745x+bB77xG6lIzNbb+99t48SQbkg==",
      "license": "MIT",
      "dependencies": {
        "@solana/addresses": "7.1.1",
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/instructions": "7.1.1",
        "@solana/keys": "7.1.1",
        "@solana/nominal-types": "7.1.1",
        "@solana/offchain-messages": "7.1.1",
        "@solana/transaction-messages": "7.1.1",
        "@solana/transactions": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/signers/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/signers/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/signers/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/spl-token": {
      "version": "0.4.15",
      "resolved": "https://registry.npmjs.org/@solana/spl-token/-/spl-token-0.4.15.tgz",
      "integrity": "sha512-3Lof3mNov8NVQ3PalIWb1Jgr/TZ6lYM+/sexv2TLqdhNFVth2OfWmH3d7QucgMjSbokkjNiNlRr6I8Fd269uaw==",
      "license": "Apache-2.0",
      "dependencies": {
        "@solana/buffer-layout": "^4.0.0",
        "@solana/buffer-layout-utils": "^0.3.0",
        "@solana/spl-token-group": "^0.0.7",
        "@solana/spl-token-metadata": "^0.1.6",
        "buffer": "^6.0.3"
      },
      "engines": {
        "node": ">=16"
      },
      "peerDependencies": {
        "@solana/web3.js": "^1.95.5"
      }
    },
    "node_modules/@solana/spl-token-group": {
      "version": "0.0.7",
      "resolved": "https://registry.npmjs.org/@solana/spl-token-group/-/spl-token-group-0.0.7.tgz",
      "integrity": "sha512-V1N/iX7Cr7H0uazWUT2uk27TMqlqedpXHRqqAbVO2gvmJyT0E0ummMEAVQeXZ05ZhQ/xF39DLSdBp90XebWEug==",
      "license": "Apache-2.0",
      "dependencies": {
        "@solana/codecs": "2.0.0-rc.1"
      },
      "engines": {
        "node": ">=16"
      },
      "peerDependencies": {
        "@solana/web3.js": "^1.95.3"
      }
    },
    "node_modules/@solana/spl-token-metadata": {
      "version": "0.1.6",
      "resolved": "https://registry.npmjs.org/@solana/spl-token-metadata/-/spl-token-metadata-0.1.6.tgz",
      "integrity": "sha512-7sMt1rsm/zQOQcUWllQX9mD2O6KhSAtY1hFR2hfFwgqfFWzSY9E9GDvFVNYUI1F0iQKcm6HmePU9QbKRXTEBiA==",
      "license": "Apache-2.0",
      "dependencies": {
        "@solana/codecs": "2.0.0-rc.1"
      },
      "engines": {
        "node": ">=16"
      },
      "peerDependencies": {
        "@solana/web3.js": "^1.95.3"
      }
    },
    "node_modules/@solana/subscribable": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/subscribable/-/subscribable-7.1.1.tgz",
      "integrity": "sha512-l4Wzc2L+7WQPeC/kaCiia1aaUY/SJJdrNHnLibKchS2pb7YbF7J2OygsweHXliWCVpG0jZwcvIVpusgygbZQLw==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1",
        "@solana/promises": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/subscribable/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/subscribable/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/sysvars": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/sysvars/-/sysvars-7.1.1.tgz",
      "integrity": "sha512-EscE/HKbBRKedG6AtQ0t9LOX87bw409viferac5YSuvuDxtZvbMpCCJs89uEQPVpgvHtjMJhfsjEwMK97uG9pA==",
      "license": "MIT",
      "dependencies": {
        "@solana/accounts": "7.1.1",
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-data-structures": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/rpc-types": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/sysvars/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/sysvars/node_modules/@solana/codecs-data-structures": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-data-structures/-/codecs-data-structures-7.1.1.tgz",
      "integrity": "sha512-MO+wMAuaatAQ96N3HhTsd7Uno+79rJw88P+OiU2n+pHK/rZuyu1yB2j12veqK4jUNWPR0aOyCuZ4rB2idrDjpg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/sysvars/node_modules/@solana/codecs-numbers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-7.1.1.tgz",
      "integrity": "sha512-TWWrQq6Wp5Yf5bSc6RbxDDYCRUBBmRtRgjvUMHGp0P9K+4uFwxllRjSZFzBPHgXj3UTeZmFJdcoD271QhAgibg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/sysvars/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/sysvars/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/transaction-confirmation": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/transaction-confirmation/-/transaction-confirmation-7.1.1.tgz",
      "integrity": "sha512-Kb3V5smmMbvdft/Z/Iu9MlsF+i44f3GLK8c8TVu0+yHo41rF7OeTnOvlQ+uw1NpCfOto4GgPMFDXklIiKdauuA==",
      "license": "MIT",
      "dependencies": {
        "@solana/addresses": "7.1.1",
        "@solana/codecs-strings": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/keys": "7.1.1",
        "@solana/promises": "7.1.1",
        "@solana/rpc": "7.1.1",
        "@solana/rpc-subscriptions": "7.1.1",
        "@solana/rpc-types": "7.1.1",
        "@solana/transaction-messages": "7.1.1",
        "@solana/transactions": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-confirmation/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-confirmation/node_modules/@solana/codecs-numbers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-7.1.1.tgz",
      "integrity": "sha512-TWWrQq6Wp5Yf5bSc6RbxDDYCRUBBmRtRgjvUMHGp0P9K+4uFwxllRjSZFzBPHgXj3UTeZmFJdcoD271QhAgibg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-confirmation/node_modules/@solana/codecs-strings": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-strings/-/codecs-strings-7.1.1.tgz",
      "integrity": "sha512-6qWl+atG60D2LmP47GyGapQFhVsG1sVhVrEaM3lV09vwrGOMeOZARZ4ObaQ5m6uQmM04G+f8dY9d17nCMbGHGg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "fastestsmallesttextencoderdecoder": "^1.0.22",
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "fastestsmallesttextencoderdecoder": {
          "optional": true
        },
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-confirmation/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-confirmation/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/transaction-introspection": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/transaction-introspection/-/transaction-introspection-7.1.1.tgz",
      "integrity": "sha512-o0f/wbwmgqRSqzr+RtCG8xZ5zTMVxnYv8LBmcDDCYvTeDPEF0EfHN8Oe28c7grQsXCIeaE+zXZ2p40lkTGZy4g==",
      "license": "MIT",
      "dependencies": {
        "@solana/addresses": "7.1.1",
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-strings": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/instructions": "7.1.1",
        "@solana/rpc-types": "7.1.1",
        "@solana/transaction-messages": "7.1.1",
        "@solana/transactions": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-introspection/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-introspection/node_modules/@solana/codecs-numbers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-7.1.1.tgz",
      "integrity": "sha512-TWWrQq6Wp5Yf5bSc6RbxDDYCRUBBmRtRgjvUMHGp0P9K+4uFwxllRjSZFzBPHgXj3UTeZmFJdcoD271QhAgibg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-introspection/node_modules/@solana/codecs-strings": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-strings/-/codecs-strings-7.1.1.tgz",
      "integrity": "sha512-6qWl+atG60D2LmP47GyGapQFhVsG1sVhVrEaM3lV09vwrGOMeOZARZ4ObaQ5m6uQmM04G+f8dY9d17nCMbGHGg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "fastestsmallesttextencoderdecoder": "^1.0.22",
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "fastestsmallesttextencoderdecoder": {
          "optional": true
        },
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-introspection/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-introspection/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/transaction-messages": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/transaction-messages/-/transaction-messages-7.1.1.tgz",
      "integrity": "sha512-UBgd/TU0c8blrYDC9sD9P+wgmOOEK4OdODxD8CxB7oumN4ZAENv20u0AdZuvu1n4OwWwc1ikhtKjwg18e4wTIg==",
      "license": "MIT",
      "dependencies": {
        "@solana/addresses": "7.1.1",
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-data-structures": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/functional": "7.1.1",
        "@solana/instructions": "7.1.1",
        "@solana/nominal-types": "7.1.1",
        "@solana/rpc-types": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-messages/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-messages/node_modules/@solana/codecs-data-structures": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-data-structures/-/codecs-data-structures-7.1.1.tgz",
      "integrity": "sha512-MO+wMAuaatAQ96N3HhTsd7Uno+79rJw88P+OiU2n+pHK/rZuyu1yB2j12veqK4jUNWPR0aOyCuZ4rB2idrDjpg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-messages/node_modules/@solana/codecs-numbers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-7.1.1.tgz",
      "integrity": "sha512-TWWrQq6Wp5Yf5bSc6RbxDDYCRUBBmRtRgjvUMHGp0P9K+4uFwxllRjSZFzBPHgXj3UTeZmFJdcoD271QhAgibg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-messages/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transaction-messages/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/transactions": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/transactions/-/transactions-7.1.1.tgz",
      "integrity": "sha512-jop8y4+xiDJlocRLxqN++33Z5PDTe72HwmtgGrcIuGB4zq7U/lUX0uZM1JVcs9d3lJ3wBy2CcLTCyoYb78Swhg==",
      "license": "MIT",
      "dependencies": {
        "@solana/addresses": "7.1.1",
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-data-structures": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/codecs-strings": "7.1.1",
        "@solana/errors": "7.1.1",
        "@solana/functional": "7.1.1",
        "@solana/instructions": "7.1.1",
        "@solana/keys": "7.1.1",
        "@solana/nominal-types": "7.1.1",
        "@solana/rpc-types": "7.1.1",
        "@solana/transaction-messages": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transactions/node_modules/@solana/codecs-core": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-7.1.1.tgz",
      "integrity": "sha512-C1UOAQ7LH8RuCTfaij6hthTZeBlpp8GuD2g9Nag/xgiNKJGvAfVrcorb+kO/sufdYI8Lu+BiVvPeKOjQDQiKqg==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transactions/node_modules/@solana/codecs-data-structures": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-data-structures/-/codecs-data-structures-7.1.1.tgz",
      "integrity": "sha512-MO+wMAuaatAQ96N3HhTsd7Uno+79rJw88P+OiU2n+pHK/rZuyu1yB2j12veqK4jUNWPR0aOyCuZ4rB2idrDjpg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transactions/node_modules/@solana/codecs-numbers": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-7.1.1.tgz",
      "integrity": "sha512-TWWrQq6Wp5Yf5bSc6RbxDDYCRUBBmRtRgjvUMHGp0P9K+4uFwxllRjSZFzBPHgXj3UTeZmFJdcoD271QhAgibg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transactions/node_modules/@solana/codecs-strings": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-strings/-/codecs-strings-7.1.1.tgz",
      "integrity": "sha512-6qWl+atG60D2LmP47GyGapQFhVsG1sVhVrEaM3lV09vwrGOMeOZARZ4ObaQ5m6uQmM04G+f8dY9d17nCMbGHGg==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "7.1.1",
        "@solana/codecs-numbers": "7.1.1",
        "@solana/errors": "7.1.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "fastestsmallesttextencoderdecoder": "^1.0.22",
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "fastestsmallesttextencoderdecoder": {
          "optional": true
        },
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transactions/node_modules/@solana/errors": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-7.1.1.tgz",
      "integrity": "sha512-q35qck8rBnNvJlPU00mnHEQm7gWvghzYz8khqVoLhjgodTzGp46VqnIOyI1LXOAF6XDal58bMNDO980MQgq8yw==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "15.0.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": ">=5.4.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/transactions/node_modules/commander": {
      "version": "15.0.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz",
      "integrity": "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg==",
      "license": "MIT",
      "engines": {
        "node": ">=22.12.0"
      }
    },
    "node_modules/@solana/wallet-adapter-base": {
      "version": "0.9.28",
      "resolved": "https://registry.npmjs.org/@solana/wallet-adapter-base/-/wallet-adapter-base-0.9.28.tgz",
      "integrity": "sha512-RCowsJPUs/UgLL/AbyeB6hozVov2UzHf7TrVZkZyJ8HLbuLswJguOnFUhRg6V1YhCp6FO7+1/qXrgeWC0qm1Jg==",
      "license": "Apache-2.0",
      "dependencies": {
        "@solana/wallet-standard-features": "^1.3.0",
        "@wallet-standard/base": "^1.1.0",
        "@wallet-standard/features": "^1.1.0",
        "eventemitter3": "^5.0.1"
      },
      "engines": {
        "node": ">=20"
      },
      "peerDependencies": {
        "@solana/web3.js": "^1.99.0"
      }
    },
    "node_modules/@solana/wallet-adapter-base/node_modules/eventemitter3": {
      "version": "5.0.4",
      "resolved": "https://registry.npmjs.org/eventemitter3/-/eventemitter3-5.0.4.tgz",
      "integrity": "sha512-mlsTRyGaPBjPedk6Bvw+aqbsXDtoAyAzm5MO7JgU+yVRyMQ5O8bD4Kcci7BS85f93veegeCPkL8R4GLClnjLFw==",
      "license": "MIT"
    },
    "node_modules/@solana/wallet-adapter-react": {
      "version": "0.15.40",
      "resolved": "https://registry.npmjs.org/@solana/wallet-adapter-react/-/wallet-adapter-react-0.15.40.tgz",
      "integrity": "sha512-vgWt2+y4PGMj2VQ5amDpQaMiqFfeBlcu1DIgr13/qccwVw6swr2AhYplH1h6vQl9n3lPosIHfnwClvKWfQfiIA==",
      "license": "Apache-2.0",
      "dependencies": {
        "@solana-mobile/wallet-adapter-mobile": "^2.2.0",
        "@solana/wallet-adapter-base": "^0.9.28",
        "@solana/wallet-standard-wallet-adapter-react": "^1.1.4"
      },
      "engines": {
        "node": ">=20"
      },
      "peerDependencies": {
        "@solana/web3.js": "^1.99.0",
        "react": "*"
      }
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/@noble/curves": {
      "version": "2.4.0",
      "resolved": "https://registry.npmjs.org/@noble/curves/-/curves-2.4.0.tgz",
      "integrity": "sha512-P4/62zrgfH33CneE3Dn4WhJVA22YUU0eR51wKIan4NVRvwsA0YnPTwWGpNbpuacSujmSFLvyzpyuR30+fbq2Ew==",
      "license": "MIT",
      "dependencies": {
        "@noble/hashes": "2.4.0"
      },
      "engines": {
        "node": ">= 20.19.0"
      },
      "funding": {
        "url": "https://paulmillr.com/funding/"
      }
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/@noble/hashes": {
      "version": "2.4.0",
      "resolved": "https://registry.npmjs.org/@noble/hashes/-/hashes-2.4.0.tgz",
      "integrity": "sha512-X5XaVWZIBCT7HHZGm5I7ZQXDwLG+bGXuSrMQAW+7Zvl87h1kmc1ZB1VSRJcpUfoUrGQp4Fkoxm5kZ+Ms+aW+eA==",
      "license": "MIT",
      "engines": {
        "node": ">= 20.19.0"
      },
      "funding": {
        "url": "https://paulmillr.com/funding/"
      }
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/@react-native-async-storage/async-storage": {
      "version": "1.24.0",
      "resolved": "https://registry.npmjs.org/@react-native-async-storage/async-storage/-/async-storage-1.24.0.tgz",
      "integrity": "sha512-W4/vbwUOYOjco0x3toB8QCr7EjIP6nE9G7o8PMguvvjYT5Awg09lyV4enACRx4s++PPulBiBSjL0KTFx2u0Z/g==",
      "license": "MIT",
      "optional": true,
      "dependencies": {
        "merge-options": "^3.0.4"
      },
      "peerDependencies": {
        "react-native": "^0.0.0-0 || >=0.60 <1.0"
      }
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/@solana-mobile/mobile-wallet-adapter-protocol": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/@solana-mobile/mobile-wallet-adapter-protocol/-/mobile-wallet-adapter-protocol-2.3.0.tgz",
      "integrity": "sha512-NqAinVV9t+S65nvdUo41Z1npg4W1JjSp/K02w6xWFv2ywCdahPHpbbHYS177nDenQR2kf/8vshLOXiyV/J6HRw==",
      "license": "Apache-2.0",
      "dependencies": {
        "@noble/curves": "^2.2.0",
        "@noble/hashes": "^2.2.0",
        "@solana/kit": "^7.0.0",
        "@solana/wallet-standard-features": "^1.3.0",
        "@solana/wallet-standard-util": "^1.1.2",
        "@wallet-standard/core": "^1.1.1"
      },
      "peerDependencies": {
        "react-native": ">0.74"
      }
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/@solana-mobile/wallet-adapter-mobile": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/@solana-mobile/wallet-adapter-mobile/-/wallet-adapter-mobile-2.3.0.tgz",
      "integrity": "sha512-b49j1xUyZH0HO6vJAVCoxIVsn3kBPi9Gb2vffu0kut5rEDRSkpuo7mLJB99c0mkTl4cM0QWo0MaFweWBMyy9nQ==",
      "license": "Apache-2.0",
      "dependencies": {
        "@solana-mobile/mobile-wallet-adapter-protocol": "^2.3.0",
        "@solana-mobile/mobile-wallet-adapter-protocol-web3js": "^2.3.0",
        "@solana-mobile/wallet-standard-mobile": "^0.6.0",
        "@solana/wallet-adapter-base": "^0.9.27",
        "@solana/wallet-standard-features": "^1.3.0",
        "@wallet-standard/core": "^1.1.1",
        "tslib": "^2.8.1"
      },
      "optionalDependencies": {
        "@react-native-async-storage/async-storage": "^1.17.7"
      },
      "peerDependencies": {
        "@solana/web3.js": "^1.98.4",
        "react-native": ">0.74"
      }
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/@types/react": {
      "version": "19.3.0",
      "resolved": "https://registry.npmjs.org/@types/react/-/react-19.3.0.tgz",
      "integrity": "sha512-N0rFCuH9YoxG9/m61l9MfpJKfmLOVU0em7ipIz6TRgSSkvReLB9vL85GB+yr8Bs5leqpvg96JSwF4ZS1s4viQg==",
      "license": "MIT",
      "optional": true,
      "peer": true,
      "dependencies": {
        "csstype": "^3.2.2"
      }
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/cliui": {
      "version": "8.0.1",
      "resolved": "https://registry.npmjs.org/cliui/-/cliui-8.0.1.tgz",
      "integrity": "sha512-BSeNnyus75C4//NQ9gQt1/csTXyo/8Sb+afLAkzAptFuMsod9HFokGNudZpi/oQV73hnVK+sR+5PVRMd+Dr7YQ==",
      "license": "ISC",
      "peer": true,
      "dependencies": {
        "string-width": "^4.2.0",
        "strip-ansi": "^6.0.1",
        "wrap-ansi": "^7.0.0"
      },
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/react-native": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/react-native/-/react-native-0.87.1.tgz",
      "integrity": "sha512-DJKG6ANoD7BtrE4z9DewiSD7/RxCX73lK5Pu49aUr85P3333Dm2roTiP0rRjQNDZdVizHSOmstWfwF/o9EjCRA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@react-native/asset-utils": "0.87.1",
        "@react-native/codegen": "0.87.1",
        "@react-native/community-cli-plugin": "0.87.1",
        "@react-native/gradle-plugin": "0.87.1",
        "@react-native/normalize-colors": "0.87.1",
        "@react-native/virtualized-lists": "0.87.1",
        "anser": "^1.4.9",
        "ansi-regex": "^5.0.0",
        "babel-plugin-syntax-hermes-parser": "0.36.1",
        "base64-js": "^1.5.1",
        "commander": "^12.0.0",
        "flow-enums-runtime": "^0.0.6",
        "hermes-compiler": "250829098.0.17",
        "invariant": "^2.2.4",
        "memoize-one": "^5.0.0",
        "metro-runtime": "^0.87.0",
        "metro-source-map": "^0.87.0",
        "nullthrows": "^1.1.1",
        "pretty-format": "^29.7.0",
        "promise": "^8.3.0",
        "react-devtools-core": "^6.1.5",
        "react-refresh": "^0.14.0",
        "regenerator-runtime": "^0.13.2",
        "scheduler": "0.27.0",
        "semver": "^7.1.3",
        "stacktrace-parser": "^0.1.10",
        "tinyglobby": "^0.2.15",
        "whatwg-fetch": "^3.0.0",
        "ws": "^7.5.10",
        "yargs": "^17.6.2"
      },
      "bin": {
        "react-native": "cli.js"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      },
      "peerDependencies": {
        "@types/react": "^19.1.1",
        "react": "^19.2.3"
      },
      "peerDependenciesMeta": {
        "@types/react": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/react-native/node_modules/@react-native/virtualized-lists": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/@react-native/virtualized-lists/-/virtualized-lists-0.87.1.tgz",
      "integrity": "sha512-qSZjeX3UJrDvyfjf7yc3E68rp1XnzE+5nu8ImklhkVC0+p/XiaHPb/KGkRqDdnQyWHN55BRYSsCMEwgVI6WRNQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "invariant": "^2.2.4",
        "nullthrows": "^1.1.1"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      },
      "peerDependencies": {
        "@types/react": "^19.2.0",
        "react": "*",
        "react-native": "0.87.1"
      },
      "peerDependenciesMeta": {
        "@types/react": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/scheduler": {
      "version": "0.27.0",
      "resolved": "https://registry.npmjs.org/scheduler/-/scheduler-0.27.0.tgz",
      "integrity": "sha512-eNv+WrVbKu1f3vbYJT/xtiF5syA5HPIMtf9IgY/nKg0sWqzAUEvqY/xm7OcZc/qafLx/iO9FgOmeSAp4v5ti/Q==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/wrap-ansi": {
      "version": "7.0.0",
      "resolved": "https://registry.npmjs.org/wrap-ansi/-/wrap-ansi-7.0.0.tgz",
      "integrity": "sha512-YVGIj2kamLSTxw6NsZjoBxfSwsn0ycdesmc4p+Q21c5zPuZ1pl+NfxVdxPtdHvmNVOQ6XSYG4AUtyt/Fi7D16Q==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ansi-styles": "^4.0.0",
        "string-width": "^4.1.0",
        "strip-ansi": "^6.0.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/chalk/wrap-ansi?sponsor=1"
      }
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/y18n": {
      "version": "5.0.8",
      "resolved": "https://registry.npmjs.org/y18n/-/y18n-5.0.8.tgz",
      "integrity": "sha512-0pfFzegeDWJHJIAmTLRP2DwHjdF5s7jo9tuztdQxAhINCdvS+3nGINqPd00AphqJR/0LhANUS6/+7SCb98YOfA==",
      "license": "ISC",
      "peer": true,
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/yargs": {
      "version": "17.7.3",
      "resolved": "https://registry.npmjs.org/yargs/-/yargs-17.7.3.tgz",
      "integrity": "sha512-GZtjxm/J/4TSxuL3FNYjCmLktBTnIw/rVmKSIyKeYAZpmJB2ig9VauCC5xsa82GNKVKDAqpOn3KVzNt0zmrU0g==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "cliui": "^8.0.1",
        "escalade": "^3.1.1",
        "get-caller-file": "^2.0.5",
        "require-directory": "^2.1.1",
        "string-width": "^4.2.3",
        "y18n": "^5.0.5",
        "yargs-parser": "^21.1.1"
      },
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/@solana/wallet-adapter-react/node_modules/yargs-parser": {
      "version": "21.1.1",
      "resolved": "https://registry.npmjs.org/yargs-parser/-/yargs-parser-21.1.1.tgz",
      "integrity": "sha512-tVpsJW7DdjecAiFpbIB1e3qxIQsE6NoPc5/eTdrbbIC4h0LVsWhnoa3g+m2HclBIujHzsxZ4VJVA+GUuc2/LBw==",
      "license": "ISC",
      "peer": true,
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/@solana/wallet-standard-chains": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/@solana/wallet-standard-chains/-/wallet-standard-chains-1.1.2.tgz",
      "integrity": "sha512-EZobEGclDBAFplpJC5F3d/s8Xnlqc5isNKuPrd5o9ZPZ7tWN84O0e68yIZ8MAOj9V7ieRadNiHtql7uIXCTyXg==",
      "license": "Apache-2.0",
      "dependencies": {
        "@wallet-standard/base": "^1.1.0"
      },
      "engines": {
        "node": ">=22"
      }
    },
    "node_modules/@solana/wallet-standard-features": {
      "version": "1.5.0",
      "resolved": "https://registry.npmjs.org/@solana/wallet-standard-features/-/wallet-standard-features-1.5.0.tgz",
      "integrity": "sha512-gxlLaEfPAqbhd3LNkK0Ks2pbVvDm1SDGqBK/ynDQy13Gu+qiURLpRCfSPjbtrw5bmqQsZ6rS2YJHL31bY/Koag==",
      "license": "Apache-2.0",
      "dependencies": {
        "@wallet-standard/base": "^1.1.0",
        "@wallet-standard/features": "^1.1.0"
      },
      "engines": {
        "node": ">=22"
      }
    },
    "node_modules/@solana/wallet-standard-util": {
      "version": "1.1.4",
      "resolved": "https://registry.npmjs.org/@solana/wallet-standard-util/-/wallet-standard-util-1.1.4.tgz",
      "integrity": "sha512-vkXUXmpYAFYK3xlaAM3dYbCOtsZLeJxq4Ygxl3rfh3z0cUsxpkONkmwCNop05HdES9+IOzofZlMXF40J00LNRg==",
      "license": "Apache-2.0",
      "dependencies": {
        "@noble/curves": "^1.8.2",
        "@solana/wallet-standard-chains": "^1.1.2",
        "@solana/wallet-standard-features": "^1.5.0"
      },
      "engines": {
        "node": ">=22"
      }
    },
    "node_modules/@solana/wallet-standard-wallet-adapter-react": {
      "version": "1.1.7",
      "resolved": "https://registry.npmjs.org/@solana/wallet-standard-wallet-adapter-react/-/wallet-standard-wallet-adapter-react-1.1.7.tgz",
      "integrity": "sha512-xxOjSLJbvupgxmpclcY415WFDKMqwZZgEqrfxCuxE6NQSDXaJc2XvSIVl692nteWyi1Ln5RDMk9G7HZaD+pj/Q==",
      "license": "Apache-2.0",
      "dependencies": {
        "@solana/wallet-standard-wallet-adapter-base": "^1.1.6",
        "@wallet-standard/app": "^1.1.0",
        "@wallet-standard/base": "^1.1.0"
      },
      "engines": {
        "node": ">=22"
      },
      "peerDependencies": {
        "@solana/wallet-adapter-base": "*",
        "react": "*"
      }
    },
    "node_modules/@solana/wallet-standard-wallet-adapter-react/node_modules/@solana/wallet-standard-wallet-adapter-base": {
      "version": "1.1.6",
      "resolved": "https://registry.npmjs.org/@solana/wallet-standard-wallet-adapter-base/-/wallet-standard-wallet-adapter-base-1.1.6.tgz",
      "integrity": "sha512-SSgi5xHzuzM0a7KfDCAuFLZYqFWI8gqkff11fncaONuzX9/6b7OgLoxOkrLjycWx6+pqCQszQC/eZPBWY61SBg==",
      "license": "Apache-2.0",
      "dependencies": {
        "@solana/wallet-adapter-base": "^0.9.24",
        "@solana/wallet-standard-chains": "^1.1.2",
        "@solana/wallet-standard-features": "^1.5.0",
        "@solana/wallet-standard-util": "^1.1.4",
        "@wallet-standard/app": "^1.1.0",
        "@wallet-standard/base": "^1.1.0",
        "@wallet-standard/features": "^1.1.0",
        "@wallet-standard/wallet": "^1.1.0"
      },
      "engines": {
        "node": ">=22"
      },
      "peerDependencies": {
        "@solana/web3.js": "^1.98.0",
        "bs58": "^6.0.0"
      }
    },
    "node_modules/@solana/wallet-standard-wallet-adapter-react/node_modules/base-x": {
      "version": "5.0.1",
      "resolved": "https://registry.npmjs.org/base-x/-/base-x-5.0.1.tgz",
      "integrity": "sha512-M7uio8Zt++eg3jPj+rHMfCC+IuygQHHCOU+IYsVtik6FWjuYpVt/+MRKcgsAMHh8mMFAwnB+Bs+mTrFiXjMzKg==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/@solana/wallet-standard-wallet-adapter-react/node_modules/bs58": {
      "version": "6.0.0",
      "resolved": "https://registry.npmjs.org/bs58/-/bs58-6.0.0.tgz",
      "integrity": "sha512-PD0wEnEYg6ijszw/u8s+iI3H17cTymlrwkKhDhPZq+Sokl3AU4htyBFTjAeNAlCCmg0f53g6ih3jATyCKftTfw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "base-x": "^5.0.0"
      }
    },
    "node_modules/@solana/web3.js": {
      "version": "1.99.0",
      "resolved": "https://registry.npmjs.org/@solana/web3.js/-/web3.js-1.99.0.tgz",
      "integrity": "sha512-QZYQ2T1z6xWisoyALPq25i/QZTsRlM02BABtAsfaQ1p8wX4SdTfxrKTRue/ZZqrhNVh5oL7T/DUFiTS9DRgxow==",
      "license": "MIT",
      "dependencies": {
        "@babel/runtime": "^7.29.7",
        "@noble/curves": "^1.9.7",
        "@noble/hashes": "^1.8.0",
        "@solana/buffer-layout": "^4.0.1",
        "@solana/codecs-numbers": "^5.5.1",
        "agentkeepalive": "^4.6.0",
        "bn.js": "^5.2.5",
        "borsh": "^0.7.0",
        "bs58": "^4.0.1",
        "buffer": "6.0.3",
        "fast-stable-stringify": "^1.0.0",
        "jayson": "^4.3.0",
        "node-fetch": "^2.7.0",
        "rpc-websockets": "^9.0.2",
        "superstruct": "^2.0.2"
      }
    },
    "node_modules/@solana/web3.js/node_modules/@solana/codecs-core": {
      "version": "5.5.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-core/-/codecs-core-5.5.1.tgz",
      "integrity": "sha512-TgBt//bbKBct0t6/MpA8ElaOA3sa8eYVvR7LGslCZ84WiAwwjCY0lW/lOYsFHJQzwREMdUyuEyy5YWBKtdh8Rw==",
      "license": "MIT",
      "dependencies": {
        "@solana/errors": "5.5.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": "^5.0.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/web3.js/node_modules/@solana/codecs-numbers": {
      "version": "5.5.1",
      "resolved": "https://registry.npmjs.org/@solana/codecs-numbers/-/codecs-numbers-5.5.1.tgz",
      "integrity": "sha512-rllMIZAHqmtvC0HO/dc/21wDuWaD0B8Ryv8o+YtsICQBuiL/0U4AGwH7Pi5GNFySYk0/crSuwfIqQFtmxNSPFw==",
      "license": "MIT",
      "dependencies": {
        "@solana/codecs-core": "5.5.1",
        "@solana/errors": "5.5.1"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": "^5.0.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/web3.js/node_modules/@solana/errors": {
      "version": "5.5.1",
      "resolved": "https://registry.npmjs.org/@solana/errors/-/errors-5.5.1.tgz",
      "integrity": "sha512-vFO3p+S7HoyyrcAectnXbdsMfwUzY2zYFUc2DEe5BwpiE9J1IAxPBGjOWO6hL1bbYdBrlmjNx8DXCslqS+Kcmg==",
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "commander": "14.0.2"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=20.18.0"
      },
      "peerDependencies": {
        "typescript": "^5.0.0"
      },
      "peerDependenciesMeta": {
        "typescript": {
          "optional": true
        }
      }
    },
    "node_modules/@solana/web3.js/node_modules/commander": {
      "version": "14.0.2",
      "resolved": "https://registry.npmjs.org/commander/-/commander-14.0.2.tgz",
      "integrity": "sha512-TywoWNNRbhoD0BXs1P3ZEScW8W5iKrnbithIl0YH+uCmBd0QpPOA8yc82DS3BIE5Ma6FnBVUsJ7wVUDz4dvOWQ==",
      "license": "MIT",
      "engines": {
        "node": ">=20"
      }
    },
    "node_modules/@solana/web3.js/node_modules/superstruct": {
      "version": "2.0.2",
      "resolved": "https://registry.npmjs.org/superstruct/-/superstruct-2.0.2.tgz",
      "integrity": "sha512-uV+TFRZdXsqXTL2pRvujROjdZQ4RAlBUS5BTh9IGm+jTqQntYThciG/qu57Gs69yjnVUSqdxF9YLmSnpupBW9A==",
      "license": "MIT",
      "engines": {
        "node": ">=14.0.0"
      }
    },
    "node_modules/@swc/helpers": {
      "version": "0.5.23",
      "resolved": "https://registry.npmjs.org/@swc/helpers/-/helpers-0.5.23.tgz",
      "integrity": "sha512-5lSsMOTXURePglDfvuAQUqkGek9Hg2kksOYay2m0+XR++b2NWYL/4sWyuvVBIs8oKnJaxkdi9whaL/sqN13afw==",
      "license": "Apache-2.0",
      "dependencies": {
        "tslib": "^2.8.0"
      }
    },
    "node_modules/@types/connect": {
      "version": "3.4.38",
      "resolved": "https://registry.npmjs.org/@types/connect/-/connect-3.4.38.tgz",
      "integrity": "sha512-K6uROf1LD88uDQqJCktA4yzL1YYAK6NgfsI0v/mTgyPKWsX1CnJ0XPSDhViejru1GcRkLWb8RlzFYJRqGUbaug==",
      "license": "MIT",
      "dependencies": {
        "@types/node": "*"
      }
    },
    "node_modules/@types/estree": {
      "version": "1.0.9",
      "resolved": "https://registry.npmjs.org/@types/estree/-/estree-1.0.9.tgz",
      "integrity": "sha512-GhdPgy1el4/ImP05X05Uw4cw2/M93BCUmnEvWZNStlCzEKME4Fkk+YpoA5OiHNQmoS7Cafb8Xa3Pya8m1Qrzeg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@types/istanbul-lib-coverage": {
      "version": "2.0.6",
      "resolved": "https://registry.npmjs.org/@types/istanbul-lib-coverage/-/istanbul-lib-coverage-2.0.6.tgz",
      "integrity": "sha512-2QF/t/auWm0lsy8XtKVPG19v3sSOQlJe/YHZgfjb/KBBHOGSV+J2q/S671rcq9uTBrLAXmZpqJiaQbMT+zNU1w==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/@types/istanbul-lib-report": {
      "version": "3.0.3",
      "resolved": "https://registry.npmjs.org/@types/istanbul-lib-report/-/istanbul-lib-report-3.0.3.tgz",
      "integrity": "sha512-NQn7AHQnk/RSLOxrBbGyJM/aVQ+pjj5HCgasFxc0K/KhoATfQ/47AyUl15I2yBUpihjmas+a+VJBOqecrFH+uA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@types/istanbul-lib-coverage": "*"
      }
    },
    "node_modules/@types/istanbul-reports": {
      "version": "3.0.4",
      "resolved": "https://registry.npmjs.org/@types/istanbul-reports/-/istanbul-reports-3.0.4.tgz",
      "integrity": "sha512-pk2B1NWalF9toCRu6gjBzR69syFjP4Od8WRAX+0mmf9lAjCRicLOWc+ZrxZHx/0XRjotgkF9t6iaMJ+aXcOdZQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@types/istanbul-lib-report": "*"
      }
    },
    "node_modules/@types/node": {
      "version": "22.20.5",
      "resolved": "https://registry.npmjs.org/@types/node/-/node-22.20.5.tgz",
      "integrity": "sha512-U2+DNr+wSjpsTS/wZGYHq7GcwfuSmKiKvoPvK22zwTlRhU91yOniN4qRR5KhIjvif7ysw/dz/hKmfDH0Ris4aA==",
      "license": "MIT",
      "dependencies": {
        "undici-types": "~6.21.0"
      }
    },
    "node_modules/@types/prop-types": {
      "version": "15.7.15",
      "resolved": "https://registry.npmjs.org/@types/prop-types/-/prop-types-15.7.15.tgz",
      "integrity": "sha512-F6bEyamV9jKGAFBEmlQnesRPGOQqS2+Uwi0Em15xenOxHaf2hv6L8YCVn3rPdPJOiJfPiCnLIRyvwVaqMY3MIw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@types/react": {
      "version": "18.3.31",
      "resolved": "https://registry.npmjs.org/@types/react/-/react-18.3.31.tgz",
      "integrity": "sha512-vfEqpXTvwT91yhmwdfouStN2hSKwTvyRs8qpLfADyrq/kxDw0hZM7Wk9Ug1FELj8hIby+S/+kQCSRFF32nv2Qw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/prop-types": "*",
        "csstype": "^3.2.2"
      }
    },
    "node_modules/@types/react-dom": {
      "version": "18.3.7",
      "resolved": "https://registry.npmjs.org/@types/react-dom/-/react-dom-18.3.7.tgz",
      "integrity": "sha512-MEe3UeoENYVFXzoXEWsvcpg6ZvlrFNlOQ7EOsvhI3CfAXwzPfO8Qwuxd40nepsYKqyyVQnTdEfv68q91yLcKrQ==",
      "dev": true,
      "license": "MIT",
      "peerDependencies": {
        "@types/react": "^18.0.0"
      }
    },
    "node_modules/@types/uuid": {
      "version": "10.0.0",
      "resolved": "https://registry.npmjs.org/@types/uuid/-/uuid-10.0.0.tgz",
      "integrity": "sha512-7gqG38EyHgyP1S+7+xomFtL+ZNHcKv6DwNaCZmJmo1vgMugyF3TCnXVg4t1uk89mLNwnLtnY3TpOpCOyp1/xHQ==",
      "license": "MIT"
    },
    "node_modules/@types/ws": {
      "version": "7.4.7",
      "resolved": "https://registry.npmjs.org/@types/ws/-/ws-7.4.7.tgz",
      "integrity": "sha512-JQbbmxZTZehdc2iszGKs5oC3NFnjeay7mtAWrdt7qNtAVK0g19muApzAy4bm9byz79xa2ZnO/BOBC2R8RC5Lww==",
      "license": "MIT",
      "dependencies": {
        "@types/node": "*"
      }
    },
    "node_modules/@types/yargs": {
      "version": "17.0.35",
      "resolved": "https://registry.npmjs.org/@types/yargs/-/yargs-17.0.35.tgz",
      "integrity": "sha512-qUHkeCyQFxMXg79wQfTtfndEC+N9ZZg76HJftDJp+qH2tV7Gj4OJi7l+PiWwJ+pWtW8GwSmqsDj/oymhrTWXjg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@types/yargs-parser": "*"
      }
    },
    "node_modules/@types/yargs-parser": {
      "version": "21.0.3",
      "resolved": "https://registry.npmjs.org/@types/yargs-parser/-/yargs-parser-21.0.3.tgz",
      "integrity": "sha512-I4q9QU9MQv4oEOz4tAHJtNz1cwuLxn2F3xcc2iV5WdqLPpUnj30aUuxt1mAxYTG+oe8CZMV/+6rU4S4gRDzqtQ==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/@vitejs/plugin-react": {
      "version": "6.1.1",
      "resolved": "https://registry.npmjs.org/@vitejs/plugin-react/-/plugin-react-6.1.1.tgz",
      "integrity": "sha512-yxLaQV9gkhS8ezJqCM6+ndU7mDY6gqAg75NQ+0IjwEI8IYOmQCgkRwHKVSfWXW076DsqMo0Dk+0FK1U+M5RgFw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@rolldown/pluginutils": "^1.0.1"
      },
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      },
      "peerDependencies": {
        "@rolldown/plugin-babel": "^0.1.7 || ^0.2.0",
        "babel-plugin-react-compiler": "^1.0.0",
        "oxc-transform-react": "^0.145.0",
        "vite": "^8.0.0"
      },
      "peerDependenciesMeta": {
        "@rolldown/plugin-babel": {
          "optional": true
        },
        "babel-plugin-react-compiler": {
          "optional": true
        },
        "oxc-transform-react": {
          "optional": true
        }
      }
    },
    "node_modules/@wallet-standard/app": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/@wallet-standard/app/-/app-1.1.1.tgz",
      "integrity": "sha512-WDGwoByhP5gwHH01r5EaLgQdLVkACPCdOMQhmhn8rsm10h/siSgTorShzBxrn0ExSPof+Lu+C3TfgqBrPa1xoQ==",
      "license": "Apache-2.0",
      "dependencies": {
        "@wallet-standard/base": "^1.1.1"
      },
      "engines": {
        "node": ">=22"
      }
    },
    "node_modules/@wallet-standard/base": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/@wallet-standard/base/-/base-1.1.1.tgz",
      "integrity": "sha512-gggIHTtxicF9XFMQ12DkfS6NAG92Ak795JeSA7f2whAQ6Y3AkMWWuCMxSZXG2NIPN42kEaZSNVjqMsJRaJRxMQ==",
      "license": "Apache-2.0",
      "engines": {
        "node": ">=22"
      }
    },
    "node_modules/@wallet-standard/core": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/@wallet-standard/core/-/core-1.1.2.tgz",
      "integrity": "sha512-QcVLGDkFtsWjTpkej2jx4FyP2cu+qOAW/lVnvlWjyhCkSEje6z+vEKURV5v+7L6IXjbze5pyFBe24yrPyoUuyw==",
      "license": "Apache-2.0",
      "dependencies": {
        "@wallet-standard/app": "^1.1.1",
        "@wallet-standard/base": "^1.1.1",
        "@wallet-standard/errors": "^0.1.2",
        "@wallet-standard/features": "^1.1.1",
        "@wallet-standard/wallet": "^1.1.1"
      },
      "engines": {
        "node": ">=22"
      }
    },
    "node_modules/@wallet-standard/errors": {
      "version": "0.1.2",
      "resolved": "https://registry.npmjs.org/@wallet-standard/errors/-/errors-0.1.2.tgz",
      "integrity": "sha512-oEzKUqJefKby6wcIvaJgrSEe/uNn/rnqkJ0P/85K+h0i5Tdo9E3L22VWq/j5K1e8hHMnZd6LgaIr8m/Wn7X/Ng==",
      "license": "Apache-2.0",
      "dependencies": {
        "chalk": "^5.4.1",
        "commander": "^13.1.0"
      },
      "bin": {
        "errors": "bin/cli.mjs"
      },
      "engines": {
        "node": ">=22"
      }
    },
    "node_modules/@wallet-standard/errors/node_modules/commander": {
      "version": "13.1.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-13.1.0.tgz",
      "integrity": "sha512-/rFeCpNJQbhSZjGVwO9RFV3xPqbnERS8MmIQzCtD/zl6gpJuV/bMLuN92oG3F7d8oDEHHRrujSXNUr8fpjntKw==",
      "license": "MIT",
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@wallet-standard/features": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/@wallet-standard/features/-/features-1.1.1.tgz",
      "integrity": "sha512-aCWYmVeSCGViyEU5k7GMoW8zxE4Gs+C1s1Pp2XLesvSNlnZ4PMES9HUnTB3hl0b3RVj7C61yze3IWyrncqg4MA==",
      "license": "Apache-2.0",
      "dependencies": {
        "@wallet-standard/base": "^1.1.1"
      },
      "engines": {
        "node": ">=22"
      }
    },
    "node_modules/@wallet-standard/wallet": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/@wallet-standard/wallet/-/wallet-1.1.1.tgz",
      "integrity": "sha512-8WiRPaKk/wNNRZhB2eVhpR/JW7/aqTCMoZhgVUCujuzDmxxmGvsosMxdCG4NAdYkoyozAHCX8/xLtlWUn5mNdQ==",
      "license": "Apache-2.0",
      "dependencies": {
        "@wallet-standard/base": "^1.1.1"
      },
      "engines": {
        "node": ">=22"
      }
    },
    "node_modules/accepts": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/accepts/-/accepts-2.0.0.tgz",
      "integrity": "sha512-5cvg6CtKwfgdmVqY1WIiXKc3Q1bkRqGLi+2W/6ao+6Y7gu/RCwRuAhGEzh5B4KlszSuTLgZYuqFqo5bImjNKng==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "mime-types": "^3.0.0",
        "negotiator": "^1.0.0"
      },
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/acorn": {
      "version": "8.18.0",
      "resolved": "https://registry.npmjs.org/acorn/-/acorn-8.18.0.tgz",
      "integrity": "sha512-lGq+9yr1/GuAWaVYIHRjvvySG5/4VfKIvC8EWxStPdcDh/Ka7FG3twP6v4d5BkravUilhIAsG4Qj83t02LWUPQ==",
      "license": "MIT",
      "peer": true,
      "bin": {
        "acorn": "bin/acorn"
      },
      "engines": {
        "node": ">=0.4.0"
      }
    },
    "node_modules/agent-base": {
      "version": "7.1.4",
      "resolved": "https://registry.npmjs.org/agent-base/-/agent-base-7.1.4.tgz",
      "integrity": "sha512-MnA+YT8fwfJPgBx3m60MNqakm30XOkyIoH1y6huTQvC0PwZG7ki8NacLBcrPbNoo8vEZy7Jpuk7+jMO+CUovTQ==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 14"
      }
    },
    "node_modules/agentkeepalive": {
      "version": "4.6.0",
      "resolved": "https://registry.npmjs.org/agentkeepalive/-/agentkeepalive-4.6.0.tgz",
      "integrity": "sha512-kja8j7PjmncONqaTsB8fQ+wE2mSU2DJ9D4XKoJ5PFWIdRMa6SLSN1ff4mOr4jCbfRSsxR4keIiySJU0N9T5hIQ==",
      "license": "MIT",
      "dependencies": {
        "humanize-ms": "^1.2.1"
      },
      "engines": {
        "node": ">= 8.0.0"
      }
    },
    "node_modules/anser": {
      "version": "1.4.10",
      "resolved": "https://registry.npmjs.org/anser/-/anser-1.4.10.tgz",
      "integrity": "sha512-hCv9AqTQ8ycjpSd3upOJd7vFwW1JaoYQ7tpham03GJ1ca8/65rqn0RpaWpItOAd6ylW9wAw6luXYPJIyPFVOww==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/ansi-regex": {
      "version": "5.0.1",
      "resolved": "https://registry.npmjs.org/ansi-regex/-/ansi-regex-5.0.1.tgz",
      "integrity": "sha512-quJQXlTSUGL2LH9SUXo8VwsY4soanhgo6LNSm84E1LBcE8s3O0wpdiRzyR9z/ZZJMlMWv37qOOb9pdJlMUEKFQ==",
      "license": "MIT",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/ansi-styles": {
      "version": "4.3.0",
      "resolved": "https://registry.npmjs.org/ansi-styles/-/ansi-styles-4.3.0.tgz",
      "integrity": "sha512-zbB9rCJAT1rbjiVDb2hqKFHNYLxgtk8NURxZ3IZwD3F6NtxbXZQCnnSi1Lkx+IDohdPlFp222wVALIheZJQSEg==",
      "license": "MIT",
      "dependencies": {
        "color-convert": "^2.0.1"
      },
      "engines": {
        "node": ">=8"
      },
      "funding": {
        "url": "https://github.com/chalk/ansi-styles?sponsor=1"
      }
    },
    "node_modules/asap": {
      "version": "2.0.6",
      "resolved": "https://registry.npmjs.org/asap/-/asap-2.0.6.tgz",
      "integrity": "sha512-BSHWgDSAiKs50o2Re8ppvp3seVHXSRM44cdSsT9FfNEUUZLOGWVCsiWaRPWM1Znn+mqZ1OfVZ3z3DWEzSp7hRA==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/asn1.js": {
      "version": "4.10.1",
      "resolved": "https://registry.npmjs.org/asn1.js/-/asn1.js-4.10.1.tgz",
      "integrity": "sha512-p32cOF5q0Zqs9uBiONKYLm6BClCoBCM5O9JfeUSlnQLBTxYdTK+pW+nXflm8UkKd2UYlEbYz5qEi0JuZR9ckSw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "bn.js": "^4.0.0",
        "inherits": "^2.0.1",
        "minimalistic-assert": "^1.0.0"
      }
    },
    "node_modules/asn1.js/node_modules/bn.js": {
      "version": "4.12.5",
      "resolved": "https://registry.npmjs.org/bn.js/-/bn.js-4.12.5.tgz",
      "integrity": "sha512-3aRg6/JxfffFD+OlOjOFR3Vo79l39ooBTFucxx+MT3dhCtzn3EmiUPQo+6/OZuI2jbXi3YKgmiTFBgChQMwIRQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/assert": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/assert/-/assert-2.1.0.tgz",
      "integrity": "sha512-eLHpSK/Y4nhMJ07gDaAzoX/XAKS8PSaojml3M0DM4JpV1LAi5JOJ/p6H/XWrl8L+DzVEvVCW1z3vWAaB9oTsQw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bind": "^1.0.2",
        "is-nan": "^1.3.2",
        "object-is": "^1.1.5",
        "object.assign": "^4.1.4",
        "util": "^0.12.5"
      }
    },
    "node_modules/available-typed-arrays": {
      "version": "1.0.7",
      "resolved": "https://registry.npmjs.org/available-typed-arrays/-/available-typed-arrays-1.0.7.tgz",
      "integrity": "sha512-wvUjBtSGN7+7SjNpq/9M2Tg350UZD3q62IFZLbRAR1bSMlCo1ZaeW+BJ+D090e4hIIZLBcTDWe4Mh4jvUDajzQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "possible-typed-array-names": "^1.0.0"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/babel-plugin-syntax-hermes-parser": {
      "version": "0.36.1",
      "resolved": "https://registry.npmjs.org/babel-plugin-syntax-hermes-parser/-/babel-plugin-syntax-hermes-parser-0.36.1.tgz",
      "integrity": "sha512-ycduwJbvdvIMmVvlAZqGggS+pm5Eu4Bk9pcV9Sm2Z4PJNRVsKkv0g7vHj+LeuC1gHTeF67sJXFOq61IlqCa2hA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "hermes-parser": "0.36.1"
      }
    },
    "node_modules/base-x": {
      "version": "3.0.11",
      "resolved": "https://registry.npmjs.org/base-x/-/base-x-3.0.11.tgz",
      "integrity": "sha512-xz7wQ8xDhdyP7tQxwdteLYeFfS68tSMNCZ/Y37WJ4bhGfKPpqEIlmIyueQHqOyoPhE6xNUqjzRr8ra0eF9VRvA==",
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "^5.0.1"
      }
    },
    "node_modules/base64-js": {
      "version": "1.5.1",
      "resolved": "https://registry.npmjs.org/base64-js/-/base64-js-1.5.1.tgz",
      "integrity": "sha512-AKpaYlHn8t4SVbOHCy+b5+KKgvR4vrsD8vbvrbiQJps7fKDTkjkDry6ji0rUJjC0kzbNePLwzxq8iypo41qeWA==",
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/feross"
        },
        {
          "type": "patreon",
          "url": "https://www.patreon.com/feross"
        },
        {
          "type": "consulting",
          "url": "https://feross.org/support"
        }
      ],
      "license": "MIT"
    },
    "node_modules/baseline-browser-mapping": {
      "version": "2.11.27",
      "resolved": "https://registry.npmjs.org/baseline-browser-mapping/-/baseline-browser-mapping-2.11.27.tgz",
      "integrity": "sha512-ElY12DaROGuan+lMmZ8Cvo/ZUbXPe7Enc/9VU/b1T3Kp4dwytRcNdR8DoSJN5SNJT/CuvcCA0DHDVmMOCePdRQ==",
      "license": "Apache-2.0",
      "peer": true,
      "bin": {
        "baseline-browser-mapping": "dist/cli.cjs"
      },
      "engines": {
        "node": ">=6.0.0"
      }
    },
    "node_modules/bigint-buffer": {
      "version": "1.1.5",
      "resolved": "https://registry.npmjs.org/bigint-buffer/-/bigint-buffer-1.1.5.tgz",
      "integrity": "sha512-trfYco6AoZ+rKhKnxA0hgX0HAbVP/s808/EuDSe2JDzUnCp/xAsli35Orvk67UrTEcwuxZqYZDmfA2RXJgxVvA==",
      "hasInstallScript": true,
      "license": "Apache-2.0",
      "dependencies": {
        "bindings": "^1.3.0"
      },
      "engines": {
        "node": ">= 10.0.0"
      }
    },
    "node_modules/bignumber.js": {
      "version": "9.3.1",
      "resolved": "https://registry.npmjs.org/bignumber.js/-/bignumber.js-9.3.1.tgz",
      "integrity": "sha512-Ko0uX15oIUS7wJ3Rb30Fs6SkVbLmPBAKdlm7q9+ak9bbIeFf0MwuBsQV6z7+X768/cHsfg+WlysDWJcmthjsjQ==",
      "license": "MIT",
      "engines": {
        "node": "*"
      }
    },
    "node_modules/bindings": {
      "version": "1.5.0",
      "resolved": "https://registry.npmjs.org/bindings/-/bindings-1.5.0.tgz",
      "integrity": "sha512-p2q/t/mhvuOj/UeLlV6566GD/guowlr0hHxClI0W9m7MWYkL1F0hLo+0Aexs9HSPCtR1SXQ0TD3MMKrXZajbiQ==",
      "license": "MIT",
      "dependencies": {
        "file-uri-to-path": "1.0.0"
      }
    },
    "node_modules/bn.js": {
      "version": "5.2.5",
      "resolved": "https://registry.npmjs.org/bn.js/-/bn.js-5.2.5.tgz",
      "integrity": "sha512-Vq886eXykuP5E6HcKSSStP3bJgrE6In5WKxVUvJ8XGpWWYs2xZHWqUwzCtGgEtBcxyd57KBFDPFoUfNzdaHCNg==",
      "license": "MIT"
    },
    "node_modules/borsh": {
      "version": "0.7.0",
      "resolved": "https://registry.npmjs.org/borsh/-/borsh-0.7.0.tgz",
      "integrity": "sha512-CLCsZGIBCFnPtkNnieW/a8wmreDmfUtjU2m9yHrzPXIlNbqVs0AQrSatSG6vdNYUqdc83tkQi2eHfF98ubzQLA==",
      "license": "Apache-2.0",
      "dependencies": {
        "bn.js": "^5.2.0",
        "bs58": "^4.0.0",
        "text-encoding-utf-8": "^1.0.2"
      }
    },
    "node_modules/braces": {
      "version": "3.0.3",
      "resolved": "https://registry.npmjs.org/braces/-/braces-3.0.3.tgz",
      "integrity": "sha512-yQbXgO/OSZVD2IsiLlro+7Hf6Q18EJrKSEsdoMzKePKXct3gvD8oLcOQdIzGupr5Fj+EDe8gO/lxc1BzfMpxvA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "fill-range": "^7.1.1"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/brorand": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/brorand/-/brorand-1.1.0.tgz",
      "integrity": "sha512-cKV8tMCEpQs4hK/ik71d6LrPOnpkpGBR0wzxqr68g2m/LB2GxVYQroAjMJZRVM1Y4BCjCKc3vAamxSzOY2RP+w==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/browser-resolve": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/browser-resolve/-/browser-resolve-2.0.0.tgz",
      "integrity": "sha512-7sWsQlYL2rGLy2IWm8WL8DCTJvYLc/qlOnsakDac87SOoCd16WLsaAMdCiAqsTNHIe+SXfaqyxyo6THoWqs8WQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "resolve": "^1.17.0"
      }
    },
    "node_modules/browserify-aes": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/browserify-aes/-/browserify-aes-1.2.0.tgz",
      "integrity": "sha512-+7CHXqGuspUn/Sl5aO7Ea0xWGAtETPXNSAjHo48JfLdPWcMng33Xe4znFvQweqc/uzk5zSOI3H52CYnjCfb5hA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "buffer-xor": "^1.0.3",
        "cipher-base": "^1.0.0",
        "create-hash": "^1.1.0",
        "evp_bytestokey": "^1.0.3",
        "inherits": "^2.0.1",
        "safe-buffer": "^5.0.1"
      }
    },
    "node_modules/browserify-cipher": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/browserify-cipher/-/browserify-cipher-1.0.1.tgz",
      "integrity": "sha512-sPhkz0ARKbf4rRQt2hTpAHqn47X3llLkUGn+xEJzLjwY8LRs2p0v7ljvI5EyoRO/mexrNunNECisZs+gw2zz1w==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "browserify-aes": "^1.0.4",
        "browserify-des": "^1.0.0",
        "evp_bytestokey": "^1.0.0"
      }
    },
    "node_modules/browserify-des": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/browserify-des/-/browserify-des-1.0.2.tgz",
      "integrity": "sha512-BioO1xf3hFwz4kc6iBhI3ieDFompMhrMlnDFC4/0/vd5MokpuAc3R+LYbwTA9A5Yc9pq9UYPqffKpW2ObuwX5A==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "cipher-base": "^1.0.1",
        "des.js": "^1.0.0",
        "inherits": "^2.0.1",
        "safe-buffer": "^5.1.2"
      }
    },
    "node_modules/browserify-rsa": {
      "version": "4.1.1",
      "resolved": "https://registry.npmjs.org/browserify-rsa/-/browserify-rsa-4.1.1.tgz",
      "integrity": "sha512-YBjSAiTqM04ZVei6sXighu679a3SqWORA3qZTEqZImnlkDIFtKc6pNutpjyZ8RJTjQtuYfeetkxM11GwoYXMIQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "bn.js": "^5.2.1",
        "randombytes": "^2.1.0",
        "safe-buffer": "^5.2.1"
      },
      "engines": {
        "node": ">= 0.10"
      }
    },
    "node_modules/browserify-sign": {
      "version": "4.2.6",
      "resolved": "https://registry.npmjs.org/browserify-sign/-/browserify-sign-4.2.6.tgz",
      "integrity": "sha512-sd+Q65fjlWCYWtZKXiKfrUc8d+4jtp/8f0W2NkwzLtoW4bI6UDnWusLWIurHnmurW0XShIRxpwiOX4EoPtXUAg==",
      "dev": true,
      "license": "ISC",
      "dependencies": {
        "bn.js": "^5.2.3",
        "browserify-rsa": "^4.1.1",
        "create-hash": "^1.2.0",
        "create-hmac": "^1.1.7",
        "elliptic": "^6.6.1",
        "inherits": "^2.0.4",
        "parse-asn1": "^5.1.9",
        "readable-stream": "^2.3.8",
        "safe-buffer": "^5.2.1"
      },
      "engines": {
        "node": ">= 0.10"
      }
    },
    "node_modules/browserify-sign/node_modules/isarray": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/isarray/-/isarray-1.0.0.tgz",
      "integrity": "sha512-VLghIWNM6ELQzo7zwmcg0NmTVyWKYjvIeM83yjp0wRDTmUnrM678fQbcKBo6n2CJEF0szoG//ytg+TKla89ALQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/browserify-sign/node_modules/readable-stream": {
      "version": "2.3.8",
      "resolved": "https://registry.npmjs.org/readable-stream/-/readable-stream-2.3.8.tgz",
      "integrity": "sha512-8p0AUk4XODgIewSi0l8Epjs+EVnWiK7NoDIEGU0HhE7+ZyY8D1IMY7odu5lRrFXGg71L15KG8QrPmum45RTtdA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "core-util-is": "~1.0.0",
        "inherits": "~2.0.3",
        "isarray": "~1.0.0",
        "process-nextick-args": "~2.0.0",
        "safe-buffer": "~5.1.1",
        "string_decoder": "~1.1.1",
        "util-deprecate": "~1.0.1"
      }
    },
    "node_modules/browserify-sign/node_modules/readable-stream/node_modules/safe-buffer": {
      "version": "5.1.2",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.1.2.tgz",
      "integrity": "sha512-Gd2UZBJDkXlY7GbJxfsE8/nvKkUEU1G38c1siN6QP6a9PT9MmHB8GnpscSmMJSoF8LOIrt8ud/wPtojys4G6+g==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/browserify-sign/node_modules/string_decoder": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/string_decoder/-/string_decoder-1.1.1.tgz",
      "integrity": "sha512-n/ShnvDi6FHbbVfviro+WojiFzv+s8MPMHBczVePfUpDJLwoLT0ht1l4YwBCbi8pJAveEEdnkHyPyTP/mzRfwg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "~5.1.0"
      }
    },
    "node_modules/browserify-sign/node_modules/string_decoder/node_modules/safe-buffer": {
      "version": "5.1.2",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.1.2.tgz",
      "integrity": "sha512-Gd2UZBJDkXlY7GbJxfsE8/nvKkUEU1G38c1siN6QP6a9PT9MmHB8GnpscSmMJSoF8LOIrt8ud/wPtojys4G6+g==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/browserify-zlib": {
      "version": "0.2.0",
      "resolved": "https://registry.npmjs.org/browserify-zlib/-/browserify-zlib-0.2.0.tgz",
      "integrity": "sha512-Z942RysHXmJrhqk88FmKBVq/v5tqmSkDz7p54G/MGyjMnCFFnC79XWNbg+Vta8W6Wb2qtSZTSxIGkJrRpCFEiA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "pako": "~1.0.5"
      }
    },
    "node_modules/browserify-zlib/node_modules/pako": {
      "version": "1.0.11",
      "resolved": "https://registry.npmjs.org/pako/-/pako-1.0.11.tgz",
      "integrity": "sha512-4hLB8Py4zZce5s4yd9XzopqwVv/yGNhV1Bl8NTmCq1763HeK2+EwVTv+leGeL13Dnh2wfbqowVPXCIO0z4taYw==",
      "dev": true,
      "license": "(MIT AND Zlib)"
    },
    "node_modules/browserslist": {
      "version": "4.29.3",
      "resolved": "https://registry.npmjs.org/browserslist/-/browserslist-4.29.3.tgz",
      "integrity": "sha512-1R4kiYKXGViqEN0CnoDrXc1StD9niAwu+j2dukWzrD4bJgsD4lDmEp0CRbc6E/vYJIfTHwPmwyaKtVSudICdPA==",
      "funding": [
        {
          "type": "opencollective",
          "url": "https://opencollective.com/browserslist"
        },
        {
          "type": "tidelift",
          "url": "https://tidelift.com/funding/github/npm/browserslist"
        },
        {
          "type": "github",
          "url": "https://github.com/sponsors/ai"
        }
      ],
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "baseline-browser-mapping": "^2.11.26",
        "caniuse-lite": "^1.0.30001813",
        "electron-to-chromium": "^1.5.439",
        "node-releases": "^2.0.57",
        "update-browserslist-db": "^1.3.3"
      },
      "bin": {
        "browserslist": "cli.js"
      },
      "engines": {
        "node": "^6 || ^7 || ^8 || ^9 || ^10 || ^11 || ^12 || >=13.7"
      }
    },
    "node_modules/bs58": {
      "version": "4.0.1",
      "resolved": "https://registry.npmjs.org/bs58/-/bs58-4.0.1.tgz",
      "integrity": "sha512-Ok3Wdf5vOIlBrgCvTq96gBkJw+JUEzdBgyaza5HLtPm7yTHkjRy8+JzNyHF7BHa0bNWOQIp3m5YF0nnFcOIKLw==",
      "license": "MIT",
      "dependencies": {
        "base-x": "^3.0.2"
      }
    },
    "node_modules/bser": {
      "version": "2.1.1",
      "resolved": "https://registry.npmjs.org/bser/-/bser-2.1.1.tgz",
      "integrity": "sha512-gQxTNE/GAfIIrmHLUE3oJyp5FO6HRBfhjnw4/wMmA63ZGDJnWBmgY/lyQBpnDUkGmAhbSe39tx2d/iTOAfglwQ==",
      "license": "Apache-2.0",
      "peer": true,
      "dependencies": {
        "node-int64": "^0.4.0"
      }
    },
    "node_modules/buffer": {
      "version": "6.0.3",
      "resolved": "https://registry.npmjs.org/buffer/-/buffer-6.0.3.tgz",
      "integrity": "sha512-FTiCpNxtwiZZHEZbcbTIcZjERVICn9yq/pDFkTl95/AxzD1naBctN7YO68riM/gLSDY7sdrMby8hofADYuuqOA==",
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/feross"
        },
        {
          "type": "patreon",
          "url": "https://www.patreon.com/feross"
        },
        {
          "type": "consulting",
          "url": "https://feross.org/support"
        }
      ],
      "license": "MIT",
      "dependencies": {
        "base64-js": "^1.3.1",
        "ieee754": "^1.2.1"
      }
    },
    "node_modules/buffer-from": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/buffer-from/-/buffer-from-1.1.2.tgz",
      "integrity": "sha512-E+XQCRwSbaaiChtv6k6Dwgc+bx+Bs6vuKJHHl5kox/BaKbhiXzqQOwK4cO22yElGp2OCmjwVhT3HmxgyPGnJfQ==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/buffer-layout": {
      "version": "1.2.2",
      "resolved": "https://registry.npmjs.org/buffer-layout/-/buffer-layout-1.2.2.tgz",
      "integrity": "sha512-kWSuLN694+KTk8SrYvCqwP2WcgQjoRCiF5b4QDvkkz8EmgD+aWAIceGFKMIAdmF/pH+vpgNV3d3kAKorcdAmWA==",
      "license": "MIT",
      "engines": {
        "node": ">=4.5"
      }
    },
    "node_modules/buffer-xor": {
      "version": "1.0.3",
      "resolved": "https://registry.npmjs.org/buffer-xor/-/buffer-xor-1.0.3.tgz",
      "integrity": "sha512-571s0T7nZWK6vB67HI5dyUF7wXiNcfaPPPTl6zYCNApANjIvYJTg7hlud/+cJpdAhS7dVzqMLmfhfHR3rAcOjQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/bufferutil": {
      "version": "4.1.0",
      "resolved": "https://registry.npmjs.org/bufferutil/-/bufferutil-4.1.0.tgz",
      "integrity": "sha512-ZMANVnAixE6AWWnPzlW2KpUrxhm9woycYvPOo67jWHyFowASTEd9s+QN1EIMsSDtwhIxN4sWE1jotpuDUIgyIw==",
      "hasInstallScript": true,
      "license": "MIT",
      "optional": true,
      "dependencies": {
        "node-gyp-build": "^4.3.0"
      },
      "engines": {
        "node": ">=6.14.2"
      }
    },
    "node_modules/builtin-status-codes": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/builtin-status-codes/-/builtin-status-codes-3.0.0.tgz",
      "integrity": "sha512-HpGFw18DgFWlncDfjTa2rcQ4W88O1mC8e8yZ2AvQY5KDaktSTwo+KRf6nHK6FRI5FyRyb/5T6+TSxfP7QyGsmQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/call-bind": {
      "version": "1.0.9",
      "resolved": "https://registry.npmjs.org/call-bind/-/call-bind-1.0.9.tgz",
      "integrity": "sha512-a/hy+pNsFUTR+Iz8TCJvXudKVLAnz/DyeSUo10I5yvFDQJBFU2s9uqQpoSrJlroHUKoKqzg+epxyP9lqFdzfBQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bind-apply-helpers": "^1.0.2",
        "es-define-property": "^1.0.1",
        "get-intrinsic": "^1.3.0",
        "set-function-length": "^1.2.2"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/call-bind-apply-helpers": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/call-bind-apply-helpers/-/call-bind-apply-helpers-1.0.2.tgz",
      "integrity": "sha512-Sp1ablJ0ivDkSzjcaJdxEunN5/XvksFJ2sMBFfq6x0ryhQV/2b/KwFe21cMpmHtPOSij8K99/wSfoEuTObmuMQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0",
        "function-bind": "^1.1.2"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/call-bound": {
      "version": "1.0.4",
      "resolved": "https://registry.npmjs.org/call-bound/-/call-bound-1.0.4.tgz",
      "integrity": "sha512-+ys997U96po4Kx/ABpBCqhA9EuxJaQWDQg7295H4hBphv3IZg0boBKuwYpt4YXp6MZ5AmZQnU/tyMTlRpaSejg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bind-apply-helpers": "^1.0.2",
        "get-intrinsic": "^1.3.0"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/camelcase": {
      "version": "6.3.0",
      "resolved": "https://registry.npmjs.org/camelcase/-/camelcase-6.3.0.tgz",
      "integrity": "sha512-Gmy6FhYlCY7uOElZUSbxo2UCDH8owEk996gkbrpsgGtrJLM3J7jGxl9Ic7Qwwj4ivOE5AWZWRMecDdF7hqGjFA==",
      "license": "MIT",
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/caniuse-lite": {
      "version": "1.0.30001814",
      "resolved": "https://registry.npmjs.org/caniuse-lite/-/caniuse-lite-1.0.30001814.tgz",
      "integrity": "sha512-/Uaf1lAzr59XcMpW0o96WoEfr+VXK2OX4U9AgFoiSHsVJ4HppnIFUjtYzsyDH2+tgANaQb2/oxYGwCPapN1FpA==",
      "funding": [
        {
          "type": "opencollective",
          "url": "https://opencollective.com/browserslist"
        },
        {
          "type": "tidelift",
          "url": "https://tidelift.com/funding/github/npm/caniuse-lite"
        },
        {
          "type": "github",
          "url": "https://github.com/sponsors/ai"
        }
      ],
      "license": "CC-BY-4.0",
      "peer": true
    },
    "node_modules/chalk": {
      "version": "5.6.2",
      "resolved": "https://registry.npmjs.org/chalk/-/chalk-5.6.2.tgz",
      "integrity": "sha512-7NzBL0rN6fMUW+f7A6Io4h40qQlG+xGmtMxfbnH/K7TAtt8JQWVQK+6g0UXKMeVJoyV5EkkNsErQ8pVD3bLHbA==",
      "license": "MIT",
      "engines": {
        "node": "^12.17.0 || ^14.13 || >=16.0.0"
      },
      "funding": {
        "url": "https://github.com/chalk/chalk?sponsor=1"
      }
    },
    "node_modules/chrome-launcher": {
      "version": "0.15.2",
      "resolved": "https://registry.npmjs.org/chrome-launcher/-/chrome-launcher-0.15.2.tgz",
      "integrity": "sha512-zdLEwNo3aUVzIhKhTtXfxhdvZhUghrnmkvcAq2NoDd+LeOHKf03H5jwZ8T/STsAlzyALkBVK552iaG1fGf1xVQ==",
      "license": "Apache-2.0",
      "peer": true,
      "dependencies": {
        "@types/node": "*",
        "escape-string-regexp": "^4.0.0",
        "is-wsl": "^2.2.0",
        "lighthouse-logger": "^1.0.0"
      },
      "bin": {
        "print-chrome-path": "bin/print-chrome-path.js"
      },
      "engines": {
        "node": ">=12.13.0"
      }
    },
    "node_modules/chromium-edge-launcher": {
      "version": "0.3.0",
      "resolved": "https://registry.npmjs.org/chromium-edge-launcher/-/chromium-edge-launcher-0.3.0.tgz",
      "integrity": "sha512-p03azHlGjtyRvFEee3cyvtsRYdniSkwjkzmM/KmVnqT5d7QkkwpJBhis/zCLMYdQMVJ5tt140TBNqqrZPaWeFA==",
      "license": "Apache-2.0",
      "peer": true,
      "dependencies": {
        "@types/node": "*",
        "escape-string-regexp": "^4.0.0",
        "is-wsl": "^2.2.0",
        "lighthouse-logger": "^1.0.0",
        "mkdirp": "^1.0.4"
      }
    },
    "node_modules/ci-info": {
      "version": "3.9.0",
      "resolved": "https://registry.npmjs.org/ci-info/-/ci-info-3.9.0.tgz",
      "integrity": "sha512-NIxF55hv4nSqQswkAeiOi1r83xy8JldOFDTWiug55KBu9Jnblncd2U6ViHmYgHf01TPZS77NJBhBMKdWj9HQMQ==",
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/sibiraj-s"
        }
      ],
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/cipher-base": {
      "version": "1.0.7",
      "resolved": "https://registry.npmjs.org/cipher-base/-/cipher-base-1.0.7.tgz",
      "integrity": "sha512-Mz9QMT5fJe7bKI7MH31UilT5cEK5EHHRCccw/YRFsRY47AuNgaV6HY3rscp0/I4Q+tTW/5zoqpSeRRI54TkDWA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "inherits": "^2.0.4",
        "safe-buffer": "^5.2.1",
        "to-buffer": "^1.2.2"
      },
      "engines": {
        "node": ">= 0.10"
      }
    },
    "node_modules/cliui": {
      "version": "6.0.0",
      "resolved": "https://registry.npmjs.org/cliui/-/cliui-6.0.0.tgz",
      "integrity": "sha512-t6wbgtoCXvAzst7QgXxJYqPt0usEfbgQdftEPbLL/cvv6HPE5VgvqCuAIDR0NgU52ds6rFwqrgakNLrHEjCbrQ==",
      "license": "ISC",
      "dependencies": {
        "string-width": "^4.2.0",
        "strip-ansi": "^6.0.0",
        "wrap-ansi": "^6.2.0"
      }
    },
    "node_modules/color-convert": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/color-convert/-/color-convert-2.0.1.tgz",
      "integrity": "sha512-RRECPsj7iu/xb5oKYcsFHSppFNnsj/52OVTRKb4zP5onXwVF3zVmmToNcOfGC+CRDpfK/U584fMg38ZHCaElKQ==",
      "license": "MIT",
      "dependencies": {
        "color-name": "~1.1.4"
      },
      "engines": {
        "node": ">=7.0.0"
      }
    },
    "node_modules/color-name": {
      "version": "1.1.4",
      "resolved": "https://registry.npmjs.org/color-name/-/color-name-1.1.4.tgz",
      "integrity": "sha512-dOy+3AuW3a2wNbZHIuMZpTcgjGuLU/uBL/ubcZF9OXbDo8ff4O8yVp5Bf0efS8uEoYo5q4Fx7dY9OgQGXgAsQA==",
      "license": "MIT"
    },
    "node_modules/commander": {
      "version": "12.1.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-12.1.0.tgz",
      "integrity": "sha512-Vw8qHK3bZM9y/P10u3Vib8o/DdkvA2OtPtZvD871QKjy74Wj1WSKFILMPRPSdUSx5RFK1arlJzEtA4PkFgnbuA==",
      "license": "MIT",
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/connect": {
      "version": "3.7.0",
      "resolved": "https://registry.npmjs.org/connect/-/connect-3.7.0.tgz",
      "integrity": "sha512-ZqRXc+tZukToSNmh5C2iWMSoV3X1YUcPbqEM4DkEG5tNQXrQUZCNVGGv3IuicnkMtPfGf3Xtp8WCXs295iQ1pQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "debug": "2.6.9",
        "finalhandler": "1.1.2",
        "parseurl": "~1.3.3",
        "utils-merge": "1.0.1"
      },
      "engines": {
        "node": ">= 0.10.0"
      }
    },
    "node_modules/connect/node_modules/debug": {
      "version": "2.6.9",
      "resolved": "https://registry.npmjs.org/debug/-/debug-2.6.9.tgz",
      "integrity": "sha512-bC7ElrdJaJnPbAP+1EotYvqZsb3ecl5wi6Bfi6BJTUcNowp6cvspg0jXznRTKDjm/E7AdgFBVeAPVMNcKGsHMA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ms": "2.0.0"
      }
    },
    "node_modules/connect/node_modules/ms": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/ms/-/ms-2.0.0.tgz",
      "integrity": "sha512-Tpp60P6IUJDTuOq/5Z8cdskzJujfwqfOTkrwIwj7IRISpnkJnT6SyJ4PCPnGMoFjC9ddhal5KVIYtAt97ix05A==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/console-browserify": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/console-browserify/-/console-browserify-1.2.0.tgz",
      "integrity": "sha512-ZMkYO/LkF17QvCPqM0gxw8yUzigAOZOSWSHg91FH6orS7vcEj5dVZTidN2fQ14yBSdg97RqhSNwLUXInd52OTA==",
      "dev": true
    },
    "node_modules/constants-browserify": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/constants-browserify/-/constants-browserify-1.0.0.tgz",
      "integrity": "sha512-xFxOwqIzR/e1k1gLiWEophSCMqXcwVHIH7akf7b/vxcUeGunlj3hvZaaqxwHsTgn+IndtkQJgSztIDWeumWJDQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/content-type": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/content-type/-/content-type-2.1.0.tgz",
      "integrity": "sha512-mj7UPXE0jaqaOsukNZRUEfEi2AcL7C/vwmwcHV0O97eO1E1pxBZuyjlZrx5seTaNBg1U6+o35wpa35Qfcc+7ag==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/convert-source-map": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/convert-source-map/-/convert-source-map-2.0.0.tgz",
      "integrity": "sha512-Kvp459HrV2FEJ1CAsi1Ku+MY3kasH19TFykTz2xWmMeq6bk2NU3XXvfJ+Q61m0xktWwt+1HSYf3JZsTms3aRJg==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/core-util-is": {
      "version": "1.0.3",
      "resolved": "https://registry.npmjs.org/core-util-is/-/core-util-is-1.0.3.tgz",
      "integrity": "sha512-ZQBvi1DcpJ4GDqanjucZ2Hj3wEO5pZDS89BWbkcrvdxksJorwUDDZamX9ldFkp9aw2lmBDLgkObEA4DWNJ9FYQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/create-ecdh": {
      "version": "4.0.4",
      "resolved": "https://registry.npmjs.org/create-ecdh/-/create-ecdh-4.0.4.tgz",
      "integrity": "sha512-mf+TCx8wWc9VpuxfP2ht0iSISLZnt0JgWlrOKZiNqyUZWnjIaCIVNQArMHnCZKfEYRg6IM7A+NeJoN8gf/Ws0A==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "bn.js": "^4.1.0",
        "elliptic": "^6.5.3"
      }
    },
    "node_modules/create-ecdh/node_modules/bn.js": {
      "version": "4.12.5",
      "resolved": "https://registry.npmjs.org/bn.js/-/bn.js-4.12.5.tgz",
      "integrity": "sha512-3aRg6/JxfffFD+OlOjOFR3Vo79l39ooBTFucxx+MT3dhCtzn3EmiUPQo+6/OZuI2jbXi3YKgmiTFBgChQMwIRQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/create-hash": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/create-hash/-/create-hash-1.2.0.tgz",
      "integrity": "sha512-z00bCGNHDG8mHAkP7CtT1qVu+bFQUPjYq/4Iv3C3kWjTFV10zIjfSoeqXo9Asws8gwSHDGj/hl2u4OGIjapeCg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "cipher-base": "^1.0.1",
        "inherits": "^2.0.1",
        "md5.js": "^1.3.4",
        "ripemd160": "^2.0.1",
        "sha.js": "^2.4.0"
      }
    },
    "node_modules/create-hmac": {
      "version": "1.1.7",
      "resolved": "https://registry.npmjs.org/create-hmac/-/create-hmac-1.1.7.tgz",
      "integrity": "sha512-MJG9liiZ+ogc4TzUwuvbER1JRdgvUFSB5+VR/g5h82fGaIRWMWddtKBHi7/sVhfjQZ6SehlyhvQYrcYkaUIpLg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "cipher-base": "^1.0.3",
        "create-hash": "^1.1.0",
        "inherits": "^2.0.1",
        "ripemd160": "^2.0.0",
        "safe-buffer": "^5.0.1",
        "sha.js": "^2.4.8"
      }
    },
    "node_modules/create-require": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/create-require/-/create-require-1.1.1.tgz",
      "integrity": "sha512-dcKFX3jn0MpIaXjisoRvexIJVEKzaq7z2rZKxf+MSr9TkdmHmsU4m2lcLojrj/FHl8mk5VxMmYA+ftRkP/3oKQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/cross-fetch": {
      "version": "3.2.0",
      "resolved": "https://registry.npmjs.org/cross-fetch/-/cross-fetch-3.2.0.tgz",
      "integrity": "sha512-Q+xVJLoGOeIMXZmbUK4HYk+69cQH6LudR0Vu/pRm2YlU/hDV9CiS0gKUMaWY5f2NeUH9C1nV3bsTlCo0FsTV1Q==",
      "license": "MIT",
      "dependencies": {
        "node-fetch": "^2.7.0"
      }
    },
    "node_modules/cross-spawn": {
      "version": "7.0.6",
      "resolved": "https://registry.npmjs.org/cross-spawn/-/cross-spawn-7.0.6.tgz",
      "integrity": "sha512-uV2QOWP2nWzsy2aMp8aRibhi9dlzF5Hgh5SHaB9OiTGEyDTiJJyx0uy51QXdyWbtAHNua4XJzUKca3OzKUd3vA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "path-key": "^3.1.0",
        "shebang-command": "^2.0.0",
        "which": "^2.0.1"
      },
      "engines": {
        "node": ">= 8"
      }
    },
    "node_modules/crypto-browserify": {
      "version": "3.12.1",
      "resolved": "https://registry.npmjs.org/crypto-browserify/-/crypto-browserify-3.12.1.tgz",
      "integrity": "sha512-r4ESw/IlusD17lgQi1O20Fa3qNnsckR126TdUuBgAu7GBYSIPvdNyONd3Zrxh0xCwA4+6w/TDArBPsMvhur+KQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "browserify-cipher": "^1.0.1",
        "browserify-sign": "^4.2.3",
        "create-ecdh": "^4.0.4",
        "create-hash": "^1.2.0",
        "create-hmac": "^1.1.7",
        "diffie-hellman": "^5.0.3",
        "hash-base": "~3.0.4",
        "inherits": "^2.0.4",
        "pbkdf2": "^3.1.2",
        "public-encrypt": "^4.0.3",
        "randombytes": "^2.1.0",
        "randomfill": "^1.0.4"
      },
      "engines": {
        "node": ">= 0.10"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/csstype": {
      "version": "3.2.3",
      "resolved": "https://registry.npmjs.org/csstype/-/csstype-3.2.3.tgz",
      "integrity": "sha512-z1HGKcYy2xA8AGQfwrn0PAy+PB7X/GSj3UVJW9qKyn43xWa+gl5nXmU4qqLMRzWVLFC8KusUX8T/0kCiOYpAIQ==",
      "devOptional": true,
      "license": "MIT"
    },
    "node_modules/debug": {
      "version": "4.4.3",
      "resolved": "https://registry.npmjs.org/debug/-/debug-4.4.3.tgz",
      "integrity": "sha512-RGwwWnwQvkVfavKVt22FGLw+xYSdzARwm0ru6DhTVA3umU5hZc28V3kO4stgYryrTlLpuvgI9GiijltAjNbcqA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ms": "^2.1.3"
      },
      "engines": {
        "node": ">=6.0"
      },
      "peerDependenciesMeta": {
        "supports-color": {
          "optional": true
        }
      }
    },
    "node_modules/decamelize": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/decamelize/-/decamelize-1.2.0.tgz",
      "integrity": "sha512-z2S+W9X73hAUUki+N+9Za2lBlun89zigOyGrsax+KUQ6wKW4ZoWpEYBkGhQjwAjjDCkWxhY0VKEhk8wzY7F5cA==",
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/decimal.js": {
      "version": "10.6.0",
      "resolved": "https://registry.npmjs.org/decimal.js/-/decimal.js-10.6.0.tgz",
      "integrity": "sha512-YpgQiITW3JXGntzdUmyUR1V812Hn8T1YVXhCu+wO3OpS4eU9l4YdD3qjyiKdV6mvV29zapkMeD390UVEf2lkUg==",
      "license": "MIT"
    },
    "node_modules/define-data-property": {
      "version": "1.1.4",
      "resolved": "https://registry.npmjs.org/define-data-property/-/define-data-property-1.1.4.tgz",
      "integrity": "sha512-rBMvIzlpA8v6E+SJZoo++HAYqsLrkg7MSfIinMPFhmkorw7X+dOXVJQs+QT69zGkzMyfDnIMN2Wid1+NbL3T+A==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "es-define-property": "^1.0.0",
        "es-errors": "^1.3.0",
        "gopd": "^1.0.1"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/define-properties": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/define-properties/-/define-properties-1.2.1.tgz",
      "integrity": "sha512-8QmQKqEASLd5nx0U1B1okLElbUuuttJ/AnYmRXbbbGDWh6uS208EjD4Xqq/I9wK7u0v6O08XhTWnt5XtEbR6Dg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "define-data-property": "^1.0.1",
        "has-property-descriptors": "^1.0.0",
        "object-keys": "^1.1.1"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/delay": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/delay/-/delay-5.0.0.tgz",
      "integrity": "sha512-ReEBKkIfe4ya47wlPYf/gu5ib6yUG0/Aez0JQZQz94kiWtRQvZIQbTiehsnwHvLSWJnQdhVeqYue7Id1dKr0qw==",
      "license": "MIT",
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/depd": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/depd/-/depd-2.0.0.tgz",
      "integrity": "sha512-g7nH6P6dyDioJogAAGprGpCtVImJhpPk/roCzdb3fIh61/s/nPsfR6onyMwkCAR/OlC3yBC0lESvUoQEAssIrw==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/des.js": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/des.js/-/des.js-1.1.0.tgz",
      "integrity": "sha512-r17GxjhUCjSRy8aiJpr8/UadFIzMzJGexI3Nmz4ADi9LYSFx4gTBp80+NaX/YsXWWLhpZ7v/v/ubEc/bCNfKwg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "inherits": "^2.0.1",
        "minimalistic-assert": "^1.0.0"
      }
    },
    "node_modules/destroy": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/destroy/-/destroy-1.2.0.tgz",
      "integrity": "sha512-2sJGJTaXIIaR1w4iJSNoN0hnMY7Gpc/n8D4qSCJw8QqFWXf7cuAgnEHxBpweaVcPevC2l3KpjYCx3NypQQgaJg==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.8",
        "npm": "1.2.8000 || >= 1.4.16"
      }
    },
    "node_modules/detect-libc": {
      "version": "2.1.2",
      "resolved": "https://registry.npmjs.org/detect-libc/-/detect-libc-2.1.2.tgz",
      "integrity": "sha512-Btj2BOOO83o3WyH59e8MgXsxEQVcarkUOpEYrubB0urwnN10yQ364rsiByU11nZlqWYZm05i/of7io4mzihBtQ==",
      "dev": true,
      "license": "Apache-2.0",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/diffie-hellman": {
      "version": "5.0.3",
      "resolved": "https://registry.npmjs.org/diffie-hellman/-/diffie-hellman-5.0.3.tgz",
      "integrity": "sha512-kqag/Nl+f3GwyK25fhUMYj81BUOrZ9IuJsjIcDE5icNM9FJHAVm3VcUDxdLPoQtTuUylWm6ZIknYJwwaPxsUzg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "bn.js": "^4.1.0",
        "miller-rabin": "^4.0.0",
        "randombytes": "^2.0.0"
      }
    },
    "node_modules/diffie-hellman/node_modules/bn.js": {
      "version": "4.12.5",
      "resolved": "https://registry.npmjs.org/bn.js/-/bn.js-4.12.5.tgz",
      "integrity": "sha512-3aRg6/JxfffFD+OlOjOFR3Vo79l39ooBTFucxx+MT3dhCtzn3EmiUPQo+6/OZuI2jbXi3YKgmiTFBgChQMwIRQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/dijkstrajs": {
      "version": "1.0.3",
      "resolved": "https://registry.npmjs.org/dijkstrajs/-/dijkstrajs-1.0.3.tgz",
      "integrity": "sha512-qiSlmBq9+BCdCA/L46dw8Uy93mloxsPSbwnm5yrKn2vMPiy8KyAskTF6zuV/j5BMsmOGZDPs7KjU+mjb670kfA==",
      "license": "MIT"
    },
    "node_modules/domain-browser": {
      "version": "4.22.0",
      "resolved": "https://registry.npmjs.org/domain-browser/-/domain-browser-4.22.0.tgz",
      "integrity": "sha512-IGBwjF7tNk3cwypFNH/7bfzBcgSCbaMOD3GsaY1AU/JRrnHnYgEM0+9kQt52iZxjNsjBtJYtao146V+f8jFZNw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://bevry.me/fund"
      }
    },
    "node_modules/dunder-proto": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/dunder-proto/-/dunder-proto-1.0.1.tgz",
      "integrity": "sha512-KIN/nDJBQRcXw0MLVhZE9iQHmG68qAVIBg9CqmUYjmQIhgij9U5MFvrqkUL5FbtyyzZuOeOt0zdeRe4UY7ct+A==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bind-apply-helpers": "^1.0.1",
        "es-errors": "^1.3.0",
        "gopd": "^1.2.0"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/ee-first": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/ee-first/-/ee-first-1.1.1.tgz",
      "integrity": "sha512-WMwm9LhRUo+WUaRN+vRuETqG89IgZphVSNkdFgeb6sS/E4OrDIN7t48CAewSHXc6C8lefD8KKfr5vY61brQlow==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/electron-to-chromium": {
      "version": "1.5.444",
      "resolved": "https://registry.npmjs.org/electron-to-chromium/-/electron-to-chromium-1.5.444.tgz",
      "integrity": "sha512-5ss/uJfoDYDHT0lfJzT6FbcskIzROIOPf0BbbFkGcvDzoJU7i//9GDrwwIHQVmIsrAGiF3ihpADBRIsrEFt1rQ==",
      "license": "ISC",
      "peer": true
    },
    "node_modules/elliptic": {
      "version": "6.6.1",
      "resolved": "https://registry.npmjs.org/elliptic/-/elliptic-6.6.1.tgz",
      "integrity": "sha512-RaddvvMatK2LJHqFJ+YA4WysVN5Ita9E35botqIYspQ4TkRAlCicdzKOjlyv/1Za5RyTNn7di//eEV0uTAfe3g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "bn.js": "^4.11.9",
        "brorand": "^1.1.0",
        "hash.js": "^1.0.0",
        "hmac-drbg": "^1.0.1",
        "inherits": "^2.0.4",
        "minimalistic-assert": "^1.0.1",
        "minimalistic-crypto-utils": "^1.0.1"
      }
    },
    "node_modules/elliptic/node_modules/bn.js": {
      "version": "4.12.5",
      "resolved": "https://registry.npmjs.org/bn.js/-/bn.js-4.12.5.tgz",
      "integrity": "sha512-3aRg6/JxfffFD+OlOjOFR3Vo79l39ooBTFucxx+MT3dhCtzn3EmiUPQo+6/OZuI2jbXi3YKgmiTFBgChQMwIRQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/emoji-regex": {
      "version": "8.0.0",
      "resolved": "https://registry.npmjs.org/emoji-regex/-/emoji-regex-8.0.0.tgz",
      "integrity": "sha512-MSjYzcWNOA0ewAHpz0MxpYFvwg6yjy1NG3xteoqz644VCo/RPgnr1/GGt+ic3iJTzQ8Eu3TdM14SawnVUmGE6A==",
      "license": "MIT"
    },
    "node_modules/encodeurl": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/encodeurl/-/encodeurl-1.0.2.tgz",
      "integrity": "sha512-TPJXq8JqFaVYm2CWmPvnP2Iyo4ZSM7/QKcSmuMLDObfpH5fi7RUGmd/rTDf+rut/saiDiQEeVTNgAmJEdAOx0w==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/error-stack-parser": {
      "version": "2.1.4",
      "resolved": "https://registry.npmjs.org/error-stack-parser/-/error-stack-parser-2.1.4.tgz",
      "integrity": "sha512-Sk5V6wVazPhq5MhpO+AUxJn5x7XSXGl1R93Vn7i+zS15KDVxQijejNCrz8340/2bgLBjR9GtEG8ZVKONDjcqGQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "stackframe": "^1.3.4"
      }
    },
    "node_modules/es-define-property": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/es-define-property/-/es-define-property-1.0.1.tgz",
      "integrity": "sha512-e3nRfgfUZ4rNGL232gUgX06QNyyez04KdjFrF+LTRoOXmrOgFKDg4BCdsjW8EnT69eqdYGmRpJwiPVYNrCaW3g==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/es-errors": {
      "version": "1.3.0",
      "resolved": "https://registry.npmjs.org/es-errors/-/es-errors-1.3.0.tgz",
      "integrity": "sha512-Zf5H2Kxt2xjTvbJvP2ZWLEICxA6j+hAmMzIlypy4xcBg1vKVnx89Wy0GbS+kf5cwCVFFzdCFh2XSCFNULS6csw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/es-object-atoms": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/es-object-atoms/-/es-object-atoms-1.1.2.tgz",
      "integrity": "sha512-HWcBoN6NileqtSydK2FqHbS/LoDd2pqrnQHLyJzBj4kOp/ky2MWMN694xOfkK8/SnUsW2DH7EfyVlydKCsm1Zw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/es6-promise": {
      "version": "4.2.8",
      "resolved": "https://registry.npmjs.org/es6-promise/-/es6-promise-4.2.8.tgz",
      "integrity": "sha512-HJDGx5daxeIvxdBxvG2cb9g4tEvwIk3i8+nhX0yGrYmZUzbkdg8QbDevheDB8gd0//uPj4c1EQua8Q+MViT0/w==",
      "license": "MIT"
    },
    "node_modules/es6-promisify": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/es6-promisify/-/es6-promisify-5.0.0.tgz",
      "integrity": "sha512-C+d6UdsYDk0lMebHNR4S2NybQMMngAOnOwYBQjTOiv0MkoJMP0Myw2mgpDLBcpfCmRLxyFqYhS/CfOENq4SJhQ==",
      "license": "MIT",
      "dependencies": {
        "es6-promise": "^4.0.3"
      }
    },
    "node_modules/esbuild": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/esbuild/-/esbuild-0.28.2.tgz",
      "integrity": "sha512-HKVLS8dvII+xoKW9kmqxbRKrnWEXfJJr/FZhhJmiqIB0e053QNYFqOBouTMO/k5sID4MvCiUCvv8b9M4h32wIA==",
      "dev": true,
      "hasInstallScript": true,
      "license": "MIT",
      "bin": {
        "esbuild": "bin/esbuild"
      },
      "engines": {
        "node": ">=18"
      },
      "optionalDependencies": {
        "@esbuild/aix-ppc64": "0.28.2",
        "@esbuild/android-arm": "0.28.2",
        "@esbuild/android-arm64": "0.28.2",
        "@esbuild/android-x64": "0.28.2",
        "@esbuild/darwin-arm64": "0.28.2",
        "@esbuild/darwin-x64": "0.28.2",
        "@esbuild/freebsd-arm64": "0.28.2",
        "@esbuild/freebsd-x64": "0.28.2",
        "@esbuild/linux-arm": "0.28.2",
        "@esbuild/linux-arm64": "0.28.2",
        "@esbuild/linux-ia32": "0.28.2",
        "@esbuild/linux-loong64": "0.28.2",
        "@esbuild/linux-mips64el": "0.28.2",
        "@esbuild/linux-ppc64": "0.28.2",
        "@esbuild/linux-riscv64": "0.28.2",
        "@esbuild/linux-s390x": "0.28.2",
        "@esbuild/linux-x64": "0.28.2",
        "@esbuild/netbsd-arm64": "0.28.2",
        "@esbuild/netbsd-x64": "0.28.2",
        "@esbuild/openbsd-arm64": "0.28.2",
        "@esbuild/openbsd-x64": "0.28.2",
        "@esbuild/openharmony-arm64": "0.28.2",
        "@esbuild/sunos-x64": "0.28.2",
        "@esbuild/win32-arm64": "0.28.2",
        "@esbuild/win32-ia32": "0.28.2",
        "@esbuild/win32-x64": "0.28.2"
      }
    },
    "node_modules/escalade": {
      "version": "3.2.0",
      "resolved": "https://registry.npmjs.org/escalade/-/escalade-3.2.0.tgz",
      "integrity": "sha512-WUj2qlxaQtO4g6Pq5c29GTcWGDyd8itL8zTlipgECz3JesAiiOKotd8JU6otB3PACgG6xkJUyVhboMS+bje/jA==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/escape-html": {
      "version": "1.0.3",
      "resolved": "https://registry.npmjs.org/escape-html/-/escape-html-1.0.3.tgz",
      "integrity": "sha512-NiSupZ4OeuGwr68lGIeym/ksIZMJodUGOSCZ/FSnTxcrekbvqrgdUxlJOMpijaKZVjAJrWrGs/6Jy8OMuyj9ow==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/escape-string-regexp": {
      "version": "4.0.0",
      "resolved": "https://registry.npmjs.org/escape-string-regexp/-/escape-string-regexp-4.0.0.tgz",
      "integrity": "sha512-TtpcNJ3XAzx3Gq8sWRzJaVajRs0uVxA2YAkdb1jm2YkPz4G6egUFAyA3n5vtEIZefPk5Wa4UXbKuS5fKkJWdgA==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/estree-walker": {
      "version": "2.0.2",
      "resolved": "https://registry.npmjs.org/estree-walker/-/estree-walker-2.0.2.tgz",
      "integrity": "sha512-Rfkk/Mp/DL7JVje3u18FxFujQlTNR2q6QfMSMB7AvCBx91NGj/ba3kCfza0f6dVDbw7YlRf/nDrn7pQrCCyQ/w==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/etag": {
      "version": "1.8.1",
      "resolved": "https://registry.npmjs.org/etag/-/etag-1.8.1.tgz",
      "integrity": "sha512-aIL5Fx7mawVa300al2BnEE4iNvo1qETxLrPI/o05L7z6go7fCw1J6EQmbK4FmJ2AS7kgVF/KEZWufBfdClMcPg==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/eventemitter3": {
      "version": "4.0.7",
      "resolved": "https://registry.npmjs.org/eventemitter3/-/eventemitter3-4.0.7.tgz",
      "integrity": "sha512-8guHBZCwKnFhYdHr2ysuRWErTwhoN2X8XELRlrRwpmfeY2jjuUN4taQMsULKUVo1K4DvZl+0pgfyoysHxvmvEw==",
      "license": "MIT"
    },
    "node_modules/events": {
      "version": "3.3.0",
      "resolved": "https://registry.npmjs.org/events/-/events-3.3.0.tgz",
      "integrity": "sha512-mQw+2fkQbALzQ7V0MY0IqdnXNOeTtP4r0lN9z7AAawCXgqea7bDii20AYrIBrFd/Hx0M2Ocz6S111CaFkUcb0Q==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=0.8.x"
      }
    },
    "node_modules/evp_bytestokey": {
      "version": "1.0.3",
      "resolved": "https://registry.npmjs.org/evp_bytestokey/-/evp_bytestokey-1.0.3.tgz",
      "integrity": "sha512-/f2Go4TognH/KvCISP7OUsHn85hT9nUkxxA9BEWxFn+Oj9o8ZNLm/40hdlgSLyuOimsrTKLUMEorQexp/aPQeA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "md5.js": "^1.3.4",
        "safe-buffer": "^5.1.1"
      }
    },
    "node_modules/exponential-backoff": {
      "version": "3.1.3",
      "resolved": "https://registry.npmjs.org/exponential-backoff/-/exponential-backoff-3.1.3.tgz",
      "integrity": "sha512-ZgEeZXj30q+I0EN+CbSSpIyPaJ5HVQD18Z1m+u1FXbAeT94mr1zw50q4q6jiiC447Nl/YTcIYSAftiGqetwXCA==",
      "license": "Apache-2.0",
      "peer": true
    },
    "node_modules/eyes": {
      "version": "0.1.8",
      "resolved": "https://registry.npmjs.org/eyes/-/eyes-0.1.8.tgz",
      "integrity": "sha512-GipyPsXO1anza0AOZdy69Im7hGFCNB7Y/NGjDlZGJ3GJJLtwNSb2vrzYrTYJRrRloVx7pl+bhUaTB8yiccPvFQ==",
      "engines": {
        "node": "> 0.1.90"
      }
    },
    "node_modules/fast-stable-stringify": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/fast-stable-stringify/-/fast-stable-stringify-1.0.0.tgz",
      "integrity": "sha512-wpYMUmFu5f00Sm0cj2pfivpmawLZ0NKdviQ4w9zJeR8JVtOpOxHmLaJuj0vxvGqMJQWyP/COUkF75/57OKyRag==",
      "license": "MIT"
    },
    "node_modules/fastestsmallesttextencoderdecoder": {
      "version": "1.0.22",
      "resolved": "https://registry.npmjs.org/fastestsmallesttextencoderdecoder/-/fastestsmallesttextencoderdecoder-1.0.22.tgz",
      "integrity": "sha512-Pb8d48e+oIuY4MaM64Cd7OW1gt4nxCHs7/ddPPZ/Ic3sg8yVGM7O9wDvZ7us6ScaUupzM+pfBolwtYhN1IxBIw==",
      "license": "CC0-1.0",
      "peer": true
    },
    "node_modules/fb-dotslash": {
      "version": "0.5.8",
      "resolved": "https://registry.npmjs.org/fb-dotslash/-/fb-dotslash-0.5.8.tgz",
      "integrity": "sha512-XHYLKk9J4BupDxi9bSEhkfss0m+Vr9ChTrjhf9l2iw3jB5C7BnY4GVPoMcqbrTutsKJso6yj2nAB6BI/F2oZaA==",
      "license": "(MIT OR Apache-2.0)",
      "peer": true,
      "bin": {
        "dotslash": "bin/dotslash"
      },
      "engines": {
        "node": ">=20"
      }
    },
    "node_modules/fb-watchman": {
      "version": "2.0.2",
      "resolved": "https://registry.npmjs.org/fb-watchman/-/fb-watchman-2.0.2.tgz",
      "integrity": "sha512-p5161BqbuCaSnB8jIbzQHOlpgsPmK5rJVDfDKO91Axs5NC1uu3HRQm6wt9cd9/+GtQQIO53JdGXXoyDpTAsgYA==",
      "license": "Apache-2.0",
      "peer": true,
      "dependencies": {
        "bser": "2.1.1"
      }
    },
    "node_modules/file-uri-to-path": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/file-uri-to-path/-/file-uri-to-path-1.0.0.tgz",
      "integrity": "sha512-0Zt+s3L7Vf1biwWZ29aARiVYLx7iMGnEUl9x33fbB/j3jR81u/O2LbqK+Bm1CDSNDKVtJ/YjwY7TUd5SkeLQLw==",
      "license": "MIT"
    },
    "node_modules/fill-range": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/fill-range/-/fill-range-7.1.1.tgz",
      "integrity": "sha512-YsGpe3WHLK8ZYi4tWDg2Jy3ebRz2rXowDxnld4bkQB00cc/1Zw9AWnC0i9ztDJitivtQvaI9KaLyKrc+hBW0yg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "to-regex-range": "^5.0.1"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/finalhandler": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/finalhandler/-/finalhandler-1.1.2.tgz",
      "integrity": "sha512-aAWcW57uxVNrQZqFXjITpW3sIUQmHGG3qSb9mUah9MgMC4NeWhNOlNjXEYq3HjRAvL6arUviZGGJsBg6z0zsWA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "debug": "2.6.9",
        "encodeurl": "~1.0.2",
        "escape-html": "~1.0.3",
        "on-finished": "~2.3.0",
        "parseurl": "~1.3.3",
        "statuses": "~1.5.0",
        "unpipe": "~1.0.0"
      },
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/finalhandler/node_modules/debug": {
      "version": "2.6.9",
      "resolved": "https://registry.npmjs.org/debug/-/debug-2.6.9.tgz",
      "integrity": "sha512-bC7ElrdJaJnPbAP+1EotYvqZsb3ecl5wi6Bfi6BJTUcNowp6cvspg0jXznRTKDjm/E7AdgFBVeAPVMNcKGsHMA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ms": "2.0.0"
      }
    },
    "node_modules/finalhandler/node_modules/ms": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/ms/-/ms-2.0.0.tgz",
      "integrity": "sha512-Tpp60P6IUJDTuOq/5Z8cdskzJujfwqfOTkrwIwj7IRISpnkJnT6SyJ4PCPnGMoFjC9ddhal5KVIYtAt97ix05A==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/find-up": {
      "version": "4.1.0",
      "resolved": "https://registry.npmjs.org/find-up/-/find-up-4.1.0.tgz",
      "integrity": "sha512-PpOwAdQ/YlXQ2vj8a3h8IipDuYRi3wceVQQGYWxNINccq40Anw7BlsEXCMbt1Zt+OLA6Fq9suIpIWD0OsnISlw==",
      "license": "MIT",
      "dependencies": {
        "locate-path": "^5.0.0",
        "path-exists": "^4.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/flow-enums-runtime": {
      "version": "0.0.6",
      "resolved": "https://registry.npmjs.org/flow-enums-runtime/-/flow-enums-runtime-0.0.6.tgz",
      "integrity": "sha512-3PYnM29RFXwvAN6Pc/scUfkI7RwhQ/xqyLUyPNlXUp9S40zI8nup9tUSrTLSVnWGBN38FNiGWbwZOB6uR4OGdw==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/flow-estree": {
      "version": "0.331.0",
      "resolved": "https://registry.npmjs.org/flow-estree/-/flow-estree-0.331.0.tgz",
      "integrity": "sha512-FVLYkSL/ITb/QXBEQvNWPjPooRGswuUtGOwrH+puSlMDneNkxy640+FZsk/TfKL+b7Wbw/Fg9FTUv2bMQDpj2w==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/flow-parser": {
      "version": "0.331.0",
      "resolved": "https://registry.npmjs.org/flow-parser/-/flow-parser-0.331.0.tgz",
      "integrity": "sha512-vEZcHIlnKeN8JSVtYFczj8sWJfHIJOkz+YG00O/oul/Bete+t1ZhTi+O6JRRLFYvGW+yJkZ0YgL16iStnbkUqQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "flow-estree": "0.331.0"
      },
      "engines": {
        "node": ">=0.4.0"
      }
    },
    "node_modules/for-each": {
      "version": "0.3.5",
      "resolved": "https://registry.npmjs.org/for-each/-/for-each-0.3.5.tgz",
      "integrity": "sha512-dKx12eRCVIzqCxFGplyFKJMPvLEWgmNtUrpTiJIR5u97zEhRG8ySrtboPHZXx7daLxQVrl643cTzbab2tkQjxg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "is-callable": "^1.2.7"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/fresh": {
      "version": "0.5.2",
      "resolved": "https://registry.npmjs.org/fresh/-/fresh-0.5.2.tgz",
      "integrity": "sha512-zJ2mQYM18rEFOudeV4GShTGIQ7RbzA7ozbU9I/XBpm7kqgMywgmylMwXHxZJmkVoYkna9d2pVXVXPdYTP9ej8Q==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/fsevents": {
      "version": "2.3.3",
      "resolved": "https://registry.npmjs.org/fsevents/-/fsevents-2.3.3.tgz",
      "integrity": "sha512-5xoDfX+fL7faATnagmWPpbFtwh/R77WmMMqqHGS65C3vvB0YHrgF+B1YmZ3441tMj5n63k0212XNoJwzlhffQw==",
      "dev": true,
      "hasInstallScript": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": "^8.16.0 || ^10.6.0 || >=11.0.0"
      }
    },
    "node_modules/function-bind": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/function-bind/-/function-bind-1.1.2.tgz",
      "integrity": "sha512-7XHNxH7qX9xG5mIwxkhumTox/MIRNcOgDrxWsMt2pAr23WHp6MrRlN7FBSFpCpr+oVO0F744iUgR82nJMfG2SA==",
      "dev": true,
      "license": "MIT",
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/generator-function": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/generator-function/-/generator-function-2.0.1.tgz",
      "integrity": "sha512-SFdFmIJi+ybC0vjlHN0ZGVGHc3lgE0DxPAT0djjVg+kjOnSqclqmj0KQ7ykTOLP6YxoqOvuAODGdcHJn+43q3g==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/gensync": {
      "version": "1.0.0-beta.2",
      "resolved": "https://registry.npmjs.org/gensync/-/gensync-1.0.0-beta.2.tgz",
      "integrity": "sha512-3hN7NaskYvMDLQY55gnW3NQ+mesEAepTqlg+VEbj7zzqEMBVNhzcGYYeqFo/TlYz6eQiFcp1HcsCZO+nGgS8zg==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/get-caller-file": {
      "version": "2.0.5",
      "resolved": "https://registry.npmjs.org/get-caller-file/-/get-caller-file-2.0.5.tgz",
      "integrity": "sha512-DyFP3BM/3YHTQOCUL/w0OZHR0lpKeGrxotcHWcqNEdnltqFwXVfhEBQ94eIo34AfQpo0rGki4cyIiftY06h2Fg==",
      "license": "ISC",
      "engines": {
        "node": "6.* || 8.* || >= 10.*"
      }
    },
    "node_modules/get-intrinsic": {
      "version": "1.3.0",
      "resolved": "https://registry.npmjs.org/get-intrinsic/-/get-intrinsic-1.3.0.tgz",
      "integrity": "sha512-9fSjSaos/fRIVIp+xSJlE6lfwhES7LNtKaCBIamHsjr2na1BiABJPo0mOjjz8GJDURarmCPGqaiVg5mfjb98CQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bind-apply-helpers": "^1.0.2",
        "es-define-property": "^1.0.1",
        "es-errors": "^1.3.0",
        "es-object-atoms": "^1.1.1",
        "function-bind": "^1.1.2",
        "get-proto": "^1.0.1",
        "gopd": "^1.2.0",
        "has-symbols": "^1.1.0",
        "hasown": "^2.0.2",
        "math-intrinsics": "^1.1.0"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/get-proto": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/get-proto/-/get-proto-1.0.1.tgz",
      "integrity": "sha512-sTSfBjoXBp89JvIKIefqw7U2CCebsc74kiY6awiGogKtoSGbgjYE/G/+l9sF3MWFPNc9IcoOC4ODfKHfxFmp0g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "dunder-proto": "^1.0.1",
        "es-object-atoms": "^1.0.0"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/gopd": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/gopd/-/gopd-1.2.0.tgz",
      "integrity": "sha512-ZUKRh6/kUFoAiTAtTYPZJ3hw9wNxx+BIBOijnlG9PnrJsCcSjs1wyyD6vJpaYtgnzDrKYRSqf3OO6Rfa93xsRg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/graceful-fs": {
      "version": "4.2.11",
      "resolved": "https://registry.npmjs.org/graceful-fs/-/graceful-fs-4.2.11.tgz",
      "integrity": "sha512-RbJ5/jmFcNNCcDV5o9eTnBLJ/HszWV0P73bc+Ff4nS/rJj+YaS6IGyiOL0VoBYX+l1Wrl3k63h/KrH+nhJ0XvQ==",
      "license": "ISC",
      "peer": true
    },
    "node_modules/has-flag": {
      "version": "4.0.0",
      "resolved": "https://registry.npmjs.org/has-flag/-/has-flag-4.0.0.tgz",
      "integrity": "sha512-EykJT/Q1KjTWctppgIAgfSO0tKVuZUjhgMr17kqTumMl6Afv3EISleU7qZUzoXDFTAHTDC4NOoG/ZxU3EvlMPQ==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/has-property-descriptors": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/has-property-descriptors/-/has-property-descriptors-1.0.2.tgz",
      "integrity": "sha512-55JNKuIW+vq4Ke1BjOTjM2YctQIvCT7GFzHwmfZPGo5wnrgkid0YQtnAleFSqumZm4az3n2BS+erby5ipJdgrg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "es-define-property": "^1.0.0"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/has-symbols": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/has-symbols/-/has-symbols-1.1.0.tgz",
      "integrity": "sha512-1cDNdwJ2Jaohmb3sg4OmKaMBwuC48sYni5HUw2DvsC8LjGTLK9h+eb1X6RyuOHe4hT0ULCW68iomhjUoKUqlPQ==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/has-tostringtag": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/has-tostringtag/-/has-tostringtag-1.0.2.tgz",
      "integrity": "sha512-NqADB8VjPFLM2V0VvHUewwwsw0ZWBaIdgo+ieHtK3hasLz4qeCRjYcqfB6AQrBggRKppKF8L52/VqdVsO47Dlw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "has-symbols": "^1.0.3"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/hash-base": {
      "version": "3.0.5",
      "resolved": "https://registry.npmjs.org/hash-base/-/hash-base-3.0.5.tgz",
      "integrity": "sha512-vXm0l45VbcHEVlTCzs8M+s0VeYsB2lnlAaThoLKGXr3bE/VWDOelNUnycUPEhKEaXARL2TEFjBOyUiM6+55KBg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "inherits": "^2.0.4",
        "safe-buffer": "^5.2.1"
      },
      "engines": {
        "node": ">= 0.10"
      }
    },
    "node_modules/hash.js": {
      "version": "1.1.7",
      "resolved": "https://registry.npmjs.org/hash.js/-/hash.js-1.1.7.tgz",
      "integrity": "sha512-taOaskGt4z4SOANNseOviYDvjEJinIkRgmp7LbKP2YTTmVxWBl87s/uzK9r+44BclBSp2X7K1hqeNfz9JbBeXA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "inherits": "^2.0.3",
        "minimalistic-assert": "^1.0.1"
      }
    },
    "node_modules/hasown": {
      "version": "2.0.4",
      "resolved": "https://registry.npmjs.org/hasown/-/hasown-2.0.4.tgz",
      "integrity": "sha512-T2UbfbBEF32wiepXIsMlTW9+dDYC6wMh/t/vYA4tuOMKqWz/n3vr1NFSxQiyP+zk2mXsoMA/i/7qV6LKut1t1A==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "function-bind": "^1.1.2"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/hermes-compiler": {
      "version": "250829098.0.17",
      "resolved": "https://registry.npmjs.org/hermes-compiler/-/hermes-compiler-250829098.0.17.tgz",
      "integrity": "sha512-qG1PXzTEtriF6oQLZF3vyHhSMxOdW5h2TqqLri0rdpstPustd2fSvRZQMVAPdlhgFwBfYnj3OUZtiO6LjYsEFw==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/hermes-estree": {
      "version": "0.36.1",
      "resolved": "https://registry.npmjs.org/hermes-estree/-/hermes-estree-0.36.1.tgz",
      "integrity": "sha512-guv1nQ6IJ7S83NRFPWc3SA7IBZrdNC9kapwOq6uXvF4wP+sDCgjzQbKPCoyYmoyZRzztF/n/c36l/rccCZSiCw==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/hermes-parser": {
      "version": "0.36.1",
      "resolved": "https://registry.npmjs.org/hermes-parser/-/hermes-parser-0.36.1.tgz",
      "integrity": "sha512-GApNk4zLHi2UWoWZZkx7LNCOSzLSc5lB55pZ/PhK7ycFeg7u5LcF88p/WbpIi1XUDtE0MpHE3uRR3u3KB7TjSQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "hermes-estree": "0.36.1"
      }
    },
    "node_modules/hmac-drbg": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/hmac-drbg/-/hmac-drbg-1.0.1.tgz",
      "integrity": "sha512-Tti3gMqLdZfhOQY1Mzf/AanLiqh1WTiJgEj26ZuYQ9fbkLomzGchCws4FyrSd4VkpBfiNhaE1On+lOz894jvXg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "hash.js": "^1.0.3",
        "minimalistic-assert": "^1.0.0",
        "minimalistic-crypto-utils": "^1.0.1"
      }
    },
    "node_modules/http-errors": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/http-errors/-/http-errors-2.0.1.tgz",
      "integrity": "sha512-4FbRdAX+bSdmo4AUFuS0WNiPz8NgFt+r8ThgNWmlrjQjt1Q7ZR9+zTlce2859x4KSXrwIsaeTqDoKQmtP8pLmQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "depd": "~2.0.0",
        "inherits": "~2.0.4",
        "setprototypeof": "~1.2.0",
        "statuses": "~2.0.2",
        "toidentifier": "~1.0.1"
      },
      "engines": {
        "node": ">= 0.8"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/http-errors/node_modules/statuses": {
      "version": "2.0.2",
      "resolved": "https://registry.npmjs.org/statuses/-/statuses-2.0.2.tgz",
      "integrity": "sha512-DvEy55V3DB7uknRo+4iOGT5fP1slR8wQohVdknigZPMpMstaKJQWhwiYBACJE3Ul2pTnATihhBYnRhZQHGBiRw==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/https-browserify": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/https-browserify/-/https-browserify-1.0.0.tgz",
      "integrity": "sha512-J+FkSdyD+0mA0N+81tMotaRMfSL9SGi+xpD3T6YApKsc3bGSXJlfXri3VyFOeYkfLRQisDk1W+jIFFKBeUBbBg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/https-proxy-agent": {
      "version": "7.0.6",
      "resolved": "https://registry.npmjs.org/https-proxy-agent/-/https-proxy-agent-7.0.6.tgz",
      "integrity": "sha512-vK9P5/iUfdl95AI+JVyUuIcVtd4ofvtrOr3HNtM2yxC9bnMbEdp3x01OhQNnjb8IJYi38VlTE3mBXwcfvywuSw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "agent-base": "^7.1.2",
        "debug": "4"
      },
      "engines": {
        "node": ">= 14"
      }
    },
    "node_modules/humanize-ms": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/humanize-ms/-/humanize-ms-1.2.1.tgz",
      "integrity": "sha512-Fl70vYtsAFb/C06PTS9dZBo7ihau+Tu/DNCk/OyHhea07S+aeMWpFFkUaXRa8fI+ScZbEI8dfSxwY7gxZ9SAVQ==",
      "license": "MIT",
      "dependencies": {
        "ms": "^2.0.0"
      }
    },
    "node_modules/ieee754": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/ieee754/-/ieee754-1.2.1.tgz",
      "integrity": "sha512-dcyqhDvX1C46lXZcVqCpK+FtMRQVdIMN6/Df5js2zouUsqG7I6sFxitIC+7KYK29KdXOLHdu9zL4sFnoVQnqaA==",
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/feross"
        },
        {
          "type": "patreon",
          "url": "https://www.patreon.com/feross"
        },
        {
          "type": "consulting",
          "url": "https://feross.org/support"
        }
      ],
      "license": "BSD-3-Clause"
    },
    "node_modules/inherits": {
      "version": "2.0.4",
      "resolved": "https://registry.npmjs.org/inherits/-/inherits-2.0.4.tgz",
      "integrity": "sha512-k/vGaX4/Yla3WzyMCvTQOXYeIHvqOKtnqBduzTHpzpQZzAskKMhZ2K+EnBiSM9zGSoIFeMpXKxa4dYeZIQqewQ==",
      "license": "ISC"
    },
    "node_modules/invariant": {
      "version": "2.2.4",
      "resolved": "https://registry.npmjs.org/invariant/-/invariant-2.2.4.tgz",
      "integrity": "sha512-phJfQVBuaJM5raOpJjSfkiD6BpbCE4Ns//LaXl6wGYtUBY83nWS6Rf9tXm2e8VaK60JEjYldbPif/A2B1C2gNA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "loose-envify": "^1.0.0"
      }
    },
    "node_modules/is-arguments": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/is-arguments/-/is-arguments-1.2.0.tgz",
      "integrity": "sha512-7bVbi0huj/wrIAOzb8U1aszg9kdi3KN/CyU19CTI7tAoZYEZoL9yCDXpbXN+uPsuWnP02cyug1gleqq+TU+YCA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bound": "^1.0.2",
        "has-tostringtag": "^1.0.2"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/is-callable": {
      "version": "1.2.7",
      "resolved": "https://registry.npmjs.org/is-callable/-/is-callable-1.2.7.tgz",
      "integrity": "sha512-1BC0BVFhS/p0qtw6enp8e+8OD0UrK0oFLztSjNzhcKA3WDuJxxAPXzPuPtKkjEY9UUoEWlX/8fgKeu2S8i9JTA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/is-core-module": {
      "version": "2.17.0",
      "resolved": "https://registry.npmjs.org/is-core-module/-/is-core-module-2.17.0.tgz",
      "integrity": "sha512-J/vG0zBCbIKOQFfufSwyXdMrsohyJIUNkrnmo6WZGzoM7tr/lsbfW5b2BvisL6zsyMzK9UxV9L6c7AoFbyXHOA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "hasown": "^2.0.4"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/is-docker": {
      "version": "2.2.1",
      "resolved": "https://registry.npmjs.org/is-docker/-/is-docker-2.2.1.tgz",
      "integrity": "sha512-F+i2BKsFrH66iaUFc0woD8sLy8getkwTwtOBjvs56Cx4CgJDeKQeqfz8wAYiSb8JOprWhHH5p77PbmYCvvUuXQ==",
      "license": "MIT",
      "peer": true,
      "bin": {
        "is-docker": "cli.js"
      },
      "engines": {
        "node": ">=8"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/is-fullwidth-code-point": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/is-fullwidth-code-point/-/is-fullwidth-code-point-3.0.0.tgz",
      "integrity": "sha512-zymm5+u+sCsSWyD9qNaejV3DFvhCKclKdizYaJUuHA83RLjb7nSuGnddCHGv0hk+KY7BMAlsWeK4Ueg6EV6XQg==",
      "license": "MIT",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/is-generator-function": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/is-generator-function/-/is-generator-function-1.1.2.tgz",
      "integrity": "sha512-upqt1SkGkODW9tsGNG5mtXTXtECizwtS2kA161M+gJPc1xdb/Ax629af6YrTwcOeQHbewrPNlE5Dx7kzvXTizA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bound": "^1.0.4",
        "generator-function": "^2.0.0",
        "get-proto": "^1.0.1",
        "has-tostringtag": "^1.0.2",
        "safe-regex-test": "^1.1.0"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/is-nan": {
      "version": "1.3.2",
      "resolved": "https://registry.npmjs.org/is-nan/-/is-nan-1.3.2.tgz",
      "integrity": "sha512-E+zBKpQ2t6MEo1VsonYmluk9NxGrbzpeeLC2xIViuO2EjU2xsXsBPwTr3Ykv9l08UYEVEdWeRZNouaZqF6RN0w==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bind": "^1.0.0",
        "define-properties": "^1.1.3"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/is-number": {
      "version": "7.0.0",
      "resolved": "https://registry.npmjs.org/is-number/-/is-number-7.0.0.tgz",
      "integrity": "sha512-41Cifkg6e8TylSpdtTpeLVMqvSBEVzTttHvERD741+pnZ8ANv0004MRL43QKPDlK9cGvNp6NZWZUBlbGXYxxng==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=0.12.0"
      }
    },
    "node_modules/is-plain-obj": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/is-plain-obj/-/is-plain-obj-2.1.0.tgz",
      "integrity": "sha512-YWnfyRwxL/+SsrWYfOpUtz5b3YD+nyfkHvjbcanzk8zgyO4ASD67uVMRt8k5bM4lLMDnXfriRhOpemw+NfT1eA==",
      "license": "MIT",
      "optional": true,
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/is-regex": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/is-regex/-/is-regex-1.2.1.tgz",
      "integrity": "sha512-MjYsKHO5O7mCsmRGxWcLWheFqN9DJ/2TmngvjKXihe6efViPqc274+Fx/4fYj/r03+ESvBdTXK0V6tA3rgez1g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bound": "^1.0.2",
        "gopd": "^1.2.0",
        "has-tostringtag": "^1.0.2",
        "hasown": "^2.0.2"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/is-typed-array": {
      "version": "1.1.15",
      "resolved": "https://registry.npmjs.org/is-typed-array/-/is-typed-array-1.1.15.tgz",
      "integrity": "sha512-p3EcsicXjit7SaskXHs1hA91QxgTw46Fv6EFKKGS5DRFLD8yKnohjF3hxoju94b/OcMZoQukzpPpBE9uLVKzgQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "which-typed-array": "^1.1.16"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/is-wsl": {
      "version": "2.2.0",
      "resolved": "https://registry.npmjs.org/is-wsl/-/is-wsl-2.2.0.tgz",
      "integrity": "sha512-fKzAra0rGJUUBwGBgNkHZuToZcn+TtXHpeCgmkMJMMYx1sQDYaCSyjJBSCa2nH1DGm7s3n1oBnohoVTBaN7Lww==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "is-docker": "^2.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/isarray": {
      "version": "2.0.5",
      "resolved": "https://registry.npmjs.org/isarray/-/isarray-2.0.5.tgz",
      "integrity": "sha512-xHjhDr3cNBK0BzdUJSPXZntQUx/mwMS5Rw4A7lPJ90XGAO6ISP/ePDNuo0vhqOZU+UD5JoodwCAAoZQd3FeAKw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/isexe": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/isexe/-/isexe-2.0.0.tgz",
      "integrity": "sha512-RHxMLp9lnKHGHRng9QFhRCMbYAcVpn69smSGcq3f36xjgVVWThj4qqLbTLlq7Ssj8B+fIQ1EuCEGI2lKsyQeIw==",
      "license": "ISC",
      "peer": true
    },
    "node_modules/isomorphic-timers-promises": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/isomorphic-timers-promises/-/isomorphic-timers-promises-1.0.1.tgz",
      "integrity": "sha512-u4sej9B1LPSxTGKB/HiuzvEQnXH0ECYkSVQU39koSwmFAxhlEAFl9RdTvLv4TOTQUgBS5O3O5fwUxk6byBZ+IQ==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/isomorphic-ws": {
      "version": "4.0.1",
      "resolved": "https://registry.npmjs.org/isomorphic-ws/-/isomorphic-ws-4.0.1.tgz",
      "integrity": "sha512-BhBvN2MBpWTaSHdWRb/bwdZJ1WaehQ2L1KngkCkfLUGF0mAWAT1sQUQacEmQ0jXkFw/czDXPNQSL5u2/Krsz1w==",
      "license": "MIT",
      "peerDependencies": {
        "ws": "*"
      }
    },
    "node_modules/jayson": {
      "version": "4.3.0",
      "resolved": "https://registry.npmjs.org/jayson/-/jayson-4.3.0.tgz",
      "integrity": "sha512-AauzHcUcqs8OBnCHOkJY280VaTiCm57AbuO7lqzcw7JapGj50BisE3xhksye4zlTSR1+1tAz67wLTl8tEH1obQ==",
      "license": "MIT",
      "dependencies": {
        "@types/connect": "^3.4.33",
        "@types/node": "^12.12.54",
        "@types/ws": "^7.4.4",
        "commander": "^2.20.3",
        "delay": "^5.0.0",
        "es6-promisify": "^5.0.0",
        "eyes": "^0.1.8",
        "isomorphic-ws": "^4.0.1",
        "json-stringify-safe": "^5.0.1",
        "stream-json": "^1.9.1",
        "uuid": "^8.3.2",
        "ws": "^7.5.10"
      },
      "bin": {
        "jayson": "bin/jayson.js"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/jayson/node_modules/@types/node": {
      "version": "12.20.55",
      "resolved": "https://registry.npmjs.org/@types/node/-/node-12.20.55.tgz",
      "integrity": "sha512-J8xLz7q2OFulZ2cyGTLE1TbbZcjpno7FaN6zdJNrgAdrJ+DZzh/uFR6YrTb4C+nXakvud8Q4+rbhoIWlYQbUFQ==",
      "license": "MIT"
    },
    "node_modules/jayson/node_modules/commander": {
      "version": "2.20.3",
      "resolved": "https://registry.npmjs.org/commander/-/commander-2.20.3.tgz",
      "integrity": "sha512-GpVkmM8vF2vQUkj2LvZmD35JxeJOLCwJ9cUkugyk2nuhbv3+mJvpLYYt+0+USMxE+oj+ey/lJEnhZw75x/OMcQ==",
      "license": "MIT"
    },
    "node_modules/jest-get-type": {
      "version": "29.6.3",
      "resolved": "https://registry.npmjs.org/jest-get-type/-/jest-get-type-29.6.3.tgz",
      "integrity": "sha512-zrteXnqYxfQh7l5FHyL38jL39di8H8rHoecLH3JNxH3BwOrBsNeabdap5e0I23lD4HHI8W5VFBZqG4Eaq5LNcw==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": "^14.15.0 || ^16.10.0 || >=18.0.0"
      }
    },
    "node_modules/jest-util": {
      "version": "29.7.0",
      "resolved": "https://registry.npmjs.org/jest-util/-/jest-util-29.7.0.tgz",
      "integrity": "sha512-z6EbKajIpqGKU56y5KBUgy1dt1ihhQJgWzUlZHArA/+X2ad7Cb5iF+AK1EWVL/Bo7Rz9uurpqw6SiBCefUbCGA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@jest/types": "^29.6.3",
        "@types/node": "*",
        "chalk": "^4.0.0",
        "ci-info": "^3.2.0",
        "graceful-fs": "^4.2.9",
        "picomatch": "^2.2.3"
      },
      "engines": {
        "node": "^14.15.0 || ^16.10.0 || >=18.0.0"
      }
    },
    "node_modules/jest-util/node_modules/chalk": {
      "version": "4.1.2",
      "resolved": "https://registry.npmjs.org/chalk/-/chalk-4.1.2.tgz",
      "integrity": "sha512-oKnbhFyRIXpUuez8iBMmyEa4nbj4IOQyuhc/wy9kY7/WVPcwIO9VA668Pu8RkO7+0G76SLROeyw9CpQ061i4mA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ansi-styles": "^4.1.0",
        "supports-color": "^7.1.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/chalk/chalk?sponsor=1"
      }
    },
    "node_modules/jest-util/node_modules/supports-color": {
      "version": "7.2.0",
      "resolved": "https://registry.npmjs.org/supports-color/-/supports-color-7.2.0.tgz",
      "integrity": "sha512-qpCAvRl9stuOHveKsn7HncJRvv501qIacKzQlO/+Lwxc9+0q2wLyv4Dfvt80/DPn2pqOBsJdDiogXGR9+OvwRw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "has-flag": "^4.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/jest-validate": {
      "version": "29.7.0",
      "resolved": "https://registry.npmjs.org/jest-validate/-/jest-validate-29.7.0.tgz",
      "integrity": "sha512-ZB7wHqaRGVw/9hST/OuFUReG7M8vKeq0/J2egIGLdvjHCmYqGARhzXmtgi+gVeZ5uXFF219aOc3Ls2yLg27tkw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@jest/types": "^29.6.3",
        "camelcase": "^6.2.0",
        "chalk": "^4.0.0",
        "jest-get-type": "^29.6.3",
        "leven": "^3.1.0",
        "pretty-format": "^29.7.0"
      },
      "engines": {
        "node": "^14.15.0 || ^16.10.0 || >=18.0.0"
      }
    },
    "node_modules/jest-validate/node_modules/chalk": {
      "version": "4.1.2",
      "resolved": "https://registry.npmjs.org/chalk/-/chalk-4.1.2.tgz",
      "integrity": "sha512-oKnbhFyRIXpUuez8iBMmyEa4nbj4IOQyuhc/wy9kY7/WVPcwIO9VA668Pu8RkO7+0G76SLROeyw9CpQ061i4mA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ansi-styles": "^4.1.0",
        "supports-color": "^7.1.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/chalk/chalk?sponsor=1"
      }
    },
    "node_modules/jest-validate/node_modules/supports-color": {
      "version": "7.2.0",
      "resolved": "https://registry.npmjs.org/supports-color/-/supports-color-7.2.0.tgz",
      "integrity": "sha512-qpCAvRl9stuOHveKsn7HncJRvv501qIacKzQlO/+Lwxc9+0q2wLyv4Dfvt80/DPn2pqOBsJdDiogXGR9+OvwRw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "has-flag": "^4.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/jest-worker": {
      "version": "29.7.0",
      "resolved": "https://registry.npmjs.org/jest-worker/-/jest-worker-29.7.0.tgz",
      "integrity": "sha512-eIz2msL/EzL9UFTFFx7jBTkeZfku0yUAyZZZmJ93H2TYEiroIx2PQjEXcwYtYl8zXCxb+PAmA2hLIt/6ZEkPHw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@types/node": "*",
        "jest-util": "^29.7.0",
        "merge-stream": "^2.0.0",
        "supports-color": "^8.0.0"
      },
      "engines": {
        "node": "^14.15.0 || ^16.10.0 || >=18.0.0"
      }
    },
    "node_modules/js-tokens": {
      "version": "4.0.0",
      "resolved": "https://registry.npmjs.org/js-tokens/-/js-tokens-4.0.0.tgz",
      "integrity": "sha512-RdJUflcE3cUzKiMqQgsCu06FPu9UdIJO0beYbPhHN4k6apgJtifcoCtT9bcxOpYBtpD2kCM6Sbzg4CausW/PKQ==",
      "license": "MIT"
    },
    "node_modules/jsc-safe-url": {
      "version": "0.2.4",
      "resolved": "https://registry.npmjs.org/jsc-safe-url/-/jsc-safe-url-0.2.4.tgz",
      "integrity": "sha512-0wM3YBWtYePOjfyXQH5MWQ8H7sdk5EXSwZvmSLKk2RboVQ2Bu239jycHDz5J/8Blf3K0Qnoy2b6xD+z10MFB+Q==",
      "license": "0BSD",
      "peer": true
    },
    "node_modules/jsesc": {
      "version": "3.1.0",
      "resolved": "https://registry.npmjs.org/jsesc/-/jsesc-3.1.0.tgz",
      "integrity": "sha512-/sM3dO2FOzXjKQhJuo0Q173wf2KOo8t4I8vHy6lF9poUp7bKT0/NHE8fPX23PwfhnykfqnC2xRxOnVw5XuGIaA==",
      "license": "MIT",
      "peer": true,
      "bin": {
        "jsesc": "bin/jsesc"
      },
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/json-stringify-safe": {
      "version": "5.0.1",
      "resolved": "https://registry.npmjs.org/json-stringify-safe/-/json-stringify-safe-5.0.1.tgz",
      "integrity": "sha512-ZClg6AaYvamvYEE82d3Iyd3vSSIjQ+odgjaTzRuO3s7toCdFKczob2i0zCh7JE8kWn17yvAWhUVxvqGwUalsRA==",
      "license": "ISC"
    },
    "node_modules/json5": {
      "version": "2.2.3",
      "resolved": "https://registry.npmjs.org/json5/-/json5-2.2.3.tgz",
      "integrity": "sha512-XmOWe7eyHYH14cLdVPoyg+GOH3rYX++KpzrylJwSW98t3Nk+U8XOl8FWKOgwtzdb8lXGf6zYwDUzeHMWfxasyg==",
      "license": "MIT",
      "peer": true,
      "bin": {
        "json5": "lib/cli.js"
      },
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/leven": {
      "version": "3.1.0",
      "resolved": "https://registry.npmjs.org/leven/-/leven-3.1.0.tgz",
      "integrity": "sha512-qsda+H8jTaUaN/x5vzW2rzc+8Rw4TAQ/4KjB46IwK5VH+IlVeeeje/EoZRpiXvIqjFgK84QffqPztGI3VBLG1A==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/lighthouse-logger": {
      "version": "1.4.2",
      "resolved": "https://registry.npmjs.org/lighthouse-logger/-/lighthouse-logger-1.4.2.tgz",
      "integrity": "sha512-gPWxznF6TKmUHrOQjlVo2UbaL2EJ71mb2CCeRs/2qBpi4L/g4LUVc9+3lKQ6DTUZwJswfM7ainGrLO1+fOqa2g==",
      "license": "Apache-2.0",
      "peer": true,
      "dependencies": {
        "debug": "^2.6.9",
        "marky": "^1.2.2"
      }
    },
    "node_modules/lighthouse-logger/node_modules/debug": {
      "version": "2.6.9",
      "resolved": "https://registry.npmjs.org/debug/-/debug-2.6.9.tgz",
      "integrity": "sha512-bC7ElrdJaJnPbAP+1EotYvqZsb3ecl5wi6Bfi6BJTUcNowp6cvspg0jXznRTKDjm/E7AdgFBVeAPVMNcKGsHMA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ms": "2.0.0"
      }
    },
    "node_modules/lighthouse-logger/node_modules/ms": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/ms/-/ms-2.0.0.tgz",
      "integrity": "sha512-Tpp60P6IUJDTuOq/5Z8cdskzJujfwqfOTkrwIwj7IRISpnkJnT6SyJ4PCPnGMoFjC9ddhal5KVIYtAt97ix05A==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/lightningcss": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss/-/lightningcss-1.33.0.tgz",
      "integrity": "sha512-WkUDrojuJs0xkgGf2udWxa3yGBRxPtxUkB79i6aCZLRgc7PM8fZe9TosfPDcvEpQZbuFASnHYmRLBLUbmLOIIA==",
      "dev": true,
      "license": "MPL-2.0",
      "dependencies": {
        "detect-libc": "^2.0.3"
      },
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      },
      "optionalDependencies": {
        "lightningcss-android-arm64": "1.33.0",
        "lightningcss-darwin-arm64": "1.33.0",
        "lightningcss-darwin-x64": "1.33.0",
        "lightningcss-freebsd-x64": "1.33.0",
        "lightningcss-linux-arm-gnueabihf": "1.33.0",
        "lightningcss-linux-arm64-gnu": "1.33.0",
        "lightningcss-linux-arm64-musl": "1.33.0",
        "lightningcss-linux-x64-gnu": "1.33.0",
        "lightningcss-linux-x64-musl": "1.33.0",
        "lightningcss-win32-arm64-msvc": "1.33.0",
        "lightningcss-win32-x64-msvc": "1.33.0"
      }
    },
    "node_modules/lightningcss-android-arm64": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-android-arm64/-/lightningcss-android-arm64-1.33.0.tgz",
      "integrity": "sha512-gEpRTalKdosp4Bb8qWtc2iOgE5SeIHlpS1up9bFq2wAyYhl1UdTObYiHe98zEM9SQvSoqQZ1IQD0JNpg3Ml5pg==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "android"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-darwin-arm64": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-darwin-arm64/-/lightningcss-darwin-arm64-1.33.0.tgz",
      "integrity": "sha512-Sciaz8eenNTKn9b3t7+xr0ipTp9YxKQY4npwQ3mrRuL0BAVHBLyZxofhaKBAVtzmtRZ/zTyo0/to4B1uWG/Djg==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-darwin-x64": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-darwin-x64/-/lightningcss-darwin-x64-1.33.0.tgz",
      "integrity": "sha512-Z5UPAxzrjlWNNyGy6i65cJzzvgJ5D3T6wMvs+gWpY9d7qRhANrxqAp6LhxIgZhWEw18RfJTGcRxjuLIBr+m8XQ==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-freebsd-x64": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-freebsd-x64/-/lightningcss-freebsd-x64-1.33.0.tgz",
      "integrity": "sha512-QQM/Ti/hQajJwCY+RiWuCZ9sdtI/XQk7nDK5vC8kkdwixezOlDgvDx7+RT+QjK6FcFT4MpsuoBnHIo/O3StRRg==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "freebsd"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-linux-arm-gnueabihf": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-arm-gnueabihf/-/lightningcss-linux-arm-gnueabihf-1.33.0.tgz",
      "integrity": "sha512-N7FVBe6iS24MlM6R/4RBTxGhQheZGs7tiQ9U32UtF75NzP5Q7xWPRqLBCKxlRQRk3rY1jCIPLzx7WzOhuUIRLQ==",
      "cpu": [
        "arm"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-linux-arm64-gnu": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-arm64-gnu/-/lightningcss-linux-arm64-gnu-1.33.0.tgz",
      "integrity": "sha512-j2v/itmy4HlNxlc6voKXYgBqNi0Ng2LShg4z7GufpEgs05P+2suBVyi9I6YHq5uoVFx9ETin3eCEhLVyXGQnKg==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-linux-arm64-musl": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-arm64-musl/-/lightningcss-linux-arm64-musl-1.33.0.tgz",
      "integrity": "sha512-yiO5ROMuYQgXbC60yjZU5CYSFZGKXL0HFATXt9mHJn1+zW55oCtMI9NfcVhYLMFDL7gV7oBPon/EmMMGg2OvtQ==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-linux-x64-gnu": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-x64-gnu/-/lightningcss-linux-x64-gnu-1.33.0.tgz",
      "integrity": "sha512-ar+Ju7LmcN0Jo4FpL4hpFybwNG9/3A/Br5KW2n2jyODg3MEZXaDYADdemoNS+BDNfMgKvylJLj4S5tyRActuAg==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-linux-x64-musl": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-x64-musl/-/lightningcss-linux-x64-musl-1.33.0.tgz",
      "integrity": "sha512-RYiYbkokw0trfKqqzfF55lginwEPrD3OJDfTuJzFs1MK6iFnDenaz1fqLLtX4ITG3OktJQXOeTaw1awrBAlZPw==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-win32-arm64-msvc": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-win32-arm64-msvc/-/lightningcss-win32-arm64-msvc-1.33.0.tgz",
      "integrity": "sha512-1K+MPfLSFVpphzpdbfkhlWk6wBrTObBzS2T6db10PNOZgR9GoVsAWzwNyuhUYYbTp23j+4RrncfujZ4uAzXvwA==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-win32-x64-msvc": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-win32-x64-msvc/-/lightningcss-win32-x64-msvc-1.33.0.tgz",
      "integrity": "sha512-OlEICDx/Xl0FqSp4bry8zFnCvGpig3Gl4gCquvYwHuqJKEC1+n9NgDniFvqHGmMv1ZkqDJrDqKKSykTDX+ehuA==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/litesvm": {
      "version": "0.1.0",
      "resolved": "https://registry.npmjs.org/litesvm/-/litesvm-0.1.0.tgz",
      "integrity": "sha512-XfpvWgYxFQUZxwFzWJTsuHRc1y34q8WtC60lhvH1xb6YX1/RBLqzIClp2JkxtlqGnDi/WPlThsXGmC3SinuPMQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@solana/web3.js": "^1.68.0",
        "bs58": "^4.0.1"
      },
      "engines": {
        "node": ">= 10"
      },
      "optionalDependencies": {
        "litesvm-darwin-arm64": "0.1.0",
        "litesvm-darwin-universal": "0.1.0",
        "litesvm-darwin-x64": "0.1.0",
        "litesvm-linux-x64-gnu": "0.1.0",
        "litesvm-linux-x64-musl": "0.1.0"
      }
    },
    "node_modules/litesvm-darwin-arm64": {
      "version": "0.1.0",
      "resolved": "https://registry.npmjs.org/litesvm-darwin-arm64/-/litesvm-darwin-arm64-0.1.0.tgz",
      "integrity": "sha512-GwBph2fNaR9UP1nhFmQYk7UMcI9+ogrzpbDl2en70FUnPc+FDlchOts2X8IL5XFCU+m4ZGoQl/N9b+FywJN5lQ==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": ">= 10"
      }
    },
    "node_modules/litesvm-darwin-universal": {
      "version": "0.1.0",
      "resolved": "https://registry.npmjs.org/litesvm-darwin-universal/-/litesvm-darwin-universal-0.1.0.tgz",
      "integrity": "sha512-GjGpz77ei+RfWiMtHiES0X8GP+TafFHWu5fAQXgXEoGia7RG32Z12iJBhwfvk0T4EKbm8bqlyqhe5Me/nARm/w==",
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": ">= 10"
      }
    },
    "node_modules/litesvm-darwin-x64": {
      "version": "0.1.0",
      "resolved": "https://registry.npmjs.org/litesvm-darwin-x64/-/litesvm-darwin-x64-0.1.0.tgz",
      "integrity": "sha512-1N/IPfoT+gcpkvG9Wm7+vcaxgl/LB8hbm85cHDQRq4O1wyiRRiR6ByeNRamj+OFEDSfI7a/1NshhMobnnr2MGQ==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": ">= 10"
      }
    },
    "node_modules/litesvm-linux-x64-gnu": {
      "version": "0.1.0",
      "resolved": "https://registry.npmjs.org/litesvm-linux-x64-gnu/-/litesvm-linux-x64-gnu-0.1.0.tgz",
      "integrity": "sha512-S6krvRz6BXxVZIkap5XkWwulSG4KsbFrxjyqP1X0zANa8jWMHEd09Zy9pPgfOetni2exg67fBmSlWq4sRfzlCw==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 10"
      }
    },
    "node_modules/litesvm-linux-x64-musl": {
      "version": "0.1.0",
      "resolved": "https://registry.npmjs.org/litesvm-linux-x64-musl/-/litesvm-linux-x64-musl-0.1.0.tgz",
      "integrity": "sha512-3E9gC5HRCEHFsfUNDhAY9JKx6ou6JazlnYMhT89JgbAN/YsJmyEgkTfY6W7TVV90g4EAJ/K4smSmg+vV413mYQ==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 10"
      }
    },
    "node_modules/locate-path": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/locate-path/-/locate-path-5.0.0.tgz",
      "integrity": "sha512-t7hw9pI+WvuwNJXwk5zVHpyhIqzg2qTlklJOf0mVxGSbe3Fp2VieZcduNYjaLDoy6p9uGpQEGWG87WpMKlNq8g==",
      "license": "MIT",
      "dependencies": {
        "p-locate": "^4.1.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/lodash.throttle": {
      "version": "4.1.1",
      "resolved": "https://registry.npmjs.org/lodash.throttle/-/lodash.throttle-4.1.1.tgz",
      "integrity": "sha512-wIkUCfVKpVsWo3JSZlc+8MB5it+2AN5W8J7YVMST30UrvcQNZ1Okbj+rbVniijTWE6FGYy4XJq/rHkas8qJMLQ==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/loose-envify": {
      "version": "1.4.0",
      "resolved": "https://registry.npmjs.org/loose-envify/-/loose-envify-1.4.0.tgz",
      "integrity": "sha512-lyuxPGr/Wfhrlem2CL/UcnUc1zcqKAImBDzukY7Y5F/yQiNdko6+fRLevlw1HgMySw7f611UIY408EtxRSoK3Q==",
      "license": "MIT",
      "dependencies": {
        "js-tokens": "^3.0.0 || ^4.0.0"
      },
      "bin": {
        "loose-envify": "cli.js"
      }
    },
    "node_modules/lru-cache": {
      "version": "5.1.1",
      "resolved": "https://registry.npmjs.org/lru-cache/-/lru-cache-5.1.1.tgz",
      "integrity": "sha512-KpNARQA3Iwv+jTA0utUVVbrh+Jlrr1Fv0e56GGzAFOXN7dk/FviaDW8LHmK52DlcH4WP2n6gI8vN1aesBFgo9w==",
      "license": "ISC",
      "peer": true,
      "dependencies": {
        "yallist": "^3.0.2"
      }
    },
    "node_modules/magic-string": {
      "version": "0.30.21",
      "resolved": "https://registry.npmjs.org/magic-string/-/magic-string-0.30.21.tgz",
      "integrity": "sha512-vd2F4YUyEXKGcLHoq+TEyCjxueSeHnFxyyjNp80yg0XV4vUhnDer/lvvlqM/arB5bXQN5K2/3oinyCRyx8T2CQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@jridgewell/sourcemap-codec": "^1.5.5"
      }
    },
    "node_modules/marky": {
      "version": "1.3.0",
      "resolved": "https://registry.npmjs.org/marky/-/marky-1.3.0.tgz",
      "integrity": "sha512-ocnPZQLNpvbedwTy9kNrQEsknEfgvcLMvOtz3sFeWApDq1MXH1TqkCIx58xlpESsfwQOnuBO9beyQuNGzVvuhQ==",
      "license": "Apache-2.0",
      "peer": true
    },
    "node_modules/math-intrinsics": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/math-intrinsics/-/math-intrinsics-1.1.0.tgz",
      "integrity": "sha512-/IXtbwEk5HTPyEwyKX6hGkYXxM9nbj64B+ilVJnC/R6B0pH5G4V3b0pVbL7DBj4tkhBAppbQUlf6F6Xl9LHu1g==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/md5.js": {
      "version": "1.3.5",
      "resolved": "https://registry.npmjs.org/md5.js/-/md5.js-1.3.5.tgz",
      "integrity": "sha512-xitP+WxNPcTTOgnTJcrhM0xvdPepipPSf3I8EIpGKeFLjt3PlJLIDG3u8EX53ZIubkb+5U2+3rELYpEhHhzdkg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "hash-base": "^3.0.0",
        "inherits": "^2.0.1",
        "safe-buffer": "^5.1.2"
      }
    },
    "node_modules/memoize-one": {
      "version": "5.2.1",
      "resolved": "https://registry.npmjs.org/memoize-one/-/memoize-one-5.2.1.tgz",
      "integrity": "sha512-zYiwtZUcYyXKo/np96AGZAckk+FWWsUdJ3cHGGmld7+AhvcWmQyGCYUh1hc4Q/pkOhb65dQR/pqCyK0cOaHz4Q==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/merge-options": {
      "version": "3.0.4",
      "resolved": "https://registry.npmjs.org/merge-options/-/merge-options-3.0.4.tgz",
      "integrity": "sha512-2Sug1+knBjkaMsMgf1ctR1Ujx+Ayku4EdJN4Z+C2+JzoeF7A3OZ9KM2GY0CpQS51NR61LTurMJrRKPhSs3ZRTQ==",
      "license": "MIT",
      "optional": true,
      "dependencies": {
        "is-plain-obj": "^2.1.0"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/merge-stream": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/merge-stream/-/merge-stream-2.0.0.tgz",
      "integrity": "sha512-abv/qOcuPfk3URPfDzmZU1LKmuw8kT+0nIHvKrKgFrwifol/doWcdA4ZqsWQ8ENrFKkd67Mfpo/LovbIUsbt3w==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/metro": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro/-/metro-0.87.1.tgz",
      "integrity": "sha512-1oyLU9elM7hPAsKIqKooEekwxiuWr27+MZBhUROPhzcbXhMDxK64GPF/hCXwBZVp1F89ODavCrBmJtLx9WtBoQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/code-frame": "^7.29.0",
        "@babel/core": "^7.25.2",
        "@babel/generator": "^7.29.1",
        "@babel/parser": "^7.29.0",
        "@babel/template": "^7.28.6",
        "@babel/traverse": "^7.29.0",
        "@babel/types": "^7.29.0",
        "accepts": "^2.0.0",
        "connect": "^3.6.5",
        "debug": "^4.4.0",
        "error-stack-parser": "^2.0.6",
        "flow-enums-runtime": "^0.0.6",
        "flow-parser": "0.331.0",
        "graceful-fs": "^4.2.4",
        "invariant": "^2.2.4",
        "jest-worker": "^29.7.0",
        "jsc-safe-url": "^0.2.2",
        "lodash.throttle": "^4.1.1",
        "metro-babel-transformer": "0.87.1",
        "metro-cache": "0.87.1",
        "metro-cache-key": "0.87.1",
        "metro-config": "0.87.1",
        "metro-core": "0.87.1",
        "metro-file-map": "0.87.1",
        "metro-resolver": "0.87.1",
        "metro-runtime": "0.87.1",
        "metro-source-map": "0.87.1",
        "metro-symbolicate": "0.87.1",
        "metro-transform-plugins": "0.87.1",
        "metro-transform-worker": "0.87.1",
        "mime-types": "^3.0.1",
        "nullthrows": "^1.1.1",
        "serialize-error": "^2.1.0",
        "source-map": "^0.5.6",
        "throat": "^5.0.0",
        "ws": "^7.5.10",
        "yargs": "^17.6.2"
      },
      "bin": {
        "metro": "src/cli.js"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro-babel-transformer": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro-babel-transformer/-/metro-babel-transformer-0.87.1.tgz",
      "integrity": "sha512-orvRIGpb0yK1yMbk5YP3dhVKjmoxUkRB9fdltGJxNppEqus/1tFpNuf9KnGFR3Qjg0izoUrJ4z6WgoBvdkXPrA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/core": "^7.25.2",
        "flow-enums-runtime": "^0.0.6",
        "flow-parser": "0.331.0",
        "metro-cache-key": "0.87.1",
        "nullthrows": "^1.1.1"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro-cache": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro-cache/-/metro-cache-0.87.1.tgz",
      "integrity": "sha512-juNPaj0Xi5tkLp8imXqvbSnEIijwKG36m7OiFFVJMqEkiURwAjkMFVek3/xpix1+LVQqO7kjVp3PvuvIM61mKQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "exponential-backoff": "^3.1.1",
        "flow-enums-runtime": "^0.0.6",
        "https-proxy-agent": "^7.0.5",
        "metro-core": "0.87.1"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro-cache-key": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro-cache-key/-/metro-cache-key-0.87.1.tgz",
      "integrity": "sha512-scqVVPMA2c+RVO12I3wyMDp5xCkRPLsyrcG4Qc3xfU5JR0EW/0sz2tjty+5UjMUtG09uiM1KYQ8HjWg7OQXHtw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "flow-enums-runtime": "^0.0.6"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro-config": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro-config/-/metro-config-0.87.1.tgz",
      "integrity": "sha512-NmkDlc/qZAdo5gTkVTuO2AKE/khemRKRH5IA+SKfqUBJigI5GqZ5TOXhmEokhlkAqzjt8dyzKhzI6FHvXoXaTQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "connect": "^3.6.5",
        "flow-enums-runtime": "^0.0.6",
        "jest-validate": "^29.7.0",
        "metro": "0.87.1",
        "metro-cache": "0.87.1",
        "metro-core": "0.87.1",
        "metro-runtime": "0.87.1"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro-core": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro-core/-/metro-core-0.87.1.tgz",
      "integrity": "sha512-xizzky/4+c/Mkznege8OW05j7bSdM39VPoEps61Se4+hf32UQujmbvLvIE9+UnP6kNEPVomk0Fw8NsBK9iRQmw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "flow-enums-runtime": "^0.0.6",
        "lodash.throttle": "^4.1.1",
        "metro-resolver": "0.87.1"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro-file-map": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro-file-map/-/metro-file-map-0.87.1.tgz",
      "integrity": "sha512-9sPuNCojC3pS4vj+ZPY7FXmHGpdJeckXuKXQrDAfJvZc60AF8owRFTkI8XdwlwrmPIB2w++KraK9FMEXvC4wJw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "debug": "^4.4.0",
        "fb-watchman": "^2.0.0",
        "flow-enums-runtime": "^0.0.6",
        "graceful-fs": "^4.2.4",
        "invariant": "^2.2.4",
        "jest-worker": "^29.7.0",
        "micromatch": "^4.0.4",
        "nullthrows": "^1.1.1"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro-minify-terser": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro-minify-terser/-/metro-minify-terser-0.87.1.tgz",
      "integrity": "sha512-YK4k1oO1wV48hfE+Nbw2rJCnAgeabzrgT/xH5ha5n9gbK4p3HYFC898cERUiyTl9vRh58CNTiXRc88f7y6PfKg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "flow-enums-runtime": "^0.0.6",
        "terser": "^5.15.0"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro-resolver": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro-resolver/-/metro-resolver-0.87.1.tgz",
      "integrity": "sha512-FXH/brY69wT6sPxaSW8BhMmDGD/6irmBr/cL4rUi+VWwqR3pbvdcfUOfyjcHucgQ7pe5IW3xJY21eHKLVKNumQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "flow-enums-runtime": "^0.0.6"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro-runtime": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro-runtime/-/metro-runtime-0.87.1.tgz",
      "integrity": "sha512-kjeuSvInsM6OzBjkCQsWxnkrKZFMKtnkCl38oXWRI9lDGs2L9hGs9Tak9sQYJ9h3gtDujneB7wZio+irgqJKDw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/runtime": "^7.25.0",
        "flow-enums-runtime": "^0.0.6"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro-source-map": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro-source-map/-/metro-source-map-0.87.1.tgz",
      "integrity": "sha512-Bqpm0PBGdy53pigIJb4HRF7QxD2pUOdgSmVh/4AWbP635kSCv+Y6ltVxUZgSnzS/QbSmzyCGijmRPlXMj2/qHw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/traverse": "^7.29.0",
        "@babel/types": "^7.29.0",
        "flow-enums-runtime": "^0.0.6",
        "invariant": "^2.2.4",
        "metro-symbolicate": "0.87.1",
        "nullthrows": "^1.1.1",
        "ob1": "0.87.1",
        "source-map": "^0.5.6",
        "vlq": "^1.0.0"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro-symbolicate": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro-symbolicate/-/metro-symbolicate-0.87.1.tgz",
      "integrity": "sha512-rcGvwabrg0lbXGRGRKl14PY3My3+dkno2jZYhdJEuH2DmjTtTkV5bYwgto4JtV/Lbe+sXE6GO1UGg654430uow==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "flow-enums-runtime": "^0.0.6",
        "invariant": "^2.2.4",
        "metro-source-map": "0.87.1",
        "nullthrows": "^1.1.1",
        "source-map": "^0.5.6",
        "vlq": "^1.0.0"
      },
      "bin": {
        "metro-symbolicate": "src/index.js"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro-transform-plugins": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro-transform-plugins/-/metro-transform-plugins-0.87.1.tgz",
      "integrity": "sha512-qMiJ/x+VfqumFJJSefKS6nj8uojzC29b2/aK8vlMuFABIqGjDucICEOXd2Yt6k/XMFAgAcaJvShUOT0HLyYaPw==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/core": "^7.25.2",
        "@babel/generator": "^7.29.1",
        "@babel/template": "^7.28.6",
        "@babel/traverse": "^7.29.0",
        "flow-enums-runtime": "^0.0.6",
        "nullthrows": "^1.1.1"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro-transform-worker": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/metro-transform-worker/-/metro-transform-worker-0.87.1.tgz",
      "integrity": "sha512-VOzs3OV405FuOLYdAhqA2wsn1F9lvueDVxMDLvCKaQ44U+yknIqphJ9eMjjsGwLDZiJq9sW3DMLhjD27JxQgqQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/core": "^7.25.2",
        "@babel/generator": "^7.29.1",
        "@babel/parser": "^7.29.0",
        "@babel/types": "^7.29.0",
        "flow-enums-runtime": "^0.0.6",
        "metro": "0.87.1",
        "metro-babel-transformer": "0.87.1",
        "metro-cache": "0.87.1",
        "metro-cache-key": "0.87.1",
        "metro-minify-terser": "0.87.1",
        "metro-source-map": "0.87.1",
        "metro-transform-plugins": "0.87.1",
        "nullthrows": "^1.1.1"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/metro/node_modules/cliui": {
      "version": "8.0.1",
      "resolved": "https://registry.npmjs.org/cliui/-/cliui-8.0.1.tgz",
      "integrity": "sha512-BSeNnyus75C4//NQ9gQt1/csTXyo/8Sb+afLAkzAptFuMsod9HFokGNudZpi/oQV73hnVK+sR+5PVRMd+Dr7YQ==",
      "license": "ISC",
      "peer": true,
      "dependencies": {
        "string-width": "^4.2.0",
        "strip-ansi": "^6.0.1",
        "wrap-ansi": "^7.0.0"
      },
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/metro/node_modules/wrap-ansi": {
      "version": "7.0.0",
      "resolved": "https://registry.npmjs.org/wrap-ansi/-/wrap-ansi-7.0.0.tgz",
      "integrity": "sha512-YVGIj2kamLSTxw6NsZjoBxfSwsn0ycdesmc4p+Q21c5zPuZ1pl+NfxVdxPtdHvmNVOQ6XSYG4AUtyt/Fi7D16Q==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ansi-styles": "^4.0.0",
        "string-width": "^4.1.0",
        "strip-ansi": "^6.0.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/chalk/wrap-ansi?sponsor=1"
      }
    },
    "node_modules/metro/node_modules/y18n": {
      "version": "5.0.8",
      "resolved": "https://registry.npmjs.org/y18n/-/y18n-5.0.8.tgz",
      "integrity": "sha512-0pfFzegeDWJHJIAmTLRP2DwHjdF5s7jo9tuztdQxAhINCdvS+3nGINqPd00AphqJR/0LhANUS6/+7SCb98YOfA==",
      "license": "ISC",
      "peer": true,
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/metro/node_modules/yargs": {
      "version": "17.7.3",
      "resolved": "https://registry.npmjs.org/yargs/-/yargs-17.7.3.tgz",
      "integrity": "sha512-GZtjxm/J/4TSxuL3FNYjCmLktBTnIw/rVmKSIyKeYAZpmJB2ig9VauCC5xsa82GNKVKDAqpOn3KVzNt0zmrU0g==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "cliui": "^8.0.1",
        "escalade": "^3.1.1",
        "get-caller-file": "^2.0.5",
        "require-directory": "^2.1.1",
        "string-width": "^4.2.3",
        "y18n": "^5.0.5",
        "yargs-parser": "^21.1.1"
      },
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/metro/node_modules/yargs-parser": {
      "version": "21.1.1",
      "resolved": "https://registry.npmjs.org/yargs-parser/-/yargs-parser-21.1.1.tgz",
      "integrity": "sha512-tVpsJW7DdjecAiFpbIB1e3qxIQsE6NoPc5/eTdrbbIC4h0LVsWhnoa3g+m2HclBIujHzsxZ4VJVA+GUuc2/LBw==",
      "license": "ISC",
      "peer": true,
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/micromatch": {
      "version": "4.0.8",
      "resolved": "https://registry.npmjs.org/micromatch/-/micromatch-4.0.8.tgz",
      "integrity": "sha512-PXwfBhYu0hBCPw8Dn0E+WDYb7af3dSLVWKi3HGv84IdF4TyFoC0ysxFd0Goxw7nSv4T/PzEJQxsYsEiFCKo2BA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "braces": "^3.0.3",
        "picomatch": "^2.3.1"
      },
      "engines": {
        "node": ">=8.6"
      }
    },
    "node_modules/miller-rabin": {
      "version": "4.0.1",
      "resolved": "https://registry.npmjs.org/miller-rabin/-/miller-rabin-4.0.1.tgz",
      "integrity": "sha512-115fLhvZVqWwHPbClyntxEVfVDfl9DLLTuJvq3g2O/Oxi8AiNouAHvDSzHS0viUJc+V5vm3eq91Xwqn9dp4jRA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "bn.js": "^4.0.0",
        "brorand": "^1.0.1"
      },
      "bin": {
        "miller-rabin": "bin/miller-rabin"
      }
    },
    "node_modules/miller-rabin/node_modules/bn.js": {
      "version": "4.12.5",
      "resolved": "https://registry.npmjs.org/bn.js/-/bn.js-4.12.5.tgz",
      "integrity": "sha512-3aRg6/JxfffFD+OlOjOFR3Vo79l39ooBTFucxx+MT3dhCtzn3EmiUPQo+6/OZuI2jbXi3YKgmiTFBgChQMwIRQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/mime": {
      "version": "1.6.0",
      "resolved": "https://registry.npmjs.org/mime/-/mime-1.6.0.tgz",
      "integrity": "sha512-x0Vn8spI+wuJ1O6S7gnbaQg8Pxh4NNHb7KSINmEWKiPE4RKOplvijn+NkmYmmRgP68mc70j2EbeTFRsrswaQeg==",
      "license": "MIT",
      "peer": true,
      "bin": {
        "mime": "cli.js"
      },
      "engines": {
        "node": ">=4"
      }
    },
    "node_modules/mime-db": {
      "version": "1.54.0",
      "resolved": "https://registry.npmjs.org/mime-db/-/mime-db-1.54.0.tgz",
      "integrity": "sha512-aU5EJuIN2WDemCcAp2vFBfp/m4EAhWJnUNSSw0ixs7/kXbd6Pg64EmwJkNdFhB8aWt1sH2CTXrLxo/iAGV3oPQ==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/mime-types": {
      "version": "3.0.2",
      "resolved": "https://registry.npmjs.org/mime-types/-/mime-types-3.0.2.tgz",
      "integrity": "sha512-Lbgzdk0h4juoQ9fCKXW4by0UJqj+nOOrI9MJ1sSj4nI8aI2eo1qmvQEie4VD1glsS250n15LsWsYtCugiStS5A==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "mime-db": "^1.54.0"
      },
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/minimalistic-assert": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/minimalistic-assert/-/minimalistic-assert-1.0.1.tgz",
      "integrity": "sha512-UtJcAD4yEaGtjPezWuO9wC4nwUnVH/8/Im3yEHQP4b67cXlD/Qr9hdITCU1xDbSEXg2XKNaP8jsReV7vQd00/A==",
      "dev": true,
      "license": "ISC"
    },
    "node_modules/minimalistic-crypto-utils": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/minimalistic-crypto-utils/-/minimalistic-crypto-utils-1.0.1.tgz",
      "integrity": "sha512-JIYlbt6g8i5jKfJ3xz7rF0LXmv2TkDxBLUkiBeZ7bAx4GnnNMr8xFpGnOxn6GhTEHx3SjRrZEoU+j04prX1ktg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/mkdirp": {
      "version": "1.0.4",
      "resolved": "https://registry.npmjs.org/mkdirp/-/mkdirp-1.0.4.tgz",
      "integrity": "sha512-vVqVZQyf3WLx2Shd0qJ9xuvqgAyKPLAiqITEtqW0oIUjzo3PePDd6fW9iFz30ef7Ysp/oiWqbhszeGWW2T6Gzw==",
      "license": "MIT",
      "peer": true,
      "bin": {
        "mkdirp": "bin/cmd.js"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/ms": {
      "version": "2.1.3",
      "resolved": "https://registry.npmjs.org/ms/-/ms-2.1.3.tgz",
      "integrity": "sha512-6FlzubTLZG3J2a/NVCAleEhjzq5oxgHyaCU9yYXvcLsvoVaHJq/s5xXI6/XXP6tz7R9xAOtHnSO/tXtF3WRTlA==",
      "license": "MIT"
    },
    "node_modules/nanoid": {
      "version": "3.3.19",
      "resolved": "https://registry.npmjs.org/nanoid/-/nanoid-3.3.19.tgz",
      "integrity": "sha512-Y2tUNy4ouw6tq5oDSKeQYGOyhkUBhNOcGV/02KC+6kd9eDGqdZd++mjMiIDilrBYvjEnCYvVtsuHCuP+okSfug==",
      "dev": true,
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/ai"
        }
      ],
      "license": "MIT",
      "bin": {
        "nanoid": "bin/nanoid.cjs"
      },
      "engines": {
        "node": "^10 || ^12 || ^13.7 || ^14 || >=15.0.1"
      }
    },
    "node_modules/negotiator": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/negotiator/-/negotiator-1.1.0.tgz",
      "integrity": "sha512-NMPBRMJgiQHjbd8phG3Vebdx4kZ1H121rbl5IkMqeOsahptB9BKo/d7oJ3zTXqTgagn2bWlNSXkh0QUGM31RYg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "content-type": "^2.1.0"
      },
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/node-fetch": {
      "version": "2.7.0",
      "resolved": "https://registry.npmjs.org/node-fetch/-/node-fetch-2.7.0.tgz",
      "integrity": "sha512-c4FRfUm/dbcWZ7U+1Wq0AwCyFL+3nt2bEw05wfxSz+DWpWsitgmSgYmy2dQdWyKC1694ELPqMs/YzUSNozLt8A==",
      "license": "MIT",
      "dependencies": {
        "whatwg-url": "^5.0.0"
      },
      "engines": {
        "node": "4.x || >=6.0.0"
      },
      "peerDependencies": {
        "encoding": "^0.1.0"
      },
      "peerDependenciesMeta": {
        "encoding": {
          "optional": true
        }
      }
    },
    "node_modules/node-gyp-build": {
      "version": "4.8.4",
      "resolved": "https://registry.npmjs.org/node-gyp-build/-/node-gyp-build-4.8.4.tgz",
      "integrity": "sha512-LA4ZjwlnUblHVgq0oBF3Jl/6h/Nvs5fzBLwdEF4nuxnFdsfajde4WfxtJr3CaiH+F6ewcIB/q4jQ4UzPyid+CQ==",
      "license": "MIT",
      "optional": true,
      "bin": {
        "node-gyp-build": "bin.js",
        "node-gyp-build-optional": "optional.js",
        "node-gyp-build-test": "build-test.js"
      }
    },
    "node_modules/node-int64": {
      "version": "0.4.0",
      "resolved": "https://registry.npmjs.org/node-int64/-/node-int64-0.4.0.tgz",
      "integrity": "sha512-O5lz91xSOeoXP6DulyHfllpq+Eg00MWitZIbtPfoSEvqIHdl5gfcY6hYzDWnj0qD5tz52PI08u9qUvSVeUBeHw==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/node-releases": {
      "version": "2.0.57",
      "resolved": "https://registry.npmjs.org/node-releases/-/node-releases-2.0.57.tgz",
      "integrity": "sha512-kQK9LGGFiHtrWiNhZtA7Qbw17AQz+dmsEKODRIVTXA9+e5MS/2gZEBhYJt13GrAz5/IOZKddH/0Z3TP/Zgo+yw==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/node-stdlib-browser": {
      "version": "1.3.1",
      "resolved": "https://registry.npmjs.org/node-stdlib-browser/-/node-stdlib-browser-1.3.1.tgz",
      "integrity": "sha512-X75ZN8DCLftGM5iKwoYLA3rjnrAEs97MkzvSd4q2746Tgpg8b8XWiBGiBG4ZpgcAqBgtgPHTiAc8ZMCvZuikDw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "assert": "^2.0.0",
        "browser-resolve": "^2.0.0",
        "browserify-zlib": "^0.2.0",
        "buffer": "^5.7.1",
        "console-browserify": "^1.1.0",
        "constants-browserify": "^1.0.0",
        "create-require": "^1.1.1",
        "crypto-browserify": "^3.12.1",
        "domain-browser": "4.22.0",
        "events": "^3.0.0",
        "https-browserify": "^1.0.0",
        "isomorphic-timers-promises": "^1.0.1",
        "os-browserify": "^0.3.0",
        "path-browserify": "^1.0.1",
        "pkg-dir": "^5.0.0",
        "process": "^0.11.10",
        "punycode": "^1.4.1",
        "querystring-es3": "^0.2.1",
        "readable-stream": "^3.6.0",
        "stream-browserify": "^3.0.0",
        "stream-http": "^3.2.0",
        "string_decoder": "^1.0.0",
        "timers-browserify": "^2.0.4",
        "tty-browserify": "0.0.1",
        "url": "^0.11.4",
        "util": "^0.12.4",
        "vm-browserify": "^1.0.1"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/node-stdlib-browser/node_modules/buffer": {
      "version": "5.7.1",
      "resolved": "https://registry.npmjs.org/buffer/-/buffer-5.7.1.tgz",
      "integrity": "sha512-EHcyIPBQ4BSGlvjB16k5KgAJ27CIsHY/2JBmCRReo48y9rQ3MaUzWX3KVlBa4U7MyX02HdVj0K7C3WaB3ju7FQ==",
      "dev": true,
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/feross"
        },
        {
          "type": "patreon",
          "url": "https://www.patreon.com/feross"
        },
        {
          "type": "consulting",
          "url": "https://feross.org/support"
        }
      ],
      "license": "MIT",
      "dependencies": {
        "base64-js": "^1.3.1",
        "ieee754": "^1.1.13"
      }
    },
    "node_modules/nullthrows": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/nullthrows/-/nullthrows-1.1.1.tgz",
      "integrity": "sha512-2vPPEi+Z7WqML2jZYddDIfy5Dqb0r2fze2zTxNNknZaFpVHU3mFB3R+DWeJWGVx0ecvttSGlJTI+WG+8Z4cDWw==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/ob1": {
      "version": "0.87.1",
      "resolved": "https://registry.npmjs.org/ob1/-/ob1-0.87.1.tgz",
      "integrity": "sha512-i8iA8uij0g1YQzS8uOJPSRCgwDjO9warIHUAu1Fqj877Wc3wlfxDYBioYWgKTBF2+URVJttyDWSEpmd99nlvtQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "flow-enums-runtime": "^0.0.6"
      },
      "engines": {
        "node": "^22.13.0 || ^24.3.0 || >= 26.0.0"
      }
    },
    "node_modules/object-inspect": {
      "version": "1.13.4",
      "resolved": "https://registry.npmjs.org/object-inspect/-/object-inspect-1.13.4.tgz",
      "integrity": "sha512-W67iLl4J2EXEGTbfeHCffrjDfitvLANg0UlX3wFUUSTx92KXRFegMHUVgSqE+wvhAbi4WqjGg9czysTV2Epbew==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/object-is": {
      "version": "1.1.6",
      "resolved": "https://registry.npmjs.org/object-is/-/object-is-1.1.6.tgz",
      "integrity": "sha512-F8cZ+KfGlSGi09lJT7/Nd6KJZ9ygtvYC0/UYYLI9nmQKLMnydpB9yvbv9K1uSkEu7FU9vYPmVwLg328tX+ot3Q==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bind": "^1.0.7",
        "define-properties": "^1.2.1"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/object-keys": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/object-keys/-/object-keys-1.1.1.tgz",
      "integrity": "sha512-NuAESUOUMrlIXOfHKzD6bpPu3tYt3xvjNdRIQ+FeT0lNb4K8WR70CaDxhuNguS2XG+GjkyMwOzsN5ZktImfhLA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/object.assign": {
      "version": "4.1.7",
      "resolved": "https://registry.npmjs.org/object.assign/-/object.assign-4.1.7.tgz",
      "integrity": "sha512-nK28WOo+QIjBkDduTINE4JkF/UJJKyf2EJxvJKfblDpyg0Q+pkOHNTL0Qwy6NP6FhE/EnzV73BxxqcJaXY9anw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bind": "^1.0.8",
        "call-bound": "^1.0.3",
        "define-properties": "^1.2.1",
        "es-object-atoms": "^1.0.0",
        "has-symbols": "^1.1.0",
        "object-keys": "^1.1.1"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/on-finished": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/on-finished/-/on-finished-2.3.0.tgz",
      "integrity": "sha512-ikqdkGAAyf/X/gPhXGvfgAytDZtDbr+bkNUJ0N9h5MI/dmdgCs3l6hoHrcUv41sRKew3jIwrp4qQDXiK99Utww==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ee-first": "1.1.1"
      },
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/open": {
      "version": "7.4.2",
      "resolved": "https://registry.npmjs.org/open/-/open-7.4.2.tgz",
      "integrity": "sha512-MVHddDVweXZF3awtlAS+6pgKLlm/JgxZ90+/NBurBoQctVOOB/zDdVjcyPzQ+0laDGbsWgrRkflI65sQeOgT9Q==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "is-docker": "^2.0.0",
        "is-wsl": "^2.1.1"
      },
      "engines": {
        "node": ">=8"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/os-browserify": {
      "version": "0.3.0",
      "resolved": "https://registry.npmjs.org/os-browserify/-/os-browserify-0.3.0.tgz",
      "integrity": "sha512-gjcpUc3clBf9+210TRaDWbf+rZZZEshZ+DlXMRCeAjp0xhTrnQsKHypIy1J3d5hKdUzj69t708EHtU8P6bUn0A==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/p-limit": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/p-limit/-/p-limit-2.3.0.tgz",
      "integrity": "sha512-//88mFWSJx8lxCzwdAABTJL2MyWB12+eIY7MDL2SqLmAkeKU9qxRvWuSyTjm3FUmpBEMuFfckAIqEaVGUDxb6w==",
      "license": "MIT",
      "dependencies": {
        "p-try": "^2.0.0"
      },
      "engines": {
        "node": ">=6"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/p-locate": {
      "version": "4.1.0",
      "resolved": "https://registry.npmjs.org/p-locate/-/p-locate-4.1.0.tgz",
      "integrity": "sha512-R79ZZ/0wAxKGu3oYMlz8jy/kbhsNrS7SKZ7PxEHBgJ5+F2mtFW2fK2cOtBh1cHYkQsbzFV7I+EoRKe6Yt0oK7A==",
      "license": "MIT",
      "dependencies": {
        "p-limit": "^2.2.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/p-try": {
      "version": "2.2.0",
      "resolved": "https://registry.npmjs.org/p-try/-/p-try-2.2.0.tgz",
      "integrity": "sha512-R4nPAVTAU0B9D35/Gk3uJf/7XYbQcyohSKdvAxIRSNghFl4e71hVoGnBNQz9cWaXxO2I10KTC+3jMdvvoKw6dQ==",
      "license": "MIT",
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/pako": {
      "version": "2.2.0",
      "resolved": "https://registry.npmjs.org/pako/-/pako-2.2.0.tgz",
      "integrity": "sha512-zJq6RP/5q+TO2OpFV3FHzlPnFjmkb7Nc99a5SNjJE+uu/PkpChs+NIZSSzbBoD+6kjiISXjfYdwj1ZRQ81dz/w==",
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/puzrin"
        },
        {
          "type": "github",
          "url": "https://github.com/sponsors/nodeca"
        }
      ],
      "license": "(MIT AND Zlib)"
    },
    "node_modules/parse-asn1": {
      "version": "5.1.9",
      "resolved": "https://registry.npmjs.org/parse-asn1/-/parse-asn1-5.1.9.tgz",
      "integrity": "sha512-fIYNuZ/HastSb80baGOuPRo1O9cf4baWw5WsAp7dBuUzeTD/BoaG8sVTdlPFksBE2lF21dN+A1AnrpIjSWqHHg==",
      "dev": true,
      "license": "ISC",
      "dependencies": {
        "asn1.js": "^4.10.1",
        "browserify-aes": "^1.2.0",
        "evp_bytestokey": "^1.0.3",
        "pbkdf2": "^3.1.5",
        "safe-buffer": "^5.2.1"
      },
      "engines": {
        "node": ">= 0.10"
      }
    },
    "node_modules/parseurl": {
      "version": "1.3.3",
      "resolved": "https://registry.npmjs.org/parseurl/-/parseurl-1.3.3.tgz",
      "integrity": "sha512-CiyeOxFT/JZyN5m0z9PfXw4SCBJ6Sygz1Dpl0wqjlhDEGGBP1GnsUVEL0p63hoG1fcj3fHynXi9NYO4nWOL+qQ==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/path-browserify": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/path-browserify/-/path-browserify-1.0.1.tgz",
      "integrity": "sha512-b7uo2UCUOYZcnF/3ID0lulOJi/bafxa1xPe7ZPsammBSpjSWQkjNxlt635YGS2MiR9GjvuXCtz2emr3jbsz98g==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/path-exists": {
      "version": "4.0.0",
      "resolved": "https://registry.npmjs.org/path-exists/-/path-exists-4.0.0.tgz",
      "integrity": "sha512-ak9Qy5Q7jYb2Wwcey5Fpvg2KoAc/ZIhLSLOSBmRmygPsGwkVVt0fZa0qrtMz+m6tJTAHfZQ8FnmB4MG4LWy7/w==",
      "license": "MIT",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/path-key": {
      "version": "3.1.1",
      "resolved": "https://registry.npmjs.org/path-key/-/path-key-3.1.1.tgz",
      "integrity": "sha512-ojmeN0qd+y0jszEtoY48r0Peq5dwMEkIlCOu6Q5f41lfkswXuKtYrhgoTpLnyIcHm24Uhqx+5Tqm2InSwLhE6Q==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/path-parse": {
      "version": "1.0.7",
      "resolved": "https://registry.npmjs.org/path-parse/-/path-parse-1.0.7.tgz",
      "integrity": "sha512-LDJzPVEEEPR+y48z93A0Ed0yXb8pAByGWo/k5YYdYgpY2/2EsOsksJrq7lOHxryrVOn1ejG6oAp8ahvOIQD8sw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/pbkdf2": {
      "version": "3.1.7",
      "resolved": "https://registry.npmjs.org/pbkdf2/-/pbkdf2-3.1.7.tgz",
      "integrity": "sha512-nS4mvFgVwUrecPTRdpdseM2fwpdfnX0/HibA8DgBRQtihUAzHQYJFU2l+OlEtiXtpqkrMvCPDwyXMUnASDt6Qw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "create-hash": "^1.2.0",
        "create-hmac": "^1.1.7",
        "ripemd160": "^2.0.3",
        "safe-buffer": "^5.2.1",
        "sha.js": "^2.4.12",
        "to-buffer": "^1.2.2"
      },
      "engines": {
        "node": ">= 0.10"
      }
    },
    "node_modules/picocolors": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/picocolors/-/picocolors-1.1.1.tgz",
      "integrity": "sha512-xceH2snhtb5M9liqDsmEw56le376mTZkEX/jEb/RxNFyegNul7eNslCXP9FDj/Lcu0X8KEyMceP2ntpaHrDEVA==",
      "license": "ISC"
    },
    "node_modules/picomatch": {
      "version": "2.3.2",
      "resolved": "https://registry.npmjs.org/picomatch/-/picomatch-2.3.2.tgz",
      "integrity": "sha512-V7+vQEJ06Z+c5tSye8S+nHUfI51xoXIXjHQ99cQtKUkQqqO1kO/KCJUfZXuB47h/YBlDhah2H3hdUGXn8ie0oA==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=8.6"
      },
      "funding": {
        "url": "https://github.com/sponsors/jonschlinkert"
      }
    },
    "node_modules/pkg-dir": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/pkg-dir/-/pkg-dir-5.0.0.tgz",
      "integrity": "sha512-NPE8TDbzl/3YQYY7CSS228s3g2ollTFnc+Qi3tqmqJp9Vg2ovUpixcJEo2HJScN2Ez+kEaal6y70c0ehqJBJeA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "find-up": "^5.0.0"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/pkg-dir/node_modules/find-up": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/find-up/-/find-up-5.0.0.tgz",
      "integrity": "sha512-78/PXT1wlLLDgTzDs7sjq9hzz0vXD+zn+7wypEe4fXQxCmdmqfGsEPQxmiCSQI3ajFV91bVSsvNtrJRiW6nGng==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "locate-path": "^6.0.0",
        "path-exists": "^4.0.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/pkg-dir/node_modules/locate-path": {
      "version": "6.0.0",
      "resolved": "https://registry.npmjs.org/locate-path/-/locate-path-6.0.0.tgz",
      "integrity": "sha512-iPZK6eYjbxRu3uB4/WZ3EsEIMJFMqAoopl3R+zuq0UjcAm/MO6KCweDgPfP3elTztoKP3KtnVHxTn2NHBSDVUw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "p-locate": "^5.0.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/pkg-dir/node_modules/p-limit": {
      "version": "3.1.0",
      "resolved": "https://registry.npmjs.org/p-limit/-/p-limit-3.1.0.tgz",
      "integrity": "sha512-TYOanM3wGwNGsZN2cVTYPArw454xnXj5qmWF1bEoAc4+cU/ol7GVh7odevjp1FNHduHc3KZMcFduxU5Xc6uJRQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "yocto-queue": "^0.1.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/pkg-dir/node_modules/p-locate": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/p-locate/-/p-locate-5.0.0.tgz",
      "integrity": "sha512-LaNjtRWUBY++zB5nE/NwcaoMylSPk+S+ZHNB1TzdbMJMny6dynpAGt7X/tl/QYq3TIeE6nxHppbo2LGymrG5Pw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "p-limit": "^3.0.2"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/playwright-core": {
      "version": "1.63.0",
      "resolved": "https://registry.npmjs.org/playwright-core/-/playwright-core-1.63.0.tgz",
      "integrity": "sha512-rYCsBF/M5HjUch52bbtVONEFjv6Xu8sm8h72dNlR5bzIE1fvC/bxgspzkjSfU+MweEMmPM8KJebG6nnyxo5mCg==",
      "dev": true,
      "license": "Apache-2.0",
      "bin": {
        "playwright-core": "cli.js"
      },
      "engines": {
        "node": ">=20"
      }
    },
    "node_modules/pngjs": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/pngjs/-/pngjs-5.0.0.tgz",
      "integrity": "sha512-40QW5YalBNfQo5yRYmiw7Yz6TKKVr3h6970B2YE+3fQpsWcrbj1PzJgxeJ19DRQjhMbKPIuMY8rFaXc8moolVw==",
      "license": "MIT",
      "engines": {
        "node": ">=10.13.0"
      }
    },
    "node_modules/possible-typed-array-names": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/possible-typed-array-names/-/possible-typed-array-names-1.1.0.tgz",
      "integrity": "sha512-/+5VFTchJDoVj3bhoqi6UeymcD00DAwb1nJwamzPvHEszJ4FpF6SNNbUbOS8yI56qHzdV8eK0qEfOSiodkTdxg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/postcss": {
      "version": "8.5.28",
      "resolved": "https://registry.npmjs.org/postcss/-/postcss-8.5.28.tgz",
      "integrity": "sha512-RRuzqDtt5Y9h3quz5hWhK+TPnsmVs6WwSU6LkJMeY4HstUEDuYTG8UJSdawMRzmzAtV+KEoG8N3Qg2qLy5vM/A==",
      "dev": true,
      "funding": [
        {
          "type": "opencollective",
          "url": "https://opencollective.com/postcss/"
        },
        {
          "type": "tidelift",
          "url": "https://tidelift.com/funding/github/npm/postcss"
        },
        {
          "type": "github",
          "url": "https://github.com/sponsors/ai"
        }
      ],
      "license": "MIT",
      "dependencies": {
        "nanoid": "^3.3.18",
        "picocolors": "^1.1.1",
        "source-map-js": "^1.2.1"
      },
      "engines": {
        "node": "^10 || ^12 || >=14"
      }
    },
    "node_modules/pretty-format": {
      "version": "29.7.0",
      "resolved": "https://registry.npmjs.org/pretty-format/-/pretty-format-29.7.0.tgz",
      "integrity": "sha512-Pdlw/oPxN+aXdmM9R00JVC9WVFoCLTKJvDVLgmJ+qAffBMxsV85l/Lu7sNx4zSzPyoL2euImuEwHhOXdEgNFZQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@jest/schemas": "^29.6.3",
        "ansi-styles": "^5.0.0",
        "react-is": "^18.0.0"
      },
      "engines": {
        "node": "^14.15.0 || ^16.10.0 || >=18.0.0"
      }
    },
    "node_modules/pretty-format/node_modules/ansi-styles": {
      "version": "5.2.0",
      "resolved": "https://registry.npmjs.org/ansi-styles/-/ansi-styles-5.2.0.tgz",
      "integrity": "sha512-Cxwpt2SfTzTtXcfOlzGEee8O+c+MmUgGrNiBcXnuWxuFJHe6a5Hz7qwhwe5OgaSYI0IJvkLqWX1ASG+cJOkEiA==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/chalk/ansi-styles?sponsor=1"
      }
    },
    "node_modules/process": {
      "version": "0.11.10",
      "resolved": "https://registry.npmjs.org/process/-/process-0.11.10.tgz",
      "integrity": "sha512-cdGef/drWFoydD1JsMzuFf8100nZl+GT+yacc2bEced5f9Rjk4z+WtFUTBu9PhOi9j/jfmBPu0mMEY4wIdAF8A==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.6.0"
      }
    },
    "node_modules/process-nextick-args": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/process-nextick-args/-/process-nextick-args-2.0.1.tgz",
      "integrity": "sha512-3ouUOpQhtgrbOa17J7+uxOTpITYWaGP7/AhoR3+A+/1e9skrzelGi/dXzEYyvbxubEF6Wn2ypscTKiKJFFn1ag==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/promise": {
      "version": "8.3.0",
      "resolved": "https://registry.npmjs.org/promise/-/promise-8.3.0.tgz",
      "integrity": "sha512-rZPNPKTOYVNEEKFaq1HqTgOwZD+4/YHS5ukLzQCypkj+OkYx7iv0mA91lJlpPPZ8vMau3IIGj5Qlwrx+8iiSmg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "asap": "~2.0.6"
      }
    },
    "node_modules/public-encrypt": {
      "version": "4.0.3",
      "resolved": "https://registry.npmjs.org/public-encrypt/-/public-encrypt-4.0.3.tgz",
      "integrity": "sha512-zVpa8oKZSz5bTMTFClc1fQOnyyEzpl5ozpi1B5YcvBrdohMjH2rfsBtyXcuNuwjsDIXmBYlF2N5FlJYhR29t8Q==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "bn.js": "^4.1.0",
        "browserify-rsa": "^4.0.0",
        "create-hash": "^1.1.0",
        "parse-asn1": "^5.0.0",
        "randombytes": "^2.0.1",
        "safe-buffer": "^5.1.2"
      }
    },
    "node_modules/public-encrypt/node_modules/bn.js": {
      "version": "4.12.5",
      "resolved": "https://registry.npmjs.org/bn.js/-/bn.js-4.12.5.tgz",
      "integrity": "sha512-3aRg6/JxfffFD+OlOjOFR3Vo79l39ooBTFucxx+MT3dhCtzn3EmiUPQo+6/OZuI2jbXi3YKgmiTFBgChQMwIRQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/punycode": {
      "version": "1.4.1",
      "resolved": "https://registry.npmjs.org/punycode/-/punycode-1.4.1.tgz",
      "integrity": "sha512-jmYNElW7yvO7TV33CjSmvSiE2yco3bV2czu/OzDKdMNVZQWfxCblURLhf+47syQRBntjfLdd/H0egrzIG+oaFQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/qrcode": {
      "version": "1.5.4",
      "resolved": "https://registry.npmjs.org/qrcode/-/qrcode-1.5.4.tgz",
      "integrity": "sha512-1ca71Zgiu6ORjHqFBDpnSMTR2ReToX4l1Au1VFLyVeBTFavzQnv5JxMFr3ukHVKpSrSA2MCk0lNJSykjUfz7Zg==",
      "license": "MIT",
      "dependencies": {
        "dijkstrajs": "^1.0.1",
        "pngjs": "^5.0.0",
        "yargs": "^15.3.1"
      },
      "bin": {
        "qrcode": "bin/qrcode"
      },
      "engines": {
        "node": ">=10.13.0"
      }
    },
    "node_modules/qs": {
      "version": "6.16.0",
      "resolved": "https://registry.npmjs.org/qs/-/qs-6.16.0.tgz",
      "integrity": "sha512-h6fhOIaRrID2CbEY2fqs+7t+UXZo+MLAnU5gRIq85uFtdiUPCdsApMlHhXogKVM4HM2DVbIjGNTTYH2OcmP1vA==",
      "dev": true,
      "license": "BSD-3-Clause",
      "dependencies": {
        "es-define-property": "^1.0.1",
        "side-channel": "^1.1.1"
      },
      "engines": {
        "node": ">=0.6"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/querystring-es3": {
      "version": "0.2.1",
      "resolved": "https://registry.npmjs.org/querystring-es3/-/querystring-es3-0.2.1.tgz",
      "integrity": "sha512-773xhDQnZBMFobEiztv8LIl70ch5MSF/jUQVlhwFyBILqq96anmoctVIYz+ZRp0qbCKATTn6ev02M3r7Ga5vqA==",
      "dev": true,
      "engines": {
        "node": ">=0.4.x"
      }
    },
    "node_modules/randombytes": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/randombytes/-/randombytes-2.1.0.tgz",
      "integrity": "sha512-vYl3iOX+4CKUWuxGi9Ukhie6fsqXqS9FE2Zaic4tNFD2N2QQaXOMFbuKK4QmDHC0JO6B1Zp41J0LpT0oR68amQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "^5.1.0"
      }
    },
    "node_modules/randomfill": {
      "version": "1.0.4",
      "resolved": "https://registry.npmjs.org/randomfill/-/randomfill-1.0.4.tgz",
      "integrity": "sha512-87lcbR8+MhcWcUiQ+9e+Rwx8MyR2P7qnt15ynUlbm3TU/fjbgz4GsvfSUDTemtCCtVCqb4ZcEFlyPNTh9bBTLw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "randombytes": "^2.0.5",
        "safe-buffer": "^5.1.0"
      }
    },
    "node_modules/range-parser": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/range-parser/-/range-parser-1.2.1.tgz",
      "integrity": "sha512-Hrgsx+orqoygnmhFbKaHE6c296J+HTAQXoxEF6gNupROmmGJRoyzfG3ccAveqCBrwr/2yxQ5BVd/GTl5agOwSg==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/react": {
      "version": "18.3.1",
      "resolved": "https://registry.npmjs.org/react/-/react-18.3.1.tgz",
      "integrity": "sha512-wS+hAgJShR0KhEvPJArfuPVN1+Hz1t0Y6n5jLrGQbkb4urgPE/0Rve+1kMB1v/oWgHgm4WIcV+i7F2pTVj+2iQ==",
      "license": "MIT",
      "dependencies": {
        "loose-envify": "^1.1.0"
      },
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/react-devtools-core": {
      "version": "6.1.5",
      "resolved": "https://registry.npmjs.org/react-devtools-core/-/react-devtools-core-6.1.5.tgz",
      "integrity": "sha512-ePrwPfxAnB+7hgnEr8vpKxL9cmnp7F322t8oqcPshbIQQhDKgFDW4tjhF2wjVbdXF9O/nyuy3sQWd9JGpiLPvA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "shell-quote": "^1.6.1",
        "ws": "^7"
      }
    },
    "node_modules/react-dom": {
      "version": "18.3.1",
      "resolved": "https://registry.npmjs.org/react-dom/-/react-dom-18.3.1.tgz",
      "integrity": "sha512-5m4nQKp+rZRb09LNH59GM4BxTh9251/ylbKIbpe7TpGxfJ+9kv6BLkLBXIjjspbgbnIBNqlI23tRnTWT0snUIw==",
      "license": "MIT",
      "dependencies": {
        "loose-envify": "^1.1.0",
        "scheduler": "^0.23.2"
      },
      "peerDependencies": {
        "react": "^18.3.1"
      }
    },
    "node_modules/react-is": {
      "version": "18.3.1",
      "resolved": "https://registry.npmjs.org/react-is/-/react-is-18.3.1.tgz",
      "integrity": "sha512-/LLMVyas0ljjAtoYiPqYiL8VWXzUUdThrmU5+n20DZv+a+ClRoevUzw5JxU+Ieh5/c87ytoTBV9G1FiKfNJdmg==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/react-refresh": {
      "version": "0.14.2",
      "resolved": "https://registry.npmjs.org/react-refresh/-/react-refresh-0.14.2.tgz",
      "integrity": "sha512-jCvmsr+1IUSMUyzOkRcvnVbX3ZYC6g9TDrDbFuFmRDq7PD4yaGbLKNQL6k2jnArV8hjYxh7hVhAZB6s9HDGpZA==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/readable-stream": {
      "version": "3.6.2",
      "resolved": "https://registry.npmjs.org/readable-stream/-/readable-stream-3.6.2.tgz",
      "integrity": "sha512-9u/sniCrY3D5WdsERHzHE4G2YCXqoG5FTHUiCC4SIbr6XcLZBY05ya9EKjYek9O5xOAwjGq+1JdGBAS7Q9ScoA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "inherits": "^2.0.3",
        "string_decoder": "^1.1.1",
        "util-deprecate": "^1.0.1"
      },
      "engines": {
        "node": ">= 6"
      }
    },
    "node_modules/regenerator-runtime": {
      "version": "0.13.11",
      "resolved": "https://registry.npmjs.org/regenerator-runtime/-/regenerator-runtime-0.13.11.tgz",
      "integrity": "sha512-kY1AZVr2Ra+t+piVaJ4gxaFaReZVH40AKNo7UCX6W+dEwBo/2oZJzqfuN1qLq1oL45o56cPaTXELwrTh8Fpggg==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/require-directory": {
      "version": "2.1.1",
      "resolved": "https://registry.npmjs.org/require-directory/-/require-directory-2.1.1.tgz",
      "integrity": "sha512-fGxEI7+wsG9xrvdjsrlmL22OMTTiHRwAMroiEeMgq8gzoLC/PQr7RsRDSTLUg/bZAZtF+TVIkHc6/4RIKrui+Q==",
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/require-main-filename": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/require-main-filename/-/require-main-filename-2.0.0.tgz",
      "integrity": "sha512-NKN5kMDylKuldxYLSUfrbo5Tuzh4hd+2E8NPPX02mZtn1VuREQToYe/ZdlJy+J3uCpfaiGF05e7B8W0iXbQHmg==",
      "license": "ISC"
    },
    "node_modules/resolve": {
      "version": "1.22.12",
      "resolved": "https://registry.npmjs.org/resolve/-/resolve-1.22.12.tgz",
      "integrity": "sha512-TyeJ1zif53BPfHootBGwPRYT1RUt6oGWsaQr8UyZW/eAm9bKoijtvruSDEmZHm92CwS9nj7/fWttqPCgzep8CA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0",
        "is-core-module": "^2.16.1",
        "path-parse": "^1.0.7",
        "supports-preserve-symlinks-flag": "^1.0.0"
      },
      "bin": {
        "resolve": "bin/resolve"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/ripemd160": {
      "version": "2.0.3",
      "resolved": "https://registry.npmjs.org/ripemd160/-/ripemd160-2.0.3.tgz",
      "integrity": "sha512-5Di9UC0+8h1L6ZD2d7awM7E/T4uA1fJRlx6zk/NvdCCVEoAnFqvHmCuNeIKoCeIixBX/q8uM+6ycDvF8woqosA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "hash-base": "^3.1.2",
        "inherits": "^2.0.4"
      },
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/ripemd160/node_modules/hash-base": {
      "version": "3.1.2",
      "resolved": "https://registry.npmjs.org/hash-base/-/hash-base-3.1.2.tgz",
      "integrity": "sha512-Bb33KbowVTIj5s7Ked1OsqHUeCpz//tPwR+E2zJgJKo9Z5XolZ9b6bdUgjmYlwnWhoOQKoTd1TYToZGn5mAYOg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "inherits": "^2.0.4",
        "readable-stream": "^2.3.8",
        "safe-buffer": "^5.2.1",
        "to-buffer": "^1.2.1"
      },
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/ripemd160/node_modules/isarray": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/isarray/-/isarray-1.0.0.tgz",
      "integrity": "sha512-VLghIWNM6ELQzo7zwmcg0NmTVyWKYjvIeM83yjp0wRDTmUnrM678fQbcKBo6n2CJEF0szoG//ytg+TKla89ALQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/ripemd160/node_modules/readable-stream": {
      "version": "2.3.8",
      "resolved": "https://registry.npmjs.org/readable-stream/-/readable-stream-2.3.8.tgz",
      "integrity": "sha512-8p0AUk4XODgIewSi0l8Epjs+EVnWiK7NoDIEGU0HhE7+ZyY8D1IMY7odu5lRrFXGg71L15KG8QrPmum45RTtdA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "core-util-is": "~1.0.0",
        "inherits": "~2.0.3",
        "isarray": "~1.0.0",
        "process-nextick-args": "~2.0.0",
        "safe-buffer": "~5.1.1",
        "string_decoder": "~1.1.1",
        "util-deprecate": "~1.0.1"
      }
    },
    "node_modules/ripemd160/node_modules/readable-stream/node_modules/safe-buffer": {
      "version": "5.1.2",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.1.2.tgz",
      "integrity": "sha512-Gd2UZBJDkXlY7GbJxfsE8/nvKkUEU1G38c1siN6QP6a9PT9MmHB8GnpscSmMJSoF8LOIrt8ud/wPtojys4G6+g==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/ripemd160/node_modules/string_decoder": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/string_decoder/-/string_decoder-1.1.1.tgz",
      "integrity": "sha512-n/ShnvDi6FHbbVfviro+WojiFzv+s8MPMHBczVePfUpDJLwoLT0ht1l4YwBCbi8pJAveEEdnkHyPyTP/mzRfwg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "~5.1.0"
      }
    },
    "node_modules/ripemd160/node_modules/string_decoder/node_modules/safe-buffer": {
      "version": "5.1.2",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.1.2.tgz",
      "integrity": "sha512-Gd2UZBJDkXlY7GbJxfsE8/nvKkUEU1G38c1siN6QP6a9PT9MmHB8GnpscSmMJSoF8LOIrt8ud/wPtojys4G6+g==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/rolldown": {
      "version": "1.2.12",
      "resolved": "https://registry.npmjs.org/rolldown/-/rolldown-1.2.12.tgz",
      "integrity": "sha512-8wafseiaG80xmXSfqidUNqZcylTlhmPZZt+za2m+js2sFZ8dTNlhIOV2WcbIPx2hgwPBJpEUGFAMZ9bgBBLTSQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@oxc-project/types": "=0.152.0",
        "@rolldown/pluginutils": "^1.0.0"
      },
      "bin": {
        "rolldown": "bin/cli.mjs"
      },
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      },
      "optionalDependencies": {
        "@rolldown/binding-android-arm-eabi": "1.2.12",
        "@rolldown/binding-android-arm64": "1.2.12",
        "@rolldown/binding-darwin-arm64": "1.2.12",
        "@rolldown/binding-darwin-x64": "1.2.12",
        "@rolldown/binding-freebsd-x64": "1.2.12",
        "@rolldown/binding-linux-arm-gnueabihf": "1.2.12",
        "@rolldown/binding-linux-arm64-gnu": "1.2.12",
        "@rolldown/binding-linux-arm64-musl": "1.2.12",
        "@rolldown/binding-linux-ppc64-gnu": "1.2.12",
        "@rolldown/binding-linux-s390x-gnu": "1.2.12",
        "@rolldown/binding-linux-x64-gnu": "1.2.12",
        "@rolldown/binding-linux-x64-musl": "1.2.12",
        "@rolldown/binding-openharmony-arm64": "1.2.12",
        "@rolldown/binding-win32-arm64-msvc": "1.2.12",
        "@rolldown/binding-win32-x64-msvc": "1.2.12"
      }
    },
    "node_modules/rpc-websockets": {
      "version": "9.3.9",
      "resolved": "https://registry.npmjs.org/rpc-websockets/-/rpc-websockets-9.3.9.tgz",
      "integrity": "sha512-2iQDaTB4g5fDB2ihrTFSJSibCEuxaRi1q7qTW7ZO9/M5/TC+ToHA4D9/ffNLEbAoHNNrcdeP05oATNk44SKZXA==",
      "license": "LGPL-3.0-only",
      "dependencies": {
        "@swc/helpers": "^0.5.11",
        "@types/uuid": "^10.0.0",
        "@types/ws": "^8.2.2",
        "buffer": "^6.0.3",
        "eventemitter3": "^5.0.1",
        "uuid": "^14.0.0",
        "ws": "^8.5.0"
      },
      "funding": {
        "type": "paypal",
        "url": "https://paypal.me/kozjak"
      },
      "optionalDependencies": {
        "bufferutil": "^4.0.1",
        "utf-8-validate": "^6.0.0"
      }
    },
    "node_modules/rpc-websockets/node_modules/@types/ws": {
      "version": "8.18.2",
      "resolved": "https://registry.npmjs.org/@types/ws/-/ws-8.18.2.tgz",
      "integrity": "sha512-67MQl+fpWKVTT1NYdnmo3U4sc/xPo/zQBncVnI74qmQa0z/b+1g6iYqNmGCPbxO+zz2aklb08a0oHfegiVd0/w==",
      "license": "MIT",
      "dependencies": {
        "@types/node": "*"
      }
    },
    "node_modules/rpc-websockets/node_modules/eventemitter3": {
      "version": "5.0.4",
      "resolved": "https://registry.npmjs.org/eventemitter3/-/eventemitter3-5.0.4.tgz",
      "integrity": "sha512-mlsTRyGaPBjPedk6Bvw+aqbsXDtoAyAzm5MO7JgU+yVRyMQ5O8bD4Kcci7BS85f93veegeCPkL8R4GLClnjLFw==",
      "license": "MIT"
    },
    "node_modules/rpc-websockets/node_modules/utf-8-validate": {
      "version": "6.0.6",
      "resolved": "https://registry.npmjs.org/utf-8-validate/-/utf-8-validate-6.0.6.tgz",
      "integrity": "sha512-q3l3P9UtEEiAHcsgsqTgf9PPjctrDWoIXW3NpOHFdRDbLvu4DLIcxHangJ4RLrWkBcKjmcs/6NkerI8T/rE4LA==",
      "hasInstallScript": true,
      "license": "MIT",
      "optional": true,
      "dependencies": {
        "node-gyp-build": "^4.3.0"
      },
      "engines": {
        "node": ">=6.14.2"
      }
    },
    "node_modules/rpc-websockets/node_modules/uuid": {
      "version": "14.0.2",
      "resolved": "https://registry.npmjs.org/uuid/-/uuid-14.0.2.tgz",
      "integrity": "sha512-xZe/16rV4aa+HGSOCiY2YeLT1OybRLrrkL/Rqaq7p7GMVXjFh+6wN4oMYgjFmnSnhY8t6Xpdl2l9qmnHYuMHwQ==",
      "funding": [
        "https://github.com/sponsors/broofa",
        "https://github.com/sponsors/ctavan"
      ],
      "license": "MIT",
      "bin": {
        "uuid": "dist-node/bin/uuid"
      }
    },
    "node_modules/rpc-websockets/node_modules/ws": {
      "version": "8.22.0",
      "resolved": "https://registry.npmjs.org/ws/-/ws-8.22.0.tgz",
      "integrity": "sha512-Ydggc987+RO0AnWtZ/7Wq9FtNvcrL1b/RO0ud9mWjUPgDrsAAwQSF51sm2hm1XofbU/4jkpGEsLFsZZxU+1DOg==",
      "license": "MIT",
      "engines": {
        "node": ">=10.0.0"
      },
      "peerDependencies": {
        "bufferutil": "^4.0.1",
        "utf-8-validate": ">=5.0.2"
      },
      "peerDependenciesMeta": {
        "bufferutil": {
          "optional": true
        },
        "utf-8-validate": {
          "optional": true
        }
      }
    },
    "node_modules/safe-buffer": {
      "version": "5.2.1",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.2.1.tgz",
      "integrity": "sha512-rp3So07KcdmmKbGvgaNxQSJr7bGVSVk5S9Eq1F+ppbRo70+YeaDxkw5Dd8NPN+GD6bjnYm2VuPuCXmpuYvmCXQ==",
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/feross"
        },
        {
          "type": "patreon",
          "url": "https://www.patreon.com/feross"
        },
        {
          "type": "consulting",
          "url": "https://feross.org/support"
        }
      ],
      "license": "MIT"
    },
    "node_modules/safe-regex-test": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/safe-regex-test/-/safe-regex-test-1.1.0.tgz",
      "integrity": "sha512-x/+Cz4YrimQxQccJf5mKEbIa1NzeCRNI5Ecl/ekmlYaampdNLPalVyIcCZNNH3MvmqBugV5TMYZXv0ljslUlaw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bound": "^1.0.2",
        "es-errors": "^1.3.0",
        "is-regex": "^1.2.1"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/scheduler": {
      "version": "0.23.2",
      "resolved": "https://registry.npmjs.org/scheduler/-/scheduler-0.23.2.tgz",
      "integrity": "sha512-UOShsPwz7NrMUqhR6t0hWjFduvOzbtv7toDH1/hIrfRNIDBnnBWd0CwJTGvTpngVlmwGCdP9/Zl/tVrDqcuYzQ==",
      "license": "MIT",
      "dependencies": {
        "loose-envify": "^1.1.0"
      }
    },
    "node_modules/semver": {
      "version": "7.8.5",
      "resolved": "https://registry.npmjs.org/semver/-/semver-7.8.5.tgz",
      "integrity": "sha512-Y7/KDsb8LjooZpwaqGyulO6DQlksgCncchHGk+sZIY4SBvUocMBEFH5Ur1fI4dV+Jvl0w6cjvucaIi40puRioA==",
      "license": "ISC",
      "peer": true,
      "bin": {
        "semver": "bin/semver.js"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/send": {
      "version": "0.19.2",
      "resolved": "https://registry.npmjs.org/send/-/send-0.19.2.tgz",
      "integrity": "sha512-VMbMxbDeehAxpOtWJXlcUS5E8iXh6QmN+BkRX1GARS3wRaXEEgzCcB10gTQazO42tpNIya8xIyNx8fll1OFPrg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "debug": "2.6.9",
        "depd": "2.0.0",
        "destroy": "1.2.0",
        "encodeurl": "~2.0.0",
        "escape-html": "~1.0.3",
        "etag": "~1.8.1",
        "fresh": "~0.5.2",
        "http-errors": "~2.0.1",
        "mime": "1.6.0",
        "ms": "2.1.3",
        "on-finished": "~2.4.1",
        "range-parser": "~1.2.1",
        "statuses": "~2.0.2"
      },
      "engines": {
        "node": ">= 0.8.0"
      }
    },
    "node_modules/send/node_modules/debug": {
      "version": "2.6.9",
      "resolved": "https://registry.npmjs.org/debug/-/debug-2.6.9.tgz",
      "integrity": "sha512-bC7ElrdJaJnPbAP+1EotYvqZsb3ecl5wi6Bfi6BJTUcNowp6cvspg0jXznRTKDjm/E7AdgFBVeAPVMNcKGsHMA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ms": "2.0.0"
      }
    },
    "node_modules/send/node_modules/debug/node_modules/ms": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/ms/-/ms-2.0.0.tgz",
      "integrity": "sha512-Tpp60P6IUJDTuOq/5Z8cdskzJujfwqfOTkrwIwj7IRISpnkJnT6SyJ4PCPnGMoFjC9ddhal5KVIYtAt97ix05A==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/send/node_modules/encodeurl": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/encodeurl/-/encodeurl-2.0.0.tgz",
      "integrity": "sha512-Q0n9HRi4m6JuGIV1eFlmvJB7ZEVxu93IrMyiMsGC0lrMJMWzRgx6WGquyfQgZVb31vhGgXnfmPNNXmxnOkRBrg==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/send/node_modules/on-finished": {
      "version": "2.4.1",
      "resolved": "https://registry.npmjs.org/on-finished/-/on-finished-2.4.1.tgz",
      "integrity": "sha512-oVlzkg3ENAhCk2zdv7IJwd/QUD4z2RxRwpkcGY8psCVcCYZNq4wYnVWALHM+brtuJjePWiYF/ClmuDr8Ch5+kg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ee-first": "1.1.1"
      },
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/send/node_modules/statuses": {
      "version": "2.0.2",
      "resolved": "https://registry.npmjs.org/statuses/-/statuses-2.0.2.tgz",
      "integrity": "sha512-DvEy55V3DB7uknRo+4iOGT5fP1slR8wQohVdknigZPMpMstaKJQWhwiYBACJE3Ul2pTnATihhBYnRhZQHGBiRw==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/serialize-error": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/serialize-error/-/serialize-error-2.1.0.tgz",
      "integrity": "sha512-ghgmKt5o4Tly5yEG/UJp8qTd0AN7Xalw4XBtDEKP655B699qMEtra1WlXeE6WIvdEG481JvRxULKsInq/iNysw==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/serve-static": {
      "version": "1.16.3",
      "resolved": "https://registry.npmjs.org/serve-static/-/serve-static-1.16.3.tgz",
      "integrity": "sha512-x0RTqQel6g5SY7Lg6ZreMmsOzncHFU7nhnRWkKgWuMTu5NN0DR5oruckMqRvacAN9d5w6ARnRBXl9xhDCgfMeA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "encodeurl": "~2.0.0",
        "escape-html": "~1.0.3",
        "parseurl": "~1.3.3",
        "send": "~0.19.1"
      },
      "engines": {
        "node": ">= 0.8.0"
      }
    },
    "node_modules/serve-static/node_modules/encodeurl": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/encodeurl/-/encodeurl-2.0.0.tgz",
      "integrity": "sha512-Q0n9HRi4m6JuGIV1eFlmvJB7ZEVxu93IrMyiMsGC0lrMJMWzRgx6WGquyfQgZVb31vhGgXnfmPNNXmxnOkRBrg==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/set-blocking": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/set-blocking/-/set-blocking-2.0.0.tgz",
      "integrity": "sha512-KiKBS8AnWGEyLzofFfmvKwpdPzqiy16LvQfK3yv/fVH7Bj13/wl3JSR1J+rfgRE9q7xUJK4qvgS8raSOeLUehw==",
      "license": "ISC"
    },
    "node_modules/set-function-length": {
      "version": "1.2.2",
      "resolved": "https://registry.npmjs.org/set-function-length/-/set-function-length-1.2.2.tgz",
      "integrity": "sha512-pgRc4hJ4/sNjWCSS9AmnS40x3bNMDTknHgL5UaMBTMyJnU90EgWh1Rz+MC9eFu4BuN/UwZjKQuY/1v3rM7HMfg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "define-data-property": "^1.1.4",
        "es-errors": "^1.3.0",
        "function-bind": "^1.1.2",
        "get-intrinsic": "^1.2.4",
        "gopd": "^1.0.1",
        "has-property-descriptors": "^1.0.2"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/setimmediate": {
      "version": "1.0.5",
      "resolved": "https://registry.npmjs.org/setimmediate/-/setimmediate-1.0.5.tgz",
      "integrity": "sha512-MATJdZp8sLqDl/68LfQmbP8zKPLQNV6BIZoIgrscFDQ+RsvK/BxeDQOgyxKKoh0y/8h3BqVFnCqQ/gd+reiIXA==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/setprototypeof": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/setprototypeof/-/setprototypeof-1.2.0.tgz",
      "integrity": "sha512-E5LDX7Wrp85Kil5bhZv46j8jOeboKq5JMmYM3gVGdGH8xFpPWXUMsNrlODCrkoxMEeNi/XZIwuRvY4XNwYMJpw==",
      "license": "ISC",
      "peer": true
    },
    "node_modules/sha.js": {
      "version": "2.4.12",
      "resolved": "https://registry.npmjs.org/sha.js/-/sha.js-2.4.12.tgz",
      "integrity": "sha512-8LzC5+bvI45BjpfXU8V5fdU2mfeKiQe1D1gIMn7XUlF3OTUrpdJpPPH4EMAnF0DsHHdSZqCdSss5qCmJKuiO3w==",
      "dev": true,
      "license": "(MIT AND BSD-3-Clause)",
      "dependencies": {
        "inherits": "^2.0.4",
        "safe-buffer": "^5.2.1",
        "to-buffer": "^1.2.0"
      },
      "bin": {
        "sha.js": "bin.js"
      },
      "engines": {
        "node": ">= 0.10"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/shebang-command": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/shebang-command/-/shebang-command-2.0.0.tgz",
      "integrity": "sha512-kHxr2zZpYtdmrN1qDjrrX/Z1rR1kG8Dx+gkpK1G4eXmvXswmcE1hTWBWYUzlraYw1/yZp6YuDY77YtvbN0dmDA==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "shebang-regex": "^3.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/shebang-regex": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/shebang-regex/-/shebang-regex-3.0.0.tgz",
      "integrity": "sha512-7++dFhtcx3353uBaq8DDR4NuxBetBzC7ZQOhmTQInHEd6bSrXdiEyzCvG07Z44UYdLShWUyXt5M/yhz8ekcb1A==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/shell-quote": {
      "version": "1.12.0",
      "resolved": "https://registry.npmjs.org/shell-quote/-/shell-quote-1.12.0.tgz",
      "integrity": "sha512-PcByqNyT/38F2kDNi006HAMRJaULuBzq/FOsw3qdZvX/GA9W/jamDaRskgHjubHiftXK5sIFxLNkvrXUwcof6Q==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/side-channel": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/side-channel/-/side-channel-1.1.1.tgz",
      "integrity": "sha512-6x6dK6zJdpTzF4sQeNYxwtvBzf6Eg4GtlesS94HOvTudUeyK2WXAaIfmDgsyslYrRBeFIlsi54AYsFGUuhmvrQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0",
        "object-inspect": "^1.13.4",
        "side-channel-list": "^1.0.1",
        "side-channel-map": "^1.0.1",
        "side-channel-weakmap": "^1.0.2"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/side-channel-list": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/side-channel-list/-/side-channel-list-1.0.1.tgz",
      "integrity": "sha512-mjn/0bi/oUURjc5Xl7IaWi/OJJJumuoJFQJfDDyO46+hBWsfaVM65TBHq2eoZBhzl9EchxOijpkbRC8SVBQU0w==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0",
        "object-inspect": "^1.13.4"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/side-channel-map": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/side-channel-map/-/side-channel-map-1.0.1.tgz",
      "integrity": "sha512-VCjCNfgMsby3tTdo02nbjtM/ewra6jPHmpThenkTYh8pG9ucZ/1P8So4u4FGBek/BjpOVsDCMoLA/iuBKIFXRA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bound": "^1.0.2",
        "es-errors": "^1.3.0",
        "get-intrinsic": "^1.2.5",
        "object-inspect": "^1.13.3"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/side-channel-weakmap": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/side-channel-weakmap/-/side-channel-weakmap-1.0.2.tgz",
      "integrity": "sha512-WPS/HvHQTYnHisLo9McqBHOJk2FkHO/tlpvldyrnem4aeQp4hai3gythswg6p01oSoTl58rcpiFAjF2br2Ak2A==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bound": "^1.0.2",
        "es-errors": "^1.3.0",
        "get-intrinsic": "^1.2.5",
        "object-inspect": "^1.13.3",
        "side-channel-map": "^1.0.1"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/source-map": {
      "version": "0.5.7",
      "resolved": "https://registry.npmjs.org/source-map/-/source-map-0.5.7.tgz",
      "integrity": "sha512-LbrmJOMUSdEVxIKvdcJzQC+nQhe8FUZQTXQy6+I75skNgn3OoQ0DZA8YnFa7gp8tqtL3KPf1kmo0R5DoApeSGQ==",
      "license": "BSD-3-Clause",
      "peer": true,
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/source-map-js": {
      "version": "1.2.2",
      "resolved": "https://registry.npmjs.org/source-map-js/-/source-map-js-1.2.2.tgz",
      "integrity": "sha512-KGj/8Y43x35aZVDtt+J4mK1hoLGHULMYfSkODJNQjNDC3oW1PqPoxMwo0pLUsWM/UEGzON/NxeHywEfNXNP3Vw==",
      "dev": true,
      "license": "BSD-3-Clause",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/source-map-support": {
      "version": "0.5.21",
      "resolved": "https://registry.npmjs.org/source-map-support/-/source-map-support-0.5.21.tgz",
      "integrity": "sha512-uBHU3L3czsIyYXKX88fdrGovxdSCoTGDRZ6SYXtSRxLZUzHg5P/66Ht6uoUlHu9EZod+inXhKo3qQgwXUT/y1w==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "buffer-from": "^1.0.0",
        "source-map": "^0.6.0"
      }
    },
    "node_modules/source-map-support/node_modules/source-map": {
      "version": "0.6.1",
      "resolved": "https://registry.npmjs.org/source-map/-/source-map-0.6.1.tgz",
      "integrity": "sha512-UjgapumWlbMhkBgzT7Ykc5YXUT46F0iKu8SGXq0bcwP5dz/h0Plj6enJqjz1Zbq2l5WaqYnrVbwWOWMyF3F47g==",
      "license": "BSD-3-Clause",
      "peer": true,
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/stackframe": {
      "version": "1.3.4",
      "resolved": "https://registry.npmjs.org/stackframe/-/stackframe-1.3.4.tgz",
      "integrity": "sha512-oeVtt7eWQS+Na6F//S4kJ2K2VbRlS9D43mAlMyVpVWovy9o+jfgH8O9agzANzaiLjclA0oYzUXEM4PurhSUChw==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/stacktrace-parser": {
      "version": "0.1.11",
      "resolved": "https://registry.npmjs.org/stacktrace-parser/-/stacktrace-parser-0.1.11.tgz",
      "integrity": "sha512-WjlahMgHmCJpqzU8bIBy4qtsZdU9lRlcZE3Lvyej6t4tuOuv1vk57OW3MBrj6hXBFx/nNoC9MPMTcr5YA7NQbg==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "type-fest": "^0.7.1"
      },
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/statuses": {
      "version": "1.5.0",
      "resolved": "https://registry.npmjs.org/statuses/-/statuses-1.5.0.tgz",
      "integrity": "sha512-OpZ3zP+jT1PI7I8nemJX4AKmAX070ZkYPVWV/AaKTJl+tXCTGyVdC1a4SL8RUQYEwk/f34ZX8UTykN68FwrqAA==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/stream-browserify": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/stream-browserify/-/stream-browserify-3.0.0.tgz",
      "integrity": "sha512-H73RAHsVBapbim0tU2JwwOiXUj+fikfiaoYAKHF3VJfA0pe2BCzkhAHBlLG6REzE+2WNZcxOXjK7lkso+9euLA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "inherits": "~2.0.4",
        "readable-stream": "^3.5.0"
      }
    },
    "node_modules/stream-chain": {
      "version": "2.2.5",
      "resolved": "https://registry.npmjs.org/stream-chain/-/stream-chain-2.2.5.tgz",
      "integrity": "sha512-1TJmBx6aSWqZ4tx7aTpBDXK0/e2hhcNSTV8+CbFJtDjbb+I1mZ8lHit0Grw9GRT+6JbIrrDd8esncgBi8aBXGA==",
      "license": "BSD-3-Clause"
    },
    "node_modules/stream-http": {
      "version": "3.2.0",
      "resolved": "https://registry.npmjs.org/stream-http/-/stream-http-3.2.0.tgz",
      "integrity": "sha512-Oq1bLqisTyK3TSCXpPbT4sdeYNdmyZJv1LxpEm2vu1ZhK89kSE5YXwZc3cWk0MagGaKriBh9mCFbVGtO+vY29A==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "builtin-status-codes": "^3.0.0",
        "inherits": "^2.0.4",
        "readable-stream": "^3.6.0",
        "xtend": "^4.0.2"
      }
    },
    "node_modules/stream-json": {
      "version": "1.9.1",
      "resolved": "https://registry.npmjs.org/stream-json/-/stream-json-1.9.1.tgz",
      "integrity": "sha512-uWkjJ+2Nt/LO9Z/JyKZbMusL8Dkh97uUBTv3AJQ74y07lVahLY4eEFsPsE97pxYBwr8nnjMAIch5eqI0gPShyw==",
      "license": "BSD-3-Clause",
      "dependencies": {
        "stream-chain": "^2.2.5"
      }
    },
    "node_modules/string_decoder": {
      "version": "1.3.0",
      "resolved": "https://registry.npmjs.org/string_decoder/-/string_decoder-1.3.0.tgz",
      "integrity": "sha512-hkRX8U1WjJFd8LsDJ2yQ/wWWxaopEsABU1XfkM8A+j0+85JAGppt16cr1Whg6KIbb4okU6Mql6BOj+uup/wKeA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "~5.2.0"
      }
    },
    "node_modules/string-width": {
      "version": "4.2.3",
      "resolved": "https://registry.npmjs.org/string-width/-/string-width-4.2.3.tgz",
      "integrity": "sha512-wKyQRQpjJ0sIp62ErSZdGsjMJWsap5oRNihHhu6G7JVO/9jIB6UyevL+tXuOqrng8j/cxKTWyWUwvSTriiZz/g==",
      "license": "MIT",
      "dependencies": {
        "emoji-regex": "^8.0.0",
        "is-fullwidth-code-point": "^3.0.0",
        "strip-ansi": "^6.0.1"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/strip-ansi": {
      "version": "6.0.1",
      "resolved": "https://registry.npmjs.org/strip-ansi/-/strip-ansi-6.0.1.tgz",
      "integrity": "sha512-Y38VPSHcqkFrCpFnQ9vuSXmquuv5oXOKpGeT6aGrr3o3Gc9AlVa6JBfUSOCnbxGGZF+/0ooI7KrPuUSztUdU5A==",
      "license": "MIT",
      "dependencies": {
        "ansi-regex": "^5.0.1"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/superstruct": {
      "version": "0.15.5",
      "resolved": "https://registry.npmjs.org/superstruct/-/superstruct-0.15.5.tgz",
      "integrity": "sha512-4AOeU+P5UuE/4nOUkmcQdW5y7i9ndt1cQd/3iUe+LTz3RxESf/W/5lg4B74HbDMMv8PHnPnGCQFH45kBcrQYoQ==",
      "license": "MIT"
    },
    "node_modules/supports-color": {
      "version": "8.1.1",
      "resolved": "https://registry.npmjs.org/supports-color/-/supports-color-8.1.1.tgz",
      "integrity": "sha512-MpUEN2OodtUzxvKQl72cUF7RQ5EiHsGvSsVG0ia9c5RbWGL2CI4C7EpPS8UTBIplnlzZiNuV56w+FuNxy3ty2Q==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "has-flag": "^4.0.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/chalk/supports-color?sponsor=1"
      }
    },
    "node_modules/supports-preserve-symlinks-flag": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/supports-preserve-symlinks-flag/-/supports-preserve-symlinks-flag-1.0.0.tgz",
      "integrity": "sha512-ot0WnXS9fgdkgIcePe6RHNk1WA8+muPa6cSjeR3V8K27q9BB1rTE3R1p7Hv0z1ZyAc8s6Vvv8DIyWf681MAt0w==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/terser": {
      "version": "5.51.2",
      "resolved": "https://registry.npmjs.org/terser/-/terser-5.51.2.tgz",
      "integrity": "sha512-bWnjSNscmuI+GJze6ZupnHP8G/cTcsJF+bXCeQknk2SHQsgbNJnLrqiH9jZ2W4STPVXH2mDKKRX3iwPhc9Cn/Q==",
      "license": "BSD-2-Clause",
      "peer": true,
      "dependencies": {
        "@jridgewell/source-map": "^0.3.3",
        "acorn": "^8.15.0",
        "commander": "^2.20.0",
        "source-map-support": "~0.5.20"
      },
      "bin": {
        "terser": "bin/terser"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/terser/node_modules/commander": {
      "version": "2.20.3",
      "resolved": "https://registry.npmjs.org/commander/-/commander-2.20.3.tgz",
      "integrity": "sha512-GpVkmM8vF2vQUkj2LvZmD35JxeJOLCwJ9cUkugyk2nuhbv3+mJvpLYYt+0+USMxE+oj+ey/lJEnhZw75x/OMcQ==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/text-encoding-utf-8": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/text-encoding-utf-8/-/text-encoding-utf-8-1.0.2.tgz",
      "integrity": "sha512-8bw4MY9WjdsD2aMtO0OzOCY3pXGYNx2d2FfHRVUKkiCPDWjKuOlhLVASS+pD7VkLTVjW268LYJHwsnPFlBpbAg=="
    },
    "node_modules/throat": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/throat/-/throat-5.0.0.tgz",
      "integrity": "sha512-fcwX4mndzpLQKBS1DVYhGAcYaYt7vsHNIvQV+WXMvnow5cgjPphq5CaayLaGsjRdSCKZFNGt7/GYAuXaNOiYCA==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/timers-browserify": {
      "version": "2.0.12",
      "resolved": "https://registry.npmjs.org/timers-browserify/-/timers-browserify-2.0.12.tgz",
      "integrity": "sha512-9phl76Cqm6FhSX9Xe1ZUAMLtm1BLkKj2Qd5ApyWkXzsMRaA7dgr81kf4wJmQf/hAvg8EEyJxDo3du/0KlhPiKQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "setimmediate": "^1.0.4"
      },
      "engines": {
        "node": ">=0.6.0"
      }
    },
    "node_modules/tinyglobby": {
      "version": "0.2.17",
      "resolved": "https://registry.npmjs.org/tinyglobby/-/tinyglobby-0.2.17.tgz",
      "integrity": "sha512-wXR/dYpcqKmfWpEdZjiKJOwCNFndD0DMnrW/cYjVGttEkBfVgcLFHoNrlj47mjOVic9yyNu65alsgF4NQyTa2g==",
      "license": "MIT",
      "dependencies": {
        "fdir": "^6.5.0",
        "picomatch": "^4.0.4"
      },
      "engines": {
        "node": ">=12.0.0"
      },
      "funding": {
        "url": "https://github.com/sponsors/SuperchupuDev"
      }
    },
    "node_modules/tinyglobby/node_modules/fdir": {
      "version": "6.5.0",
      "resolved": "https://registry.npmjs.org/fdir/-/fdir-6.5.0.tgz",
      "integrity": "sha512-tIbYtZbucOs0BRGqPJkshJUYdL+SDH7dVM8gjy+ERp3WAUjLEFJE+02kanyHtwjWOnwrKYBiwAmM0p4kLJAnXg==",
      "license": "MIT",
      "engines": {
        "node": ">=12.0.0"
      },
      "peerDependencies": {
        "picomatch": "^3 || ^4"
      },
      "peerDependenciesMeta": {
        "picomatch": {
          "optional": true
        }
      }
    },
    "node_modules/tinyglobby/node_modules/picomatch": {
      "version": "4.0.7",
      "resolved": "https://registry.npmjs.org/picomatch/-/picomatch-4.0.7.tgz",
      "integrity": "sha512-qcJu88Q2IWqJsDD529JKMdwGm/dvInW4HvQnRwiH9JtihJvzGOscDtHE3x1pBKeUOTysQ8kVmLnJ2kJu7yhcGA==",
      "license": "MIT",
      "engines": {
        "node": ">=12"
      },
      "funding": {
        "url": "https://github.com/sponsors/jonschlinkert"
      }
    },
    "node_modules/to-buffer": {
      "version": "1.2.2",
      "resolved": "https://registry.npmjs.org/to-buffer/-/to-buffer-1.2.2.tgz",
      "integrity": "sha512-db0E3UJjcFhpDhAF4tLo03oli3pwl3dbnzXOUIlRKrp+ldk/VUxzpWYZENsw2SZiuBjHAk7DfB0VU7NKdpb6sw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "isarray": "^2.0.5",
        "safe-buffer": "^5.2.1",
        "typed-array-buffer": "^1.0.3"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/to-regex-range": {
      "version": "5.0.1",
      "resolved": "https://registry.npmjs.org/to-regex-range/-/to-regex-range-5.0.1.tgz",
      "integrity": "sha512-65P7iz6X5yEr1cwcgvQxbbIw7Uk3gOy5dIdtZ4rDveLqhrdJP+Li/Hx6tyK0NEb+2GCyneCMJiGqrADCSNk8sQ==",
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "is-number": "^7.0.0"
      },
      "engines": {
        "node": ">=8.0"
      }
    },
    "node_modules/toidentifier": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/toidentifier/-/toidentifier-1.0.1.tgz",
      "integrity": "sha512-o5sSPKEkg/DIQNmH43V0/uerLrpzVedkUh8tGNvaeXpfpuwjKenlSox/2O/BTlZUtEe+JG7s5YhEz608PlAHRA==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=0.6"
      }
    },
    "node_modules/toml": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/toml/-/toml-3.0.0.tgz",
      "integrity": "sha512-y/mWCZinnvxjTKYhJ+pYxwD0mRLVvOtdS2Awbgxln6iEnt4rk0yBxeSBHkGJcPucRiG0e55mwWp+g/05rsrd6w==",
      "license": "MIT"
    },
    "node_modules/tr46": {
      "version": "0.0.3",
      "resolved": "https://registry.npmjs.org/tr46/-/tr46-0.0.3.tgz",
      "integrity": "sha512-N3WMsuqV66lT30CrXNbEjx4GEwlow3v6rr4mCcv6prnfwhS01rkgyFdjPNBYd9br7LpXV1+Emh01fHnq2Gdgrw==",
      "license": "MIT"
    },
    "node_modules/tslib": {
      "version": "2.8.1",
      "resolved": "https://registry.npmjs.org/tslib/-/tslib-2.8.1.tgz",
      "integrity": "sha512-oJFu94HQb+KVduSUQL7wnpmqnfmLsOA/nAh6b6EH0wCEoK0/mPeXU6c3wKDV83MkOuHPRHtSXKKU99IBazS/2w==",
      "license": "0BSD"
    },
    "node_modules/tsx": {
      "version": "4.23.15",
      "resolved": "https://registry.npmjs.org/tsx/-/tsx-4.23.15.tgz",
      "integrity": "sha512-Yiex1Ovn8z2xPpOWckIiysV1SSyRMY9BkLF++q0yKiDxCqRhosKfMg3janKkiLBwZ5c/YryloKwGZcrEmtwxKw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "esbuild": "~0.28.0"
      },
      "bin": {
        "tsx": "dist/cli.mjs"
      },
      "engines": {
        "node": ">=18.0.0"
      },
      "optionalDependencies": {
        "fsevents": "~2.3.3"
      }
    },
    "node_modules/tty-browserify": {
      "version": "0.0.1",
      "resolved": "https://registry.npmjs.org/tty-browserify/-/tty-browserify-0.0.1.tgz",
      "integrity": "sha512-C3TaO7K81YvjCgQH9Q1S3R3P3BtN3RIM8n+OvX4il1K1zgE8ZhI0op7kClgkxtutIE8hQrcrHBXvIheqKUUCxw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/type-fest": {
      "version": "0.7.1",
      "resolved": "https://registry.npmjs.org/type-fest/-/type-fest-0.7.1.tgz",
      "integrity": "sha512-Ne2YiiGN8bmrmJJEuTWTLJR32nh/JdL1+PSicowtNb0WFpn59GK8/lfD61bVtzguz7b3PBt74nxpv/Pw5po5Rg==",
      "license": "(MIT OR CC0-1.0)",
      "peer": true,
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/typed-array-buffer": {
      "version": "1.0.3",
      "resolved": "https://registry.npmjs.org/typed-array-buffer/-/typed-array-buffer-1.0.3.tgz",
      "integrity": "sha512-nAYYwfY3qnzX30IkA6AQZjVbtK6duGontcQm1WSG1MD94YLqK0515GNApXkoxKOWMusVssAHWLh9SeaoefYFGw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "call-bound": "^1.0.3",
        "es-errors": "^1.3.0",
        "is-typed-array": "^1.1.14"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/typescript": {
      "version": "5.9.3",
      "resolved": "https://registry.npmjs.org/typescript/-/typescript-5.9.3.tgz",
      "integrity": "sha512-jl1vZzPDinLr9eUt3J/t7V6FgNEw9QjvBPdysz9KfQDD41fQrC2Y4vKQdiaUpFT4bXlb1RHhLpp8wtm6M5TgSw==",
      "license": "Apache-2.0",
      "bin": {
        "tsc": "bin/tsc",
        "tsserver": "bin/tsserver"
      },
      "engines": {
        "node": ">=14.17"
      }
    },
    "node_modules/undici-types": {
      "version": "6.21.0",
      "resolved": "https://registry.npmjs.org/undici-types/-/undici-types-6.21.0.tgz",
      "integrity": "sha512-iwDZqg0QAGrg9Rav5H4n0M64c3mkR59cJ6wQp+7C4nI0gsmExaedaYLNO44eT4AtBBwjbTiGPMlt2Md0T9H9JQ==",
      "license": "MIT"
    },
    "node_modules/unpipe": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/unpipe/-/unpipe-1.0.0.tgz",
      "integrity": "sha512-pjy2bYhSsufwWlKwPc+l3cN7+wuJlK6uz0YdJEOlQDbl6jo/YlPi4mb8agUkVC8BF7V8NuzeyPNqRksA3hztKQ==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/update-browserslist-db": {
      "version": "1.3.3",
      "resolved": "https://registry.npmjs.org/update-browserslist-db/-/update-browserslist-db-1.3.3.tgz",
      "integrity": "sha512-pJ2sYawQS0R/WI928Gj5GlPhTGzbMelq0+4INtSYNDV9ErKJcX6xjGWkoG/VnB3dpUm00zALaqkrUD77pO5TDQ==",
      "funding": [
        {
          "type": "opencollective",
          "url": "https://opencollective.com/browserslist"
        },
        {
          "type": "tidelift",
          "url": "https://tidelift.com/funding/github/npm/browserslist"
        },
        {
          "type": "github",
          "url": "https://github.com/sponsors/ai"
        }
      ],
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "escalade": "^3.2.0",
        "picocolors": "^1.1.1"
      },
      "bin": {
        "update-browserslist-db": "cli.js"
      },
      "peerDependencies": {
        "browserslist": ">= 4.21.0"
      }
    },
    "node_modules/url": {
      "version": "0.11.4",
      "resolved": "https://registry.npmjs.org/url/-/url-0.11.4.tgz",
      "integrity": "sha512-oCwdVC7mTuWiPyjLUz/COz5TLk6wgp0RCsN+wHZ2Ekneac9w8uuV0njcbbie2ME+Vs+d6duwmYuR3HgQXs1fOg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "punycode": "^1.4.1",
        "qs": "^6.12.3"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/utf-8-validate": {
      "version": "5.0.10",
      "resolved": "https://registry.npmjs.org/utf-8-validate/-/utf-8-validate-5.0.10.tgz",
      "integrity": "sha512-Z6czzLq4u8fPOyx7TU6X3dvUZVvoJmxSQ+IcrlmagKhilxlhZgxPK6C5Jqbkw1IDUmFTM+cz9QDnnLTwDz/2gQ==",
      "hasInstallScript": true,
      "license": "MIT",
      "optional": true,
      "peer": true,
      "dependencies": {
        "node-gyp-build": "^4.3.0"
      },
      "engines": {
        "node": ">=6.14.2"
      }
    },
    "node_modules/util": {
      "version": "0.12.5",
      "resolved": "https://registry.npmjs.org/util/-/util-0.12.5.tgz",
      "integrity": "sha512-kZf/K6hEIrWHI6XqOFUiiMa+79wE/D8Q+NCNAWclkyg3b4d2k7s0QGepNjiABc+aR3N1PAyHL7p6UcLY6LmrnA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "inherits": "^2.0.3",
        "is-arguments": "^1.0.4",
        "is-generator-function": "^1.0.7",
        "is-typed-array": "^1.1.3",
        "which-typed-array": "^1.1.2"
      }
    },
    "node_modules/util-deprecate": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/util-deprecate/-/util-deprecate-1.0.2.tgz",
      "integrity": "sha512-EPD5q1uXyFxJpCrLnCc1nHnq3gOa6DZBocAIiI2TaSCA7VCJ1UJDMagCzIkXNsUYfD1daK//LTEQ8xiIbrHtcw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/utils-merge": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/utils-merge/-/utils-merge-1.0.1.tgz",
      "integrity": "sha512-pMZTvIkT1d+TFGvDOqodOclx0QWkkgi6Tdoa8gC8ffGAAqz9pzPTZWAybbsHHoED/ztMtkv/VoYTYyShUn81hA==",
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">= 0.4.0"
      }
    },
    "node_modules/uuid": {
      "version": "8.3.2",
      "resolved": "https://registry.npmjs.org/uuid/-/uuid-8.3.2.tgz",
      "integrity": "sha512-+NYs2QeMWy+GWFOEm9xnn6HCDp0l7QBD7ml8zLUmJ+93Q5NF0NocErnwkTkXVFNiX3/fpC6afS8Dhb/gz7R7eg==",
      "deprecated": "uuid@10 and below is no longer supported.  For ESM codebases, update to uuid@latest.  For CommonJS codebases, use uuid@11 (but be aware this version will likely be deprecated in 2028).",
      "license": "MIT",
      "bin": {
        "uuid": "dist/bin/uuid"
      }
    },
    "node_modules/vite": {
      "version": "8.3.2",
      "resolved": "https://registry.npmjs.org/vite/-/vite-8.3.2.tgz",
      "integrity": "sha512-SQr1x6W5vVSbROg7vsyXIaxK9b0G7zsT68acdWWRmnBUsgDieLCRG+Rep9WdZgcposvv/GSnr4GUUBqB3vXq6w==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "lightningcss": "^1.33.0",
        "picomatch": "^4.0.7",
        "postcss": "^8.5.28",
        "rolldown": "~1.2.11",
        "tinyglobby": "^0.2.17"
      },
      "bin": {
        "vite": "bin/vite.js"
      },
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      },
      "funding": {
        "url": "https://github.com/vitejs/vite?sponsor=1"
      },
      "optionalDependencies": {
        "fsevents": "~2.3.3"
      },
      "peerDependencies": {
        "@types/node": "^20.19.0 || >=22.12.0",
        "@vitejs/devtools": "^0.7.1",
        "esbuild": "^0.27.0 || ^0.28.0",
        "jiti": ">=1.21.0",
        "less": "^4.0.0",
        "sass": "^1.70.0",
        "sass-embedded": "^1.70.0",
        "stylus": ">=0.54.8",
        "sugarss": "^5.0.0",
        "terser": "^5.16.0",
        "tsx": "^4.8.1",
        "yaml": "^2.4.2"
      },
      "peerDependenciesMeta": {
        "@types/node": {
          "optional": true
        },
        "@vitejs/devtools": {
          "optional": true
        },
        "esbuild": {
          "optional": true
        },
        "jiti": {
          "optional": true
        },
        "less": {
          "optional": true
        },
        "sass": {
          "optional": true
        },
        "sass-embedded": {
          "optional": true
        },
        "stylus": {
          "optional": true
        },
        "sugarss": {
          "optional": true
        },
        "terser": {
          "optional": true
        },
        "tsx": {
          "optional": true
        },
        "yaml": {
          "optional": true
        }
      }
    },
    "node_modules/vite-plugin-node-polyfills": {
      "version": "0.28.0",
      "resolved": "https://registry.npmjs.org/vite-plugin-node-polyfills/-/vite-plugin-node-polyfills-0.28.0.tgz",
      "integrity": "sha512-NXct/ci2ef4fRyCfTb8fk2HmR80Rv7icLd+cRH41TnUugDzdKMFKqFPpZYCFUInZMMem9bkLv5pkq02+7Xu7+w==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@rollup/plugin-inject": "^5.0.5",
        "node-stdlib-browser": "^1.3.1"
      },
      "funding": {
        "url": "https://github.com/sponsors/davidmyersdev"
      },
      "peerDependencies": {
        "vite": "^2.0.0 || ^3.0.0 || ^4.0.0 || ^5.0.0 || ^6.0.0 || ^7.0.0 || ^8.0.0"
      }
    },
    "node_modules/vite/node_modules/picomatch": {
      "version": "4.0.7",
      "resolved": "https://registry.npmjs.org/picomatch/-/picomatch-4.0.7.tgz",
      "integrity": "sha512-qcJu88Q2IWqJsDD529JKMdwGm/dvInW4HvQnRwiH9JtihJvzGOscDtHE3x1pBKeUOTysQ8kVmLnJ2kJu7yhcGA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=12"
      },
      "funding": {
        "url": "https://github.com/sponsors/jonschlinkert"
      }
    },
    "node_modules/vlq": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/vlq/-/vlq-1.0.1.tgz",
      "integrity": "sha512-gQpnTgkubC6hQgdIcRdYGDSDc+SaujOdyesZQMv6JlfQee/9Mp0Qhnys6WxDWvQnL5WZdT7o2Ul187aSt0Rq+w==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/vm-browserify": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/vm-browserify/-/vm-browserify-1.1.2.tgz",
      "integrity": "sha512-2ham8XPWTONajOR0ohOKOHXkm3+gaBmGut3SRuu75xLd/RRaY6vqgh8NBYYk7+RW3u5AtzPQZG8F10LHkl0lAQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/webidl-conversions": {
      "version": "3.0.1",
      "resolved": "https://registry.npmjs.org/webidl-conversions/-/webidl-conversions-3.0.1.tgz",
      "integrity": "sha512-2JAn3z8AR6rjK8Sm8orRC0h/bcl/DqL7tRPdGZ4I1CjdF+EaMLmYxBHyXuKL849eucPFhvBoxMsflfOb8kxaeQ==",
      "license": "BSD-2-Clause"
    },
    "node_modules/whatwg-fetch": {
      "version": "3.6.20",
      "resolved": "https://registry.npmjs.org/whatwg-fetch/-/whatwg-fetch-3.6.20.tgz",
      "integrity": "sha512-EqhiFU6daOA8kpjOWTL0olhVOF3i7OrFzSYiGsEMB8GcXS+RrzauAERX65xMeNWVqxA6HXH2m69Z9LaKKdisfg==",
      "license": "MIT",
      "peer": true
    },
    "node_modules/whatwg-url": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/whatwg-url/-/whatwg-url-5.0.0.tgz",
      "integrity": "sha512-saE57nupxk6v3HY35+jzBwYa0rKSy0XR8JSxZPwgLr7ys0IBzhGviA1/TUGJLmSVqs8pb9AnvICXEuOHLprYTw==",
      "license": "MIT",
      "dependencies": {
        "tr46": "~0.0.3",
        "webidl-conversions": "^3.0.0"
      }
    },
    "node_modules/which": {
      "version": "2.0.2",
      "resolved": "https://registry.npmjs.org/which/-/which-2.0.2.tgz",
      "integrity": "sha512-BLI3Tl1TW3Pvl70l3yq3Y64i+awpwXqsGBYWkkqMtnbXgrMD+yj7rhW0kuEDxzJaYXGjEW5ogapKNMEKNMjibA==",
      "license": "ISC",
      "peer": true,
      "dependencies": {
        "isexe": "^2.0.0"
      },
      "bin": {
        "node-which": "bin/node-which"
      },
      "engines": {
        "node": ">= 8"
      }
    },
    "node_modules/which-module": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/which-module/-/which-module-2.0.1.tgz",
      "integrity": "sha512-iBdZ57RDvnOR9AGBhML2vFZf7h8vmBjhoaZqODJBFWHVtKkDmKuHai3cx5PgVMrX5YDNp27AofYbAwctSS+vhQ==",
      "license": "ISC"
    },
    "node_modules/which-typed-array": {
      "version": "1.1.24",
      "resolved": "https://registry.npmjs.org/which-typed-array/-/which-typed-array-1.1.24.tgz",
      "integrity": "sha512-wk4Mf4pR5mRP7eYuuTBCIQ9d0ud2Fv2jRLQpfgnRjbOxAFHmjKFValgTpitVKzJJS8ajnYQV2Du1SZ8j6b/EUQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "available-typed-arrays": "^1.0.7",
        "call-bind": "^1.0.9",
        "call-bound": "^1.0.4",
        "for-each": "^0.3.5",
        "get-proto": "^1.0.1",
        "gopd": "^1.2.0",
        "has-tostringtag": "^1.0.2"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/wrap-ansi": {
      "version": "6.2.0",
      "resolved": "https://registry.npmjs.org/wrap-ansi/-/wrap-ansi-6.2.0.tgz",
      "integrity": "sha512-r6lPcBGxZXlIcymEu7InxDMhdW0KDxpLgoFLcguasxCaJ/SOIZwINatK9KY/tf+ZrlywOKU0UDj3ATXUBfxJXA==",
      "license": "MIT",
      "dependencies": {
        "ansi-styles": "^4.0.0",
        "string-width": "^4.1.0",
        "strip-ansi": "^6.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/ws": {
      "version": "7.5.13",
      "resolved": "https://registry.npmjs.org/ws/-/ws-7.5.13.tgz",
      "integrity": "sha512-rsKI6xDBFVf4r/x8XyChGK04QR/XHroxs/jUcoWvtEZM8TPU/X/uIY9B1CsSzYws9ZJb/6bbBu7dPhFW00CAoA==",
      "license": "MIT",
      "engines": {
        "node": ">=8.3.0"
      },
      "peerDependencies": {
        "bufferutil": "^4.0.1",
        "utf-8-validate": "^5.0.2"
      },
      "peerDependenciesMeta": {
        "bufferutil": {
          "optional": true
        },
        "utf-8-validate": {
          "optional": true
        }
      }
    },
    "node_modules/xtend": {
      "version": "4.0.2",
      "resolved": "https://registry.npmjs.org/xtend/-/xtend-4.0.2.tgz",
      "integrity": "sha512-LKYU1iAXJXUgAXn9URjiu+MWhyUXHsvfp7mcuYm9dSUKK0/CjtrUwFAxD82/mCWbtLsGjFIad0wIsod4zrTAEQ==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=0.4"
      }
    },
    "node_modules/y18n": {
      "version": "4.0.3",
      "resolved": "https://registry.npmjs.org/y18n/-/y18n-4.0.3.tgz",
      "integrity": "sha512-JKhqTOwSrqNA1NY5lSztJ1GrBiUodLMmIZuLiDaMRJ+itFd+ABVE8XBjOvIWL+rSqNDC74LCSFmlb/U4UZ4hJQ==",
      "license": "ISC"
    },
    "node_modules/yallist": {
      "version": "3.1.1",
      "resolved": "https://registry.npmjs.org/yallist/-/yallist-3.1.1.tgz",
      "integrity": "sha512-a4UGQaWPH59mOXUYnAG2ewncQS4i4F43Tv3JoAM+s2VDAmS9NsK8GpDMLrCHPksFT7h3K6TOoUNn2pb7RoXx4g==",
      "license": "ISC",
      "peer": true
    },
    "node_modules/yargs": {
      "version": "15.4.1",
      "resolved": "https://registry.npmjs.org/yargs/-/yargs-15.4.1.tgz",
      "integrity": "sha512-aePbxDmcYW++PaqBsJ+HYUFwCdv4LVvdnhBy78E57PIor8/OVvhMrADFFEDh8DHDFRv/O9i3lPhsENjO7QX0+A==",
      "license": "MIT",
      "dependencies": {
        "cliui": "^6.0.0",
        "decamelize": "^1.2.0",
        "find-up": "^4.1.0",
        "get-caller-file": "^2.0.1",
        "require-directory": "^2.1.1",
        "require-main-filename": "^2.0.0",
        "set-blocking": "^2.0.0",
        "string-width": "^4.2.0",
        "which-module": "^2.0.0",
        "y18n": "^4.0.0",
        "yargs-parser": "^18.1.2"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/yargs-parser": {
      "version": "18.1.3",
      "resolved": "https://registry.npmjs.org/yargs-parser/-/yargs-parser-18.1.3.tgz",
      "integrity": "sha512-o50j0JeToy/4K6OZcaQmW6lyXXKhq7csREXcDwk2omFPJEwUNOVtJKvmDr9EI1fAJZUyZcRF7kxGBWmRXudrCQ==",
      "license": "ISC",
      "dependencies": {
        "camelcase": "^5.0.0",
        "decamelize": "^1.2.0"
      },
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/yargs-parser/node_modules/camelcase": {
      "version": "5.3.1",
      "resolved": "https://registry.npmjs.org/camelcase/-/camelcase-5.3.1.tgz",
      "integrity": "sha512-L28STB170nwWS63UjtlEOE3dldQApaJXZkOI1uMFfzf3rRuPegHaHesyee+YxQ+W6SvRDQV6UrdOdRiR153wJg==",
      "license": "MIT",
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/yocto-queue": {
      "version": "0.1.0",
      "resolved": "https://registry.npmjs.org/yocto-queue/-/yocto-queue-0.1.0.tgz",
      "integrity": "sha512-rVksvsnNCdJ/ohGc6xgPwyN8eheCxsiLM8mxuE/t/mOVqJewPuO1miLpTHQiRgTKCLexL4MeAFVagts7HmNZ2Q==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    }
  }
}
OWNCURVE_EOF

cat > 'tsconfig.json' <<'OWNCURVE_EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "esnext",
    "moduleResolution": "bundler",
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "strict": true,
    "noImplicitAny": false,
    "skipLibCheck": true
  },
  "include": ["scripts/**/*.ts", "tests/**/*.ts"]
}
OWNCURVE_EOF

cat > '.gitignore' <<'OWNCURVE_EOF'
target/
logs/
node_modules/
.anchor/
test-ledger/
.owncurve/
local/
.deps/
app/dist/
app/.env.local
OWNCURVE_EOF

cat > 'README.md' <<'OWNCURVE_EOF'
# OwnCurve

Ownership coins on Meteora's Dynamic Bonding Curve (DBC).

A raise is a normal DBC launch whose config names OwnCurve's treasury PDA as
`fee_claimer` and `leftover_receiver`. At graduation the DBC migration fee (up to
99% of the raise) is pulled into an on-chain treasury instead of a wallet. The team
is paid in milestone tranches; holders can lock tokens to reject a tranche, and a
rejection that reaches quorum turns the treasury into a pro-rata redemption pool.
After graduation the treasury also owns the DAMM v2 LP position, so it keeps earning
trading fees forever.

Built for the Colosseum Crypto World's Fair — "Best use of Meteora's DBC" sidetrack.

## Lifecycle

```
Pending --bind_pool--> Bonding --harvest (CPI)--> Funded
Funded --propose_release + reject votes--> finalize
    quorum not reached -> tranche to team -> Funded (next milestone) / Completed (last)
    quorum reached     -> Liquidating -> redeem (burn tokens, receive NAV share)
Any time after launch: collect_trading_fees, collect_surplus, claim_lp_fees -> treasury
```

## Instructions

| Instruction | Caller | What it does |
| --- | --- | --- |
| `init_raise` | team | Milestone tranches (sum 10000 bps), min treasury %, challenge window, reject quorum |
| `bind_pool` | anyone | Validates the live DBC config + pool before anyone buys (see guarantees) |
| `harvest` | anyone | CPI `withdraw_migration_fee` signed by the treasury PDA |
| `collect_trading_fees` | anyone | CPI `claim_trading_fee`: partner share of curve fees → treasury |
| `collect_surplus` | anyone | CPI `partner_withdraw_surplus` → treasury |
| `claim_lp_fees` | anyone | CPI DAMM v2 `claim_position_fee` for the treasury-owned position |
| `propose_release` | team | Opens a challenge window for the next milestone |
| `reject` | holder | Locks base tokens in escrow as a reject vote |
| `finalize` | anyone | Pays the tranche, or switches to liquidation if quorum was met |
| `withdraw_vote` | holder | Returns locked tokens after finalize |
| `redeem` | holder | In liquidation: burn tokens, receive a pro-rata share of the treasury |

## On-chain guarantees (enforced by `bind_pool` / `init_raise`)

- `fee_claimer` and `leftover_receiver` of the DBC config are the treasury PDA: only this program can move the raise.
- The creator gets 0% of the migration fee and its DAMM v2 LP is 100% permanently locked (no liquidity rug).
- The creator never holds the mint authority (no infinite mint).
- The migration fee routed to the treasury is at least the raise's `min_treasury_pct` (≥ 50%).
- Holders always get a challenge window of ≥ 60 s, and blocking a tranche never needs more than 30% of supply.
- Fees, surplus and LP fees can only be sent to treasury-owned token accounts.

## Verified against DBC source (program 0.2.1, commit f552f20)

- `MAX_MIGRATION_FEE_PERCENTAGE = 99`; `create_config` takes `fee_claimer` as an unchecked account, so it can be a PDA.
- `withdraw_migration_fee`, `claim_trading_fee` and `partner_withdraw_surplus` require `fee_claimer` as signer.
- On DAMM v2 migration the partner position is minted to `config.fee_claimer` (the treasury).

## Devnet (F1)

Program `GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh`: a full raise was created, bought to
graduation, harvested (0.4 SOL = 80% of 0.5 SOL into the treasury PDA) and migrated to DAMM v2.

## Web app

`app/` is a Vite + React front end that reuses the same client as the scripts (`scripts/lib/owncurve.ts`).
It lists every raise, draws the treasury as a vault split into tranches, shows the guarantees that
`bind_pool` checked on-chain, and lets anyone buy, object, settle and redeem. Connect a browser wallet
(Phantom, Solflare, Backpack…) or click **Use a test wallet** to try it on devnet without installing anything.

```
npm run app            # http://localhost:5173 (devnet; set VITE_RPC_URL in app/.env.local)
npm run e2e            # Chromium drives the whole lifecycle against LiteSVM with the real programs
```

## Build and test

```
anchor build --skip-lint --tools-version v1.52 --arch v0
npm ci
CLUSTER=local npx tsx --test tests/owncurve.test.ts   # 17 integration tests, real DBC + DAMM v2 binaries
CLUSTER=local npx tsx scripts/f1.ts --migrate        # end-to-end flow in LiteSVM
npx tsx scripts/f1.ts --migrate                      # same flow on devnet
```

Local tests need `local/dynamic_bonding_curve.so` (built from DBC source at f552f20) and
`local/damm_v2.so` (DBC repo test fixture); `owncurve.sh` prepares both.

## Known limitations (MVP)

- Tokens sitting in the DBC/DAMM v2 pool count as circulating supply, so redemption pays them
  out only when someone buys them from the pool and redeems (an arbitrage floor, by design).
- Votes are locked tokens with no snapshot; flash-borrowed votes are possible but cost a round trip.

## License

MIT
OWNCURVE_EOF

mkdir -p 'scripts/lib'
cat > 'scripts/lib/net.ts' <<'OWNCURVE_EOF'
// Red de trabajo: devnet real, o LiteSVM en memoria (para tests locales con los
// binarios reales de DBC). Ambos exponen lo mismo: `conn` (tipo Connection) y `send`.
import {
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
  ComputeBudgetProgram,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import fs from "fs";
import os from "os";
import path from "path";

export type Net = {
  cluster: "devnet" | "local";
  conn: Connection;
  payer: Keypair;
  send: (label: string, ixs: TransactionInstruction[], signers: Keypair[]) => Promise<string>;
  explorer: (sig: string) => string;
  /** local: adelanta el reloj del validador; devnet: espera de verdad. */
  advanceTime: (secs: number) => Promise<void>;
  /** local: airdrop; devnet: transferencia desde la wallet principal. */
  fund: (to: PublicKey, lamports: number) => Promise<void>;
  svm?: any;
};

export function loadKeypair(file: string): Keypair {
  const p = file.startsWith("~") ? path.join(os.homedir(), file.slice(1)) : file;
  return Keypair.fromSecretKey(Uint8Array.from(JSON.parse(fs.readFileSync(p, "utf8"))));
}

export async function makeNet(): Promise<Net> {
  const cluster = (process.env.CLUSTER ?? "devnet") as "devnet" | "local";
  if (cluster === "local") return makeLocal();

  const url = process.env.RPC_URL ?? "https://api.devnet.solana.com";
  const conn = new Connection(url, "confirmed");
  const payer = loadKeypair(process.env.WALLET ?? "~/.config/solana/id.json");
  const send = async (label: string, ixs: TransactionInstruction[], signers: Keypair[]) => {
    const tx = new Transaction().add(
      ...withBudget(ixs, [
        ComputeBudgetProgram.setComputeUnitLimit({ units: 1_000_000 }),
        ComputeBudgetProgram.setComputeUnitPrice({ microLamports: 20_000 }),
      ]),
    );
    tx.feePayer = payer.publicKey;
    let lastErr: unknown;
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        const sig = await sendAndConfirmTransaction(conn, tx, dedupe([payer, ...signers]), {
          commitment: "confirmed",
        });
        return sig;
      } catch (e: any) {
        lastErr = e;
        const logs: string[] | undefined = e?.logs ?? e?.transactionLogs;
        const msg = String(e?.message ?? e);
        // Errores del programa: no tiene sentido reintentar.
        if (logs || /custom program error|Simulation failed/i.test(msg)) {
          throw new TxError(label, msg, logs);
        }
        console.log(`   … ${label}: reintento ${attempt}/3 (${msg.slice(0, 80)})`);
        await new Promise((r) => setTimeout(r, 2500 * attempt));
      }
    }
    throw new TxError(label, String((lastErr as any)?.message ?? lastErr));
  };
  return {
    cluster,
    conn,
    payer,
    send,
    explorer: (sig) => `https://explorer.solana.com/tx/${sig}?cluster=devnet`,
    advanceTime: (secs) => new Promise((r) => setTimeout(r, (secs + 2) * 1000)),
    fund: async (to, lamports) => {
      await send("fondear", [SystemProgram.transfer({ fromPubkey: payer.publicKey, toPubkey: to, lamports })], []);
    },
  };
}

export class TxError extends Error {
  constructor(public label: string, message: string, public logs?: string[]) {
    super(`${label}: ${message}`);
  }
}

// Añade nuestras instrucciones de ComputeBudget solo si la transacción (p. ej. del SDK
// de Meteora) no trae ya las suyas: Solana rechaza instrucciones de presupuesto duplicadas.
function withBudget(ixs: TransactionInstruction[], budget: TransactionInstruction[]) {
  const present = new Set(
    ixs.filter((ix) => ix.programId.equals(ComputeBudgetProgram.programId)).map((ix) => ix.data[0]),
  );
  return [...budget.filter((ix) => !present.has(ix.data[0])), ...ixs];
}

function dedupe(kps: Keypair[]): Keypair[] {
  const seen = new Set<string>();
  return kps.filter((k) => !seen.has(k.publicKey.toBase58()) && seen.add(k.publicKey.toBase58()));
}

// ---------------------------------------------------------------------------
// LiteSVM: validador en memoria con los .so reales de DBC y de OwnCurve.
// ---------------------------------------------------------------------------
async function makeLocal(): Promise<Net> {
  const { LiteSVM, FailedTransactionMetadata } = await import("litesvm");
  const svm = new LiteSVM();
  const so = (env: string, def: string) => process.env[env] ?? def;
  const DBC = new PublicKey("dbcij3LWUppWqq96dh6gJWwBifmcGfLSB5D4DuSMaqN");
  const DAMM_V2 = new PublicKey("cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG");
  const idl = JSON.parse(fs.readFileSync("target/idl/owncurve.json", "utf8"));
  svm.addProgramFromFile(DBC, so("DBC_SO", "local/dynamic_bonding_curve.so"));
  if (fs.existsSync(so("DAMM_V2_SO", "local/damm_v2.so"))) {
    svm.addProgramFromFile(DAMM_V2, so("DAMM_V2_SO", "local/damm_v2.so"));
  }
  svm.addProgramFromFile(new PublicKey(idl.address), "target/deploy/owncurve.so");

  // Igual que en mainnet/devnet: la pool authority de DBC tiene lamports para "flash rent".
  const [poolAuthority] = PublicKey.findProgramAddressSync([Buffer.from("pool_authority")], DBC);
  svm.setAccount(poolAuthority, {
    lamports: 1_000_000_000,
    data: new Uint8Array(),
    owner: new PublicKey("11111111111111111111111111111111"),
    executable: false,
  });

  // Mint de SOL envuelto (wSOL), como en los tests de DBC: 9 decimales, inicializado.
  const nativeMint = new Uint8Array(82);
  nativeMint[44] = 9;
  nativeMint[45] = 1;
  svm.setAccount(new PublicKey("So11111111111111111111111111111111111111112"), {
    lamports: 1_390_379_946_687,
    data: nativeMint,
    owner: new PublicKey("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
    executable: false,
  });

  const payer = Keypair.generate();
  svm.airdrop(payer.publicKey, BigInt(100e9));
  const conn = new SvmConnection(svm) as unknown as Connection;

  const send = async (label: string, ixs: TransactionInstruction[], signers: Keypair[]) => {
    const tx = new Transaction().add(
      ...withBudget(ixs, [ComputeBudgetProgram.setComputeUnitLimit({ units: 1_400_000 })]),
    );
    tx.feePayer = payer.publicKey;
    tx.recentBlockhash = svm.latestBlockhash();
    tx.sign(...dedupe([payer, ...signers]));
    if (process.env.DEBUG) console.log(`   [svm] ${label}: ${tx.instructions.length} ix, ${tx.serialize().length} bytes`);
    const res = svm.sendTransaction(tx);
    svm.expireBlockhash();
    if (res instanceof FailedTransactionMetadata) {
      throw new TxError(label, res.err().toString(), res.meta().logs());
    }
    return Buffer.from(tx.signature!).toString("hex").slice(0, 16);
  };
  const advanceTime = async (secs: number) => {
    const c = svm.getClock();
    c.unixTimestamp = c.unixTimestamp + BigInt(secs);
    c.slot = c.slot + BigInt(Math.max(1, Math.ceil(secs * 2.5)));
    svm.setClock(c);
  };
  const fund = async (to: PublicKey, lamports: number) => {
    svm.airdrop(to, BigInt(lamports));
  };
  return { cluster: "local", conn, payer, send, explorer: (s) => `local:${s}`, advanceTime, fund, svm };
}

// Lo mínimo de Connection que usan Anchor y el SDK de DBC, respaldado por LiteSVM.
class SvmConnection {
  commitment = "confirmed";
  rpcEndpoint = "litesvm";
  constructor(private svm: any) {}
  private info(pk: PublicKey) {
    const a = this.svm.getAccount(pk);
    // LiteSVM devuelve las cuentas cerradas como vacías; una RPC real devuelve null.
    if (!a || (Number(a.lamports) === 0 && a.data.length === 0)) return null;
    return {
      data: Buffer.from(a.data),
      executable: a.executable,
      lamports: Number(a.lamports),
      owner: new PublicKey(a.owner),
      rentEpoch: 0,
    };
  }
  private ctx() {
    return { slot: Number(this.svm.getClock().slot) };
  }
  async getAccountInfo(pk: PublicKey) {
    return this.info(pk);
  }
  async getAccountInfoAndContext(pk: PublicKey) {
    return { context: this.ctx(), value: this.info(pk) };
  }
  async getMultipleAccountsInfo(pks: PublicKey[]) {
    return pks.map((p) => this.info(p));
  }
  async getMultipleAccountsInfoAndContext(pks: PublicKey[]) {
    return { context: this.ctx(), value: pks.map((p) => this.info(p)) };
  }
  async getSlot() {
    return Number(this.svm.getClock().slot);
  }
  async getBlockTime() {
    return Number(this.svm.getClock().unixTimestamp);
  }
  async getBalance(pk: PublicKey) {
    return Number(this.svm.getBalance(pk) ?? 0n);
  }
  async getLatestBlockhash() {
    return { blockhash: this.svm.latestBlockhash(), lastValidBlockHeight: 1_000_000_000 };
  }
  async getMinimumBalanceForRentExemption(n: number) {
    return Number(this.svm.minimumBalanceForRentExemption(BigInt(n)));
  }
  async getTokenAccountBalance(pk: PublicKey) {
    const a = this.info(pk);
    const amount = a ? Buffer.from(a.data).readBigUInt64LE(64) : 0n;
    return { context: this.ctx(), value: { amount: amount.toString(), decimals: 9, uiAmount: Number(amount) / 1e9 } };
  }
}

/** Carga el IDL compilado (solo Node). */
export function loadIdl(path = "target/idl/owncurve.json") {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}
OWNCURVE_EOF

mkdir -p 'scripts/lib'
cat > 'scripts/lib/owncurve.ts' <<'OWNCURVE_EOF'
// Cliente de OwnCurve: todas las operaciones del ciclo de vida de un raise.
// Lo usan el script de devnet (scripts/f1.ts) y los tests (tests/owncurve.test.ts).
import { AnchorProvider, BN, Program, Wallet } from "@anchor-lang/core";
import {
  ActivationType,
  BaseFeeMode,
  CollectFeeMode,
  DAMM_V2_MIGRATION_FEE_ADDRESS,
  DammV2DynamicFeeMode,
  DynamicBondingCurveClient,
  MigratedCollectFeeMode,
  MigrationFeeOption,
  MigrationOption,
  SwapMode,
  TokenAuthorityOption,
  TokenDecimal,
  TokenType,
  buildCurve,
  createDammV2Program,
  deriveDammV2EventAuthority,
  deriveDammV2PoolAddress,
  deriveDammV2PoolAuthority,
  deriveDammV2TokenVaultAddress,
  deriveDbcEventAuthority,
  deriveDbcPoolAddress,
  deriveDbcPoolAuthority,
  getCurrentPoint,
} from "@meteora-ag/dynamic-bonding-curve-sdk";
import {
  NATIVE_MINT,
  TOKEN_2022_PROGRAM_ID,
  TOKEN_PROGRAM_ID,
  createAssociatedTokenAccountIdempotentInstruction,
  createSyncNativeInstruction,
  createTransferCheckedInstruction,
  getAssociatedTokenAddressSync,
} from "@solana/spl-token";
import { Keypair, PublicKey, SystemProgram, TransactionInstruction } from "@solana/web3.js";
import { createLocalDammV2Config } from "./local-damm";
import type { Net } from "./net";

export const DBC = new PublicKey("dbcij3LWUppWqq96dh6gJWwBifmcGfLSB5D4DuSMaqN");
export const DAMM_V2 = new PublicKey("cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG");
export const BASE_DECIMALS = 6;

export type RaiseParams = {
  thresholdSol: number;
  treasuryPct: number; // % de lo recaudado que va a la tesorería (migration fee)
  tranchesBps: number[];
  challengeSecs: number;
  quorumBps: number;
  // Solo para tests de seguridad: configs DBC "maliciosas".
  feeClaimer?: PublicKey;
  creatorMigrationFeePct?: number;
  creatorUnlockedLpPct?: number;
};

export const DEFAULT_PARAMS: RaiseParams = {
  thresholdSol: 0.5,
  treasuryPct: 80,
  tranchesBps: [3000, 3000, 4000],
  challengeSecs: 60,
  quorumBps: 1000,
};

export const ps = (p: any) => p.poolState ?? p; // SDK ≥1.5.8 anida el estado del pool
export const stateName = (s: any) => Object.keys(s)[0];

export function curveConfig(p: RaiseParams) {
  // Con t% a la tesorería, solo (100−t)% de lo recaudado entra al pool: el % de suministro
  // que migra debe ser s < (1−t)(1−s) para que el precio de graduación quede por encima
  // de la curva. Para t=80 ⇒ s < 16,7%. Usamos la mitad del límite.
  const r = 1 - p.treasuryPct / 100;
  const supplyPct = Math.max(1, Math.floor(((r / (1 + r)) * 100) / 2));
  return buildCurve({
    token: {
      tokenType: TokenType.Token2022,
      tokenBaseDecimal: TokenDecimal.SIX,
      tokenQuoteDecimal: TokenDecimal.NINE,
      tokenAuthorityOption: TokenAuthorityOption.Immutable,
      totalTokenSupply: 1_000_000_000,
      leftover: 0,
    },
    fee: {
      baseFeeParams: {
        baseFeeMode: BaseFeeMode.FeeSchedulerLinear,
        feeSchedulerParam: { startingFeeBps: 100, endingFeeBps: 100, numberOfPeriod: 0, totalDuration: 0 },
      },
      dynamicFeeEnabled: false,
      collectFeeMode: CollectFeeMode.QuoteToken,
      creatorTradingFeePercentage: 0,
      poolCreationFee: 0,
      enableFirstSwapWithMinFee: false,
    },
    migration: {
      migrationOption: MigrationOption.MET_DAMM_V2,
      migrationFeeOption: MigrationFeeOption.Customizable,
      migrationFee: { feePercentage: p.treasuryPct, creatorFeePercentage: p.creatorMigrationFeePct ?? 0 },
      migratedPoolFee: {
        collectFeeMode: MigratedCollectFeeMode.QuoteToken,
        dynamicFee: DammV2DynamicFeeMode.Disabled,
        poolFeeBps: 100,
      },
    },
    // El LP graduado queda 100% bloqueado a nombre del partner = la tesorería.
    liquidityDistribution: {
      partnerPermanentLockedLiquidityPercentage: 100 - (p.creatorUnlockedLpPct ?? 0),
      partnerLiquidityPercentage: 0,
      creatorPermanentLockedLiquidityPercentage: 0,
      creatorLiquidityPercentage: p.creatorUnlockedLpPct ?? 0,
    },
    lockedVesting: {
      totalLockedVestingAmount: 0,
      numberOfVestingPeriod: 0,
      cliffUnlockAmount: 0,
      totalVestingDuration: 0,
      cliffDurationFromMigrationTime: 0,
    },
    activationType: ActivationType.Timestamp,
    percentageSupplyOnMigration: supplyPct,
    migrationQuoteThreshold: p.thresholdSol,
  });
}

export class Raise {
  constructor(
    readonly oc: OwnCurve,
    readonly config: PublicKey,
    readonly baseMint: PublicKey,
  ) {}
  get pid() {
    return this.oc.programId;
  }
  get raise() {
    return PublicKey.findProgramAddressSync([Buffer.from("raise"), this.config.toBuffer()], this.pid)[0];
  }
  get treasury() {
    return PublicKey.findProgramAddressSync([Buffer.from("treasury"), this.config.toBuffer()], this.pid)[0];
  }
  get escrow() {
    return PublicKey.findProgramAddressSync([Buffer.from("escrow"), this.raise.toBuffer()], this.pid)[0];
  }
  get pool() {
    return deriveDbcPoolAddress(NATIVE_MINT, this.baseMint, this.config);
  }
  get treasuryQuote() {
    return getAssociatedTokenAddressSync(NATIVE_MINT, this.treasury, true);
  }
  get treasuryBase() {
    return getAssociatedTokenAddressSync(this.baseMint, this.treasury, true, TOKEN_2022_PROGRAM_ID);
  }
  get escrowBase() {
    return getAssociatedTokenAddressSync(this.baseMint, this.escrow, true, TOKEN_2022_PROGRAM_ID);
  }
  baseAta(owner: PublicKey) {
    return getAssociatedTokenAddressSync(this.baseMint, owner, true, TOKEN_2022_PROGRAM_ID);
  }
  quoteAta(owner: PublicKey) {
    return getAssociatedTokenAddressSync(NATIVE_MINT, owner, true);
  }
  voteRecord(voter: PublicKey, nonce: number) {
    return PublicKey.findProgramAddressSync(
      [Buffer.from("vote"), this.raise.toBuffer(), voter.toBuffer(), new BN(nonce).toArrayLike(Buffer, "le", 4)],
      this.pid,
    )[0];
  }
  async fetch(): Promise<any> {
    return (this.oc.program.account as any).raise.fetch(this.raise);
  }
  async fetchNullable(): Promise<any> {
    return (this.oc.program.account as any).raise.fetchNullable(this.raise);
  }
  async state(): Promise<string> {
    return stateName((await this.fetch()).state);
  }
}

export class OwnCurve {
  readonly program: Program<any>;
  readonly dbc: DynamicBondingCurveClient;
  readonly programId: PublicKey;

  constructor(readonly net: Net, idl: any) {
    this.programId = new PublicKey(idl.address);
    // Solo construimos instrucciones (nunca .rpc()), así que el "wallet" del provider
    // no firma nada: basta con la clave pública. Funciona igual en Node y en el navegador.
    const wallet = {
      publicKey: net.payer.publicKey,
      signTransaction: async (t: any) => t,
      signAllTransactions: async (t: any) => t,
    } as unknown as Wallet;
    const provider = new AnchorProvider(net.conn, wallet, { commitment: "confirmed" });
    this.program = new Program(idl, provider) as Program<any>;
    this.dbc = new DynamicBondingCurveClient(net.conn, "confirmed");
  }
  get payer() {
    return this.net.payer.publicKey;
  }
  get m() {
    return this.program.methods as any;
  }

  // ---------------------------------------------------------------- creación
  /** init_raise + create_config de DBC en UNA transacción. */
  async createRaise(params: RaiseParams, configKp = Keypair.generate(), team = this.net.payer) {
    const r = new Raise(this, configKp.publicKey, PublicKey.default);
    const initRaise = await this.m
      .initRaise({
        minTreasuryPct: params.treasuryPct,
        trancheBps: params.tranchesBps,
        challengeWindow: new BN(params.challengeSecs),
        rejectQuorumBps: params.quorumBps,
      })
      .accountsStrict({
        team: team.publicKey,
        dbcConfig: configKp.publicKey,
        raise: r.raise,
        treasury: r.treasury,
        systemProgram: SystemProgram.programId,
      })
      .instruction();
    const createConfig = await this.dbc.partner.createConfig({
      config: configKp.publicKey,
      feeClaimer: params.feeClaimer ?? r.treasury,
      leftoverReceiver: r.treasury,
      payer: this.payer,
      quoteMint: NATIVE_MINT,
      ...curveConfig(params),
    });
    const sig = await this.net.send("init_raise + create_config", [initRaise, ...createConfig.instructions], [
      configKp,
      team,
    ]);
    return { sig, configKp };
  }

  /** create_pool de DBC + bind_pool en UNA transacción: el launch nace validado. */
  async launchPool(
    config: PublicKey,
    baseMintKp = Keypair.generate(),
    team = this.net.payer,
    withPool = true,
    meta: { name: string; symbol: string; uri: string } = {
      name: "OwnCurve Demo",
      symbol: "OWND",
      uri: "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json",
    },
  ) {
    const r = new Raise(this, config, baseMintKp.publicKey);
    const ixs: TransactionInstruction[] = [];
    if (withPool && !(await this.net.conn.getAccountInfo(r.pool))) {
      const createPool = await this.dbc.creator.createPool({
        baseMint: baseMintKp.publicKey,
        config,
        ...meta,
        payer: this.payer,
        poolCreator: team.publicKey,
      });
      ixs.push(...createPool.instructions);
    }
    ixs.push(
      await this.m
        .bindPool()
        .accountsStrict({ raise: r.raise, treasury: r.treasury, dbcConfig: config, dbcPool: r.pool })
        .instruction(),
    );
    const sig = await this.net.send("create_pool + bind_pool", ixs, ixs.length > 1 ? [baseMintKp, team] : []);
    return { sig, raise: r };
  }

  // ---------------------------------------------------------------- curva
  /** Compra en la curva con `lamportsIn` de SOL. PartialFill nunca pasa del umbral;
   *  ExactIn puede pasarse y deja un excedente ("surplus") en el pool. */
  async buy(r: Raise, lamportsIn: BN, buyer = this.net.payer, mode: SwapMode.PartialFill | SwapMode.ExactIn = SwapMode.PartialFill) {
    const cfg = await this.dbc.state.getPoolConfig(r.config);
    const pool = await this.dbc.state.getPool(r.pool);
    const quote = this.dbc.pool.swapQuote2({
      virtualPool: pool as any,
      config: cfg!,
      swapBaseForQuote: false,
      hasReferral: false,
      eligibleForFirstSwapWithMinFee: false,
      currentPoint: await getCurrentPoint(this.net.conn, cfg!.activationType),
      slippageBps: 500,
      swapMode: mode,
      amountIn: lamportsIn,
    });
    const swap = await this.dbc.pool.swap2({
      owner: buyer.publicKey,
      pool: r.pool,
      swapBaseForQuote: false,
      referralTokenAccount: null,
      payer: buyer.publicKey,
      swapMode: mode,
      amountIn: lamportsIn,
      minimumAmountOut: quote.minimumAmountOut ?? new BN(0),
    });
    return this.net.send("compra en la curva", swap.instructions, [buyer]);
  }

  async curve(r: Raise) {
    const cfg = await this.dbc.state.getPoolConfig(r.config);
    const pool = ps(await this.dbc.state.getPool(r.pool));
    const threshold = new BN(cfg!.migrationQuoteThreshold.toString());
    const reserve = new BN(pool.quoteReserve.toString());
    return { cfg: cfg!, pool, threshold, reserve, complete: reserve.gte(threshold) };
  }

  async buyToComplete(r: Raise, buyer = this.net.payer) {
    const sigs: string[] = [];
    for (let i = 0; i < 8; i++) {
      const c = await this.curve(r);
      if (c.complete) return sigs;
      const remaining = c.threshold.sub(c.reserve);
      sigs.push(await this.buy(r, remaining.muln(103).divn(100).addn(10_000), buyer));
    }
    throw new Error("La curva no se completó tras 8 compras");
  }

  // ---------------------------------------------------------------- tesorería
  private dbcAccounts(r: Raise, pool: any) {
    return {
      dbcPoolAuthority: deriveDbcPoolAuthority(),
      dbcConfig: r.config,
      dbcPool: r.pool,
      dbcQuoteVault: pool.quoteVault,
      dbcEventAuthority: deriveDbcEventAuthority(),
      dbcProgram: DBC,
    };
  }

  private ensureTreasuryAtas(r: Raise) {
    return [
      createAssociatedTokenAccountIdempotentInstruction(this.payer, r.treasuryQuote, r.treasury, NATIVE_MINT),
      createAssociatedTokenAccountIdempotentInstruction(
        this.payer,
        r.treasuryBase,
        r.treasury,
        r.baseMint,
        TOKEN_2022_PROGRAM_ID,
      ),
    ];
  }

  async harvest(r: Raise) {
    const { pool } = await this.curve(r);
    const ix = await this.m
      .harvest()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        quoteMint: NATIVE_MINT,
        ...this.dbcAccounts(r, pool),
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send("harvest", [...this.ensureTreasuryAtas(r), ix], []);
  }

  async collectTradingFees(r: Raise) {
    const { pool } = await this.curve(r);
    const ix = await this.m
      .collectTradingFees()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryBase: r.treasuryBase,
        treasuryQuote: r.treasuryQuote,
        baseMint: r.baseMint,
        quoteMint: NATIVE_MINT,
        ...this.dbcAccounts(r, pool),
        dbcBaseVault: pool.baseVault,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send("collect_trading_fees", [...this.ensureTreasuryAtas(r), ix], []);
  }

  async collectSurplus(r: Raise) {
    const { pool } = await this.curve(r);
    const ix = await this.m
      .collectSurplus()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        quoteMint: NATIVE_MINT,
        ...this.dbcAccounts(r, pool),
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send("collect_surplus", [ix], []);
  }

  // ---------------------------------------------------------------- DAMM v2
  async dammConfig(): Promise<PublicKey> {
    return this.net.cluster === "local"
      ? createLocalDammV2Config(this.net)
      : DAMM_V2_MIGRATION_FEE_ADDRESS[MigrationFeeOption.Customizable];
  }

  async dammPool(r: Raise) {
    return deriveDammV2PoolAddress(await this.dammConfig(), r.baseMint, NATIVE_MINT);
  }

  async migrate(r: Raise) {
    const m = await this.dbc.migration.migrateToDammV2({
      payer: this.payer,
      pool: r.pool,
      dammConfig: await this.dammConfig(),
    });
    const sig = await this.net.send("migrate_damm_v2", m.transaction.instructions, [
      m.firstPositionNftKeypair,
      m.secondPositionNftKeypair,
    ]);
    return { sig, nftMints: [m.firstPositionNftKeypair.publicKey, m.secondPositionNftKeypair.publicKey] };
  }

  /** De las posiciones creadas al migrar, devuelve la que pertenece a la tesorería. */
  async treasuryPosition(r: Raise, nftMints: PublicKey[]) {
    for (const mint of nftMints) {
      const nftAccount = PublicKey.findProgramAddressSync([Buffer.from("position_nft_account"), mint.toBuffer()], DAMM_V2)[0];
      const info = await this.net.conn.getAccountInfo(nftAccount);
      if (info && new PublicKey(info.data.subarray(32, 64)).equals(r.treasury)) {
        const position = PublicKey.findProgramAddressSync([Buffer.from("position"), mint.toBuffer()], DAMM_V2)[0];
        return { nftMint: mint, nftAccount, position };
      }
    }
    throw new Error("Ninguna posición de DAMM v2 pertenece a la tesorería");
  }

  async claimLpFees(r: Raise, pos: { nftAccount: PublicKey; position: PublicKey }) {
    const pool = await this.dammPool(r);
    const ix = await this.m
      .claimLpFees()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryBase: r.treasuryBase,
        treasuryQuote: r.treasuryQuote,
        baseMint: r.baseMint,
        quoteMint: NATIVE_MINT,
        dammPoolAuthority: deriveDammV2PoolAuthority(),
        dammPool: pool,
        position: pos.position,
        dammBaseVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
        dammQuoteVault: deriveDammV2TokenVaultAddress(pool, NATIVE_MINT),
        positionNftAccount: pos.nftAccount,
        dammEventAuthority: deriveDammV2EventAuthority(),
        dammProgram: DAMM_V2,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send("claim_lp_fees", [...this.ensureTreasuryAtas(r), ix], []);
  }

  /** Swap SOL→token en el pool DAMM v2 graduado (genera comisiones de LP). */
  async dammBuy(r: Raise, lamportsIn: BN, buyer = this.net.payer) {
    const damm = createDammV2Program(this.net.conn) as any;
    const pool = await this.dammPool(r);
    const wsol = r.quoteAta(buyer.publicKey);
    const out = r.baseAta(buyer.publicKey);
    const ixs = [
      createAssociatedTokenAccountIdempotentInstruction(buyer.publicKey, wsol, buyer.publicKey, NATIVE_MINT),
      createAssociatedTokenAccountIdempotentInstruction(buyer.publicKey, out, buyer.publicKey, r.baseMint, TOKEN_2022_PROGRAM_ID),
      SystemProgram.transfer({ fromPubkey: buyer.publicKey, toPubkey: wsol, lamports: BigInt(lamportsIn.toString()) }),
      createSyncNativeInstruction(wsol),
      await damm.methods
        .swap({ amountIn: lamportsIn, minimumAmountOut: new BN(0) })
        .accountsPartial({
          poolAuthority: deriveDammV2PoolAuthority(),
          pool,
          inputTokenAccount: wsol,
          outputTokenAccount: out,
          tokenAVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
          tokenBVault: deriveDammV2TokenVaultAddress(pool, NATIVE_MINT),
          tokenAMint: r.baseMint,
          tokenBMint: NATIVE_MINT,
          payer: buyer.publicKey,
          tokenAProgram: TOKEN_2022_PROGRAM_ID,
          tokenBProgram: TOKEN_PROGRAM_ID,
          referralTokenAccount: null,
          eventAuthority: deriveDammV2EventAuthority(),
          program: DAMM_V2,
        })
        .instruction(),
    ];
    return this.net.send("swap en DAMM v2", ixs, [buyer]);
  }

  // ---------------------------------------------------------------- gobernanza
  async propose(r: Raise, team = this.net.payer) {
    const ix = await this.m.proposeRelease().accountsStrict({ team: team.publicKey, raise: r.raise }).instruction();
    return this.net.send("propose_release", [ix], [team]);
  }

  async reject(r: Raise, voter: Keypair, amount: BN) {
    const raise = await r.fetch();
    const ix = await this.m
      .reject(amount)
      .accountsStrict({
        voter: voter.publicKey,
        raise: r.raise,
        vote: r.voteRecord(voter.publicKey, raise.proposalNonce),
        escrow: r.escrow,
        escrowBase: r.escrowBase,
        voterBase: r.baseAta(voter.publicKey),
        baseMint: r.baseMint,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        systemProgram: SystemProgram.programId,
      })
      .instruction();
    const ata = createAssociatedTokenAccountIdempotentInstruction(
      this.payer,
      r.escrowBase,
      r.escrow,
      r.baseMint,
      TOKEN_2022_PROGRAM_ID,
    );
    return this.net.send("reject", [ata, ix], [voter]);
  }

  async finalize(r: Raise) {
    const raise = await r.fetch();
    const teamQuote = r.quoteAta(raise.team);
    const ix = await this.m
      .finalize()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        treasuryBase: r.treasuryBase,
        teamQuote,
        quoteMint: NATIVE_MINT,
        baseMint: r.baseMint,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send(
      "finalize",
      [
        ...this.ensureTreasuryAtas(r),
        createAssociatedTokenAccountIdempotentInstruction(this.payer, teamQuote, raise.team, NATIVE_MINT),
        ix,
      ],
      [],
    );
  }

  async withdrawVote(r: Raise, voter: Keypair, nonce: number) {
    const ix = await this.m
      .withdrawVote()
      .accountsStrict({
        voter: voter.publicKey,
        raise: r.raise,
        vote: r.voteRecord(voter.publicKey, nonce),
        escrow: r.escrow,
        escrowBase: r.escrowBase,
        voterBase: r.baseAta(voter.publicKey),
        baseMint: r.baseMint,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
      })
      .instruction();
    return this.net.send("withdraw_vote", [ix], [voter]);
  }

  async redeem(r: Raise, holder: Keypair, amount: BN) {
    const holderQuote = r.quoteAta(holder.publicKey);
    const ix = await this.m
      .redeem(amount)
      .accountsStrict({
        holder: holder.publicKey,
        raise: r.raise,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        treasuryBase: r.treasuryBase,
        holderBase: r.baseAta(holder.publicKey),
        holderQuote,
        baseMint: r.baseMint,
        quoteMint: NATIVE_MINT,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send(
      "redeem",
      [
        ...this.ensureTreasuryAtas(r),
        createAssociatedTokenAccountIdempotentInstruction(this.payer, holderQuote, holder.publicKey, NATIVE_MINT),
        ix,
      ],
      [holder],
    );
  }

  // ---------------------------------------------------------------- utilidades
  async tokenBalance(ata: PublicKey): Promise<BN> {
    const info = await this.net.conn.getAccountInfo(ata);
    // Cuenta inexistente o cerrada (p. ej. wSOL tras unwrap) ⇒ saldo 0.
    return info && info.data.length >= 72 ? new BN(info.data.readBigUInt64LE(64).toString()) : new BN(0);
  }

  async mintSupply(mint: PublicKey): Promise<BN> {
    const info = await this.net.conn.getAccountInfo(mint);
    return new BN(info!.data.readBigUInt64LE(36).toString());
  }

  async transferBase(r: Raise, from: Keypair, to: PublicKey, amount: BN) {
    const dst = r.baseAta(to);
    return this.net.send(
      "transferir tokens",
      [
        createAssociatedTokenAccountIdempotentInstruction(this.payer, dst, to, r.baseMint, TOKEN_2022_PROGRAM_ID),
        createTransferCheckedInstruction(
          r.baseAta(from.publicKey),
          r.baseMint,
          dst,
          from.publicKey,
          BigInt(amount.toString()),
          BASE_DECIMALS,
          [],
          TOKEN_2022_PROGRAM_ID,
        ),
      ],
      [from],
    );
  }
}
OWNCURVE_EOF

mkdir -p 'scripts/lib'
cat > 'scripts/lib/local-damm.ts' <<'OWNCURVE_EOF'
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
OWNCURVE_EOF

mkdir -p 'scripts'
cat > 'scripts/f1.ts' <<'OWNCURVE_EOF'
// F1 · Validación técnica de OwnCurve sobre Meteora DBC (devnet o LiteSVM).
//
//  1. init_raise + DBC create_config en UNA transacción (fee_claimer y leftover = tesorería PDA)
//  2. DBC create_pool + bind_pool en UNA transacción (el launch nace validado)
//  3. Compras hasta completar la curva
//  4. harvest: CPI withdraw_migration_fee firmada por la PDA → la tesorería recibe el 80%
//  5. (--migrate) migración a DAMM v2
//
// Reanudable en devnet: guarda claves y progreso en .owncurve/f1-devnet.json.
// Uso:  npx tsx scripts/f1.ts --migrate            (devnet)
//       CLUSTER=local npx tsx scripts/f1.ts --migrate   (LiteSVM con los .so reales)
import { BN } from "@anchor-lang/core";
import { Keypair, LAMPORTS_PER_SOL, PublicKey } from "@solana/web3.js";
import fs from "fs";
import { DEFAULT_PARAMS, OwnCurve, Raise, ps, stateName } from "./lib/owncurve";
import { TxError, loadIdl, makeNet } from "./lib/net";

const DO_MIGRATE = process.argv.includes("--migrate");
const PARAMS = { ...DEFAULT_PARAMS, thresholdSol: Number(process.env.THRESHOLD_SOL ?? DEFAULT_PARAMS.thresholdSol) };

type State = { programId: string; config: number[]; baseMint: number[]; sigs: Record<string, string> };

const log = (step: string, msg: string) => console.log(`  ✔ ${step.padEnd(12)} ${msg}`);
const sol = (v: number | bigint | BN) => (Number(v.toString()) / LAMPORTS_PER_SOL).toFixed(4);
const kp = (s: number[]) => Keypair.fromSecretKey(Uint8Array.from(s));

async function main() {
  const net = await makeNet();
  const oc = new OwnCurve(net, loadIdl());
  const payer = net.payer.publicKey;

  console.log(`\n  Red        : ${net.cluster}`);
  console.log(`  Programa   : ${oc.programId.toBase58()}`);
  console.log(`  Wallet     : ${payer.toBase58()} (${sol(await net.conn.getBalance(payer))} SOL)`);
  const prog = await net.conn.getAccountInfo(oc.programId);
  if (!prog?.executable) throw new Error(`El programa ${oc.programId.toBase58()} no está desplegado en ${net.cluster}`);

  // ------------------------------------------------------------ estado reanudable
  const stateFile = `.owncurve/f1-${net.cluster}.json`;
  let st: State | null = null;
  if (net.cluster === "devnet" && fs.existsSync(stateFile)) {
    st = JSON.parse(fs.readFileSync(stateFile, "utf8"));
    if (st!.programId !== oc.programId.toBase58()) st = null;
  }
  st ??= {
    programId: oc.programId.toBase58(),
    config: Array.from(Keypair.generate().secretKey),
    baseMint: Array.from(Keypair.generate().secretKey),
    sigs: {},
  };
  const save = () => {
    if (net.cluster !== "devnet") return;
    fs.mkdirSync(".owncurve", { recursive: true });
    fs.writeFileSync(stateFile, JSON.stringify(st, null, 2));
  };
  save();

  const configKp = kp(st.config);
  const baseMintKp = kp(st.baseMint);
  const r = new Raise(oc, configKp.publicKey, baseMintKp.publicKey);
  console.log(`  Config DBC : ${r.config.toBase58()}`);
  console.log(`  Tesorería  : ${r.treasury.toBase58()}\n`);

  // F1.2 raise + config DBC (atómico)
  if (!(await r.fetchNullable())) {
    st.sigs.raise = (await oc.createRaise(PARAMS, configKp)).sig;
    save();
  }
  const cfg = await oc.dbc.state.getPoolConfig(r.config);
  if (!cfg || !new PublicKey(cfg.feeClaimer).equals(r.treasury)) throw new Error("fee_claimer no es la tesorería");
  log("F1.2 config", `fee_claimer = tesorería · migration fee ${cfg.migrationFeePercentage}% · umbral ${sol(cfg.migrationQuoteThreshold)} SOL`);

  // F1.3 pool + bind_pool (atómico) y compras
  if ((await r.state()) === "pending") {
    st.sigs.pool = (await oc.launchPool(r.config, baseMintKp)).sig;
    save();
  }
  log("F1.3 pool", `${r.pool.toBase58()} · raise en estado "${await r.state()}"`);
  const buys = await oc.buyToComplete(r);
  buys.forEach((s, i) => (st!.sigs[`buy${i}`] = s));
  save();
  const c = await oc.curve(r);
  log("F1.3 curva", `completa · reserva ${sol(c.reserve)} SOL ≥ umbral ${sol(c.threshold)} SOL`);

  // F1.5 harvest
  if ((await r.state()) === "bonding") {
    st.sigs.harvest = await oc.harvest(r);
    save();
  }
  const raise = await r.fetch();
  const funded = new BN(raise.fundedAmount.toString());
  const expected = c.threshold.muln(PARAMS.treasuryPct).divn(100);
  if (stateName(raise.state) !== "funded" || !funded.eq(expected)) {
    throw new Error(`harvest no cuadra: estado=${stateName(raise.state)} funded=${funded} esperado=${expected}`);
  }
  log("F1.5 harvest", `tesorería = ${sol(funded)} SOL (${PARAMS.treasuryPct}% de ${sol(c.threshold)}) · estado "funded"`);

  // F1.4 migración (opcional)
  let migrated = Boolean(ps(await oc.dbc.state.getPool(r.pool)).isMigrated);
  if (DO_MIGRATE && !migrated) {
    try {
      st.sigs.migrate = (await oc.migrate(r)).sig;
      save();
      migrated = true;
    } catch (e: any) {
      console.log(`  ! F1.4 migración: falló (${String(e.message).slice(0, 120)})`);
      if (e instanceof TxError && e.logs) for (const l of e.logs.slice(-15)) console.log("      " + l);
      console.log(`    No bloquea F1. Alternativa: https://migrator.meteora.ag  con el pool ${r.pool.toBase58()}`);
    }
  }
  if (migrated) log("F1.4 migrar", "pool graduado a DAMM v2");
  else if (!DO_MIGRATE) console.log("  · F1.4 migrar  pendiente (ejecuta con --migrate)");

  const result = {
    cluster: net.cluster,
    programId: oc.programId.toBase58(),
    config: r.config.toBase58(),
    pool: r.pool.toBase58(),
    baseMint: r.baseMint.toBase58(),
    treasury: r.treasury.toBase58(),
    treasuryQuote: r.treasuryQuote.toBase58(),
    fundedSol: sol(funded),
    migrated,
    txs: Object.fromEntries(Object.entries(st.sigs).map(([k, v]) => [k, net.explorer(v)])),
  };
  fs.mkdirSync(".owncurve", { recursive: true });
  fs.writeFileSync(`.owncurve/f1-result-${net.cluster}.json`, JSON.stringify(result, null, 2));
  console.log(`\n  PUERTA F1 SUPERADA: la tesorería PDA cobró el migration fee por CPI.\n`);
  for (const [k, v] of Object.entries(result.txs)) console.log(`  ${k.padEnd(8)} ${v}`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(`\n  ✘ ${e.message ?? e}`);
    if (e instanceof TxError && e.logs) {
      console.error("  Logs del programa (últimas 25 líneas):");
      for (const l of e.logs.slice(-25)) console.error("    " + l);
    }
    process.exit(1);
  });
OWNCURVE_EOF

mkdir -p 'scripts'
cat > 'scripts/demo.ts' <<'OWNCURVE_EOF'
// F3 · Demo de punta a punta en devnet (o LiteSVM) con dos raises reales:
//
//  A "camino feliz":  lanzar → graduar → harvest → comisiones → migrar a DAMM v2 →
//                     comisiones de LP → los 3 tramos liberados al equipo
//  B "rechazo":       lanzar → graduar → harvest → el equipo propone → un holder bloquea
//                     con quórum → liquidación → el holder redime sus tokens por SOL
//
// Reanudable: guarda claves y progreso en .owncurve/demo-<cluster>.json.
// Resultado: .owncurve/demo-result-<cluster>.json y docs/DEMO-<cluster>.md (enlaces para jueces).
//
// Uso:  npx tsx scripts/demo.ts            (devnet)
//       CLUSTER=local npx tsx scripts/demo.ts
import { BN } from "@anchor-lang/core";
import { Keypair, LAMPORTS_PER_SOL, PublicKey } from "@solana/web3.js";
import fs from "fs";
import { TxError, loadIdl, makeNet } from "./lib/net";
import { DEFAULT_PARAMS, OwnCurve, Raise, RaiseParams, stateName } from "./lib/owncurve";

type Step = { name: string; sig?: string; note?: string };
type RaiseState = { config: number[]; baseMint: number[]; nftMints?: string[]; steps: Step[] };
type DemoState = { programId: string; voter: number[]; a: RaiseState; b: RaiseState };

const sol = (v: BN | number | bigint) => (Number(v.toString()) / LAMPORTS_PER_SOL).toFixed(4);
const kp = (s: number[]) => Keypair.fromSecretKey(Uint8Array.from(s));
const newRaiseState = (): RaiseState => ({
  config: Array.from(Keypair.generate().secretKey),
  baseMint: Array.from(Keypair.generate().secretKey),
  steps: [],
});

async function main() {
  const net = await makeNet();
  const oc = new OwnCurve(net, loadIdl());
  const payer = net.payer.publicKey;
  const prog = await net.conn.getAccountInfo(oc.programId);
  if (!prog?.executable) throw new Error(`El programa ${oc.programId.toBase58()} no está desplegado en ${net.cluster}`);

  console.log(`\n  Red      : ${net.cluster}`);
  console.log(`  Programa : ${oc.programId.toBase58()}`);
  console.log(`  Wallet   : ${payer.toBase58()} (${sol(await net.conn.getBalance(payer))} SOL)`);

  // ---------------------------------------------------------------- estado reanudable
  const file = `.owncurve/demo-${net.cluster}.json`;
  let st: DemoState | null =
    net.cluster === "devnet" && fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null;
  if (st && st.programId !== oc.programId.toBase58()) st = null;
  st ??= {
    programId: oc.programId.toBase58(),
    voter: Array.from(Keypair.generate().secretKey),
    a: newRaiseState(),
    b: newRaiseState(),
  };
  const save = () => {
    fs.mkdirSync(".owncurve", { recursive: true });
    if (net.cluster === "devnet") fs.writeFileSync(file, JSON.stringify(st, null, 2));
  };
  save();

  /** Ejecuta un paso una sola vez (aunque el script se relance) y lo registra. */
  const step = async (rs: RaiseState, name: string, fn: () => Promise<string | void>, note?: () => Promise<string>) => {
    if (rs.steps.some((s) => s.name === name)) {
      console.log(`  · ${name.padEnd(28)} (ya hecho)`);
      return;
    }
    const sig = (await fn()) || undefined;
    const n = note ? await note() : undefined;
    rs.steps.push({ name, sig, note: n });
    save();
    console.log(`  ✔ ${name.padEnd(28)} ${n ?? ""}`);
  };

  /** finalize con reintentos: el reloj de devnet puede ir unos segundos por detrás. */
  const finalizeWhenReady = async (r: Raise) => {
    for (let i = 0; i < 12; i++) {
      try {
        return await oc.finalize(r);
      } catch (e: any) {
        const text = `${e.message}\n${(e.logs ?? []).join("\n")}`;
        if (!/ChallengeWindowOpen/.test(text)) throw e;
        await net.advanceTime(5);
      }
    }
    throw new Error("La ventana de rechazo no cerró a tiempo");
  };

  // ================================================================ RAISE A
  console.log(`\n  ── Raise A · camino feliz ─────────────────────────────`);
  const pA: RaiseParams = { ...DEFAULT_PARAMS, thresholdSol: Number(process.env.THRESHOLD_A ?? 0.5) };
  const A = new Raise(oc, kp(st.a.config).publicKey, kp(st.a.baseMint).publicKey);
  await step(st.a, "A1 crear raise + config DBC", async () => (await oc.createRaise(pA, kp(st!.a.config))).sig);
  await step(st.a, "A2 lanzar pool + bind_pool", async () => (await oc.launchPool(A.config, kp(st!.a.baseMint))).sig);
  await step(st.a, "A3 comprar hasta graduar", async () => (await oc.buyToComplete(A)).at(-1), async () => {
    const c = await oc.curve(A);
    return `reserva ${sol(c.reserve)} SOL`;
  });
  await step(st.a, "A4 harvest", () => oc.harvest(A), async () => `tesorería ${sol((await A.fetch()).fundedAmount)} SOL`);
  await step(st.a, "A5 cobrar comisiones curva", () => oc.collectTradingFees(A), async () => {
    return `+${sol((await A.fetch()).feesCollected)} SOL`;
  });
  await step(st.a, "A6 migrar a DAMM v2", async () => {
    const m = await oc.migrate(A);
    st!.a.nftMints = m.nftMints.map((k) => k.toBase58());
    return m.sig;
  });
  await step(st.a, "A7 swap en DAMM v2", async () => {
    try {
      return await oc.dammBuy(A, new BN(0.02 * LAMPORTS_PER_SOL));
    } catch (e: any) {
      console.log(`    ! swap en DAMM v2 falló (${String(e.message).slice(0, 80)}); se sigue sin comisiones de LP`);
    }
  });
  await step(st.a, "A8 cobrar comisiones de LP", async () => {
    const pos = await oc.treasuryPosition(A, st!.a.nftMints!.map((s) => new PublicKey(s)));
    return oc.claimLpFees(A, pos);
  }, async () => `fees totales ${sol((await A.fetch()).feesCollected)} SOL`);
  for (let i = 1; i <= pA.tranchesBps.length; i++) {
    await step(st.a, `A9.${i} proponer tramo ${i}`, async () => {
      const raise = await A.fetch();
      const active = raise.milestones.some((m: any) => stateName(m.status) === "proposed");
      if (!active) return oc.propose(A);
    });
    await step(st.a, `A9.${i} esperar ventana (${pA.challengeSecs}s)`, async () => net.advanceTime(pA.challengeSecs));
    await step(st.a, `A9.${i} finalizar tramo ${i}`, () => finalizeWhenReady(A), async () => {
      const raise = await A.fetch();
      return `liberado ${sol(raise.releasedAmount)} / ${sol(raise.fundedAmount)} SOL`;
    });
  }
  const finalA = await A.fetch();

  // ================================================================ RAISE B
  console.log(`\n  ── Raise B · rechazo y liquidación ─────────────────────`);
  const pB: RaiseParams = { ...DEFAULT_PARAMS, thresholdSol: Number(process.env.THRESHOLD_B ?? 0.3) };
  const B = new Raise(oc, kp(st.b.config).publicKey, kp(st.b.baseMint).publicKey);
  const voter = kp(st.voter);
  await step(st.b, "B1 crear raise + config DBC", async () => (await oc.createRaise(pB, kp(st!.b.config))).sig);
  await step(st.b, "B2 lanzar pool + bind_pool", async () => (await oc.launchPool(B.config, kp(st!.b.baseMint))).sig);
  await step(st.b, "B3 comprar hasta graduar", async () => (await oc.buyToComplete(B)).at(-1));
  await step(st.b, "B4 harvest", () => oc.harvest(B), async () => `tesorería ${sol((await B.fetch()).fundedAmount)} SOL`);
  await step(st.b, "B5 fondear al holder", () => net.fund(voter.publicKey, 0.03 * LAMPORTS_PER_SOL));
  await step(st.b, "B6 holder recibe 15% del suministro", async () => {
    const circ = (await oc.mintSupply(B.baseMint)).sub(await oc.tokenBalance(B.treasuryBase));
    return oc.transferBase(B, net.payer, voter.publicKey, circ.muln(1500).divn(10_000));
  });
  await step(st.b, "B7 equipo propone tramo 1", () => oc.propose(B));
  await step(st.b, "B8 holder vota rechazo", async () => {
    const bal = await oc.tokenBalance(B.baseAta(voter.publicKey));
    return oc.reject(B, voter, bal);
  }, async () => `bloqueados ${(await B.fetch()).proposalRejectWeight.toString()} tokens (base units)`);
  await step(st.b, `B9 esperar ventana (${pB.challengeSecs}s)`, async () => net.advanceTime(pB.challengeSecs));
  await step(st.b, "B10 finalizar → liquidación", () => finalizeWhenReady(B), async () => `estado "${await B.state()}"`);
  await step(st.b, "B11 holder retira su voto", () => oc.withdrawVote(B, voter, 0));
  let redeemPaid = new BN(0);
  await step(st.b, "B12 holder redime por SOL", async () => {
    const amount = await oc.tokenBalance(B.baseAta(voter.publicKey));
    const before = await oc.tokenBalance(B.quoteAta(voter.publicKey));
    const sig = await oc.redeem(B, voter, amount);
    redeemPaid = (await oc.tokenBalance(B.quoteAta(voter.publicKey))).sub(before);
    return sig;
  }, async () => `recibió ${sol(redeemPaid)} SOL (wSOL) por sus tokens`);
  const finalB = await B.fetch();

  // ================================================================ resumen
  const link = (s?: string) => (s ? net.explorer(s) : "");
  const addr = (a: PublicKey) =>
    net.cluster === "devnet" ? `https://explorer.solana.com/address/${a.toBase58()}?cluster=devnet` : a.toBase58();
  const result = {
    cluster: net.cluster,
    programId: oc.programId.toBase58(),
    raiseA: {
      config: A.config.toBase58(),
      treasury: A.treasury.toBase58(),
      state: stateName(finalA.state),
      fundedSol: sol(finalA.fundedAmount),
      releasedSol: sol(finalA.releasedAmount),
      feesSol: sol(finalA.feesCollected),
      steps: st.a.steps.map((s) => ({ ...s, link: link(s.sig) })),
    },
    raiseB: {
      config: B.config.toBase58(),
      treasury: B.treasury.toBase58(),
      state: stateName(finalB.state),
      fundedSol: sol(finalB.fundedAmount),
      steps: st.b.steps.map((s) => ({ ...s, link: link(s.sig) })),
    },
  };
  fs.writeFileSync(`.owncurve/demo-result-${net.cluster}.json`, JSON.stringify(result, null, 2));

  const md = [
    `# OwnCurve · demo en ${net.cluster}`,
    ``,
    `Programa: [\`${oc.programId.toBase58()}\`](${addr(oc.programId)})`,
    ``,
    `## Raise A · camino feliz`,
    ``,
    `Tesorería [\`${A.treasury.toBase58()}\`](${addr(A.treasury)}) · financiado ${result.raiseA.fundedSol} SOL · liberado al equipo ${result.raiseA.releasedSol} SOL · comisiones cobradas ${result.raiseA.feesSol} SOL · estado final **${result.raiseA.state}**.`,
    ``,
    `| Paso | Resultado | Transacción |`,
    `| --- | --- | --- |`,
    ...result.raiseA.steps.filter((s) => s.sig).map((s) => `| ${s.name} | ${s.note ?? ""} | [ver](${s.link}) |`),
    ``,
    `## Raise B · rechazo y liquidación`,
    ``,
    `Tesorería [\`${B.treasury.toBase58()}\`](${addr(B.treasury)}) · financiado ${result.raiseB.fundedSol} SOL · estado final **${result.raiseB.state}**: el equipo no cobró nada y los holders redimen contra la tesorería.`,
    ``,
    `| Paso | Resultado | Transacción |`,
    `| --- | --- | --- |`,
    ...result.raiseB.steps.filter((s) => s.sig).map((s) => `| ${s.name} | ${s.note ?? ""} | [ver](${s.link}) |`),
    ``,
  ].join("\n");
  fs.mkdirSync("docs", { recursive: true });
  fs.writeFileSync(`docs/DEMO-${net.cluster}.md`, md);

  const okA = result.raiseA.state === "completed" && result.raiseA.releasedSol === result.raiseA.fundedSol;
  const okB = result.raiseB.state === "liquidating";
  if (!okA || !okB) throw new Error(`Demo incompleta: A=${result.raiseA.state} B=${result.raiseB.state}`);
  console.log(`\n  PUERTA F3 SUPERADA: ciclo completo en ${net.cluster} (A completado, B en liquidación).`);
  console.log(`  Resumen para jueces: docs/DEMO-${net.cluster}.md`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(`\n  ✘ ${e.message ?? e}`);
    if (e instanceof TxError && e.logs) {
      console.error("  Logs del programa (últimas 25 líneas):");
      for (const l of e.logs.slice(-25)) console.error("    " + l);
    }
    console.error("  Vuelve a ejecutar: el demo retoma desde el último paso completado.");
    process.exit(1);
  });
OWNCURVE_EOF

mkdir -p 'tests'
cat > 'tests/owncurve.test.ts' <<'OWNCURVE_EOF'
// F2 · Tests de integración de OwnCurve contra los binarios reales de Meteora (DBC + DAMM v2)
// en LiteSVM. Cada test arranca un validador limpio.
//
// Ejecutar:  CLUSTER=local npx tsx --test tests/owncurve.test.ts
import { BN } from "@anchor-lang/core";
import { SwapMode } from "@meteora-ag/dynamic-bonding-curve-sdk";
import { Keypair, LAMPORTS_PER_SOL } from "@solana/web3.js";
import assert from "node:assert/strict";
import { test } from "node:test";
import { loadIdl, makeNet } from "../scripts/lib/net";
import { DEFAULT_PARAMS, OwnCurve, Raise, RaiseParams, stateName } from "../scripts/lib/owncurve";

process.env.CLUSTER = "local";

// ------------------------------------------------------------------ utilidades
async function setup(params: Partial<RaiseParams> = {}) {
  const net = await makeNet();
  const oc = new OwnCurve(net, loadIdl());
  return { net, oc, p: { ...DEFAULT_PARAMS, ...params } };
}

/** Raise lanzado y validado (estado "bonding"). */
async function bondingRaise(params: Partial<RaiseParams> = {}) {
  const s = await setup(params);
  const { configKp } = await s.oc.createRaise(s.p);
  const { raise: r } = await s.oc.launchPool(configKp.publicKey);
  return { ...s, r };
}

/** Raise con la curva completa y el migration fee ya en la tesorería (estado "funded"). */
async function fundedRaise(params: Partial<RaiseParams> = {}) {
  const s = await bondingRaise(params);
  await s.oc.buyToComplete(s.r);
  await s.oc.harvest(s.r);
  return s;
}

async function expectError(p: Promise<unknown>, name: string) {
  try {
    await p;
  } catch (e: any) {
    const text = `${e.message}\n${(e.logs ?? []).join("\n")}`;
    assert.match(text, new RegExp(name), `se esperaba ${name}, llegó:\n${text.slice(-600)}`);
    return;
  }
  assert.fail(`se esperaba el error ${name} y la transacción pasó`);
}

const raiseOf = (r: Raise) => r.fetch();
const n = (v: any) => new BN(v.toString());

/** Tokens con derecho sobre la tesorería, igual que el programa: suministro − tokens de la tesorería. */
async function circulating(oc: OwnCurve, r: Raise) {
  return (await oc.mintSupply(r.baseMint)).sub(await oc.tokenBalance(r.treasuryBase));
}

// ------------------------------------------------------------------ flujo feliz
test("2.4 flujo feliz: la tesorería se financia y los 3 tramos se liberan al equipo", async () => {
  const { oc, net, r, p } = await fundedRaise();
  const funded = n((await raiseOf(r)).fundedAmount);
  assert.ok(funded.eq(new BN(p.thresholdSol * LAMPORTS_PER_SOL).muln(p.treasuryPct).divn(100)), "80% del umbral");

  const teamQuote = r.quoteAta(net.payer.publicKey);
  let paid = new BN(0);
  for (let i = 0; i < p.tranchesBps.length; i++) {
    await oc.propose(r);
    await net.advanceTime(p.challengeSecs + 1);
    const before = await oc.tokenBalance(teamQuote);
    await oc.finalize(r);
    const got = (await oc.tokenBalance(teamQuote)).sub(before);
    const isLast = i === p.tranchesBps.length - 1;
    const expected = isLast ? funded.sub(paid) : funded.muln(p.tranchesBps[i]).divn(10_000);
    assert.ok(got.eq(expected), `tramo ${i + 1}: recibido ${got} esperado ${expected}`);
    paid = paid.add(got);
  }
  const raise = await raiseOf(r);
  assert.equal(stateName(raise.state), "completed");
  assert.ok(n(raise.releasedAmount).eq(funded), "todo lo financiado fue liberado, ni un lamport más");
});

test("2.1 comisiones de trading de la curva van a la tesorería", async () => {
  const { oc, r } = await fundedRaise();
  const before = await oc.tokenBalance(r.treasuryQuote);
  await oc.collectTradingFees(r);
  const delta = (await oc.tokenBalance(r.treasuryQuote)).sub(before);
  const raise = await raiseOf(r);
  assert.ok(delta.gtn(0), "la tesorería recibió comisiones");
  assert.ok(n(raise.feesCollected).eq(delta), "fees_collected registra lo cobrado");
});

test("2.1 excedente: la curva no deja pasarse del umbral; collect_surplus cobra lo que haya, una sola vez", async () => {
  const { oc, r } = await bondingRaise();
  const c0 = await oc.curve(r);
  await oc.buy(r, c0.threshold.muln(9).divn(10)); // ~90% de la curva
  const c1 = await oc.curve(r);
  // Una compra exacta que rebasaría el umbral se rechaza: el precio no puede pasar el de graduación.
  await expectError(
    oc.buy(r, c1.threshold.sub(c1.reserve).add(c0.threshold.divn(20)), undefined, SwapMode.ExactIn),
    "Insufficient Liquidity|InsufficientLiquidity",
  );
  await oc.buyToComplete(r);
  await oc.harvest(r);
  const before = await oc.tokenBalance(r.treasuryQuote);
  await oc.collectSurplus(r);
  const delta = (await oc.tokenBalance(r.treasuryQuote)).sub(before);
  assert.ok(delta.gten(0));
  assert.ok(n((await raiseOf(r)).feesCollected).eq(delta), "fees_collected registra el excedente (0 con esta curva)");
  await expectError(oc.collectSurplus(r), "SurplusHasBeenWithdraw");
});

test("2.1 tras migrar a DAMM v2, la tesorería cobra las comisiones de su posición de LP", async () => {
  const { oc, r } = await fundedRaise();
  const { nftMints } = await oc.migrate(r);
  const pos = await oc.treasuryPosition(r, nftMints);
  await oc.dammBuy(r, new BN(0.2 * LAMPORTS_PER_SOL));
  const before = await oc.tokenBalance(r.treasuryQuote);
  await oc.claimLpFees(r, pos);
  const delta = (await oc.tokenBalance(r.treasuryQuote)).sub(before);
  assert.ok(delta.gtn(0), "comisiones de LP en SOL para la tesorería");
  assert.ok(n((await raiseOf(r)).feesCollected).eq(delta));
});

// ------------------------------------------------------------------ rechazo y liquidación
test("2.5 rechazo con quórum → liquidación → redención proporcional al NAV", async () => {
  const { oc, net, r, p } = await fundedRaise();
  const voter = Keypair.generate();
  await net.fund(voter.publicKey, LAMPORTS_PER_SOL);
  const circ = await circulating(oc, r);
  const stake = circ.muln(p.quorumBps + 500).divn(10_000); // quórum + 5%
  await oc.transferBase(r, net.payer, voter.publicKey, stake);

  await oc.propose(r);
  const nonce = (await raiseOf(r)).proposalNonce;
  await oc.reject(r, voter, stake);
  assert.ok((await oc.tokenBalance(r.baseAta(voter.publicKey))).isZero(), "tokens bloqueados en escrow");
  await net.advanceTime(p.challengeSecs + 1);
  await oc.finalize(r);
  assert.equal(stateName((await raiseOf(r)).state), "liquidating");
  assert.ok((await oc.tokenBalance(r.quoteAta(net.payer.publicKey))).isZero(), "el equipo no cobró nada");

  await oc.withdrawVote(r, voter, nonce);
  assert.ok((await oc.tokenBalance(r.baseAta(voter.publicKey))).eq(stake), "votos devueltos");

  const tq = await oc.tokenBalance(r.treasuryQuote);
  const c2 = await circulating(oc, r);
  const expected = stake.mul(tq).div(c2);
  const supplyBefore = await oc.mintSupply(r.baseMint);
  await oc.redeem(r, voter, stake);
  assert.ok((await oc.tokenBalance(r.quoteAta(voter.publicKey))).eq(expected), "pago = tokens × NAV / circulante");
  assert.ok((await oc.mintSupply(r.baseMint)).eq(supplyBefore.sub(stake)), "los tokens se queman");
});

test("2.5 un rechazo por debajo del quórum no bloquea el tramo", async () => {
  const { oc, net, r, p } = await fundedRaise();
  const voter = Keypair.generate();
  await net.fund(voter.publicKey, LAMPORTS_PER_SOL);
  const stake = (await circulating(oc, r)).muln(p.quorumBps - 200).divn(10_000);
  await oc.transferBase(r, net.payer, voter.publicKey, stake);
  await oc.propose(r);
  await oc.reject(r, voter, stake);
  await net.advanceTime(p.challengeSecs + 1);
  await oc.finalize(r);
  const raise = await raiseOf(r);
  assert.equal(stateName(raise.state), "funded");
  assert.ok(n(raise.releasedAmount).gtn(0), "el tramo 1 se liberó");
});

// ------------------------------------------------------------------ seguridad
test("2.6 bind_pool rechaza una config DBC cuyo fee_claimer no es la tesorería", async () => {
  const s = await setup();
  const { configKp } = await s.oc.createRaise({ ...s.p, feeClaimer: s.net.payer.publicKey });
  await expectError(s.oc.launchPool(configKp.publicKey), "FeeClaimerNotTreasury");
});

test("2.6 bind_pool rechaza una config que comparte el migration fee con el creador", async () => {
  const s = await setup();
  const { configKp } = await s.oc.createRaise({ ...s.p, creatorMigrationFeePct: 10 });
  await expectError(s.oc.launchPool(configKp.publicKey), "CreatorMigrationFeeNotZero");
});

test("2.6 bind_pool rechaza una config que deja LP desbloqueado al creador (rug de liquidez)", async () => {
  const s = await setup();
  const { configKp } = await s.oc.createRaise({ ...s.p, creatorUnlockedLpPct: 20 });
  await expectError(s.oc.launchPool(configKp.publicKey), "CreatorLpNotLocked");
});

test("2.6 init_raise impone límites de gobernanza: ventana ≥ 60 s, quórum ≤ 30%, tesorería ≥ 50%", async () => {
  const s = await setup();
  await expectError(s.oc.createRaise({ ...s.p, challengeSecs: 5 }), "InvalidGovernance");
  await expectError(s.oc.createRaise({ ...s.p, quorumBps: 5000 }), "InvalidGovernance");
  await expectError(s.oc.createRaise({ ...s.p, treasuryPct: 40 }), "InvalidGovernance");
});

test("2.6 nadie fuera del programa puede retirar el migration fee de DBC", async () => {
  const { oc, net, r } = await bondingRaise();
  await oc.buyToComplete(r);
  const attacker = Keypair.generate();
  await net.fund(attacker.publicKey, LAMPORTS_PER_SOL);
  const tx = await oc.dbc.partner.partnerWithdrawMigrationFee({ pool: r.pool, sender: attacker.publicKey });
  await expectError(net.send("ataque", tx.instructions, [attacker]), "NotPermitToDoThisAction");
  await oc.harvest(r); // el camino legítimo sigue funcionando
  assert.equal(stateName((await raiseOf(r)).state), "funded");
});

test("2.6 harvest no se puede ejecutar dos veces", async () => {
  const { oc, r } = await fundedRaise();
  await expectError(oc.harvest(r), "InvalidState");
});

test("2.6 harvest antes de completar la curva falla en DBC", async () => {
  const { oc, r } = await bondingRaise();
  await expectError(oc.harvest(r), "NotPermitToDoThisAction");
});

test("2.6 solo el equipo puede proponer un tramo", async () => {
  const { oc, net, r } = await fundedRaise();
  const attacker = Keypair.generate();
  await net.fund(attacker.publicKey, LAMPORTS_PER_SOL);
  await expectError(oc.propose(r, attacker), "NotTeam");
});

test("2.6 ventanas: no se finaliza antes de tiempo ni se vota fuera de plazo", async () => {
  const { oc, net, r, p } = await fundedRaise();
  await oc.propose(r);
  await expectError(oc.finalize(r), "ChallengeWindowOpen");
  await net.advanceTime(p.challengeSecs + 1);
  await expectError(oc.reject(r, net.payer, new BN(1_000_000)), "ChallengeWindowClosed");
});

test("2.6 no se puede redimir si el raise no está en liquidación", async () => {
  const { oc, net, r } = await fundedRaise();
  await expectError(oc.redeem(r, net.payer, new BN(1_000_000)), "InvalidState");
});

test("2.6 init_raise rechaza tramos que no suman 100%", async () => {
  const s = await setup();
  await expectError(s.oc.createRaise({ ...s.p, tranchesBps: [5000, 4000] }), "InvalidMilestones");
});
OWNCURVE_EOF

mkdir -p 'app'
cat > 'app/index.html' <<'OWNCURVE_EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="description" content="Token launches on Meteora DBC where the raise sits in an on-chain treasury and is paid out by milestone." />
    <title>OwnCurve</title>
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><rect width='32' height='32' rx='6' fill='%2316302E'/><path d='M6 24 C14 24 16 8 26 8' stroke='%23EDF1EA' stroke-width='3' fill='none'/></svg>" />
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
OWNCURVE_EOF

mkdir -p 'app/src'
cat > 'app/src/App.tsx' <<'OWNCURVE_EOF'
import { useEffect, useState } from "react";
import { Header } from "./components/Header";
import { Create } from "./pages/Create";
import { Home } from "./pages/Home";
import { RaisePage } from "./pages/RaisePage";
import { AccountProvider } from "./lib/wallet";

function useHashRoute() {
  const [hash, setHash] = useState(() => location.hash || "#/");
  useEffect(() => {
    const on = () => {
      setHash(location.hash || "#/");
      window.scrollTo(0, 0);
    };
    window.addEventListener("hashchange", on);
    return () => window.removeEventListener("hashchange", on);
  }, []);
  return hash;
}

export function App() {
  const hash = useHashRoute();
  const raise = hash.match(/^#\/raise\/([1-9A-HJ-NP-Za-km-z]{32,44})$/);
  return (
    <AccountProvider>
      <Header />
      {hash === "#/new" ? <Create /> : raise ? <RaisePage config={raise[1]} /> : <Home />}
      <footer className="foot">
        <p>
          OwnCurve runs on Meteora's Dynamic Bonding Curve and DAMM v2. Open source, MIT licensed. Built for the Colosseum
          Crypto World's Fair.
        </p>
      </footer>
    </AccountProvider>
  );
}
OWNCURVE_EOF

mkdir -p 'app/src/components'
cat > 'app/src/components/Guarantees.tsx' <<'OWNCURVE_EOF'
// Lo que bind_pool comprobó en cadena antes de que nadie comprara, releído en vivo de la
// config de Meteora DBC. Es la respuesta a "¿por qué no me pueden hacer un rug?".
import { PublicKey } from "@solana/web3.js";
import type { RaiseDetail } from "../lib/data";
import { explorerAddress } from "../lib/browserNet";

export function Guarantees({ d }: { d: RaiseDetail }) {
  const cfg = d.cfg;
  if (!cfg) return null;
  const treasury = d.r.treasury;
  const items: { ok: boolean; text: string }[] = [
    {
      ok: new PublicKey(cfg.feeClaimer).equals(treasury),
      text: "Only this program can move the raise: Meteora pays the migration fee to the treasury, not to a wallet.",
    },
    {
      ok: cfg.migrationFeePercentage >= d.raise.minTreasuryPct && cfg.creatorMigrationFeePercentage === 0,
      text: `${cfg.migrationFeePercentage}% of the raise goes to the treasury and 0% to the creator.`,
    },
    {
      ok: cfg.creatorLiquidityPercentage === 0 && cfg.creatorLiquidityVestingInfo.vestingPercentage === 0,
      text: "The team cannot pull liquidity after graduation: its LP share is permanently locked.",
    },
    {
      ok: cfg.tokenUpdateAuthority !== 3,
      text: "Nobody can mint more tokens.",
    },
    {
      ok: Number(d.raise.challengeWindow) >= 60 && d.raise.rejectQuorumBps <= 3000,
      text: `Every payment waits ${Number(d.raise.challengeWindow)} s for objections; ${
        d.raise.rejectQuorumBps / 100
      }% of the supply can stop it.`,
    },
  ];
  const link = explorerAddress(treasury);
  return (
    <section className="guarantees" aria-labelledby="g-title">
      <h2 id="g-title">Checked on-chain before the first buy</h2>
      <ul>
        {items.map((it) => (
          <li key={it.text} className={it.ok ? "ok" : "bad"}>
            <span className="mark" aria-hidden>
              {it.ok ? "✓" : "✕"}
            </span>
            {it.text}
          </li>
        ))}
      </ul>
      <p className="fine">
        Treasury account{" "}
        {link ? (
          <a className="addr" href={link} target="_blank" rel="noreferrer">
            {treasury.toBase58()}
          </a>
        ) : (
          <span className="addr">{treasury.toBase58()}</span>
        )}
      </p>
    </section>
  );
}
OWNCURVE_EOF

mkdir -p 'app/src/components'
cat > 'app/src/components/Header.tsx' <<'OWNCURVE_EOF'
import { useWallet } from "@solana/wallet-adapter-react";
import { WalletReadyState } from "@solana/wallet-adapter-base";
import { useEffect, useState } from "react";
import { CLUSTER, short, useAccount } from "../lib/wallet";
import { explainError } from "../lib/browserNet";

export function Header() {
  const acc = useAccount();
  const adapter = useWallet();
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  useEffect(() => {
    if (!msg) return;
    const id = setTimeout(() => setMsg(null), 6000);
    return () => clearTimeout(id);
  }, [msg]);
  const installed = adapter.wallets.filter((w) => w.readyState === WalletReadyState.Installed);

  const airdrop = async () => {
    setBusy(true);
    setMsg(null);
    try {
      await acc.requestSol();
      setMsg("1 devnet SOL added.");
    } catch (e) {
      setMsg(`The devnet faucet refused (${explainError(e)}). Try faucet.solana.com.`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <header className="masthead">
      <div className="masthead-row">
        <a href="#/" className="wordmark" aria-label="OwnCurve home">
          Own<span>Curve</span>
        </a>
        <nav className="nav">
          <a href="#/">Raises</a>
          <a href="#/new">Launch a raise</a>
        </nav>
        <div className="account">
          <span className="network" title="All transactions use this network">
            {CLUSTER === "devnet" ? "Solana devnet" : "Local validator"}
          </span>
          {acc.signer ? (
            <>
              <span className="who">
                <strong>{short(acc.signer.publicKey)}</strong>
                <span>{acc.balance === null ? "…" : `${acc.balance.toFixed(3)} SOL`}</span>
              </span>
              {acc.kind === "burner" && (
                <button className="btn quiet" onClick={airdrop} disabled={busy}>
                  {busy ? "Requesting…" : "Get 1 SOL"}
                </button>
              )}
              <button className="btn quiet" onClick={acc.disconnect}>
                Disconnect
              </button>
            </>
          ) : (
            <>
              {installed.map((w) => (
                <button key={w.adapter.name} className="btn" onClick={() => adapter.select(w.adapter.name)}>
                  Connect {w.adapter.name}
                </button>
              ))}
              <button className="btn quiet" onClick={acc.useBurner} title="A throwaway key kept in this browser">
                Use a test wallet
              </button>
            </>
          )}
        </div>
      </div>
      {msg && <p className="flash">{msg}</p>}
    </header>
  );
}
OWNCURVE_EOF

mkdir -p 'app/src/components'
cat > 'app/src/components/VaultBar.tsx' <<'OWNCURVE_EOF'
// El elemento central de la interfaz: la tesorería dibujada como una bóveda dividida en
// tramos. Liberado = tinta llena; propuesto = latón con cuenta atrás; bloqueado = guilloché.
import { BN } from "@anchor-lang/core";
import { stateName } from "../../../scripts/lib/owncurve";
import { fmtSol } from "../lib/data";
import { useNow } from "../lib/useNow";

type Props = {
  state: string;
  raise: any;
  curve: { reserve: BN; threshold: BN } | null;
  treasuryPct: number;
  clockSkew?: number;
};

export function VaultBar({ state, raise, curve, treasuryPct, clockSkew = 0 }: Props) {
  const now = useNow(clockSkew);

  if (state === "pending" || state === "bonding") {
    const pct = curve ? Math.min(100, (Number(curve.reserve.toString()) / Number(curve.threshold.toString())) * 100) : 0;
    return (
      <figure className="vault" aria-label={`Bonding curve ${pct.toFixed(0)}% filled`}>
        <div className="vault-track curve">
          <div className="vault-fill" style={{ width: `${pct}%` }} />
        </div>
        <figcaption className="vault-caption">
          <span className="big">{curve ? fmtSol(curve.reserve) : "0.000"}</span>
          <span>
            of {curve ? fmtSol(curve.threshold) : "—"} SOL raised on the curve. At graduation {treasuryPct}% moves into
            the treasury.
          </span>
        </figcaption>
      </figure>
    );
  }

  const funded = new BN(raise.fundedAmount.toString());
  const count = Number(raise.milestoneCount);
  const ms = raise.milestones.slice(0, count) as any[];
  let paidSoFar = new BN(0);
  const segments = ms.map((m, i) => {
    const isLast = i === count - 1;
    const amount = isLast
      ? funded.sub(ms.slice(0, i).reduce((a, x) => a.add(funded.muln(x.trancheBps).divn(10_000)), new BN(0)))
      : funded.muln(m.trancheBps).divn(10_000);
    const status = stateName(m.status);
    paidSoFar = status === "released" ? paidSoFar.add(amount) : paidSoFar;
    return { i, bps: m.trancheBps as number, amount, status };
  });
  const endsAt = Number(raise.proposalEndsAt.toString());
  const left = Math.max(0, endsAt - now);

  return (
    <figure className={`vault ${state}`} aria-label="Treasury tranches">
      <div className="vault-track">
        {segments.map((s) => (
          <div
            key={s.i}
            className={`seg ${state === "liquidating" && s.status !== "released" ? "returned" : s.status}`}
            style={{ flexGrow: s.bps }}
          />
        ))}
      </div>
      <ol className="seg-labels">
        {segments.map((s) => (
          <li key={s.i} style={{ flexGrow: s.bps }}>
            <span className="amt">{fmtSol(s.amount)} SOL</span>
            <span className="what">
              Tranche {s.i + 1}, {s.bps / 100}%:{" "}
              {state === "liquidating" && s.status !== "released"
                ? "back to holders"
                : s.status === "released"
                  ? "paid to team"
                  : s.status === "proposed"
                    ? left > 0
                      ? `objections close in ${fmtLeft(left)}`
                      : "ready to settle"
                    : "locked"}
            </span>
          </li>
        ))}
      </ol>
    </figure>
  );
}

export function fmtLeft(secs: number) {
  const m = Math.floor(secs / 60);
  const s = Math.floor(secs % 60);
  return m > 0 ? `${m} min ${s.toString().padStart(2, "0")} s` : `${s} s`;
}
OWNCURVE_EOF

mkdir -p 'app/src/lib'
cat > 'app/src/lib/browserNet.ts' <<'OWNCURVE_EOF'
// Red para el navegador: misma interfaz `Net` que usan los scripts, pero firmando con la
// wallet del usuario (Phantom, Solflare…) o con una wallet desechable de devnet.
import {
  ComputeBudgetProgram,
  Connection,
  Keypair,
  PublicKey,
  SendTransactionError,
  SystemProgram,
  Transaction,
  TransactionInstruction,
} from "@solana/web3.js";
import type { Net } from "../../../scripts/lib/net";

export type TxSigner = {
  publicKey: PublicKey;
  signTransaction: (tx: Transaction) => Promise<Transaction>;
};

export class TxFailed extends Error {
  constructor(public label: string, message: string, public logs?: string[]) {
    super(message);
  }
}

export const CLUSTER = (import.meta.env.VITE_CLUSTER ?? "devnet") as "devnet" | "local";
export const RPC_URL = import.meta.env.VITE_RPC_URL ?? "https://api.devnet.solana.com";

export function explorerTx(sig: string) {
  return CLUSTER === "devnet" ? `https://explorer.solana.com/tx/${sig}?cluster=devnet` : "";
}
export function explorerAddress(a: PublicKey | string) {
  const s = typeof a === "string" ? a : a.toBase58();
  return CLUSTER === "devnet" ? `https://explorer.solana.com/address/${s}?cluster=devnet` : "";
}

function withBudget(ixs: TransactionInstruction[]) {
  const present = new Set(
    ixs.filter((ix) => ix.programId.equals(ComputeBudgetProgram.programId)).map((ix) => ix.data[0]),
  );
  const budget = [
    ComputeBudgetProgram.setComputeUnitLimit({ units: 1_200_000 }),
    ComputeBudgetProgram.setComputeUnitPrice({ microLamports: CLUSTER === "devnet" ? 20_000 : 0 }),
  ];
  return [...budget.filter((ix) => !present.has(ix.data[0])), ...ixs];
}

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

export async function confirm(conn: Connection, sig: string, label: string) {
  const until = Date.now() + 90_000;
  while (Date.now() < until) {
    const { value } = await conn.getSignatureStatuses([sig]);
    const st = value[0];
    if (st?.err) throw new TxFailed(label, `Transaction failed: ${JSON.stringify(st.err)}`);
    if (st && (st.confirmationStatus === "confirmed" || st.confirmationStatus === "finalized")) return;
    await sleep(1200);
  }
  throw new TxFailed(label, "The network did not confirm the transaction in 90 seconds. Check your wallet history.");
}

export function makeBrowserNet(conn: Connection, signer: TxSigner): Net {
  const wallet = signer.publicKey;
  const send = async (label: string, ixs: TransactionInstruction[], signers: Keypair[]) => {
    const tx = new Transaction().add(...withBudget(ixs));
    tx.feePayer = wallet;
    tx.recentBlockhash = (await conn.getLatestBlockhash("confirmed")).blockhash;
    // Claves generadas por la app (config DBC, mint, NFTs de posición) firman aquí;
    // la wallet del usuario firma después.
    const extra = signers.filter((k) => k.secretKey && !k.publicKey.equals(wallet));
    if (extra.length) tx.partialSign(...extra);
    const signed = await signer.signTransaction(tx);
    let sig: string;
    try {
      sig = await conn.sendRawTransaction(signed.serialize(), { skipPreflight: false, preflightCommitment: "confirmed" });
    } catch (e: any) {
      const logs = e instanceof SendTransactionError ? (e.logs ?? undefined) : e?.logs;
      throw new TxFailed(label, String(e?.message ?? e), logs);
    }
    await confirm(conn, sig, label);
    return sig;
  };
  return {
    cluster: CLUSTER,
    conn,
    payer: { publicKey: wallet } as unknown as Keypair,
    send,
    explorer: explorerTx,
    advanceTime: (secs) => sleep(secs * 1000),
    fund: async (to, lamports) => {
      await send("Fund", [SystemProgram.transfer({ fromPubkey: wallet, toPubkey: to, lamports })], []);
    },
  };
}

// Mensajes legibles para los errores del programa y de Meteora.
const FRIENDLY: Record<string, string> = {
  ChallengeWindowOpen: "Holders still have time to object. Settle the tranche when the countdown ends.",
  ChallengeWindowClosed: "The objection window for this tranche has closed.",
  NotTeam: "Only the team that created this raise can propose a tranche.",
  InvalidState: "That action is not available at this stage of the raise.",
  ProposalActive: "A tranche is already waiting for holders. Settle it first.",
  NoActiveProposal: "There is no tranche waiting for holders right now.",
  VoteStillLocked: "Your tokens unlock once the tranche is settled.",
  InvalidGovernance: "Use at least 50% to the treasury, a window of 60 s or more and a quorum of 30% or less.",
  InvalidMilestones: "Tranches must add up to 100%, with 1 to 5 tranches.",
  NotPermitToDoThisAction: "Meteora refused the action: the curve has not graduated yet.",
  InsufficientFundsForRent: "Your wallet does not have enough SOL for this transaction.",
};

export function explainError(e: any): string {
  const text = `${e?.message ?? e}\n${(e?.logs ?? []).join("\n")}`;
  const code = text.match(/Error Code: (\w+)/)?.[1];
  if (code && FRIENDLY[code]) return FRIENDLY[code];
  if (/User rejected|rejected the request/i.test(text)) return "You cancelled the signature in your wallet.";
  if (/insufficient (funds|lamports)|Attempt to debit an account but found no record/i.test(text))
    return "Your wallet does not have enough SOL for this transaction.";
  if (/Insufficient Liquidity/i.test(text)) return "That buy is larger than what is left on the curve.";
  if (code) return `The program rejected the transaction (${code}).`;
  return String(e?.message ?? e).slice(0, 220);
}
OWNCURVE_EOF

mkdir -p 'app/src/lib'
cat > 'app/src/lib/data.ts' <<'OWNCURVE_EOF'
import { BN } from "@anchor-lang/core";
import { TOKEN_2022_PROGRAM_ID, getTokenMetadata } from "@solana/spl-token";
import { Connection, Keypair, LAMPORTS_PER_SOL, PublicKey } from "@solana/web3.js";
import { useCallback, useEffect, useRef, useState } from "react";
import idl from "../../../target/idl/owncurve.json";
import type { Net } from "../../../scripts/lib/net";
import { BASE_DECIMALS, OwnCurve, Raise, ps, stateName } from "../../../scripts/lib/owncurve";
import { CLUSTER } from "./browserNet";

export const IDL = idl as any;
export const PROGRAM_ID = new PublicKey(IDL.address);

/** Cliente de solo lectura (sin wallet): para listar y mostrar raises. */
export function readOnlyClient(conn: Connection) {
  const net: Net = {
    cluster: CLUSTER,
    conn,
    payer: { publicKey: PublicKey.default } as unknown as Keypair,
    send: async () => {
      throw new Error("Connect a wallet first");
    },
    explorer: (s) => s,
    advanceTime: async () => {},
    fund: async () => {},
  };
  return new OwnCurve(net, IDL);
}

export const lamportsToSol = (v: BN | number | bigint) => Number(v.toString()) / LAMPORTS_PER_SOL;
export const fmtSol = (v: BN | number | bigint, digits = 3) =>
  lamportsToSol(v).toLocaleString("en-US", { minimumFractionDigits: digits, maximumFractionDigits: digits });
export const fmtTokens = (v: BN) =>
  (Number(v.toString()) / 10 ** BASE_DECIMALS).toLocaleString("en-US", { maximumFractionDigits: 0 });

const DEFAULT = PublicKey.default;

async function tokenMeta(conn: Connection, mint: PublicKey) {
  try {
    const m = await getTokenMetadata(conn, mint, "confirmed", TOKEN_2022_PROGRAM_ID);
    if (m) return { name: m.name, symbol: m.symbol };
  } catch {
    /* sin metadata */
  }
  return { name: "Unnamed token", symbol: "?" };
}

export type RaiseRow = {
  config: string;
  name: string;
  symbol: string;
  state: string;
  treasurySol: number;
  progress: number | null; // 0..1 mientras está en la curva
  fundedSol: number;
};

export async function listRaises(oc: OwnCurve): Promise<RaiseRow[]> {
  // Solo cuentas con el tamaño actual: los raises creados por versiones anteriores del
  // programa (p. ej. el de la F1 en devnet) tienen otro tamaño y no se pueden decodificar.
  const client = (oc.program.account as any).raise;
  const all: { publicKey: PublicKey; account: any }[] = await client.all([{ dataSize: client.size }]);
  const rows = await Promise.all(
    all.map(async ({ account }) => {
      const config = new PublicKey(account.dbcConfig);
      const baseMint = new PublicKey(account.baseMint);
      const r = new Raise(oc, config, baseMint);
      const state = stateName(account.state);
      const bound = !baseMint.equals(DEFAULT);
      const meta = bound ? await tokenMeta(oc.net.conn, baseMint) : { name: "Not launched yet", symbol: "—" };
      let progress: number | null = null;
      if (state === "bonding") {
        try {
          const c = await oc.curve(r);
          progress = Math.min(1, lamportsToSol(c.reserve) / lamportsToSol(c.threshold));
        } catch {
          progress = 0;
        }
      }
      const treasury = bound ? await oc.tokenBalance(r.treasuryQuote) : new BN(0);
      return {
        config: config.toBase58(),
        ...meta,
        state,
        treasurySol: lamportsToSol(treasury),
        progress,
        fundedSol: lamportsToSol(account.fundedAmount),
      };
    }),
  );
  const order = ["bonding", "funded", "liquidating", "completed", "pending"];
  return rows.sort((a, b) => order.indexOf(a.state) - order.indexOf(b.state) || b.fundedSol - a.fundedSol);
}

export type Vote = { nonce: number; amount: BN };

export type RaiseDetail = {
  r: Raise;
  raise: any;
  state: string;
  name: string;
  symbol: string;
  team: PublicKey;
  curve: { reserve: BN; threshold: BN; complete: boolean; migrated: boolean } | null;
  cfg: any | null;
  treasuryQuote: BN;
  circulating: BN;
  navPerMillion: number; // SOL que recibe quien redime 1.000.000 tokens
  proposal: { milestone: number; endsAt: number; rejectWeight: BN; quorum: BN } | null;
  user: { base: BN; sol: number; votes: Vote[] } | null;
  /** Segundos que el reloj de la cadena va por delante (+) o por detrás (−) del navegador. */
  clockSkew: number;
};

export async function loadRaise(oc: OwnCurve, config: PublicKey, user: PublicKey | null): Promise<RaiseDetail> {
  const raisePda = PublicKey.findProgramAddressSync([Buffer.from("raise"), config.toBuffer()], oc.programId)[0];
  const raise = await (oc.program.account as any).raise.fetch(raisePda);
  const baseMint = new PublicKey(raise.baseMint);
  const r = new Raise(oc, config, baseMint);
  const state = stateName(raise.state);
  const bound = !baseMint.equals(DEFAULT);
  const meta = bound ? await tokenMeta(oc.net.conn, baseMint) : { name: "Not launched yet", symbol: "—" };
  const cfg = await oc.dbc.state.getPoolConfig(config).catch(() => null);

  let curve: RaiseDetail["curve"] = null;
  let circulating = new BN(0);
  let treasuryQuote = new BN(0);
  if (bound) {
    const pool = await oc.dbc.state.getPool(r.pool).catch(() => null);
    if (pool && cfg) {
      const p = ps(pool);
      const threshold = new BN(cfg.migrationQuoteThreshold.toString());
      const reserve = new BN(p.quoteReserve.toString());
      curve = { reserve, threshold, complete: reserve.gte(threshold), migrated: Boolean(p.isMigrated) };
    }
    treasuryQuote = await oc.tokenBalance(r.treasuryQuote);
    circulating = (await oc.mintSupply(baseMint)).sub(await oc.tokenBalance(r.treasuryBase));
  }
  const navPerMillion = circulating.isZero()
    ? 0
    : (lamportsToSol(treasuryQuote) * 1_000_000 * 10 ** BASE_DECIMALS) / Number(circulating.toString());

  const active = raise.milestones.findIndex((m: any) => stateName(m.status) === "proposed");
  const proposal =
    state === "funded" && active >= 0
      ? {
          milestone: active,
          endsAt: Number(raise.proposalEndsAt.toString()),
          rejectWeight: new BN(raise.proposalRejectWeight.toString()),
          quorum: circulating.muln(raise.rejectQuorumBps).divn(10_000),
        }
      : null;

  let userInfo: RaiseDetail["user"] = null;
  if (user && bound) {
    const base = await oc.tokenBalance(r.baseAta(user));
    const sol = (await oc.net.conn.getBalance(user)) / LAMPORTS_PER_SOL;
    const nonces = Array.from({ length: Number(raise.proposalNonce) + 1 }, (_, i) => i);
    const infos = await oc.net.conn.getMultipleAccountsInfo(nonces.map((n) => r.voteRecord(user, n)));
    const votes: Vote[] = [];
    infos.forEach((info, i) => {
      if (!info) return;
      const v = oc.program.coder.accounts.decode("voteRecord", info.data);
      votes.push({ nonce: nonces[i], amount: new BN(v.amount.toString()) });
    });
    userInfo = { base, sol, votes };
  }

  let clockSkew = 0;
  try {
    const t = await oc.net.conn.getBlockTime(await oc.net.conn.getSlot());
    if (t) clockSkew = t - Math.floor(Date.now() / 1000);
  } catch {
    /* sin hora de la cadena: usamos la del navegador */
  }

  return {
    r,
    raise,
    state,
    clockSkew,
    ...meta,
    team: new PublicKey(raise.team),
    curve,
    cfg,
    treasuryQuote,
    circulating,
    navPerMillion,
    proposal,
    user: userInfo,
  };
}

/** Lee `fn` al montar y cada `ms` milisegundos; `reload` fuerza una lectura inmediata. */
export function usePoll<T>(fn: () => Promise<T>, deps: unknown[], ms = 6000) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const fnRef = useRef(fn);
  fnRef.current = fn;
  const reload = useCallback(() => {
    fnRef
      .current()
      .then((d) => {
        setData(d);
        setError(null);
      })
      .catch((e) => setError(String(e?.message ?? e)));
  }, []);
  useEffect(() => {
    reload();
    const id = setInterval(reload, ms);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return { data, error, reload };
}
OWNCURVE_EOF

mkdir -p 'app/src/lib'
cat > 'app/src/lib/useAction.ts' <<'OWNCURVE_EOF'
import { useCallback, useState } from "react";
import { explainError, explorerTx } from "./browserNet";

export type ActionState = { busy: string | null; error: string | null; done: { text: string; link: string } | null };

/** Ejecuta una acción on-chain mostrando progreso, el resultado con enlace o un error legible. */
export function useAction(onDone?: () => void) {
  const [s, setS] = useState<ActionState>({ busy: null, error: null, done: null });
  const run = useCallback(
    async (label: string, doneText: string, fn: () => Promise<string | void>) => {
      setS({ busy: label, error: null, done: null });
      try {
        const sig = await fn();
        setS({ busy: null, error: null, done: { text: doneText, link: sig ? explorerTx(sig) : "" } });
        onDone?.();
      } catch (e) {
        console.error(e);
        setS({ busy: null, error: explainError(e), done: null });
      }
    },
    [onDone],
  );
  return { ...s, run };
}
OWNCURVE_EOF

mkdir -p 'app/src/lib'
cat > 'app/src/lib/useNow.ts' <<'OWNCURVE_EOF'
import { useEffect, useState } from "react";

/** Hora actual en segundos Unix (ajustada al reloj de la cadena con `skew`), cada segundo. */
export function useNow(skew = 0) {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  useEffect(() => {
    const id = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(id);
  }, []);
  return now + skew;
}
OWNCURVE_EOF

mkdir -p 'app/src/lib'
cat > 'app/src/lib/wallet.tsx' <<'OWNCURVE_EOF'
// Una sola "cuenta activa" para toda la app: la wallet del navegador (estándar Wallet
// Standard: Phantom, Solflare, Backpack…) o una wallet desechable guardada en este navegador.
import { WalletProvider, useWallet } from "@solana/wallet-adapter-react";
import { Connection, Keypair, LAMPORTS_PER_SOL, PublicKey, Transaction } from "@solana/web3.js";
import { ReactNode, createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { CLUSTER, RPC_URL, TxSigner, confirm } from "./browserNet";

const BURNER_KEY = "owncurve.burner.v1";

function loadBurner(): Keypair | null {
  try {
    const raw = localStorage.getItem(BURNER_KEY);
    return raw ? Keypair.fromSecretKey(Uint8Array.from(JSON.parse(raw))) : null;
  } catch {
    return null;
  }
}
function saveBurner(kp: Keypair | null) {
  try {
    if (kp) localStorage.setItem(BURNER_KEY, JSON.stringify(Array.from(kp.secretKey)));
    else localStorage.removeItem(BURNER_KEY);
  } catch {
    /* almacenamiento no disponible: la wallet vive solo en memoria */
  }
}

type Account = {
  conn: Connection;
  signer: TxSigner | null;
  kind: "browser" | "burner" | null;
  balance: number | null;
  refreshBalance: () => void;
  useBurner: () => void;
  forgetBurner: () => void;
  requestSol: () => Promise<void>;
  disconnect: () => void;
};

const Ctx = createContext<Account | null>(null);

export function AccountProvider({ children }: { children: ReactNode }) {
  return (
    <WalletProvider wallets={[]} autoConnect>
      <Inner>{children}</Inner>
    </WalletProvider>
  );
}

function Inner({ children }: { children: ReactNode }) {
  const conn = useMemo(() => new Connection(RPC_URL, "confirmed"), []);
  const adapter = useWallet();
  const [burner, setBurner] = useState<Keypair | null>(() => loadBurner());
  const [balance, setBalance] = useState<number | null>(null);
  const [tick, setTick] = useState(0);

  const signer: TxSigner | null = useMemo(() => {
    if (burner)
      return {
        publicKey: burner.publicKey,
        signTransaction: async (tx: Transaction) => {
          tx.partialSign(burner);
          return tx;
        },
      };
    if (adapter.publicKey && adapter.signTransaction)
      return { publicKey: adapter.publicKey, signTransaction: adapter.signTransaction as TxSigner["signTransaction"] };
    return null;
  }, [burner, adapter.publicKey, adapter.signTransaction]);

  useEffect(() => {
    if (!signer) return setBalance(null);
    let live = true;
    conn.getBalance(signer.publicKey).then((b) => live && setBalance(b / LAMPORTS_PER_SOL)).catch(() => {});
    const id = setInterval(() => setTick((t) => t + 1), 15_000);
    return () => {
      live = false;
      clearInterval(id);
    };
  }, [signer, conn, tick]);

  const useBurnerCb = useCallback(() => {
    const kp = loadBurner() ?? Keypair.generate();
    saveBurner(kp);
    if (adapter.connected) adapter.disconnect().catch(() => {});
    setBurner(kp);
  }, [adapter]);

  const requestSol = useCallback(async () => {
    if (!signer) return;
    const sig = await conn.requestAirdrop(signer.publicKey, 1 * LAMPORTS_PER_SOL);
    await confirm(conn, sig, "Airdrop");
    setTick((t) => t + 1);
  }, [conn, signer]);

  const value: Account = {
    conn,
    signer,
    kind: burner ? "burner" : signer ? "browser" : null,
    balance,
    refreshBalance: () => setTick((t) => t + 1),
    useBurner: useBurnerCb,
    forgetBurner: () => {
      saveBurner(null);
      setBurner(null);
    },
    requestSol,
    disconnect: () => {
      setBurner(null);
      if (adapter.connected) adapter.disconnect().catch(() => {});
    },
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useAccount() {
  const v = useContext(Ctx);
  if (!v) throw new Error("useAccount fuera de AccountProvider");
  return v;
}

export function short(k: PublicKey | string, n = 4) {
  const s = typeof k === "string" ? k : k.toBase58();
  return `${s.slice(0, n)}…${s.slice(-n)}`;
}

export { CLUSTER };
OWNCURVE_EOF

mkdir -p 'app/src'
cat > 'app/src/main.tsx' <<'OWNCURVE_EOF'
import "@fontsource-variable/bricolage-grotesque";
import "@fontsource/public-sans/400.css";
import "@fontsource/public-sans/600.css";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import "./styles.css";

createRoot(document.getElementById("root")!).render(<App />);
OWNCURVE_EOF

mkdir -p 'app/src/pages'
cat > 'app/src/pages/Create.tsx' <<'OWNCURVE_EOF'
import { Keypair } from "@solana/web3.js";
import { FormEvent, useState } from "react";
import { DEFAULT_PARAMS, OwnCurve } from "../../../scripts/lib/owncurve";
import { explainError, makeBrowserNet } from "../lib/browserNet";
import { IDL } from "../lib/data";
import { useAccount } from "../lib/wallet";

const METADATA_URI =
  "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json";

export function Create() {
  const acc = useAccount();
  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  const [target, setTarget] = useState("0.5");
  const [treasury, setTreasury] = useState("80");
  const [tranches, setTranches] = useState("30, 30, 40");
  const [windowSecs, setWindowSecs] = useState("60");
  const [quorum, setQuorum] = useState("10");
  const [step, setStep] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const trancheList = tranches
    .split(/[,\s]+/)
    .filter(Boolean)
    .map(Number);
  const trancheSum = trancheList.reduce((a, b) => a + b, 0);
  const formError =
    trancheList.some((t) => !Number.isFinite(t) || t <= 0) || trancheSum !== 100 || trancheList.length > 5
      ? "Tranches must be 1 to 5 positive numbers that add up to 100."
      : Number(treasury) < 50 || Number(treasury) > 99
        ? "Send between 50% and 99% of the raise to the treasury."
        : Number(windowSecs) < 60
          ? "Give holders at least 60 seconds to object."
          : Number(quorum) <= 0 || Number(quorum) > 30
            ? "The quorum must be between 1% and 30% of the supply."
            : !(Number(target) > 0)
              ? "Set how much SOL the curve should raise."
              : null;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!acc.signer || formError) return;
    setError(null);
    try {
      const oc = new OwnCurve(makeBrowserNet(acc.conn, acc.signer), IDL);
      const configKp = Keypair.generate();
      const baseMintKp = Keypair.generate();
      const params = {
        ...DEFAULT_PARAMS,
        thresholdSol: Number(target),
        treasuryPct: Math.round(Number(treasury)),
        tranchesBps: trancheList.map((t) => Math.round(t * 100)),
        challengeSecs: Math.round(Number(windowSecs)),
        quorumBps: Math.round(Number(quorum) * 100),
      };
      setStep("Creating the raise and its Meteora curve (1 of 2)…");
      await oc.createRaise(params, configKp);
      setStep("Opening the curve and checking it on-chain (2 of 2)…");
      await oc.launchPool(configKp.publicKey, baseMintKp, undefined, true, {
        name: name.trim(),
        symbol: symbol.trim().toUpperCase(),
        uri: METADATA_URI,
      });
      acc.refreshBalance();
      location.hash = `#/raise/${configKp.publicKey.toBase58()}`;
    } catch (err) {
      console.error(err);
      setError(explainError(err));
    } finally {
      setStep(null);
    }
  };

  return (
    <main className="page narrow">
      <h1>Launch a raise</h1>
      <p className="muted">
        Your token trades on a Meteora bonding curve. When the curve graduates, the share you choose goes to a treasury
        that pays you one tranche at a time.
      </p>
      <form className="form" onSubmit={submit}>
        <fieldset>
          <legend>Token</legend>
          <label>
            Name
            <input value={name} onChange={(e) => setName(e.target.value)} maxLength={32} required placeholder="Lighthouse Labs" />
          </label>
          <label>
            Symbol
            <input value={symbol} onChange={(e) => setSymbol(e.target.value)} maxLength={10} required placeholder="LIGHT" />
          </label>
        </fieldset>
        <fieldset>
          <legend>Raise</legend>
          <label>
            SOL the curve raises before graduating
            <input inputMode="decimal" value={target} onChange={(e) => setTarget(e.target.value)} />
          </label>
          <label>
            Share that goes to the treasury (%)
            <input inputMode="numeric" value={treasury} onChange={(e) => setTreasury(e.target.value)} />
          </label>
          <label>
            Tranches (% of the treasury, in order)
            <input value={tranches} onChange={(e) => setTranches(e.target.value)} />
            <small>Add up to 100. Now: {trancheSum}.</small>
          </label>
        </fieldset>
        <fieldset>
          <legend>Holder protection</legend>
          <label>
            Seconds holders have to object to each tranche
            <input inputMode="numeric" value={windowSecs} onChange={(e) => setWindowSecs(e.target.value)} />
          </label>
          <label>
            Supply that can stop a tranche (%)
            <input inputMode="decimal" value={quorum} onChange={(e) => setQuorum(e.target.value)} />
          </label>
        </fieldset>
        {formError && <p className="error">{formError}</p>}
        {error && <p className="error">{error}</p>}
        {step && <p className="progress">{step}</p>}
        <button className="btn primary" disabled={!acc.signer || !!formError || !!step}>
          {acc.signer ? (step ? "Launching…" : "Launch raise") : "Connect a wallet to launch"}
        </button>
      </form>
    </main>
  );
}
OWNCURVE_EOF

mkdir -p 'app/src/pages'
cat > 'app/src/pages/Home.tsx' <<'OWNCURVE_EOF'
import { useMemo } from "react";
import { fmtSol, listRaises, readOnlyClient, usePoll } from "../lib/data";
import { useAccount } from "../lib/wallet";

const STATE_LABEL: Record<string, string> = {
  pending: "Not launched",
  bonding: "On the curve",
  funded: "Paying in tranches",
  liquidating: "Holders redeeming",
  completed: "Fully paid",
};

export function Home() {
  const { conn } = useAccount();
  const oc = useMemo(() => readOnlyClient(conn), [conn]);
  const { data: rows, error } = usePoll(() => listRaises(oc), [oc], 10_000);

  return (
    <main className="page">
      <section className="lede">
        <h1>Token launches where the money waits for the work.</h1>
        <p>
          OwnCurve sends what a Meteora bonding curve raises into an on-chain treasury. The team is paid one milestone
          at a time, and holders can stop a payment and take their share back.
        </p>
        <a className="btn primary" href="#/new">
          Launch a raise
        </a>
      </section>

      <section aria-labelledby="ledger-title" className="ledger">
        <h2 id="ledger-title">Raises</h2>
        {error && <p className="error">Could not read raises from the network: {error}</p>}
        {!rows && !error && <p className="muted">Reading raises from the chain…</p>}
        {rows && rows.length === 0 && (
          <p className="muted">
            No raises yet. <a href="#/new">Launch the first one</a>.
          </p>
        )}
        {rows && rows.length > 0 && (
          <table>
            <thead>
              <tr>
                <th scope="col">Token</th>
                <th scope="col">Stage</th>
                <th scope="col" className="num">
                  Raised into treasury
                </th>
                <th scope="col" className="num">
                  Treasury now
                </th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.config} onClick={() => (location.hash = `#/raise/${r.config}`)}>
                  <td>
                    <a href={`#/raise/${r.config}`}>
                      <strong>{r.name}</strong> <span className="muted">{r.symbol}</span>
                    </a>
                  </td>
                  <td>
                    <span className={`stage ${r.state}`}>{STATE_LABEL[r.state] ?? r.state}</span>
                    {r.progress !== null && (
                      <span className="mini-track" aria-label={`${Math.round(r.progress * 100)}% of the curve`}>
                        <span style={{ width: `${r.progress * 100}%` }} />
                      </span>
                    )}
                  </td>
                  <td className="num">{r.fundedSol > 0 ? `${fmtSol(r.fundedSol * 1e9)} SOL` : "—"}</td>
                  <td className="num">{r.treasurySol > 0 ? `${fmtSol(r.treasurySol * 1e9)} SOL` : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </main>
  );
}

export { STATE_LABEL };
OWNCURVE_EOF

mkdir -p 'app/src/pages'
cat > 'app/src/pages/RaisePage.tsx' <<'OWNCURVE_EOF'
import { BN } from "@anchor-lang/core";
import { LAMPORTS_PER_SOL, PublicKey } from "@solana/web3.js";
import { useMemo, useState } from "react";
import { OwnCurve, stateName } from "../../../scripts/lib/owncurve";
import { Guarantees } from "../components/Guarantees";
import { VaultBar, fmtLeft } from "../components/VaultBar";
import { makeBrowserNet } from "../lib/browserNet";
import { IDL, RaiseDetail, fmtSol, fmtTokens, loadRaise, readOnlyClient, usePoll } from "../lib/data";
import { useAction } from "../lib/useAction";
import { useNow } from "../lib/useNow";
import { short, useAccount } from "../lib/wallet";
import { STATE_LABEL } from "./Home";

export function RaisePage({ config }: { config: string }) {
  const acc = useAccount();
  const configKey = useMemo(() => {
    try {
      return new PublicKey(config);
    } catch {
      return null;
    }
  }, [config]);
  const reader = useMemo(() => readOnlyClient(acc.conn), [acc.conn]);
  const me = acc.signer?.publicKey ?? null;
  const { data: d, error, reload } = usePoll(
    () => (configKey ? loadRaise(reader, configKey, me) : Promise.reject(new Error("Invalid address"))),
    [reader, configKey?.toBase58(), me?.toBase58()],
    6000,
  );

  if (!configKey) return <main className="page"><p className="error">That is not a valid raise address.</p></main>;
  if (error && !d) return <main className="page"><p className="error">Could not load this raise: {error}</p></main>;
  if (!d) return <main className="page"><p className="muted">Reading the raise from the chain…</p></main>;

  const treasuryPct = d.cfg?.migrationFeePercentage ?? d.raise.minTreasuryPct;
  return (
    <main className="page raise">
      <div className="raise-head">
        <div>
          <p className="crumb">
            <a href="#/">Raises</a>
          </p>
          <h1>
            {d.name} <span className="sym">{d.symbol}</span>
          </h1>
        </div>
        <span className={`stage big ${d.state}`}>{STATE_LABEL[d.state] ?? d.state}</span>
      </div>

      <VaultBar state={d.state} raise={d.raise} curve={d.curve} treasuryPct={treasuryPct} clockSkew={d.clockSkew} />

      {d.state === "bonding" || d.state === "pending" ? (
        <dl className="figures">
          <div>
            <dt>Graduates at</dt>
            <dd>{d.curve ? fmtSol(d.curve.threshold) : "—"} SOL</dd>
          </div>
          <div>
            <dt>Goes to the treasury</dt>
            <dd>{d.curve ? fmtSol(d.curve.threshold.muln(treasuryPct).divn(100)) : "—"} SOL</dd>
          </div>
          <div>
            <dt>Paid to the team in</dt>
            <dd>
              {Number(d.raise.milestoneCount)} tranches of{" "}
              {(d.raise.milestones as any[])
                .slice(0, Number(d.raise.milestoneCount))
                .map((m) => `${m.trancheBps / 100}%`)
                .join(", ")}
            </dd>
          </div>
        </dl>
      ) : (
        <dl className="figures">
          <div>
            <dt>Treasury holds</dt>
            <dd>{fmtSol(d.treasuryQuote)} SOL</dd>
          </div>
          <div>
            <dt>Paid to the team</dt>
            <dd>
              {fmtSol(d.raise.releasedAmount)} of {fmtSol(d.raise.fundedAmount)} SOL
            </dd>
          </div>
          <div>
            <dt>Fees earned by the treasury</dt>
            <dd>{fmtSol(d.raise.feesCollected, 4)} SOL</dd>
          </div>
          <div>
            <dt>Redeem value of 1,000,000 tokens</dt>
            <dd>{d.navPerMillion.toFixed(4)} SOL</dd>
          </div>
        </dl>
      )}

      <div className="columns">
        <Actions d={d} reload={reload} />
        <Guarantees d={d} />
      </div>
    </main>
  );
}

function Actions({ d, reload }: { d: RaiseDetail; reload: () => void }) {
  const acc = useAccount();
  const now = useNow(d.clockSkew);
  const act = useAction(() => {
    reload();
    acc.refreshBalance();
  });
  const [buySol, setBuySol] = useState("0.1");
  const oc = useMemo(() => (acc.signer ? new OwnCurve(makeBrowserNet(acc.conn, acc.signer), IDL) : null), [acc.conn, acc.signer]);

  const me = acc.signer?.publicKey;
  const isTeam = !!me && me.equals(d.team);
  const r = oc ? new (d.r.constructor as any)(oc, d.r.config, d.r.baseMint) : d.r;
  const nonce = Number(d.raise.proposalNonce);
  const lockedVotes = d.user?.votes.filter((v) => v.nonce < nonce) ?? [];
  const activeVote = d.user?.votes.find((v) => v.nonce === nonce);
  const nextMilestone = (d.raise.milestones as any[]).findIndex((m) => stateName(m.status) === "locked");
  const nextAmount =
    nextMilestone >= 0 ? new BN(d.raise.fundedAmount.toString()).muln(d.raise.milestones[nextMilestone].trancheBps).divn(10_000) : null;
  const windowOpen = d.proposal ? now < d.proposal.endsAt : false;
  const myBase = d.user?.base ?? new BN(0);
  const redeemPreview = d.circulating.isZero() ? 0 : (Number(myBase.toString()) / Number(d.circulating.toString())) * Number(d.treasuryQuote.toString());

  const buttons: JSX.Element[] = [];
  const btn = (key: string, label: string, done: string, fn: () => Promise<string | void>, primary = false) =>
    buttons.push(
      <button key={key} className={`btn ${primary ? "primary" : ""}`} disabled={!!act.busy} onClick={() => act.run(label, done, fn)}>
        {act.busy === label ? "Waiting for the network…" : label}
      </button>,
    );

  if (oc) {
    if (d.state === "bonding" && d.curve && !d.curve.complete) {
      buttons.push(
        <div key="buy" className="buy">
          <label>
            SOL to spend
            <input inputMode="decimal" value={buySol} onChange={(e) => setBuySol(e.target.value)} />
          </label>
          <button
            className="btn primary"
            disabled={!!act.busy || !(Number(buySol) > 0)}
            onClick={() =>
              act.run("Buy on the curve", `Bought ${d.symbol}.`, () =>
                oc.buy(r, new BN(Math.round(Number(buySol) * LAMPORTS_PER_SOL))),
              )
            }
          >
            {act.busy === "Buy on the curve" ? "Waiting for the network…" : `Buy ${d.symbol}`}
          </button>
        </div>,
      );
    }
    if (d.state === "bonding" && d.curve?.complete)
      btn("harvest", "Move the raise into the treasury", "The treasury is funded.", () => oc.harvest(r), true);

    if (d.state === "funded") {
      if (!d.proposal && isTeam && nextMilestone >= 0 && nextAmount)
        btn(
          "propose",
          `Request tranche ${nextMilestone + 1} (${fmtSol(nextAmount)} SOL)`,
          "Tranche requested. Holders can object until the countdown ends.",
          () => oc.propose(r),
          true,
        );
      if (d.proposal && windowOpen && myBase.gtn(0))
        btn(
          "reject",
          `Object with my ${fmtTokens(myBase)} tokens`,
          "Objection recorded. Your tokens unlock after the tranche is settled.",
          () => oc.reject(r, oc.net.payer, myBase),
        );
      if (d.proposal && !windowOpen)
        btn("finalize", `Settle tranche ${d.proposal.milestone + 1}`, "Tranche settled.", () => oc.finalize(r), true);
    }
    if (lockedVotes.length > 0)
      btn("withdraw", "Unlock my voted tokens", "Your tokens are back in your wallet.", async () => {
        let sig: string | undefined;
        for (const v of lockedVotes) sig = await oc.withdrawVote(r, oc.net.payer, v.nonce);
        return sig;
      });
    if (d.state === "liquidating" && myBase.gtn(0))
      btn(
        "redeem",
        `Redeem my tokens for ${(redeemPreview / LAMPORTS_PER_SOL).toFixed(4)} SOL`,
        "Redeemed. The SOL is in your wallet as wrapped SOL.",
        () => oc.redeem(r, oc.net.payer, myBase),
        true,
      );
    if (["funded", "completed", "liquidating"].includes(d.state)) {
      if (d.curve && !d.curve.migrated)
        btn("migrate", "Graduate the pool to Meteora DAMM v2", "The token now trades on DAMM v2.", async () => (await oc.migrate(r)).sig);
      btn("fees", "Collect curve trading fees", "Fees moved into the treasury.", () => oc.collectTradingFees(r));
    }
  }

  return (
    <section className="actions" aria-labelledby="a-title">
      <h2 id="a-title">What you can do</h2>
      {d.proposal && (
        <div className="proposal">
          <p>
            <strong>Tranche {d.proposal.milestone + 1}</strong> is waiting.{" "}
            {windowOpen ? `Objections close in ${fmtLeft(d.proposal.endsAt - now)}.` : "The objection window has closed."}
          </p>
          <div className="quorum" aria-label="Objections against quorum">
            <span style={{ width: `${Math.min(100, quorumPct(d.proposal.rejectWeight, d.proposal.quorum))}%` }} />
          </div>
          <p className="fine">
            {fmtTokens(d.proposal.rejectWeight)} tokens object;{" "}
            {d.proposal.rejectWeight.gte(d.proposal.quorum)
              ? "that is enough to stop the payment and open redemptions."
              : `${fmtTokens(d.proposal.quorum)} would stop the payment and open redemptions.`}
          </p>
        </div>
      )}
      {!acc.signer && <p className="muted">Connect a wallet or use a test wallet to buy, object or redeem.</p>}
      {acc.signer && (
        <p className="fine">
          You hold {fmtTokens(myBase)} {d.symbol}
          {activeVote ? ` in your wallet and ${fmtTokens(activeVote.amount)} locked in an objection` : ""}
          {lockedVotes.length ? ` and ${fmtTokens(lockedVotes.reduce((a, v) => a.add(v.amount), new BN(0)))} ready to unlock` : ""}.{" "}
          {isTeam ? "You created this raise." : `Team: ${short(d.team)}.`}
        </p>
      )}
      <div className="buttons">{buttons}</div>
      {acc.signer && buttons.length === 0 && <p className="muted">Nothing to do right now for this wallet.</p>}
      {act.error && <p className="error" role="alert">{act.error}</p>}
      {act.done && (
        <p className="ok" role="status">
          {act.done.text}{" "}
          {act.done.link && (
            <a href={act.done.link} target="_blank" rel="noreferrer">
              View transaction
            </a>
          )}
        </p>
      )}
    </section>
  );
}

function quorumPct(weight: BN, quorum: BN) {
  return quorum.isZero() ? 0 : (Number(weight.toString()) / Number(quorum.toString())) * 100;
}
OWNCURVE_EOF

mkdir -p 'app/src'
cat > 'app/src/styles.css' <<'OWNCURVE_EOF'
/* OwnCurve · "papel de seguridad": papel verdoso, tinta profunda, guilloché en lo bloqueado. */
:root {
  --paper: #edf1ea;
  --paper-2: #e3e9df;
  --ink: #16302e;
  --ink-soft: #4e6662;
  --line: #c6d1c8;
  --vault: #2e6b57;
  --brass: #b07d2a;
  --intaglio: #a23b3b;
  --white: #f8faf6;

  --display: "Bricolage Grotesque Variable", "Bricolage Grotesque", system-ui, sans-serif;
  --text: "Public Sans", system-ui, sans-serif;

  --s1: 4px;
  --s2: 8px;
  --s3: 16px;
  --s4: 24px;
  --s5: 40px;
  --s6: 64px;
  color-scheme: light;
}

* {
  box-sizing: border-box;
}
html {
  background: var(--paper);
}
body {
  margin: 0;
  color: var(--ink);
  background: var(--paper);
  font: 400 16px/1.55 var(--text);
  font-variant-numeric: tabular-nums;
  -webkit-font-smoothing: antialiased;
}
a {
  color: var(--ink);
  text-decoration-thickness: 1px;
  text-underline-offset: 3px;
}
a:hover {
  color: var(--vault);
}
:focus-visible {
  outline: 2px solid var(--brass);
  outline-offset: 2px;
}
h1,
h2 {
  font-family: var(--display);
  font-weight: 700;
  letter-spacing: -0.02em;
  margin: 0;
}
h1 {
  font-size: clamp(2.2rem, 5vw, 3.6rem);
  line-height: 1.02;
  font-variation-settings: "wdth" 85;
}
h2 {
  font-size: 1.35rem;
  line-height: 1.2;
}
code,
.addr {
  font: inherit;
  word-break: break-all;
}
.muted {
  color: var(--ink-soft);
}
.fine {
  color: var(--ink-soft);
  font-size: 0.875rem;
}

/* ------------------------------------------------------------------ cabecera */
.masthead {
  border-bottom: 1px solid var(--line);
  background: var(--paper);
  position: sticky;
  top: 0;
  z-index: 5;
}
.masthead-row {
  max-width: 1120px;
  margin: 0 auto;
  padding: var(--s3) var(--s3);
  display: flex;
  align-items: center;
  gap: var(--s4);
  flex-wrap: wrap;
}
.wordmark {
  font-family: var(--display);
  font-weight: 800;
  font-size: 1.5rem;
  letter-spacing: -0.03em;
  text-decoration: none;
}
.wordmark span {
  font-weight: 400;
}
.nav {
  display: flex;
  gap: var(--s3);
}
.nav a {
  text-decoration: none;
  color: var(--ink-soft);
}
.nav a:hover {
  color: var(--ink);
}
.account {
  margin-left: auto;
  display: flex;
  align-items: center;
  gap: var(--s2);
  flex-wrap: wrap;
}
.network {
  font-size: 0.8rem;
  color: var(--ink-soft);
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 2px 10px;
}
.who {
  display: inline-flex;
  flex-direction: column;
  line-height: 1.15;
  font-size: 0.85rem;
  text-align: right;
}
.who span {
  color: var(--ink-soft);
}
.flash {
  max-width: 1120px;
  margin: 0 auto;
  padding: 0 var(--s3) var(--s2);
  font-size: 0.875rem;
  color: var(--ink-soft);
}

/* ------------------------------------------------------------------ botones */
.btn {
  font: 600 0.95rem/1 var(--text);
  color: var(--ink);
  background: var(--white);
  border: 1.5px solid var(--ink);
  border-radius: 6px;
  padding: 10px 16px;
  cursor: pointer;
  text-decoration: none;
  display: inline-block;
}
.btn:hover:not(:disabled) {
  background: var(--paper-2);
}
.btn.primary {
  background: var(--ink);
  color: var(--paper);
}
.btn.primary:hover:not(:disabled) {
  background: var(--vault);
  border-color: var(--vault);
  color: var(--white);
}
.btn.quiet {
  border-color: var(--line);
  font-weight: 400;
}
.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

/* ------------------------------------------------------------------ páginas */
.page {
  max-width: 1120px;
  margin: 0 auto;
  padding: var(--s5) var(--s3) var(--s6);
}
.page.narrow {
  max-width: 680px;
}
.lede {
  max-width: 760px;
  padding: var(--s4) 0 var(--s6);
}
.lede p {
  font-size: 1.15rem;
  max-width: 62ch;
  margin: var(--s4) 0 var(--s4);
}

/* Registro de raises: filas, no tarjetas */
.ledger h2 {
  margin-bottom: var(--s3);
}
table {
  width: 100%;
  border-collapse: collapse;
}
th {
  text-align: left;
  font-weight: 600;
  font-size: 0.85rem;
  color: var(--ink-soft);
  border-bottom: 1.5px solid var(--ink);
  padding: var(--s2) var(--s2);
}
td {
  border-bottom: 1px solid var(--line);
  padding: var(--s3) var(--s2);
  vertical-align: middle;
}
tbody tr {
  cursor: pointer;
}
tbody tr:hover td {
  background: var(--paper-2);
}
td a {
  text-decoration: none;
}
.num {
  text-align: right;
}
.stage {
  font-size: 0.85rem;
  padding: 2px 10px;
  border-radius: 999px;
  border: 1px solid currentColor;
  white-space: nowrap;
}
.stage.bonding,
.stage.pending {
  color: var(--ink-soft);
}
.stage.funded {
  color: var(--brass);
}
.stage.completed {
  color: var(--vault);
}
.stage.liquidating {
  color: var(--intaglio);
}
.stage.big {
  font-size: 0.95rem;
  padding: 6px 14px;
}
.mini-track {
  display: inline-block;
  vertical-align: middle;
  margin-left: var(--s2);
  width: 80px;
  height: 6px;
  border-radius: 3px;
  background: var(--line);
  overflow: hidden;
}
.mini-track span {
  display: block;
  height: 100%;
  background: var(--ink);
}

/* ------------------------------------------------------------------ raise */
.raise-head {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  gap: var(--s3);
  flex-wrap: wrap;
  margin-bottom: var(--s5);
}
.crumb {
  margin: 0 0 var(--s2);
  font-size: 0.9rem;
}
.sym {
  font-weight: 400;
  color: var(--ink-soft);
  font-size: 0.5em;
  letter-spacing: 0;
}

/* La bóveda */
.vault {
  margin: 0 0 var(--s5);
}
.vault-track {
  display: flex;
  gap: 3px;
  height: 56px;
  border: 1.5px solid var(--ink);
  border-radius: 8px;
  padding: 3px;
  background: var(--white);
}
.vault-track.curve {
  display: block;
  position: relative;
  /* lo que falta por recaudar lleva la misma trama que lo bloqueado */
  background:
    repeating-linear-gradient(60deg, transparent 0 5px, rgba(22, 48, 46, 0.16) 5px 6px),
    repeating-linear-gradient(-60deg, transparent 0 5px, rgba(22, 48, 46, 0.16) 5px 6px), var(--paper);
}
.vault-fill {
  height: 100%;
  border-radius: 5px;
  background: var(--ink);
  transition: width 600ms ease;
}
.seg {
  flex-basis: 0;
  border-radius: 5px;
}
.seg.released {
  background: var(--vault);
}
.seg.proposed {
  background: var(--brass);
}
/* guilloché: dos tramas finas cruzadas, como en el papel de seguridad */
.seg.locked {
  background:
    repeating-linear-gradient(60deg, transparent 0 5px, rgba(22, 48, 46, 0.22) 5px 6px),
    repeating-linear-gradient(-60deg, transparent 0 5px, rgba(22, 48, 46, 0.22) 5px 6px), var(--paper);
}
.seg.returned {
  background:
    repeating-linear-gradient(90deg, transparent 0 4px, rgba(162, 59, 59, 0.35) 4px 5px), #f3e6e4;
}
.vault-caption {
  display: flex;
  align-items: baseline;
  gap: var(--s3);
  flex-wrap: wrap;
  margin-top: var(--s3);
  color: var(--ink-soft);
}
.vault-caption .big {
  font-family: var(--display);
  font-size: 2.2rem;
  font-weight: 700;
  color: var(--ink);
}
.seg-labels {
  list-style: none;
  display: flex;
  gap: 3px;
  margin: var(--s2) 0 0;
  padding: 0 3px;
}
.seg-labels li {
  flex-basis: 0;
  min-width: 0;
  display: flex;
  flex-direction: column;
  border-left: 1.5px solid var(--ink);
  padding-left: var(--s2);
}
.seg-labels .amt {
  font-family: var(--display);
  font-weight: 700;
  font-size: 1.25rem;
}
.seg-labels .what {
  font-size: 0.85rem;
  color: var(--ink-soft);
}

.figures {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: var(--s4);
  margin: 0 0 var(--s5);
  padding: var(--s4) 0;
  border-top: 1px solid var(--line);
  border-bottom: 1px solid var(--line);
}
.figures dt {
  font-size: 0.85rem;
  color: var(--ink-soft);
}
.figures dd {
  margin: var(--s1) 0 0;
  font-size: 1.15rem;
  font-weight: 600;
}

.columns {
  display: grid;
  grid-template-columns: 1.1fr 1fr;
  gap: var(--s5);
  align-items: start;
}
.actions h2,
.guarantees h2 {
  margin-bottom: var(--s3);
}
.buttons {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: var(--s2);
  margin: var(--s3) 0;
}
.buy {
  display: flex;
  align-items: flex-end;
  gap: var(--s2);
  flex-wrap: wrap;
}
.buy label {
  display: flex;
  flex-direction: column;
  font-size: 0.85rem;
  color: var(--ink-soft);
}
.buy input {
  width: 120px;
}
.proposal {
  border: 1.5px solid var(--brass);
  border-radius: 8px;
  padding: var(--s3);
  margin-bottom: var(--s3);
  background: #f6efe1;
}
.proposal p {
  margin: 0 0 var(--s2);
}
.quorum {
  height: 8px;
  border-radius: 4px;
  background: var(--white);
  border: 1px solid var(--line);
  overflow: hidden;
}
.quorum span {
  display: block;
  height: 100%;
  background: var(--intaglio);
}

.guarantees ul {
  list-style: none;
  margin: 0;
  padding: 0;
}
.guarantees li {
  display: grid;
  grid-template-columns: 28px 1fr;
  gap: var(--s2);
  padding: var(--s2) 0;
  border-bottom: 1px solid var(--line);
}
.guarantees .mark {
  width: 22px;
  height: 22px;
  border-radius: 50%;
  display: grid;
  place-items: center;
  font-size: 0.8rem;
  border: 1.5px solid var(--vault);
  color: var(--vault);
}
.guarantees li.bad .mark {
  border-color: var(--intaglio);
  color: var(--intaglio);
}

/* ------------------------------------------------------------------ formulario */
.form {
  margin-top: var(--s4);
  display: flex;
  flex-direction: column;
  gap: var(--s4);
}
fieldset {
  border: 0;
  border-top: 1.5px solid var(--ink);
  margin: 0;
  padding: var(--s3) 0 0;
  display: grid;
  gap: var(--s3);
}
legend {
  font-family: var(--display);
  font-weight: 700;
  font-size: 1.15rem;
  padding: 0 var(--s2) 0 0;
}
label {
  display: flex;
  flex-direction: column;
  gap: var(--s1);
  font-size: 0.95rem;
}
small {
  color: var(--ink-soft);
}
input {
  font: 400 1rem var(--text);
  color: var(--ink);
  background: var(--white);
  border: 1.5px solid var(--line);
  border-radius: 6px;
  padding: 10px 12px;
}
input:focus {
  border-color: var(--ink);
}

.error {
  color: var(--intaglio);
}
.ok {
  color: var(--vault);
}
.progress {
  color: var(--brass);
}

.foot {
  max-width: 1120px;
  margin: 0 auto;
  padding: var(--s4) var(--s3) var(--s5);
  border-top: 1px solid var(--line);
  color: var(--ink-soft);
  font-size: 0.875rem;
}

@media (max-width: 820px) {
  .figures {
    grid-template-columns: repeat(2, 1fr);
  }
  .network {
    display: none;
  }
  .masthead-row {
    gap: var(--s2) var(--s3);
  }
  .account .btn {
    padding: 8px 12px;
  }
  .columns {
    grid-template-columns: 1fr;
  }
  .account {
    margin-left: 0;
    width: 100%;
  }
  .seg-labels .amt {
    font-size: 1rem;
  }
}
@media (prefers-reduced-motion: reduce) {
  .vault-fill {
    transition: none;
  }
}
OWNCURVE_EOF

mkdir -p 'app/src'
cat > 'app/src/vite-env.d.ts' <<'OWNCURVE_EOF'
/// <reference types="vite/client" />
interface ImportMetaEnv {
  readonly VITE_RPC_URL?: string;
  readonly VITE_CLUSTER?: "devnet" | "local";
}
OWNCURVE_EOF

mkdir -p 'app'
cat > 'app/tsconfig.json' <<'OWNCURVE_EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noImplicitAny": false,
    "resolveJsonModule": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "noEmit": true,
    "types": ["vite/client"]
  },
  "include": ["src"]
}
OWNCURVE_EOF

mkdir -p 'app'
cat > 'app/vite.config.ts' <<'OWNCURVE_EOF'
import react from "@vitejs/plugin-react";
import path from "path";
import { defineConfig } from "vite";
import { nodePolyfills } from "vite-plugin-node-polyfills";

// La app vive en app/ pero reutiliza el cliente de scripts/lib y el IDL de target/idl.
export default defineConfig({
  root: path.resolve(__dirname),
  base: "./",
  envDir: path.resolve(__dirname),
  plugins: [react(), nodePolyfills({ include: ["buffer", "crypto", "stream", "util", "process"], globals: { Buffer: true, process: true } })],
  server: { port: 5173, fs: { allow: [path.resolve(__dirname, "..")] } },
  build: { outDir: path.resolve(__dirname, "dist"), emptyOutDir: true, chunkSizeWarningLimit: 4000 },
});
OWNCURVE_EOF

mkdir -p 'tests/e2e'
cat > 'tests/e2e/rpc-server.ts' <<'OWNCURVE_EOF'
// Servidor JSON-RPC mínimo sobre LiteSVM (con los .so reales de DBC, DAMM v2 y OwnCurve).
// Implementa lo que usan web3.js, Anchor y el SDK de Meteora desde el navegador, más un
// método propio `owncurve_warp` para adelantar el reloj en los tests de la interfaz.
import { PublicKey, Transaction, VersionedTransaction } from "@solana/web3.js";
import bs58 from "bs58";
import http from "http";
import { makeNet } from "../../scripts/lib/net";

export async function startRpc(port = 8899) {
  process.env.CLUSTER = "local";
  const net = await makeNet();
  const svm = net.svm;
  const known = new Set<string>(); // LiteSVM no enumera cuentas: recordamos las que aparecen
  const statuses = new Map<string, { slot: number; err: any }>();
  const remember = (k: PublicKey | string) => known.add(typeof k === "string" ? k : k.toBase58());

  const slot = () => Number(svm.getClock().slot);
  const ctx = () => ({ slot: slot(), apiVersion: "3.1.14" });
  const acct = (pk: PublicKey) => {
    const a = svm.getAccount(pk);
    if (!a || (Number(a.lamports) === 0 && a.data.length === 0)) return null;
    return {
      data: [Buffer.from(a.data).toString("base64"), "base64"],
      executable: a.executable,
      lamports: Number(a.lamports),
      owner: new PublicKey(a.owner).toBase58(),
      rentEpoch: 0,
      space: a.data.length,
    };
  };
  const fakeSig = () => bs58.encode(Buffer.from(Array.from({ length: 64 }, () => Math.floor(Math.random() * 256))));
  const advance = () => {
    const c = svm.getClock();
    c.slot = c.slot + 1n;
    c.unixTimestamp = c.unixTimestamp + 1n;
    svm.setClock(c);
  };

  const methods: Record<string, (p: any[]) => any> = {
    getVersion: () => ({ "solana-core": "3.1.14", "feature-set": 0 }),
    getGenesisHash: () => "EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG",
    getSlot: () => slot(),
    getBlockHeight: () => slot(),
    getEpochInfo: () => ({ absoluteSlot: slot(), blockHeight: slot(), epoch: 0, slotIndex: slot(), slotsInEpoch: 432000 }),
    getBlockTime: () => Number(svm.getClock().unixTimestamp),
    getLatestBlockhash: () => ({ context: ctx(), value: { blockhash: svm.latestBlockhash(), lastValidBlockHeight: slot() + 150 } }),
    getMinimumBalanceForRentExemption: ([n]) => Number(svm.minimumBalanceForRentExemption(BigInt(n))),
    getBalance: ([pk]) => ({ context: ctx(), value: Number(svm.getBalance(new PublicKey(pk)) ?? 0n) }),
    getAccountInfo: ([pk]) => {
      remember(pk);
      return { context: ctx(), value: acct(new PublicKey(pk)) };
    },
    getMultipleAccounts: ([pks]) => ({ context: ctx(), value: pks.map((k: string) => (remember(k), acct(new PublicKey(k)))) }),
    getTokenAccountBalance: ([pk]) => {
      const a = svm.getAccount(new PublicKey(pk));
      const amount = a && a.data.length >= 72 ? Buffer.from(a.data).readBigUInt64LE(64) : 0n;
      return { context: ctx(), value: { amount: amount.toString(), decimals: 9, uiAmount: Number(amount) / 1e9, uiAmountString: "" } };
    },
    getProgramAccounts: ([program, cfg]) => {
      const owner = new PublicKey(program);
      const out: any[] = [];
      for (const k of known) {
        const pk = new PublicKey(k);
        const a = svm.getAccount(pk);
        if (!a || !new PublicKey(a.owner).equals(owner)) continue;
        const data = Buffer.from(a.data);
        const ok = (cfg?.filters ?? []).every((f: any) => {
          if (f.dataSize !== undefined) return data.length === f.dataSize;
          if (f.memcmp) {
            const want = f.memcmp.encoding === "base64" ? Buffer.from(f.memcmp.bytes, "base64") : Buffer.from(bs58.decode(f.memcmp.bytes));
            return data.subarray(f.memcmp.offset, f.memcmp.offset + want.length).equals(want);
          }
          return true;
        });
        if (ok) out.push({ pubkey: k, account: acct(pk) });
      }
      return cfg?.withContext ? { context: ctx(), value: out } : out;
    },
    getSignatureStatuses: ([sigs]) => ({
      context: ctx(),
      value: sigs.map((s: string) => {
        const st = statuses.get(s);
        return st ? { slot: st.slot, confirmations: null, err: st.err, confirmationStatus: "confirmed", status: st.err ? { Err: st.err } : { Ok: null } } : null;
      }),
    }),
    requestAirdrop: ([pk, lamports]) => {
      remember(pk);
      svm.airdrop(new PublicKey(pk), BigInt(lamports));
      const sig = fakeSig();
      statuses.set(sig, { slot: slot(), err: null });
      return sig;
    },
    sendTransaction: ([b64]) => {
      const raw = Buffer.from(b64, "base64");
      let tx: Transaction | VersionedTransaction;
      let keys: PublicKey[];
      try {
        tx = Transaction.from(raw);
        keys = tx.compileMessage().accountKeys;
      } catch {
        tx = VersionedTransaction.deserialize(raw);
        keys = tx.message.staticAccountKeys;
      }
      keys.forEach(remember);
      const res: any = svm.sendTransaction(tx as any);
      svm.expireBlockhash();
      advance();
      if (res.constructor.name === "FailedTransactionMetadata" || typeof res.err === "function") {
        const logs: string[] = res.meta().logs();
        const err = { message: "Transaction simulation failed: " + res.err().toString(), logs };
        throw Object.assign(new Error(err.message), { rpc: { code: -32002, message: err.message, data: { err: res.err().toString(), logs, accounts: null, unitsConsumed: 0 } } });
      }
      const sig = bs58.encode((tx as any).signature ?? (tx as any).signatures[0]);
      statuses.set(sig, { slot: slot(), err: null });
      return sig;
    },
    // Solo para tests: adelanta el reloj de la cadena.
    owncurve_warp: ([secs]) => {
      const c = svm.getClock();
      c.unixTimestamp = c.unixTimestamp + BigInt(secs);
      c.slot = c.slot + BigInt(Math.ceil(secs * 2.5));
      svm.setClock(c);
      return Number(c.unixTimestamp);
    },
    owncurve_airdrop: ([pk, lamports]) => {
      remember(pk);
      svm.airdrop(new PublicKey(pk), BigInt(lamports));
      return true;
    },
  };

  const server = http.createServer((req, res) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "*");
    res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
    if (req.method === "OPTIONS") return res.end();
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      const reqs = JSON.parse(body);
      const one = (r: any) => {
        const fn = methods[r.method];
        if (!fn) return { jsonrpc: "2.0", id: r.id, error: { code: -32601, message: `Method not found: ${r.method}` } };
        try {
          return { jsonrpc: "2.0", id: r.id, result: fn(r.params ?? []) };
        } catch (e: any) {
          return { jsonrpc: "2.0", id: r.id, error: e.rpc ?? { code: -32000, message: String(e.message ?? e) } };
        }
      };
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify(Array.isArray(reqs) ? reqs.map(one) : one(reqs)));
    });
  });
  await new Promise<void>((r) => server.listen(port, "127.0.0.1", () => r()));
  return { server, svm, net, url: `http://127.0.0.1:${port}` };
}

if (require.main === module) {
  startRpc().then(({ url }) => console.log(`LiteSVM RPC listo en ${url}`));
}
OWNCURVE_EOF

mkdir -p 'tests/e2e'
cat > 'tests/e2e/ui.e2e.ts' <<'OWNCURVE_EOF'
// Test E2E de la interfaz: navegador real (Chromium) + app (Vite) + LiteSVM con los
// programas reales. Dos personas con wallets de prueba: el equipo y un holder.
//
//  equipo lanza un raise → holder compra → equipo completa la curva → tesorería financiada →
//  equipo pide el tramo 1 → holder objeta con quórum → se cierra la ventana → liquidación →
//  holder desbloquea sus tokens y los redime por SOL
//
// Ejecutar: npx tsx tests/e2e/ui.e2e.ts   (SHOTS=dir guarda capturas)
import { chromium, Page } from "playwright-core";
import fs from "fs";
import path from "path";
import { createServer } from "vite";
import { startRpc } from "./rpc-server";

const CHROME = process.env.CHROME_PATH ?? "/opt/pw-browsers/chromium-1194/chrome-linux/chrome";
const SHOTS = process.env.SHOTS;
let shotN = 0;

async function main() {
  const rpc = await startRpc(8899);
  process.env.VITE_CLUSTER = "local";
  process.env.VITE_RPC_URL = rpc.url;
  const vite = await createServer({
    configFile: path.resolve("app/vite.config.ts"),
    server: { port: 5199, strictPort: true },
    logLevel: "error",
  });
  await vite.listen();
  const appUrl = "http://localhost:5199/";
  const browser = await chromium.launch({ executablePath: CHROME });
  const errors: string[] = [];

  const person = async (name: string) => {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
    const page = await ctx.newPage();
    page.on("pageerror", (e) => errors.push(`${name}: ${e.message}`));
    await page.goto(appUrl);
    await page.getByRole("button", { name: "Use a test wallet" }).click();
    await page.getByRole("button", { name: "Get 1 SOL" }).waitFor();
    const secret = JSON.parse((await page.evaluate(() => localStorage.getItem("owncurve.burner.v1")))!);
    const { Keypair } = await import("@solana/web3.js");
    const pk = Keypair.fromSecretKey(Uint8Array.from(secret)).publicKey;
    rpc.svm.airdrop(pk, 5_000_000_000n);
    return { page, pk };
  };
  const shot = async (page: Page, name: string) => {
    if (!SHOTS) return;
    fs.mkdirSync(SHOTS, { recursive: true });
    await page.screenshot({ path: `${SHOTS}/${String(++shotN).padStart(2, "0")}-${name}.png`, fullPage: true });
  };
  const ok = async (page: Page, text: RegExp | string) => {
    await page.getByRole("status").filter({ hasText: text }).waitFor({ timeout: 30_000 });
  };
  const step = (s: string) => console.log(`  ✔ ${s}`);

  try {
    const team = await person("equipo");
    const holder = await person("holder");
    await shot(team.page, "inicio-vacio");
    // El botón de airdrop de la wallet de prueba funciona contra la red
    await team.page.getByRole("button", { name: "Get 1 SOL" }).click();
    await team.page.getByText("1 devnet SOL added.").waitFor();
    step("wallets de prueba creadas y fondeadas");

    // 1. Lanzar
    await team.page.getByRole("link", { name: "Launch a raise" }).first().click();
    await team.page.getByLabel("Name").fill("Lighthouse Labs");
    await team.page.getByLabel("Symbol").fill("light");
    await shot(team.page, "formulario");
    await team.page.getByRole("button", { name: "Launch raise" }).click();
    await team.page.getByRole("heading", { name: /Lighthouse Labs/ }).waitFor({ timeout: 30_000 });
    const raiseUrl = team.page.url();
    await team.page.getByText("On the curve").first().waitFor();
    step(`raise lanzado: ${raiseUrl.split("/").pop()}`);
    await shot(team.page, "raise-en-curva");

    // 2. Holder compra, luego el equipo completa la curva
    await holder.page.goto(raiseUrl);
    await holder.page.getByLabel("SOL to spend").fill("0.2");
    await holder.page.getByRole("button", { name: "Buy LIGHT" }).click();
    await ok(holder.page, "Bought LIGHT.");
    step("holder compró 0.2 SOL");
    await team.page.getByLabel("SOL to spend").fill("0.5");
    await team.page.getByRole("button", { name: "Buy LIGHT" }).click();
    await ok(team.page, "Bought LIGHT.");
    await team.page.getByRole("button", { name: "Move the raise into the treasury" }).click();
    await ok(team.page, "The treasury is funded.");
    await team.page.getByText("Paying in tranches").first().waitFor();
    step("curva completa y tesorería financiada desde la interfaz");
    await shot(team.page, "tesoreria-financiada");

    // 3. El equipo pide el tramo 1; el holder objeta
    await team.page.getByRole("button", { name: /Request tranche 1/ }).click();
    await ok(team.page, "Tranche requested.");
    await holder.page.reload();
    await holder.page.getByRole("button", { name: /Object with my/ }).click();
    await ok(holder.page, "Objection recorded.");
    step("tramo 1 pedido y objetado por el holder");
    await shot(holder.page, "objecion");

    // 4. Pasa la ventana: se liquida
    rpc.svm && (await fetch(rpc.url, { method: "POST", body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "owncurve_warp", params: [61] }) }));
    await team.page.reload();
    await team.page.getByRole("button", { name: "Settle tranche 1" }).click();
    await ok(team.page, "Tranche settled.");
    await team.page.getByText("Holders redeeming").first().waitFor();
    step("ventana cerrada: el raise pasó a liquidación");
    await shot(team.page, "liquidacion");

    // 5. El holder desbloquea y redime
    await holder.page.reload();
    await holder.page.getByRole("button", { name: "Unlock my voted tokens" }).click();
    await ok(holder.page, "Your tokens are back");
    await holder.page.getByRole("button", { name: /Redeem my tokens for/ }).click();
    await ok(holder.page, "Redeemed.");
    step("el holder redimió sus tokens por SOL");
    await shot(holder.page, "redimido");

    // 6. La lista de inicio refleja el estado, aunque haya un raise de una versión vieja
    //    del programa (como el de la F1 en devnet, 8 bytes más corto).
    const { Keypair, PublicKey } = await import("@solana/web3.js");
    const idl = JSON.parse(fs.readFileSync("target/idl/owncurve.json", "utf8"));
    const disc = Buffer.from(idl.accounts.find((a: any) => a.name === "Raise").discriminator);
    const legacy = Keypair.generate().publicKey;
    rpc.svm.setAccount(legacy, { lamports: 10_000_000, data: Buffer.concat([disc, Buffer.alloc(227)]), owner: new PublicKey(idl.address), executable: false });
    await fetch(rpc.url, { method: "POST", body: JSON.stringify({ jsonrpc: "2.0", id: 2, method: "getAccountInfo", params: [legacy.toBase58()] }) });
    await team.page.goto(appUrl);
    await team.page.getByRole("cell", { name: /Lighthouse Labs/ }).waitFor();
    await team.page.getByText("Holders redeeming").first().waitFor();
    step("la lista de raises muestra el raise en liquidación");
    await shot(team.page, "inicio-con-raise");

    // Vista móvil
    await team.page.setViewportSize({ width: 390, height: 844 });
    await team.page.goto(raiseUrl);
    await team.page.getByRole("heading", { name: /Lighthouse Labs/ }).waitFor();
    await shot(team.page, "movil-raise");

    if (errors.length) throw new Error("Errores de JavaScript en la página:\n" + errors.join("\n"));
    console.log("\n  E2E OK: el ciclo completo funciona desde la interfaz.");
  } finally {
    await browser.close();
    await vite.close();
    rpc.server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(`\n  ✘ ${e.message ?? e}`);
    process.exit(1);
  });
OWNCURVE_EOF

ok "app/ (React), scripts/lib (cliente compartido), tests/e2e"

# =============================================================================
step "3/7 Dependencias (npm ci; la primera vez tarda 1–2 min)"
# =============================================================================
run "npm ci" npm ci --no-audit --no-fund

# =============================================================================
step "4/7 Programa e IDL (sin cambios en el programa: no hay que redesplegar)"
# =============================================================================
run "anchor keys sync" anchor keys sync
run "anchor build" anchor build --skip-lint --tools-version v1.52 --arch v0
PROGRAM_ID=$(solana address -k target/deploy/owncurve-keypair.json)
SO_HASH=$(sha256sum target/deploy/owncurve.so | awk '{print $1}')
if [ -f .owncurve/deployed-devnet.sha256 ] && [ "$(cat .owncurve/deployed-devnet.sha256)" = "$SO_HASH" ]; then
  ok "El programa de devnet coincide con este binario ($PROGRAM_ID)"
else
  warn "El binario local difiere del desplegado en devnet (no debería pasar en F4; avísame)"
fi

# =============================================================================
step "5/7 Regresión: tests del programa y demo en local"
# =============================================================================
if [ -f local/dynamic_bonding_curve.so ] && [ -f local/damm_v2.so ]; then
  run "17 tests de integración" env CLUSTER=local npx tsx --test tests/owncurve.test.ts
  run "Demo completa en local" env CLUSTER=local npx tsx scripts/demo.ts
else
  warn "Sin binarios locales (los prepara el script de F2): se salta la regresión"
fi

# =============================================================================
step "6/7 Compilar la interfaz"
# =============================================================================
RPC="${RPC_URL:-$(solana config get | awk '/RPC URL/{print $3}')}"
case "$RPC" in *devnet*) ;; *) RPC="https://api.devnet.solana.com";; esac
# Solo en tu máquina (app/.env.local está en .gitignore): la app usa tu RPC de devnet.
printf 'VITE_CLUSTER=devnet\nVITE_RPC_URL=%s\n' "$RPC" > app/.env.local
ok "app/.env.local → RPC ${RPC%%/solana-devnet/*}/…"
run "vite build (comprueba que la app compila)" npx vite build --config app/vite.config.ts

CHROME=$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)
if [ -n "$CHROME" ] && [ -f local/dynamic_bonding_curve.so ]; then
  echo "+ CHROME_PATH=$CHROME npx tsx tests/e2e/ui.e2e.ts" >> "$LOG"
  if CHROME_PATH="$CHROME" timeout 300 npx tsx tests/e2e/ui.e2e.ts >> "$LOG" 2>&1; then
    ok "Test E2E en navegador: el ciclo completo funciona desde la interfaz"
  else
    warn "El test E2E en navegador falló en esta máquina (detalle en el log); la app se arranca igual"
  fi
else
  warn "Sin Chromium instalado: se salta el test E2E en navegador (opcional)"
fi

git add -A >> "$LOG" 2>&1
git diff --cached --quiet || git commit -qm "F4: interfaz web (Vite + React) y test E2E en navegador" >> "$LOG" 2>&1
ok "Cambios guardados en git"

# =============================================================================
step "7/7 Arrancar la app"
# =============================================================================
echo -e "\n${G}================ F4 LISTA ================${N}"
echo -e "  Abre en el navegador de Kali:  ${B}http://localhost:5173${N}"
echo -e "  Red: devnet · Programa: $PROGRAM_ID"
echo -e "  Sin extensión de wallet: pulsa ${B}Use a test wallet${N} y luego ${B}Get 1 SOL${N}"
echo -e "  (si el faucet de devnet se niega, envía SOL a esa dirección con: solana transfer <dirección> 1 --allow-unfunded-recipient)"
echo -e "  Para pararla: Ctrl+C · Para volver a abrirla: cd ~/owncurve && npm run app"
echo -e "\n  Prueba: lanza un raise, compra, pásalo a tesorería, pide un tramo… y cuéntame qué tal se ve."
if [ "${NO_SERVE:-0}" = "1" ]; then exit 0; fi
exec npx vite --config app/vite.config.ts --host 127.0.0.1 --port 5173
