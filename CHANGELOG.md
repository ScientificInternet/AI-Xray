# Changelog

## v2.0.0 (2026-05-08)

### Rewritten from scratch
- Single `install.sh` replacing all previous scripts
- VMESS + WS + TLS only (removed Reality, VLESS, Trojan, XTLS, KCP, gRPC)
- AI-powered camouflage site generation with 3-layer fallback:
  - Level 1: Real-time AI generation via Cloudflare Worker
  - Level 2: Local rendering from open-source template pool
  - Level 3: Temporary jiami.dog redirect
- Simplified VPS quality check (3 tests instead of 8)
- Single-file management command `ai-xray`
- Clean repo structure: 7 files total

### Removed
- All multi-protocol support
- `install-simple.sh`, `install-full.sh`
- Legacy README variants
- `_worker.js`, `wrangler.toml`
- All test reports and work logs

### Reference
- `docs/reference/xray-v1-reference.sh` retained as historical reference
