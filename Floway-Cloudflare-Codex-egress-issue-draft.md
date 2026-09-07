# [Codex][Cloudflare] No viable built-in egress: `direct_connect` cannot dial `chatgpt.com` and `direct_fetch` is rejected with 403

> **Provenance.** This report was drafted with Codex from a human-directed live reproduction, then reviewed by the reporter before filing. The observations below come from one Cloudflare Workers deployment. Claims that may not generalize to every account or colo are marked accordingly. No credentials, account identifiers, domain names, or complete upstream error pages are included.

## Summary

On Cloudflare Workers, a Codex upstream with an empty Proxy Fallback List resolves to `direct_connect`. Model refresh then fails before HTTP because Cloudflare Workers cannot open outbound TCP sockets to Cloudflare-owned IP ranges, and `chatgpt.com` resolves to that network.

Explicitly selecting `direct_fetch` avoids the TCP restriction and reaches the ChatGPT HTTP edge, but in the reproduced deployment the Codex `/models` request is rejected with an HTML `403` response from the upstream edge.

The result is that neither built-in direct transport provides a working Codex path in this deployment:

- empty list / `direct_connect` -> deterministic TCP dial failure;
- explicit `direct_fetch` -> upstream HTML 403;
- no operator-managed proxy -> no remaining fallback candidate.

The second result may be environment- or egress-dependent. This issue does not claim that every Cloudflare account or colo receives the same 403.

## Environment

- Floway: `main` at `ac2bbb04352033a7d9d74574a9d465d40395ef06`
- Platform: Cloudflare Workers
- Wrangler: `4.81.0`
- Observed runtime location: `SIN`
- Provider: Codex, using subscription credentials imported through the dashboard
- Credential status: refreshed successfully and shown as healthy before model refresh
- Proxy catalog: empty
- Initial `proxy_fallback_list`: `[]`

## Reproduction

1. Deploy Floway to Cloudflare Workers.
2. Import a Codex credential through the dashboard and confirm that credential refresh completes successfully.
3. Leave the upstream's Proxy Fallback List empty.
4. Refresh the upstream model list.
5. Observe the `direct_connect` failure.
6. Retry the same model-catalog operation with `direct_fetch` as the only egress candidate.
7. Observe the upstream 403.

The `direct_fetch` comparison was performed as a request-scoped override so that it tested the transport without changing the persisted reproduction state.

## Actual behavior

### Empty list / `direct_connect`

Model refresh fails with:

```text
ProxyDialError: tcp connect to chatgpt.com:443 failed
```

This matches the current implicit fallback in [`packages/gateway/src/dial/fetcher.ts`](https://github.com/Menci/Floway/blob/ac2bbb04352033a7d9d74574a9d465d40395ef06/packages/gateway/src/dial/fetcher.ts#L73-L80) and Cloudflare's documented restriction on outbound TCP sockets to Cloudflare IP ranges.

### Explicit `direct_fetch`

The request reaches the upstream HTTP path, but model refresh fails with:

```text
Codex /models fetch failed: 403 <html>...
```

Only the status and response shape are included here. The complete HTML response is deliberately omitted.

The error is raised by [`fetchCodexCatalog`](https://github.com/Menci/Floway/blob/ac2bbb04352033a7d9d74574a9d465d40395ef06/packages/provider-codex/src/models.ts#L25-L44) after the fetcher returns a non-2xx HTTP response. This distinguishes it from the preceding TCP dial failure.

## Expected behavior

Floway should make the supported deployment boundary actionable for a Cloudflare-hosted Codex upstream. In particular:

1. A newly imported Codex upstream on Cloudflare should not silently inherit a transport that is known to be unable to dial its fixed `chatgpt.com` backend.
2. If no built-in transport is viable, the dashboard or model-refresh error should say that the operator needs an externally managed proxy or a non-Workers deployment, rather than suggesting another credential refresh.
3. The Cloudflare deployment documentation should describe the Codex-specific interaction between the `direct_connect` restriction and a possible upstream rejection on `direct_fetch`.

This expected outcome does not require Floway to bypass or weaken ChatGPT's upstream anti-abuse controls.

## Existing documentation and related change

PR [#357](https://github.com/Menci/Floway/pull/357) changed an empty Proxy Fallback List from `direct_fetch` to `direct_connect` and already records the relevant tradeoff:

- Workers refuse to `connect()` to Cloudflare-owned addresses.
- An upstream resolving to one must explicitly select Direct (Fetch).

Cloudflare's TCP Socket documentation likewise states that outbound TCP sockets to Cloudflare IP ranges are blocked and recommends `fetch()` for HTTP requests on ports 80 or 443:

- https://developers.cloudflare.com/workers/runtime-apis/tcp-sockets/

The advisory explains the first failure. It does not cover the observed state where the required `direct_fetch` path itself reaches the ChatGPT edge but receives a 403.

## What has been ruled out

- The initial error is not an expired access token: it occurs before an HTTP response exists.
- General HTTP reachability is available through `direct_fetch`: that path returns an upstream HTTP response.
- The two errors are not aliases for one failure: one is a socket dial error and the other is an HTTP 403 returned after transport establishment.
- There was no configured external proxy or fallback candidate during the reproduction.

## What this issue does not claim

- It does not claim that every Cloudflare Workers deployment receives the same `direct_fetch` 403.
- It does not establish which exact ChatGPT/Cloudflare edge rule generated the 403.
- It does not claim that the imported account or credential was suspended.
- It does not request header spoofing, origin bypass, or any other workaround for upstream anti-abuse enforcement.

## Possible fix directions

These are possible directions rather than a prescribed design:

1. Let the Codex provider declare that its fixed `chatgpt.com` backend is incompatible with Cloudflare `direct_connect`, then validate or warn when the resolved egress policy selects it.
2. Add a Cloudflare/Codex preflight that exercises model discovery through the resolved egress policy and reports transport-specific remediation.
3. Classify the known socket restriction separately from credential failures, and classify an upstream HTML 403 separately from a Codex API authentication response.
4. Document an operator-supported topology for Codex when neither built-in direct transport works, such as an external proxy or the Node deployment target.

## Security and privacy notes

The reporter can provide additional redacted status codes and transport outcomes if needed. Credentials, authorization headers, ChatGPT account identifiers, Cloudflare account/resource identifiers, deployment domains, cookies, and complete edge error pages will not be posted publicly.
