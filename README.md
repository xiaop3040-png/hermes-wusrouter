# Hermes Agent — WusRouter installer

Interactive installer for an existing Hermes Agent installation using `https://wusrouter.com/v1`.

## One-line setup

Review [install.sh](./install.sh), then run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xiaop3040-png/hermes-wusrouter/main/install.sh)
```

## What it does

- Requires `hermes`, `curl`, `python3`, Bash, and an interactive terminal.
- Prompts for an API key without echoing it.
- Authenticates against `GET /v1/models` and lets you select a model.
- Backs up `~/.hermes/config.yaml` and `~/.hermes/.env`.
- Attempts to configure Hermes using its `config set` command.
- Rolls back both files if configuration fails.
- Does not automatically perform paid inference.

**Important:** Review scripts before execution. The API key is sent to WusRouter and stored locally. Backups may contain credentials. This installer has not been end-to-end tested with a live WusRouter account or every Hermes version.

## Restore

Copy `config.yaml` and `.env` from the backup directory reported by the installer into `~/.hermes/`. If a file did not exist previously, remove the new counterpart.
