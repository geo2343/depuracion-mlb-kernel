# BOS V15 — Integrity close

QA: **PASS**

Reopened blocks reconstructed: B3, B6, B7, B17, B20, B22-B26. V14 granular closure remains authoritative for B11/B13-B15/B18/B19. All performance data are pregame through 2026-07-23; Game 824733 result/events are excluded.

## QA
| cutoff     |   game_pk |   pregame_games |   B03_rows |   B03_players |   B06_rows |   B07_rows |   B07_players |   B07_windows_min |   B17_rows |   B20_rows |   B22_B24_rows |   B25_rows | B26_present   | V14_QA   | status   |
|:-----------|----------:|----------------:|-----------:|--------------:|-----------:|-----------:|--------------:|------------------:|-----------:|-----------:|---------------:|-----------:|:--------------|:---------|:---------|
| 2026-07-23 |    824733 |             101 |        130 |            13 |         13 |        156 |            13 |                12 |         10 |         13 |              3 |          4 | True          | PASS     | PASS     |

## Segment matrix
| BLOCK    | ORDERS      | BATTERS                                                                                                 |   SEASON_PA |   BB_PCT |   K_PCT |   XBH_PCT |   HR_PCT |   HR_SHARE_XBH |   MEAN_WOBA |   MEAN_XWOBA |   U10_PA |   U10_MEAN_WOBA | ORDER_CHANGES_VS_U10                                                                                                                              | STRENGTH               | VULNERABILITY                              | MATCHUP                             | SAMPLE                             |
|:---------|:------------|:--------------------------------------------------------------------------------------------------------|------------:|---------:|--------:|----------:|---------:|---------------:|------------:|-------------:|---------:|----------------:|:--------------------------------------------------------------------------------------------------------------------------------------------------|:-----------------------|:-------------------------------------------|:------------------------------------|:-----------------------------------|
| B22_TOP4 | 1,2,3,4     | Anthony Seigler | Ceddanne Rafaela | Wilyer Abreu | Willson Contreras                                   |        1323 |  7.93651 | 21.0128 |   9.5994  |  3.62812 |       0.377953 |    0.358331 |     0.339043 |      146 |        0.3951   | Anthony Seigler:1->1.0 | Ceddanne Rafaela:2->2.0 | Wilyer Abreu:3->3.0 | Willson Contreras:4->4.0                                                 | traffic/power balanced | no single dominant aggregate vulnerability | Use B18 individual matrix; no pick. | Season + U10 explicitly separated. |
| B23_TOP6 | 1,2,3,4,5,6 | Anthony Seigler | Ceddanne Rafaela | Wilyer Abreu | Willson Contreras | Masataka Yoshida | Caleb Durbin |        1891 |  7.82655 | 18.4558 |   9.09572 |  3.27869 |       0.360465 |    0.346812 |     0.327556 |      219 |        0.39994  | Anthony Seigler:1->1.0 | Ceddanne Rafaela:2->2.0 | Wilyer Abreu:3->3.0 | Willson Contreras:4->4.0 | Masataka Yoshida:5->5.0 | Caleb Durbin:6->6.0 | traffic/power balanced | no single dominant aggregate vulnerability | Use B18 individual matrix; no pick. | Season + U10 explicitly separated. |
| B24_6_9  | 6,7,8,9     | Caleb Durbin | Jarren Duran | Andruw Monasterio | Connor Wong                                           |        1079 |  7.32159 | 21.8721 |   7.87766 |  2.68767 |       0.341176 |    0.313264 |     0.302022 |      123 |        0.374953 | Caleb Durbin:6->6.0 | Jarren Duran:7->7.0 | Andruw Monasterio:6->8.0 | Connor Wong:8->9.0                                                         | traffic/power balanced | no single dominant aggregate vulnerability | Use B18 individual matrix; no pick. | Season + U10 explicitly separated. |

## Toronto bullpen comparator
```json
{
  "window": "2026-07-17..2026-07-23",
  "games": 7,
  "bullpen_ip": "29.1",
  "ER": 14,
  "K": 30,
  "BB": 8,
  "ER9": 4.295454545454546,
  "pitches": 484,
  "used_on_2026-07-23": [
    {
      "pitcher": "Louis Varland",
      "pitches": 15,
      "outs": 3
    },
    {
      "pitcher": "Tyler Rogers",
      "pitches": 9,
      "outs": 3
    }
  ],
  "u10_opponent_bullpen_ER9": 3.9789473684210526,
  "comparability_delta_ER9": 0.3165071770334933,
  "note": "Availability inferred only from recent workload; no guarantee of manager usage."
}
```

No pick or JRC verdict is emitted.