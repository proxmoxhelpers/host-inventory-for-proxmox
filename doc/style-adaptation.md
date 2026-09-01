# Style adaptation for POSIX shell

The supplied Batch File Style Guide v1.8.0 remains the project coding standard in spirit.

Applied principles include:
- explicit setup / main / end flow;
- readable application metadata and semantic versioning;
- documented reusable functions with independent versions;
- descriptive function-private prefixes;
- explicit dependencies, outputs, returns and side effects;
- built-in help/version before installation or collection;
- semantic ANSI color separated from machine-readable output;
- standalone collectors where practical;
- capability detection for optional tools;
- focused tests for public commands and failure paths;
- immutable versioned project deliveries.

v0.5.0 extends the interface discipline to human-readable output: every collection function has a corresponding documented `print_*_summary` function. Summary functions consume collector envelopes instead of independently probing the host, so presentation cannot silently diverge from the machine-readable evidence.

Batch-specific parser, label, CALL and ERRORLEVEL mechanics are not forced onto POSIX shell.


v0.7.0 keeps collector and view applications independently executable. The duplication is intentional: individual files can be copied to a Proxmox host without requiring a shared runtime or sibling collector.
