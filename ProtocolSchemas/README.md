# Codex app-server protocol baseline

`Codex-0.142.4/` is generated from the exact external executable used as the
first verified BenBenBen baseline:

```sh
/opt/homebrew/bin/codex app-server generate-json-schema \
  --out ProtocolSchemas/Codex-0.142.4
```

The client advertises `experimentalApi: false` and only depends on the stable
thread, turn, account, streaming, Diff, usage, and approval surface covered by
the contract tests. Generated schemas may contain experimental definitions;
their presence is not permission for the app to call them.

When the selected Codex version changes, generate a new versioned directory,
run `AgentProtocolTests`, and update `CodexProtocolBaseline.codexVersion` only
after reviewing the schema diff.
