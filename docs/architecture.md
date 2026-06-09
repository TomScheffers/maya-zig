# Maya Query Engine Architecture

Design reference for Maya's streaming query engine on Apache Iceberg at scale. Informed by DuckDB (push execution), DataFusion (planning/optimizer), Polars (morsel parallelism), and Snowflake (partition pruning + pipelined DAG execution).

---

## Goals

- Execute SQL/analytics queries over **very large Iceberg tables**
- Most queries have joins and window functions keyed on **partition-aligned columns**
- **Partition-scattered, parallel push pipelines** as the primary execution strategy
- Bounded memory via partition-local execution; explicit spill when needed
- Zig-native implementation building on existing parquet reader, columnar frame, and `std.Io` concurrency

---

## Core Insight: Partition-Aligned Execution

If joins and window functions are keyed on columns that align with how data is physically organized, we can run **mostly independent pipelines per partition** and avoid expensive global shuffles.

### Three layers of alignment

| Layer | What it does | Iceberg mechanism |
|---|---|---|
| **Plan-time pruning** | Skip files/manifests | Manifest filtering, partition spec, column stats |
| **Scan-time co-location** | Each worker reads only its partition's files | `partition=` in manifest entries, bucket transforms |
| **Execution-time locality** | Join/window/agg stay partition-local | No repartition exchange needed |

### Important refinement

**Hash-partitioning the execution plan is not the same as Iceberg being partitioned on that column.**

1. **Prefer Iceberg's native partition spec** when join/window keys match (identity, year/month/day/hour, bucket transforms)
2. **Only hash-repartition at execution time** when tables are partitioned differently or one side isn't partitioned
3. Treat **co-partitioned join** as an optimizer rule: if `A.partition_key ≡ B.partition_key` and both scans are aligned, elide the exchange entirely

### Window functions

If `PARTITION BY` matches the physical partition key, each pipeline computes windows **locally** with bounded state (often one sorted run per partition, or O(1) state for running aggregates).

---

## Reference: Snowflake-Style Execution

Snowflake uses **push-based, vectorized, pipelined DAG execution** — operators push batches downstream as fast as consumers accept them. Output rows can appear while scans are still active.

They still have blocking operators; they're just **rare in pruned, partition-local plans**:

| Streaming (non-blocking) | Blocking (pipeline breakers) |
|---|---|
| Filter, project | Global sort |
| Many aggregations after partition-local partial agg | Global distinct |
| Hash join when build side fits or is partition-local | Cross-partition hash join build |
| | Some window patterns |

Snowflake minimizes blockers through:
- Aggressive **micro-partition pruning** (static + runtime/dynamic pruning from build-side stats)
- **Co-located plan fragments** — pieces that don't exchange data until a late merge
- **Push flow control** with backpressure instead of deep recursive pull

**Target for Maya:** not zero blocking operators, but optimized plans that are almost entirely partition-local pipelines with a late merge.

---

## Recommended Architecture

Hybrid of **DataFusion-style planning** + **DuckDB-style push execution**, with partition-first planning as the differentiator.

### High-level flow
