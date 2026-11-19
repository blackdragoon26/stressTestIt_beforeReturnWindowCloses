# Myprod handoff: the DOA Kit website

The website in `docs/` runs as an ordinary Myprod managed app. This repository builds and publishes the
image. The Myprod operator registers and deploys it. Contract:
[application-onboarding.md](https://github.com/blackdragoon26/Myprod/blob/main/docs/application-onboarding.md)
and [arm64-application-cicd.md](https://github.com/blackdragoon26/Myprod/blob/main/docs/arm64-application-cicd.md).

## Handoff manifest

```txt
name: doakit-site
source commit: the commit that the "Publish and deploy website" workflow run built
image: ghcr.io/blackdragoon26/doakit-site
image digest: printed in that workflow run's summary (sha256:...), multi-platform index
architecture: linux/amd64, linux/arm64
container port: 8080
health path: /healthz
recommended CPU MHz: 100
recommended memory MB: 64
ephemeral data behavior: none written; the image holds only static files
required environment variables: none
required secrets: none
publicly pullable without authentication: yes, once the GHCR package is set to public (see below)
local container smoke command: docker buildx build --platform linux/amd64 --load -t site:smoke -f deploy/Dockerfile . && docker run --rm -p 127.0.0.1:8080:8080 site:smoke
health-check result: 200 "ok" (local, 2026-11-19, amd64; the arm64 variant builds, not run locally)
project test command and result: the workflow's "Smoke test the image" step: every page, doc, script, font 200; POST 405
known limitations: the docs pages load the Markdown renderer from cdn.jsdelivr.net (pinned, SRI-checked)
```

Proposed domain: `doakit.sankalpjha.dev` (rename freely: the product name is not final).

## Operator steps

1. **Push this repository.** The workflow publishes `ghcr.io/blackdragoon26/doakit-site:sha-<commit>` and
   prints the digest in the run summary. The deploy job reports "deployment skipped" for now.
2. **Make the package public:** GitHub, your profile, **Packages**, `doakit-site`, **Package settings**,
   **Change visibility**, Public. Check with `docker pull ghcr.io/blackdragoon26/doakit-site@sha256:<digest>`
   while logged out.
3. **Register** at <https://control.sankalpjha.dev/>, **Managed Apps**, **Add application**:

   | Field | Value |
   | --- | --- |
   | Name | `doakit-site` |
   | Domain | `doakit.sankalpjha.dev` |
   | Container image | `ghcr.io/blackdragoon26/doakit-site@sha256:<digest from step 1>` |
   | Target node | `oracle-worker-1` |
   | Container port | `8080` |
   | CPU reservation | `100` MHz |
   | Memory reservation | `64` MB |
   | Health path | `/healthz` |
   | Environment | none |
   | Create and verify DNS automatically | on |

4. **Deploy** the app (a separate action with its own confirmation). Then check
   `https://doakit.sankalpjha.dev/healthz` returns `ok`.
5. **Automate later releases:** open the app's **CI tokens**, generate one, and save it in this repository
   under **Settings, Secrets and variables, Actions** as `MYPROD_DEPLOY_TOKEN`. From then on, every push
   that changes `docs/` or `deploy/` publishes a new digest and deploys it.

The image needs no secrets and writes nothing. No extra compute is needed: the reservation fits the
existing worker.
