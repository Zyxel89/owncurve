# OwnCurve · demo en local

Programa: [`GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh`](GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh)

## Raise A · camino feliz

Tesorería [`59VaU1nPwF3gxj8aS2LqB9WHnwAfGmaTaEhhXjTRm7Yv`](59VaU1nPwF3gxj8aS2LqB9WHnwAfGmaTaEhhXjTRm7Yv) · financiado 0.4000 SOL · liberado al equipo 0.4000 SOL · comisiones cobradas 0.0042 SOL · estado final **completed**.

| Paso | Resultado | Transacción |
| --- | --- | --- |
| A1 crear raise + config DBC |  | [ver](local:b401914d6a563752) |
| A2 lanzar pool + bind_pool |  | [ver](local:d80c188037878b82) |
| A3 comprar hasta graduar | reserva 0.5000 SOL | [ver](local:5d4d9110ae0553d6) |
| A4 harvest | tesorería 0.4000 SOL | [ver](local:ec9c961b40420334) |
| A5 cobrar comisiones curva | +0.0040 SOL | [ver](local:317e8b21e3b684aa) |
| A6 migrar a DAMM v2 |  | [ver](local:57ef98daacc1538a) |
| A7 swap en DAMM v2 |  | [ver](local:8b951e4f1b0ec6ab) |
| A8 cobrar comisiones de LP | fees totales 0.0042 SOL | [ver](local:d87062065370a118) |
| A9.1 proponer tramo 1 |  | [ver](local:75437db7d0ff642a) |
| A9.1 finalizar tramo 1 | liberado 0.1200 / 0.4000 SOL | [ver](local:a243a1d3a864d2ca) |
| A9.2 proponer tramo 2 |  | [ver](local:cabb21cc46b4c2ae) |
| A9.2 finalizar tramo 2 | liberado 0.2400 / 0.4000 SOL | [ver](local:af53fd3003a4fb65) |
| A9.3 proponer tramo 3 |  | [ver](local:0b8530a34b9a9e55) |
| A9.3 finalizar tramo 3 | liberado 0.4000 / 0.4000 SOL | [ver](local:ef9e3fe22dc23186) |

## Raise B · rechazo y liquidación

Tesorería [`9Kek3VrDM7nMAyMwiPk6La24xUQxfiBNoLFfYsdY51hG`](9Kek3VrDM7nMAyMwiPk6La24xUQxfiBNoLFfYsdY51hG) · financiado 0.2400 SOL · estado final **liquidating**: el equipo no cobró nada y los holders redimen contra la tesorería.

| Paso | Resultado | Transacción |
| --- | --- | --- |
| B1 crear raise + config DBC |  | [ver](local:3739e9c0b95fd57e) |
| B2 lanzar pool + bind_pool |  | [ver](local:edb8ec0e0de10e39) |
| B3 comprar hasta graduar |  | [ver](local:104436cc79a91672) |
| B4 harvest | tesorería 0.2400 SOL | [ver](local:dae9c58588397622) |
| B6 holder recibe 15% del suministro |  | [ver](local:6b4648075d7f1e04) |
| B7 equipo propone tramo 1 |  | [ver](local:a44b10ab33894c77) |
| B8 holder vota rechazo | bloqueados 150000000000000 tokens (base units) | [ver](local:181be1a9a90bf479) |
| B10 finalizar → liquidación | estado "liquidating" | [ver](local:32e05526d9ba32d5) |
| B11 holder retira su voto |  | [ver](local:baccc194a4dcf151) |
| B12 holder redime por SOL | recibió 0.0360 SOL (wSOL) por sus tokens | [ver](local:65346cdbaecc10fc) |
