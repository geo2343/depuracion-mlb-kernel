# ATH V4.2 — DEFENSA Y QA FINAL DE INVESTIGACIÓN

| PERIOD      |   PLAYERS |   FRV_TOTAL |   INF_OF_RUNS |   RANGE_RUNS |   ARM_RUNS |   DP_RUNS |   REC_1B_RUNS |   CATCHING_RUNS |   FRAMING_RUNS |   THROWING_RUNS |   BLOCKING_RUNS |   TOP_LEVEL_RECON |   TOP_LEVEL_DELTA |   CATCHER_COMPONENT_RECON |   CATCHER_DELTA |
|:------------|----------:|------------:|--------------:|-------------:|-----------:|----------:|--------------:|----------------:|---------------:|----------------:|----------------:|------------------:|------------------:|--------------------------:|----------------:|
| 2024        |        23 |     -51.487 |       -32.755 |      -39.022 |      3.563 |     4.445 |        -1.741 |         -18.732 |        -14.59  |           2.471 |          -6.613 |           -51.487 |                 0 |                   -18.732 |               0 |
| 2025        |        25 |     -17.44  |       -14.038 |      -11.01  |     -2.175 |    -1.506 |         0.652 |          -3.402 |         -2.954 |          -0.043 |          -0.404 |           -17.44  |                 0 |                    -3.402 |              -0 |
| 2026_CUTOFF |        25 |     -21.615 |       -18.321 |      -22.436 |      0.826 |     0.35  |         2.939 |          -3.295 |         -6.49  |           2.009 |           1.186 |           -21.615 |                 0 |                    -3.295 |              -0 |

## Control final

**PASS** — 425 juegos; RS 643/733/453; RA 764/817/565; 1,829 carreras ofensivas trazadas; 0 sin responsiblePitcher; Statcast ofensivo 162/162/101; F7=18 filas; F10=9 filas; rotación/bullpen 2024 cerrados; defensa Savant 3/3 periodos reconciliada.

- `FRV_TOTAL = INF_OF_RUNS + CATCHING_RUNS` en cada periodo.
- `CATCHING_RUNS = FRAMING_RUNS + THROWING_RUNS + BLOCKING_RUNS` en cada periodo.
- `THROWING_RUNS` se conserva como componente primario del control del running game por el catcher; no se sustituye por bases robadas brutas.
- El histórico O/U permanece como subsistema separado y no forma parte de este QA de investigación del equipo.