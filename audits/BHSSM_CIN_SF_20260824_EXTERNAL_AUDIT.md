# BHSSM — CIN @ SF — AUDITORÍA EXTERNA DE EJECUCIÓN

Fecha del partido: 2026-08-24  
Game PK: 823183  
Estadio: Oracle Park  
Corte histórico soberano: 2026-08-23  
Snapshot pregame de datos: `dc36be0d29c98f75a80889e413cdf8ce405ad05b` — 2026-08-24T23:27:04Z  
Primer lanzamiento usado por el firewall: 2026-08-25T01:45:00Z

## 1. Alcance

Esta auditoría revisa la ejecución BHSSM aplicada a los 18 bateadores del lineup oficial CIN @ SF. Distingue estrictamente:

1. que el código haya ejecutado;
2. que los datos hayan sido materializados;
3. que se hayan calculado candidatos estadísticos;
4. que el modelo esté certificado para convertir esos candidatos en change points/versiones soberanas.

Una ejecución de software exitosa no equivale a certificación estadística.

## 2. Lineups utilizados

### Cincinnati
1. Elly De La Cruz — 682829
2. Sal Stewart — 701398
3. Dane Myers — 667472
4. Tyler Stephenson — 663886
5. Eugenio Suarez — 553993
6. Matt McLain — 680574
7. JJ Bleday — 668709
8. Jose Trevino — 624431
9. Ivan Johnson — 671155

### San Francisco
1. Drew Gilbert — 687551
2. Rafael Devers — 646240
3. Jung Hoo Lee — 808982
4. Turner Hill — 806367
5. Drew Cavanaugh — 701852
6. Nate Furman — 801501
7. Shay Whitcomb — 694376
8. Grant McCray — 687529
9. Christian Koss — 683766

Abridores registrados: Chase Burns (RHP) por CIN y Carson Whisenhunt (LHP) por SF.

## 3. Ingesta materializada

La primera ejecución numérica completa produjo:

- 583,853 pitcheos MLB previos al corte en el universo de liga;
- 18,948 pitcheos de los 18 bateadores objetivo;
- 8,624 swings;
- 4,674 apariciones al plato reconstruidas;
- 3,124 bolas bateadas;
- 448 checkpoints de estado técnico.

Se materializaron las cuatro tablas atómicas:

- `BTDE_ATOMIC_PITCH_FEATURES.parquet`
- `BTDE_ATOMIC_SWING_FEATURES.parquet`
- `BTDE_ATOMIC_PA_FEATURES.parquet`
- `BTDE_ATOMIC_BIP_FEATURES.parquet`

También se produjeron Source Manifest, Metric Registry, ontología de pitcheos, Measurement Regime Registry, historia AS-OF, historia smoothed, búsqueda de configuración, candidatos de change point, candidatos de versiones y candidatos de patrones.

## 4. Corrección del fallo de implementación anterior

La ejecución ATL@MIL anterior fallaba en Pandas 3.0 al asignar una lista booleana a `retrospective_cp` cuando la columna había sido materializada como `float64`.

La ejecución CIN@SF precrea explícitamente `retrospective_cp` con dtype booleano. La corrida completa posterior terminó correctamente y produjo artefactos, por lo que este fallo quedó resuelto.

## 5. Cobertura real por bateador

La presencia de un jugador en los datos RAW no garantiza historia BHSSM suficiente.

Checkpoints técnicos construidos:

| Equipo | Bateador | Checkpoints | Elegible para detector (>=3) |
|---|---|---:|---|
| CIN | Elly De La Cruz | 51 | Sí |
| CIN | Sal Stewart | 56 | Sí |
| CIN | Dane Myers | 26 | Sí |
| CIN | Tyler Stephenson | 37 | Sí |
| CIN | Eugenio Suarez | 40 | Sí |
| CIN | Matt McLain | 40 | Sí |
| CIN | JJ Bleday | 42 | Sí |
| CIN | Jose Trevino | 8 | Sí |
| CIN | Ivan Johnson | 0 | No |
| SF | Drew Gilbert | 30 | Sí |
| SF | Rafael Devers | 55 | Sí |
| SF | Jung Hoo Lee | 44 | Sí |
| SF | Turner Hill | 0 | No |
| SF | Drew Cavanaugh | 8 | Sí |
| SF | Nate Furman | 0 | No |
| SF | Shay Whitcomb | 1 | No |
| SF | Grant McCray | 3 | Sí, mínima |
| SF | Christian Koss | 7 | Sí |

Por tanto, sólo 14/18 cumplen el mínimo operativo del detector implementado. Cuatro no pueden recibir legítimamente un change point con esta corrida: Ivan Johnson, Turner Hill, Nate Furman y Shay Whitcomb.

## 6. Candidatos calculados — NO CERTIFICADOS

El motor calculó cuatro candidatos antes de aplicar la puerta estricta:

| Bateador | Primera observación | p_change | Distancia de estado | Candidato calculado |
|---|---|---:|---:|---|
| Sal Stewart | 2026-07-28 | 0.5985 | 5.3628 | STRUCTURAL_CHANGE |
| Matt McLain | 2026-06-01 | 0.4292 | 2.9322 | SUPPORTED_CHANGE |
| Matt McLain | 2026-07-03 | 0.5301 | 5.1894 | STRUCTURAL_CHANGE |
| Jung Hoo Lee | 2026-05-04 | 0.4115 | 3.8640 | STRUCTURAL_CHANGE |

Estos cuatro registros son evidencia diagnóstica del comportamiento del ejecutor. **No son change points BHSSM certificados.**

La misma regla se aplica a las 18 filas de `HISTORICAL_VERSION_MAP` producidas antes del gate: son candidatos diagnósticos y no un mapa soberano de versiones.

## 7. Validación temporal obtenida

La validación holdout de la ejecución produjo:

- TP = 1
- FP = 1
- FN = 7
- Precision = 0.50
- Recall = 0.125
- F1 = 0.20
- Detection delay = 1 checkpoint

El recall extremadamente bajo y F1=0.20 impiden considerar superada la certificación temporal.

## 8. Auditoría del BHSSM_ENGINE_CONFIG

Configuración candidata calculada:

- hazard_lambda = 12
- possible_change_threshold = 0.35
- PELT penalty = 2.0
- change_match_tolerance = 2
- minimum_material_change = 2.4511
- structural_material_change = 3.0268
- minimum version duration = 3 checkpoints
- minimum sample authority = 0.5

Problema de gobernanza: estos parámetros fueron seleccionados/calibrados dentro de la corrida específica CIN@SF y después congelados. Eso demuestra reproducibilidad posterior, pero no precommitment. Un threshold no se vuelve soberano simplemente porque se congele después de haber sido escogido en la propia ejecución del partido.

Resultado: `THRESHOLD_PRECOMMITMENT_TEST = FAIL`.

## 9. Sobredeclaraciones detectadas en la auditoría automática inicial

La primera salida automática marcó varios controles como PASS con evidencia insuficiente. La auditoría externa los corrige:

### REGIME_CHANGE_TEST
Se marcó PASS, pero no existe una prueba de perturbación documentada que someta el modelo a cambios reales del régimen de medición. Debe quedar LIMITED.

### PITCH_RECLASSIFICATION_TEST
El runner lo aproximaba por tasa de pitch types desconocidos. Una tasa baja de códigos desconocidos no equivale a probar robustez ante reclasificación histórica. Debe quedar LIMITED.

### CONTEXT_MODEL_APPLIED
Sí existe ajuste contextual, pero no está completo. Incluye pitch family, velocidad, movimiento, ubicación, mano, conteo y un proxy previo de calidad del pitcher. No incorpora de forma completa los competidores contextuales pertinentes del contrato —park/game state, starter vs reliever, catcher y defensa cuando corresponda—. Debe quedar LIMITED para certificación.

### COUNTEREVIDENCE_SEARCHED
El código prueba cambio de exposición de pitch mix, pero no ingiere de manera completa injury regime, return from IL, playing-time change, platoon usage change y lineup usage change. No puede conservar PASS contractual.

### VERSION_DURATION_CONTROLLED
Existe una regla mínima de tres checkpoints descrita por el propio código como “semi-Markov-like”. No es todavía un modelo de duración semi-Markov estimado/validado. Debe quedar LIMITED.

## 10. Diferencias entre implementación y contrato estadístico completo

La implementación es funcional como prototipo cuantitativo, pero todavía simplifica varias piezas del contrato:

- las métricas técnicas principales se convierten en residuales de ventanas móviles y z-scores;
- no está implementada en toda su extensión la capa jerárquica Beta/Logistic-Binomial para las señales binarias;
- no está implementada en toda su extensión la capa robusta Student-t posterior para las señales continuas;
- `state_uncertainty` es un proxy conservador, no una incertidumbre posterior integral calibrada;
- faltan campos atómicos suficientes de swing mechanics;
- no existe expected BIP conversion profundo con la cobertura requerida.

Por tanto, `HIERARCHICAL_METRIC_MODEL_COMPLIANCE`, `LATENT_STATE_POSTERIOR_MODEL`, `STATE_UNCERTAINTY_CALIBRATION`, `SWING_MECHANICS_ATOMIC` y `BIP_EXPECTED_CONVERSION_ATOMIC` no pueden certificarse como PASS.

## 11. Convergencia del modelo contextual

Los logs de ejecución muestran múltiples `ConvergenceWarning` de scikit-learn para LogisticRegression (`max_iter was reached`). El pipeline produjo resultados, pero no debe afirmarse convergencia completa de todos los modelos contextuales.

Resultado: `CONTEXT_MODEL_CONVERGENCE_TEST = LIMITED`.

## 12. Patrones temporales

La corrida calculó cuatro patrones con correlaciones Spearman de validación positivas y FDR muy bajo. Sin embargo, las observaciones provienen de checkpoints móviles solapados y medidas repetidas dentro de bateadores.

La corrección Benjamini-Hochberg controla multiplicidad entre patrones, pero no resuelve por sí sola la dependencia dentro de jugador/ventanas solapadas.

Por tanto, los cuatro patrones quedan como `PATTERN_CANDIDATES_UNCERTIFIED`; no como `PATTERN_REGISTRY` soberano hasta implementar validación temporal sensible a dependencia/cluster/repeated measures.

## 13. Controles que sí quedaron sustentados

- identificación del partido y de los 18 bateadores;
- snapshot de datos pregame;
- corte histórico 2026-08-23;
- timestamp firewall / no future game data;
- tablas atómicas materializadas;
- denominadores y relojes implementados;
- BOCPD ejecutado;
- PELT ejecutado;
- separación AS-OF vs smoothed;
- FDR aplicado a la familia de patrones calculados;
- repetición determinista de detectores con misma data/config;
- Source Manifest y hashes de archivos fuente;
- autoridad bloqueada para CURRENT_VERSION, TODAY_STATE, MATCHUP, P(HIT) y decisión de apuesta.

## 14. Veredicto contractual

La conclusión soberana correcta es:

`MODEL_CERTIFICATION_GATE = FAIL`

`BHSSM_STATISTICAL_AUDIT = FAIL`

`BHSSM_EXECUTION_STATUS = BLOCKED_BY_MODEL_CERTIFICATION`

`CHANGE_POINT_REGISTRY = NOT_AUTHORIZED`

`HISTORICAL_VERSION_MAP = NOT_AUTHORIZED`

`PATTERN_REGISTRY = NOT_AUTHORIZED`

`HANDOFF_TO_CVD = BLOCKED`

`CURRENT_VERSION = OUTSIDE_BHSSM_AUTHORITY / NOT AUTHORIZED`

`P(HIT) = NOT AUTHORIZED`

`BETTING_DECISION = NOT AUTHORIZED`

Los cálculos diagnósticos se conservan expresamente para auditoría y desarrollo. No deben borrarse ni promoverse a conclusiones soberanas.

## 15. Qué falta para convertir BHSSM en motor certificado

1. Entrenar y validar un `BHSSM_ENGINE_CONFIG` independiente del partido y congelarlo antes de cualquier ejecución objetivo.
2. Mejorar/validar convergencia de los modelos de EXPECTED_RESPONSE.
3. Implementar la jerarquía estadística del contrato para métricas binarias y continuas.
4. Implementar posterior/uncertainty real del estado latente.
5. Incorporar swing mechanics atómico con cobertura suficiente.
6. Construir expected BIP conversion reproducible.
7. Ejecutar pruebas reales de regime change y pitch reclassification robustness.
8. Incorporar contraevidencia de salud, IL, playing time, platoon y lineup role.
9. Sustituir la regla “semi-Markov-like” por el control de duración certificado definido por el contrato.
10. Implementar validación de patrones sensible a dependencia temporal y repetición por jugador.
11. Resolver cobertura insuficiente para bateadores con historia mínima o establecer una política explícita de `NO_STATE_ESTIMABLE`.
12. Repetir rolling-origin hasta alcanzar los umbrales de certificación predefinidos, sin ajustar esos umbrales al partido CIN@SF.

Hasta entonces, la salida correcta no es inventar una versión actual, sino conservar la evidencia y bloquear el handoff.
