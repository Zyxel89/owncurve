# OwnCurve · demo en local

Programa: [`GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh`](GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh)

## Raise A · camino feliz

Tesorería [`3Vmx4kHtCXVMdyCrps8bQLaKsmAZmx9uiq3PPRwd8q3y`](3Vmx4kHtCXVMdyCrps8bQLaKsmAZmx9uiq3PPRwd8q3y) · financiado 0.4000 SOL · liberado al equipo 0.4000 SOL · comisiones cobradas 0.0042 SOL · estado final **completed**.

| Paso | Resultado | Transacción |
| --- | --- | --- |
| A1 crear raise + config DBC |  | [ver](local:d96ed6dcc1e5b9f4) |
| A2 lanzar pool + bind_pool |  | [ver](local:daca7829d132787f) |
| A3 comprar hasta graduar | reserva 0.5000 SOL | [ver](local:64937d2e207704bd) |
| A4 harvest | tesorería 0.4000 SOL | [ver](local:1239e43715307240) |
| A5 cobrar comisiones curva | +0.0040 SOL | [ver](local:75ec6f8eb71e0432) |
| A6 migrar a DAMM v2 |  | [ver](local:1942708cc9e178a9) |
| A7 swap en DAMM v2 |  | [ver](local:2840c4edd60d874e) |
| A8 cobrar comisiones de LP | fees totales 0.0042 SOL | [ver](local:dc5f34962954c136) |
| A9.1 proponer tramo 1 |  | [ver](local:b572152cd1a39565) |
| A9.1 finalizar tramo 1 | liberado 0.1200 / 0.4000 SOL | [ver](local:2903dfdc72a6c937) |
| A9.2 proponer tramo 2 |  | [ver](local:a563bba3634a0b0d) |
| A9.2 finalizar tramo 2 | liberado 0.2400 / 0.4000 SOL | [ver](local:4968e2597ce5efdb) |
| A9.3 proponer tramo 3 |  | [ver](local:c0a0324b2b023a1f) |
| A9.3 finalizar tramo 3 | liberado 0.4000 / 0.4000 SOL | [ver](local:6e47fd04386c9974) |

## Raise B · rechazo y liquidación

Tesorería [`CLJfyKaMG38b3dSgtCCxgwSo8YQkhAKJ9FPk7HLQ59Zu`](CLJfyKaMG38b3dSgtCCxgwSo8YQkhAKJ9FPk7HLQ59Zu) · financiado 0.2400 SOL · estado final **liquidating**: el equipo no cobró nada y los holders redimen contra la tesorería.

| Paso | Resultado | Transacción |
| --- | --- | --- |
| B1 crear raise + config DBC |  | [ver](local:242f4c9d122e9286) |
| B2 lanzar pool + bind_pool |  | [ver](local:e815f55b70ff16f2) |
| B3 comprar hasta graduar |  | [ver](local:bd288920a9976288) |
| B4 harvest | tesorería 0.2400 SOL | [ver](local:46d7268e1a9bc5bd) |
| B6 holder recibe 15% del suministro |  | [ver](local:355ab8f2ae389ee2) |
| B7 equipo propone tramo 1 |  | [ver](local:9ba4e5c1226e8e47) |
| B8 holder vota rechazo | bloqueados 150000000000000 tokens (base units) | [ver](local:3d3ec27bac3a1b1f) |
| B10 finalizar → liquidación | estado "liquidating" | [ver](local:67cae562b19f83fc) |
| B11 holder retira su voto |  | [ver](local:9d078defa69416e4) |
| B12 holder redime por SOL | recibió 0.0360 SOL (wSOL) por sus tokens | [ver](local:fff6ee347a12b32c) |
