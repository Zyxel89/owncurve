# OwnCurve · demo en local

Programa: [`GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh`](GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh)

## Raise A · camino feliz

Tesorería [`91Sqg5d5snzbHgE1aRmceiNFFqRBYsfWFxGcxTtyvmF1`](91Sqg5d5snzbHgE1aRmceiNFFqRBYsfWFxGcxTtyvmF1) · financiado 0.4000 SOL · liberado al equipo en 3 tramos con evidencia 0.3200 SOL (todo lo cobrable: 0.3200) · comisiones cobradas 0.0042 SOL · defensa del piso 0.0396 SOL · la tesorería conserva 0.0446 SOL de respaldo para los holders · estado final **completed**.

| Paso | Resultado | Transacción |
| --- | --- | --- |
| A1 crear raise + config DBC |  | [ver](local:5a105120c6872966) |
| A2 lanzar pool + bind_pool |  | [ver](local:12b9217f1b0cf8f9) |
| A3 comprar hasta graduar | reserva 0.5000 SOL | [ver](local:8df424bb96a12bc3) |
| A4 harvest | tesorería 0.4000 SOL | [ver](local:c26553755b7e55fa) |
| A5 cobrar comisiones curva | +0.0040 SOL | [ver](local:ae25dc7fdea5081f) |
| A6 migrar a DAMM v2 |  | [ver](local:99895fb5eb09dcec) |
| A7 swap en DAMM v2 |  | [ver](local:2f11a475f47643a1) |
| A8 cobrar comisiones de LP | fees totales 0.0042 SOL | [ver](local:3988e6bb9b128bd3) |
| A8b venta de pánico en DAMM v2 | precio 0.0000203 vs respaldo 0.000404 SOL/M tokens | [ver](local:80ed921edf18068a) |
| A8c defend_floor | recompró 0.0396 SOL, quemó 473,177,901 tokens, respaldo +71% | [ver](local:c56407c8fe4624aa) |
| A9.1 proponer tramo 1 |  | [ver](local:beae36fec3f651fa) |
| A9.1 finalizar tramo 1 | liberado 0.0960 / 0.3200 SOL | [ver](local:a88bf3df891ac68f) |
| A9.2 proponer tramo 2 |  | [ver](local:559eef80e0550ffc) |
| A9.2 finalizar tramo 2 | liberado 0.1920 / 0.3200 SOL | [ver](local:7bc302dc4278800a) |
| A9.3 proponer tramo 3 |  | [ver](local:4716ad1265b61ccc) |
| A9.3 finalizar tramo 3 | liberado 0.3200 / 0.3200 SOL | [ver](local:10fc7277bfd838bc) |

## Raise B · rechazo y liquidación

Tesorería [`AbbNsuTG4U6yAkMBe2kbt4vT7ZfLBDYSgbvWmoohUR7k`](AbbNsuTG4U6yAkMBe2kbt4vT7ZfLBDYSgbvWmoohUR7k) · financiado 0.2400 SOL · estado final **liquidating**: el equipo no cobró nada y los holders redimen contra la tesorería.

| Paso | Resultado | Transacción |
| --- | --- | --- |
| B1 crear raise + config DBC |  | [ver](local:85fe1c2fd4936f30) |
| B2 lanzar pool + bind_pool |  | [ver](local:29bcb90358b72fe9) |
| B3 comprar hasta graduar |  | [ver](local:bfc2daeae9841b90) |
| B4 harvest | tesorería 0.2400 SOL | [ver](local:b1ad3e684bfee074) |
| B6 holder recibe 15% del suministro |  | [ver](local:d5a5716006edaf01) |
| B7 equipo propone tramo 1 |  | [ver](local:cc0b63a449e0e953) |
| B8 holder vota rechazo | bloqueados 150000000000000 tokens (base units) | [ver](local:17d4003e48a37303) |
| B10 finalizar → liquidación | estado "liquidating" | [ver](local:ba939bc3de039c8e) |
| B11 holder retira su voto |  | [ver](local:a300799b495f834a) |
| B12 holder redime por SOL | recibió 0.0360 SOL (wSOL) por sus tokens | [ver](local:8c67edf28685f5b2) |
