# Analisi Costi / Tempi / Benefici
## Lift-and-Shift vs Refactor Cloud-Native — Contoso Financial

---

## 1. Ipotesi di base

- Team disponibile: 3 stream paralleli (uno per workload)
- Workload: Web App, Batch Job notturno, Reporting DB
- Cloud target: AWS
- Orizzonte di analisi: 24 mesi post-migrazione

---

## 2. Timeline comparata

### Lift-and-Shift

| Workload | Attività | Settimane |
|----------|----------|-----------|
| Web App | Impacchetta su AMI, lancia su EC2 + ALB | 2–3 |
| Batch Job | Sposta su EC2 scheduled, stessa cron | 1–2 |
| Reporting DB | Dump + restore su RDS, aggiorna connection string | 2–3 |
| **Cutover + stabilizzazione** | Test, rollback plan, go-live | 2 |
| **Totale elapsed (parallelo)** | | **~6–7 settimane** |

> Il collo di bottiglia è il Reporting DB: la migrazione dati con downtime controllato richiede una finestra di manutenzione larga.

### Refactor Cloud-Native

| Workload | Attività | Settimane |
|----------|----------|-----------|
| Web App | Containerizza (Dockerfile multi-stage), ECS Fargate, CloudFront, S3 per statici | 4–5 |
| Batch Job | Refactor su AWS Batch + EventBridge, rendi idempotente, output su S3 | 3–4 |
| Reporting DB | RDS Multi-AZ, read replica, IAM auth, migrazione credenziali 5 team | 3–4 |
| **Cutover + stabilizzazione** | Test, rollback plan, go-live | 2 |
| **Totale elapsed (parallelo)** | | **~8–9 settimane** |

### Delta reale: **2 settimane** di differenza

Con 3 stream paralleli il refactor non è "due volte più lungo" — è il 25–30% in più sul tempo totale.
Senza parallelizzazione (sequenziale) il delta sarebbe 6–8 settimane: lì il lift-and-shift vince sul tempo.

---

## 3. Costi di migrazione (one-time)

| Voce | Lift-and-Shift | Refactor |
|------|---------------|---------|
| Effort team (settimane/persona) | ~9 | ~15 |
| Costo stimato team (€450/giorno) | ~€16.200 | ~€27.000 |
| Tooling / licenze aggiuntive | basso | medio (CI/CD, registry) |
| **Totale stimato one-time** | **~€18.000** | **~€30.000** |

> Delta iniziale: **~€12.000** a favore del lift-and-shift.

---

## 4. Costi operativi mensili post-migrazione (AWS)

### Lift-and-Shift — infrastruttura "as-is" su EC2

| Risorsa | Configurazione | Costo/mese |
|---------|---------------|------------|
| Web App | 2x EC2 t3.large (24/7, over-provisioned) | ~€240 |
| Batch Job | 1x EC2 c5.2xlarge (24/7 acceso per sicurezza) | ~€280 |
| Reporting DB | RDS db.m5.large Single-AZ | ~€180 |
| ALB + trasferimento dati | — | ~€60 |
| **Totale mensile** | | **~€760/mese** |

> Problema strutturale: il Batch Job on-prem girava di notte ma la VM era accesa H24. Su EC2 si replica lo stesso pattern — si paga anche quando non fa nulla.

### Refactor Cloud-Native

| Risorsa | Configurazione | Costo/mese |
|---------|---------------|------------|
| Web App | ECS Fargate (auto-scaling, 0.5 vCPU/1GB baseline) | ~€90 |
| Batch Job | AWS Batch (paga solo l'esecuzione, ~2h/notte) | ~€15 |
| Reporting DB | RDS db.m5.large Multi-AZ + 1 read replica | ~€320 |
| CloudFront + S3 | CDN + statici | ~€30 |
| ALB + trasferimento dati | — | ~€40 |
| **Totale mensile** | | **~€495/mese** |

### Delta operativo: **€265/mese** a favore del refactor

---

## 5. Analisi break-even

| | Valore |
|---|---|
| Costo extra one-time refactor | +€12.000 |
| Risparmio mensile operativo | €265/mese |
| **Break-even** | **~45 mesi** |

A prima vista sembra lungo. Ma questo calcolo **non include**:

- Il costo del **secondo progetto di refactor** che il lift-and-shift rende inevitabile (il CTO lo vorrà entro 12–18 mesi). Quel progetto costerà più del primo perché ora hai anche il debito tecnico cloud da smontare.
- Il costo del **downtime** che un'architettura non-HA (Single-AZ, EC2 fisso) porta con sé.
- Il costo delle **operazioni manuali** che restano su un'infrastruttura non cloud-native (patch, scaling manuale, backup).

### Ricalcolo con secondo progetto di refactor incluso

| Scenario | Costo 24 mesi |
|----------|--------------|
| Lift-and-Shift (migrazione + ops 24m + secondo refactor stimato €25k) | €18.200 + €18.240 + €25.000 = **€61.440** |
| Refactor diretto (migrazione + ops 24m) | €30.000 + €11.880 = **€41.880** |

**Risparmio netto a 24 mesi: ~€19.500 a favore del refactor.**

---

## 6. Benefici non monetizzati

| Beneficio | Lift-and-Shift | Refactor |
|-----------|---------------|---------|
| Auto-scaling web app | No | Sì (Fargate) |
| Batch idempotente e riavviabile | No | Sì |
| Read replica per isolare carichi analitici | No | Sì |
| HA Multi-AZ DB | No (Single-AZ) | Sì |
| Residency controls (Compliance) | Parziale | Completo (VPC, KMS) |
| Onboarding sviluppatori più rapido | No | Sì (container) |
| SRE dorme la notte | No | Più probabile |

---

## 7. Rischi per approach

### Rischi del Lift-and-Shift
- **Debito tecnico garantito:** il refactor avverrà comunque, ma in condizioni peggiori (sotto pressione, con prod live sul cloud)
- **Costi nascosti:** EC2 over-provisioned, storage non ottimizzato, nessun auto-scaling
- **Dipendenze hardcoded** (IP, filesystem condivisi) si portano sul cloud e diventano più difficili da risolvere
- **Il CTO non è allineato:** rischio di conflitto interno post-go-live

### Rischi del Refactor
- **Timeline più lunga:** 2 settimane extra di esposizione (gestibile con parallizzazione)
- **Complessità di coordinamento** tra i 3 stream (mitigabile con CLAUDE.md per workload e checkpoint settimanali)
- **Curva di apprendimento** su ECS/AWS Batch per il team (mitigabile con formazione mirata nelle prime 2 settimane)

---

## 8. Conclusione dello studio

Il refactor costa **€12.000 in più oggi** ma **risparmia €19.500 nei 24 mesi** se si considera il costo inevitabile del secondo progetto che il lift-and-shift genera.

La parallelizzazione per workload riduce il delta temporale a **sole 2 settimane** rispetto al lift-and-shift, rendendo l'argomento "è troppo lento" non difendibile con i dati.

**Raccomandazione:** refactor cloud-native diretto, con i 3 stream in parallelo.
Il Memo dovrebbe portare questa analisi davanti a CFO e CTO come base della decisione.
