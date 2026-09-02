# KC V1.0 — RECÁLCULO Y QA FINAL

## Estado rector

- Equipo: Kansas City Royals (MLBAM 118)
- Corte: 2026-07-22
- Universo: 427 juegos — 162 (2024) + 162 (2025) + 103 (2026 al corte)
- Estado QA: PASS
- Statcast: 427/427 juegos
- Carreras trazadas: 1,824
- Carreras sin resolver: 0
- Defensa reconciliada: sí

## Resultados colectivos

| Periodo | G | W-L | RS | RA | R/G | RA/G | Diferencial |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2024 | 162 | 86-76 | 735 | 644 | 4.537 | 3.975 | +91 |
| 2025 | 162 | 82-80 | 651 | 637 | 4.019 | 3.932 | +14 |
| 2026 al 22/07 | 103 | 43-60 | 438 | 534 | 4.252 | 5.184 | -96 |

## Forma reciente al corte

- Últimos 3: 3-0, 12 RS, 9 RA, +3.
- Últimos 5: 4-1, 20 RS, 29 RA, -9.
- Últimos 7: 5-2, 29 RS, 43 RA, -14.
- Últimos 10: 5-5, 36 RS, 61 RA, -25.

## Clasificación 2026 al corte

- Ofensiva: Media — 20.ª MLB por R/G.
- Pitcheo: Débil — 27.º MLB por RA/G.
- Defensa: Media — FRV +2.146.

## Unidades de pitcheo 2026 al corte

- Abridores: 543.0 IP, ERA 4.641, WHIP 1.359, K/9 7.773, BB/9 3.381, HR/9 1.276, FIP 4.433.
- Bullpen: 364.667 IP, ERA 5.380, WHIP 1.555, K/9 7.676, BB/9 4.615, HR/9 1.530, FIP 5.320.

## Controles de cobertura

- F7: 18 filas.
- TTO: 12 filas.
- Unidades abridor/bullpen: 6 filas.
- Splits por mano: 6 filas.
- F10: 9 filas.
- Defensa: 3 periodos.

## Trazabilidad reproducible

- QA: `runtime/kc_v10_final/qa_final_team_research.json`
- Síntesis: `runtime/kc_v10_final/kc_v10_synthesis.json`
- Reconstrucción por juego: `runtime/kc_v10_final/kc_427_game_reconstruction.csv`
- Universo: `runtime/kc_v10_final/kc_427_gamelog_universe.csv`
- Carreras: `runtime/kc_v10_final/kc_run_trace.csv`
- Resultados: `runtime/kc_v10_final/phase2_results_summary.csv`
- Forma reciente: `runtime/kc_v10_final/phase2_recent_form.csv`
- Fuerza de rival: `runtime/kc_v10_final/phase7_integral_matrix.csv`
- Mano: `runtime/kc_v10_final/phase8_handedness_splits.csv`
- Rotación/bullpen: `runtime/kc_v10_final/phase9_rotation_bullpen.csv`
- TTO: `runtime/kc_v10_final/phase9_tto.csv`
- Tercios RA: `runtime/kc_v10_final/phase9_ra_thirds.csv`
- Familias de pitcheo: `runtime/kc_v10_final/phase10_pitch_family_splits.csv`
- Defensa: `runtime/kc_v10_final/phase11_savant_defense_team.csv`
- Ranking MLB al corte: `runtime/kc_v10_final/league_ranks_2026_cutoff.csv`

## Nota de higiene documental

El generador heredado produjo inicialmente un archivo denominado `BAL_V42_FINAL.md`. Su contenido fue auditado y correspondía íntegramente a KC V1.0. Ese artefacto mal nombrado se reemplazó por este archivo canónico `KC_V10_FINAL.md`; no existió contaminación cuantitativa del universo ni del QA.
