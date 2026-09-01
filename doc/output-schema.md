# Host Inventory for Proxmox output schema v0.5.0

Each collector emits one JSON envelope:

```json
{
  "schema_version": "0.5.0",
  "collector": "cpu-topology",
  "collected_at": "ISO timestamp",
  "hostname": "host",
  "data": {},
  "notes": [],
  "errors": []
}
```

The matching `print_*_view` and `print_*_summary` functions consume this envelope and render factual human-readable text. `print_*_summary` is now a backward-compatible alias of the richer view renderer.

`run_all.sh` writes:
- one `collect_*.json` file per successful collector;
- one `summaries/collect_*.txt` summary per successfully rendered collector;
- `inventory.json`, a JSON array containing successful envelopes;
- `manifest.json`, orchestration metadata;
- `summary.txt`, the concatenated human-readable summaries.

A successful manifest collector item has:

```json
{
  "script": "collect_platform.sh",
  "file": "collect_platform.json",
  "summary_file": "summaries/collect_platform.txt",
  "rc": 0,
  "success": true
}
```

Summary rendering remains descriptive. Policy/evaluation state is intentionally absent from this schema.


## Harmonized model

Collector envelopes remain schema `0.5.0`. `harmonize_host.sh` emits a separate `host-map` model with schema `0.8.9`; see `host-map-schema.md`.
