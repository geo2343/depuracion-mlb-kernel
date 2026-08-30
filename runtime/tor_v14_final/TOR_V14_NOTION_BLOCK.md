# TOR V1.4 — CIERRE PBP FINAL

QA: **PASS** — 426 juegos, 1871 carreras, 1871 trazas, 0 carreras sin clasificación final.

| PERIOD      |   G |   RS |   OFF_HALF_INNINGS |   HALF_INNINGS_3PLUS |   HALF_INNINGS_3PLUS_PCT |   GAMES_WITH_3PLUS |   GAMES_WITH_3PLUS_PCT |   STARTER_RUNS |   STARTER_RUNS_G |   BULLPEN_RUNS |   BULLPEN_RUNS_G |   RESPONSIBLE_PITCHER_FALLBACKS |
|:------------|----:|-----:|-------------------:|---------------------:|-------------------------:|-------------------:|-----------------------:|---------------:|-----------------:|---------------:|-----------------:|--------------------------------:|
| 2024        | 162 |  671 |               1436 |                   75 |                      5.2 |                 65 |                   40.1 |            435 |            2.685 |            236 |            1.457 |                               0 |
| 2025        | 162 |  798 |               1432 |                   96 |                      6.7 |                 72 |                   44.4 |            453 |            2.796 |            345 |            2.13  |                               0 |
| 2026_CUTOFF | 102 |  402 |                907 |                   43 |                      4.7 |                 34 |                   33.3 |            221 |            2.167 |            181 |            1.775 |                               0 |

## Método
- Universo: MLB StatsAPI `stats=gameLog`, filtrado por fecha de corte.
- Media entrada 3+: linescore oficial por gamePk.
- Carreras abridor/bullpen: `responsiblePitcher` de cada corredor anotador; si MLB omite ese campo se registra explícitamente el fallback al pitcher actual y se conserva en la auditoría.
- Abridor rival: `gamesStarted=1` en boxscore; control duro por juego: STARTER_RUNS + BULLPEN_RUNS = RS.
- RBI no se usa como sustituto de carreras.