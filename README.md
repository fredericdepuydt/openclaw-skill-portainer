# Portainer Skill Fork

This repository is a fork of the original Portainer skill:
<https://clawhub.ai/asteinberger/portainer>

## What this fork adds

- Supports two operation modes:
  - **Direct Portainer mode** (original behavior, uses `X-API-Key`)
  - **Compatible proxy mode** (uses `Authorization: Bearer` when URL ends in `/portainer`)
- Adds read-only commands for:
  - `networks`
  - `container-info`
- Keeps write operations (`start`/`stop`/`restart`/`redeploy`) available **only in direct mode**.
- Designed so `PORTAINER_URL` can point to either:
  - Portainer: `https://portainer.example:9443`
  - Compatible proxy: `https://proxy.example:8000/portainer`

## Configuration

### Direct Portainer mode

```bash
export PORTAINER_URL="https://portainer.example:9443"
export PORTAINER_API_KEY="ptr_xxx"
```

### Compatible proxy mode

```bash
export PORTAINER_URL="https://proxy.example:8000/portainer"
export PORTAINER_API_KEY="your_proxy_token"
```

## Commands

### Read commands (all modes)

```bash
./portainer.sh status
./portainer.sh endpoints
./portainer.sh containers [endpoint-id]
./portainer.sh stacks
./portainer.sh stack-info <stack-id>
./portainer.sh networks [endpoint-id]
./portainer.sh container-info <container-name> [endpoint-id]
./portainer.sh logs <container-name> [endpoint-id] [tail]
```

### Write commands (direct mode only)

```bash
./portainer.sh redeploy <stack-id>
./portainer.sh start <container> [endpoint-id]
./portainer.sh stop <container> [endpoint-id]
./portainer.sh restart <container> [endpoint-id]
```

In proxy mode, write commands are intentionally blocked.

## Security notes

- In proxy mode, sensitive data redaction is expected to happen server-side.
- Keep `PORTAINER_API_KEY` scoped and rotated.
