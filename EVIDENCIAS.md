# Evidências de funcionamento

Este documento separa evidência versionada, validação repetível e pendências externas.
Os arquivos existentes foram gerados por execução real da stack; não há screenshot
fabricado nem execução de CI de outro repositório apresentada como evidência deste.

Reprodução local:

```bash
docker compose down -v
docker compose up --build -d
./scripts/wait-stack.sh
./scripts/smoke-test.sh
./scripts/generate-traffic.sh 3
./scripts/verify-stack.sh --skip-tests
./scripts/capture-evidence.sh
```

## Matriz da rubrica

| Requisito | Implementação e validação | Evidência versionada |
|---|---|---|
| Dockerfile multistage | Build Maven/JDK separado de runtime JRE; a auditoria verifica ausência de fonte e toolchain | [`Dockerfile`](Dockerfile), [`18-multistage-inspecao.txt`](docs/evidencias/18-multistage-inspecao.txt) |
| Testes | `mvn test` local e no estágio de build | [`19-mvn-test.txt`](docs/evidencias/19-mvn-test.txt) |
| Compose sem setup manual | `app`, Prometheus, Grafana, MongoDB, OpenSearch, Graylog e `graylog-init`, com healthchecks e provisionamento | [`10-docker-compose-ps.txt`](docs/evidencias/10-docker-compose-ps.txt), [`docker-compose.yml`](docker-compose.yml) |
| Prometheus | Scrape de `app:8080/actuator/prometheus`, target UP e consultas reais | [`02-prometheus-targets.png`](docs/evidencias/02-prometheus-targets.png), [`12-prometheus-targets.json`](docs/evidencias/12-prometheus-targets.json), [`14-prometheus-metricas-consultadas.txt`](docs/evidencias/14-prometheus-metricas-consultadas.txt) |
| Grafana | Data source e dashboard provisionados; heap, CPU, RPS, contagem HTTP e latência por famílias | [`05-grafana-dashboard.png`](docs/evidencias/05-grafana-dashboard.png), [`15-grafana-provisionamento.txt`](docs/evidencias/15-grafana-provisionamento.txt), [`spring-boot-observability.json`](grafana/dashboards/spring-boot-observability.json) |
| Graylog | Input GELF automático, logs DEBUG/INFO/WARN/ERROR, campos estruturados e stack trace | [`11-graylog-init-logs.txt`](docs/evidencias/11-graylog-init-logs.txt), [`16-graylog-logs-por-nivel.txt`](docs/evidencias/16-graylog-logs-por-nivel.txt), [`17-graylog-mensagem-exemplo.txt`](docs/evidencias/17-graylog-mensagem-exemplo.txt) |
| CI/CD e GHCR | Workflow versionado com build/teste/package, Compose lint, imagem, smoke, publicação em push na `main` e Trivy. Por regra deste fechamento, ele não é executado. | [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml) |

## Evidências visuais

| Arquivo | Conteúdo |
|---|---|
| [`01-interface-aplicacao.png`](docs/evidencias/01-interface-aplicacao.png) | Aplicação em execução e ações reais. |
| [`02-prometheus-targets.png`](docs/evidencias/02-prometheus-targets.png) | Target `spring-boot-app` UP. |
| [`03-prometheus-grafico-rps.png`](docs/evidencias/03-prometheus-grafico-rps.png) | Tráfego HTTP por status. |
| [`04-graylog-logs.png`](docs/evidencias/04-graylog-logs.png) | Graylog Search com logs reais, timestamps, origem e mensagens nos níveis DEBUG/INFO/WARN/ERROR. |
| [`05-grafana-dashboard.png`](docs/evidencias/05-grafana-dashboard.png) | Dashboard atual com o painel de latência por família HTTP e séries 2xx, 4xx e 5xx visíveis. |

### Capturas concluídas

`04-graylog-logs.png` foi capturado no Graylog Search com a consulta
`application:spring-devops-observability`; a tela mostra timestamps, origem e mensagens
reais. `05-grafana-dashboard.png` mostra o painel **Tempo medio de resposta por familia
HTTP** com as três séries 2xx, 4xx e 5xx. A API do Grafana e `verify-stack.sh` também
validam esse painel na stack local.

## Auditoria local esperada

`verify-stack.sh` valida Dockerfile, containers, endpoints, Prometheus, Grafana, Graylog e
a suíte Maven. A auditoria agora exige dados de latência média para 2xx, 4xx e 5xx e a
existência do painel correspondente no dashboard. Os números nos arquivos históricos são
registros da última execução; execute a sequência acima para gerar números atuais após esta
alteração.

## Workflow versionado, sem execução

O arquivo [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml) é mantido como
parte da entrega acadêmica, mas **não deve ser disparado neste fechamento**. Qualquer
commit ou push futuro deste trabalho deve incluir `[skip ci]`; não há nova run, imagem
GHCR ou screenshot de Actions a registrar.

## Links atuais

| Item | Endereço |
|---|---|
| Repositório público atual | https://github.com/lcsrj/spring-devops-observability- |
| Workflow versionado | https://github.com/lcsrj/spring-devops-observability-/blob/main/.github/workflows/ci-cd.yml |

> O nome final do repositório é `spring-devops-observability-`; nenhuma renomeação é
> necessária ou deve ser tentada.
