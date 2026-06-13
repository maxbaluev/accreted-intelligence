# Accreted Intelligence

> *Most AI forgets. This is the architecture for AI that remembers what worked — and gets wiser.*

A model that scores 90% on a benchmark today scores 90% tomorrow. It doesn't learn from deployment, doesn't track which of its outputs led to good outcomes, doesn't remember last week's mistake. It generates intelligence and throws it away.

**Accreted intelligence** is the bet that this is temporary: move learning out of model weights and into *scored external state* — where judgment compounds from contact with reality, and the model is a **replaceable processor** rather than the locus of intelligence.

**acc** is a working kernel for that thesis: a Recursive Language Model over a late-interaction scored-token memory. Two verbs over one memory; credit defaults to a weak prior, and only reality earns full weight.

### Read
- **[Whitepaper →](whitepaper.md)** — the problem (credit assignment + retrieval-to-action binding), the thesis, the architecture *with the math*, and an honest account of what's proven vs. open.
- **[Architecture overview →](architecture-overview.md)** — the skimmable tour: two verbs, late-interaction memory, reality-gated credit, the trust-kernel.

### The primitives, in the open
The engine is private; the building blocks are public — each shippable on its own:
- **[maxsim-rs](https://github.com/maxbaluev/maxsim-rs)** — late-interaction MaxSim, in clean Rust.
- **[colpali-retrieve](https://github.com/maxbaluev/colpali-retrieve)** — multimodal late interaction (text → document images).
- **[scored-rerank](https://github.com/maxbaluev/scored-rerank)** — ranking that learns from outcomes (Beta posteriors + Thompson sampling).
- **[mcp-retrieve](https://github.com/maxbaluev/mcp-retrieve)** — late-interaction retrieval as an MCP tool.

---
Max Baluev · maxbaluev@outlook.com · [Telegram](https://t.me/maxbaluev)
