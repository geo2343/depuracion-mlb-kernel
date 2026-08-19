# DepuracionMLB Kernel

Kernel externo para `@DepuracionMLB`.

## Arquitectura

- **ChatGPT / LLM**: razonamiento deportivo y salidas estructuradas.
- **Kernel**: control de estado, dependencias, cutoff, ownership, recovery, validación, trazas y cierre.
- **Supabase**: persistencia de runs, games, evidencia, eventos y auditoría.
- **Vercel**: ejecución HTTP del Kernel.
- **Google Drive**: informes y documentación humana; no es la base técnica del runtime.

## Estado

`FOUNDATION_BUILDING`

El runtime V0.1 consolidado de Drive se importa como baseline auditado, no como producción. Antes de esta importación se reprodujeron localmente:

- `pytest -q test_runtime.py` → **70 passed**
- `python stress_audit.py` → **STRESS_OK 500 randomized runs**

El baseline conserva `PROTOTYPE_SIMULATION`. Las capas de persistencia real, API desplegable y tool/LLM bridges se desarrollan aparte y no pueden auto-declararse validadas.

## Principio

**El LLM razona. El Kernel controla. Las herramientas demuestran. El Validator comprueba.**
